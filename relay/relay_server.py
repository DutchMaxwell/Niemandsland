"""Niemandsland Relay Server - WebSocket relay for internet multiplayer.

A lightweight message relay that forwards game data between players
in the same room. Does NOT understand game logic - only routes messages.

Security features:
- Cryptographically random room codes (secrets module)
- Rate limiting per peer
- Connection limits per IP
- Message size limits
- Room expiration (4 hours)
- Heartbeat timeout (30 seconds)
- Strict input validation
"""

import argparse
import asyncio
import json
import logging
import secrets
import ssl
import struct
import time
from dataclasses import dataclass, field
from typing import Optional

import websockets
from websockets.asyncio.server import ServerConnection

# --- Configuration ---
MAX_ROOMS = 100
MAX_PEERS_PER_ROOM = 8
ROOM_EXPIRY_SECONDS = 14400  # 4 hours
HEARTBEAT_TIMEOUT_SECONDS = 30
MAX_MESSAGE_SIZE = 1048576  # 1MB — game state serializations can be large
# 300 was far too low for a 2-player game's bursty army sync (a clean client tops out at
# ~220 msg/s, but fragmented army-unit RPCs + a high-refresh framerate can spike higher).
# The relay stays a dumb router; the client owns pacing (token bucket). 2000 gives headroom
# while still catching a genuinely misbehaving peer.
RATE_LIMIT_MESSAGES_PER_SECOND = 2000
# A legitimate reconnect storm behind one NAT (guest churns peer 3,4,5...) must not trip a
# second 4429 ("Too many connections from this IP") and turn a transient blip into a dead room.
MAX_CONNECTIONS_PER_IP = 10
CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"  # 30 chars, no ambiguous 0/O/1/I/L
CODE_LENGTH = 6  # 30^6 = 729,000,000 possibilities
HOST_REJOIN_WINDOW_SECONDS = 20  # keep a room alive this long after the host drops, so they can rejoin

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger("relay")


@dataclass
class Peer:
    """Represents a connected player."""
    websocket: ServerConnection
    peer_id: int
    room_code: str
    ip_address: str
    last_heartbeat: float = field(default_factory=time.monotonic)
    message_timestamps: list = field(default_factory=list)


@dataclass
class Room:
    """Represents a game room with connected peers."""
    code: str
    peers: dict[int, Peer] = field(default_factory=dict)
    created_at: float = field(default_factory=time.monotonic)
    next_peer_id: int = 2  # Host is always peer_id 1
    host_disconnected_at: float = 0.0  # >0 = host dropped; room preserved until rejoin or window expiry
    is_public: bool = False  # listed in the room browser; private rooms join by code only


class RelayServer:
    """WebSocket relay server for Niemandsland multiplayer."""

    def __init__(self):
        self.rooms: dict[str, Room] = {}
        self.connections: dict[ServerConnection, Peer] = {}
        self.ip_connection_counts: dict[str, int] = {}

    def generate_room_code(self) -> str:
        """Generate a cryptographically random room code.

        Uses secrets.token_bytes() for unpredictable randomness.
        Retries if the generated code collides with an existing room.
        """
        for _ in range(10):  # Max retries to avoid infinite loop
            raw = secrets.token_bytes(CODE_LENGTH)
            code = "".join(CODE_ALPHABET[b % len(CODE_ALPHABET)] for b in raw)
            if code not in self.rooms:
                return code
        # Extremely unlikely fallback
        raise RuntimeError("Failed to generate unique room code after 10 attempts")

    async def handle_connection(self, websocket: ServerConnection) -> None:
        """Main handler for a new WebSocket connection."""
        ip = websocket.remote_address[0] if websocket.remote_address else "unknown"

        # Check connection limit per IP
        current_count = self.ip_connection_counts.get(ip, 0)
        if current_count >= MAX_CONNECTIONS_PER_IP:
            await websocket.close(4429, "Too many connections from this IP")
            return

        self.ip_connection_counts[ip] = current_count + 1

        try:
            async for message in websocket:
                peer = self.connections.get(websocket)

                if isinstance(message, str):
                    # JSON control message
                    await self._handle_control_message(websocket, message, ip)
                elif isinstance(message, bytes):
                    # Binary game data
                    if peer:
                        if not self._check_rate_limit(peer):
                            await websocket.close(4429, "Rate limit exceeded")
                            break
                        if len(message) > MAX_MESSAGE_SIZE:
                            await websocket.close(4413, "Message too large")
                            break
                        await self._handle_binary_message(peer, message)
        except websockets.exceptions.ConnectionClosed:
            pass
        finally:
            await self._remove_connection(websocket, ip)

    async def _handle_control_message(
        self, websocket: ServerConnection, raw: str, ip: str
    ) -> None:
        """Parse and dispatch a JSON control message."""
        try:
            msg = json.loads(raw)
        except json.JSONDecodeError:
            await websocket.close(4400, "Invalid JSON")
            return

        if not isinstance(msg, dict) or "type" not in msg:
            await websocket.close(4400, "Missing 'type' field")
            return

        msg_type = msg["type"]

        peer = self.connections.get(websocket)

        # Rate limit control messages too
        if peer and not self._check_rate_limit(peer):
            await websocket.close(4429, "Rate limit exceeded")
            return

        if msg_type == "create_room":
            # Only an explicit JSON boolean true makes a room public; a truthy
            # string like "false"/"0" must NOT leak the room into the browser.
            await self._handle_create_room(websocket, ip, msg.get("public", False) is True)
        elif msg_type == "join_room":
            code = msg.get("code", "")
            if not isinstance(code, str):
                await self._send_error(websocket, "Invalid code format")
                return
            await self._handle_join_room(websocket, code, ip)
        elif msg_type == "list_rooms":
            await self._handle_list_rooms(websocket)
        elif msg_type == "heartbeat":
            if peer:
                peer.last_heartbeat = time.monotonic()
            await websocket.send(json.dumps({"type": "heartbeat_ack"}))
        else:
            await self._send_error(websocket, f"Unknown message type: {msg_type}")

    async def _handle_create_room(
        self, websocket: ServerConnection, ip: str, is_public: bool = False
    ) -> None:
        """Create a new room and assign the creator as host (peer_id=1)."""
        # Check if this connection already has a room
        if websocket in self.connections:
            await self._send_error(websocket, "Already in a room")
            return

        # Check room limit
        if len(self.rooms) >= MAX_ROOMS:
            await self._send_error(websocket, "Server full, try again later")
            return

        code = self.generate_room_code()
        room = Room(code=code, is_public=is_public)
        peer = Peer(
            websocket=websocket,
            peer_id=1,
            room_code=code,
            ip_address=ip,
        )
        room.peers[1] = peer
        self.rooms[code] = room
        self.connections[websocket] = peer

        await websocket.send(json.dumps({
            "type": "room_created",
            "code": code,
            "peer_id": 1,
        }))
        logger.info("Room %s created by %s", code, ip)

    async def _handle_join_room(
        self, websocket: ServerConnection, code: str, ip: str
    ) -> None:
        """Join an existing room by code."""
        # Check if this connection already has a room
        if websocket in self.connections:
            await self._send_error(websocket, "Already in a room")
            return

        # Normalize code (case-insensitive)
        code = code.upper().strip()

        room = self.rooms.get(code)
        if not room:
            await self._send_error(websocket, "Room not found")
            return

        # Rehost: the host dropped but the room was preserved (HOST_RECONNECT.md).
        # The first joiner reclaims peer_id 1 and resumes hosting; the guests were
        # never booted, so the host re-syncs full state to them after this.
        if room.host_disconnected_at > 0.0 and 1 not in room.peers:
            room.host_disconnected_at = 0.0
            peer = Peer(websocket=websocket, peer_id=1, room_code=code, ip_address=ip)
            room.peers[1] = peer
            self.connections[websocket] = peer
            await websocket.send(json.dumps({
                "type": "room_rejoined_host",
                "peer_id": 1,
            }))
            for guest in room.peers.values():
                if guest.peer_id == 1:
                    continue
                # Tell the waiting guest the host is back...
                try:
                    await guest.websocket.send(json.dumps({
                        "type": "peer_connected",
                        "peer_id": 1,
                    }))
                except websockets.exceptions.ConnectionClosed:
                    pass
                # ...and tell the rejoined host about each guest, so its peer list
                # is rebuilt and it can re-sync state to them (like a normal join).
                try:
                    await websocket.send(json.dumps({
                        "type": "peer_connected",
                        "peer_id": guest.peer_id,
                    }))
                except websockets.exceptions.ConnectionClosed:
                    pass
            logger.info("Host rejoined room %s from %s", code, ip)
            return

        if len(room.peers) >= MAX_PEERS_PER_ROOM:
            await self._send_error(websocket, "Room is full")
            return

        peer_id = room.next_peer_id
        room.next_peer_id += 1

        peer = Peer(
            websocket=websocket,
            peer_id=peer_id,
            room_code=code,
            ip_address=ip,
        )
        room.peers[peer_id] = peer
        self.connections[websocket] = peer

        # Notify the joiner
        await websocket.send(json.dumps({
            "type": "room_joined",
            "peer_id": peer_id,
        }))

        # Notify existing peers about the new peer
        for existing_peer in room.peers.values():
            if existing_peer.peer_id != peer_id:
                try:
                    await existing_peer.websocket.send(json.dumps({
                        "type": "peer_connected",
                        "peer_id": peer_id,
                    }))
                except websockets.exceptions.ConnectionClosed:
                    pass

        # Notify joiner about existing peers
        for existing_peer in room.peers.values():
            if existing_peer.peer_id != peer_id:
                try:
                    await websocket.send(json.dumps({
                        "type": "peer_connected",
                        "peer_id": existing_peer.peer_id,
                    }))
                except websockets.exceptions.ConnectionClosed:
                    pass

        logger.info("Peer %d joined room %s from %s", peer_id, code, ip)

    async def _handle_list_rooms(self, websocket: ServerConnection) -> None:
        """Reply with the joinable public rooms for the room browser.

        Works on a connection that has NOT created or joined a room — the browser
        lists before it joins. Private rooms (the default) are never listed; a
        host that dropped (room paused) or a full room is excluded so the browser
        only ever offers a room a player can actually join.
        """
        rooms = [
            {"code": room.code, "players": len(room.peers)}
            for room in self.rooms.values()
            if room.is_public
            and room.host_disconnected_at == 0.0
            and len(room.peers) < MAX_PEERS_PER_ROOM
        ]
        await websocket.send(json.dumps({"type": "rooms_list", "rooms": rooms}))

    async def _handle_binary_message(self, sender: Peer, data: bytes) -> None:
        """Forward a binary game data message to the target peer(s).

        Binary frame format:
          [target_peer_id: 4 bytes int32 BE] [payload]
          target_peer_id = 0 means broadcast to all other peers in the room.

        When forwarding, the relay prepends the sender's peer_id so the
        receiver knows who sent the message:
          [source_peer_id: 4 bytes int32 BE] [payload]
        """
        if len(data) < 4:
            return  # Too short, ignore

        target_peer_id = struct.unpack(">i", data[:4])[0]
        payload = data[4:]
        forwarded = struct.pack(">i", sender.peer_id) + payload

        room = self.rooms.get(sender.room_code)
        if not room:
            return

        if target_peer_id == 0:
            # Broadcast to all peers except sender
            for peer in room.peers.values():
                if peer.peer_id != sender.peer_id:
                    try:
                        await peer.websocket.send(forwarded)
                    except websockets.exceptions.ConnectionClosed:
                        pass
        else:
            # Send to specific peer
            target = room.peers.get(target_peer_id)
            if target:
                try:
                    await target.websocket.send(forwarded)
                except websockets.exceptions.ConnectionClosed:
                    pass

    def _check_rate_limit(self, peer: Peer) -> bool:
        """Check if a peer has exceeded the rate limit.

        Returns True if the message is allowed, False if rate limited.
        """
        now = time.monotonic()
        # Remove timestamps older than 1 second
        peer.message_timestamps = [
            t for t in peer.message_timestamps if now - t < 1.0
        ]
        if len(peer.message_timestamps) >= RATE_LIMIT_MESSAGES_PER_SECOND:
            logger.warning("Rate limit exceeded for peer %d", peer.peer_id)
            return False
        peer.message_timestamps.append(now)
        return True

    async def _remove_connection(
        self, websocket: ServerConnection, ip: str
    ) -> None:
        """Clean up when a connection is closed."""
        # Decrement IP count
        if ip in self.ip_connection_counts:
            self.ip_connection_counts[ip] -= 1
            if self.ip_connection_counts[ip] <= 0:
                del self.ip_connection_counts[ip]

        peer = self.connections.pop(websocket, None)
        if not peer:
            return

        room = self.rooms.get(peer.room_code)
        if not room:
            return

        del room.peers[peer.peer_id]

        if peer.peer_id == 1:
            # Host disconnected. Preserve the room for a short window so the host
            # can rejoin and re-sync state, instead of booting everyone on a Wi-Fi
            # blip (see HOST_RECONNECT.md). Only tear it down if no guests remain to
            # rejoin to. Guests keep their sockets OPEN and are told the host paused.
            if room.peers:
                room.host_disconnected_at = time.monotonic()
                logger.info(
                    "Host left room %s, preserving %ds for rejoin (%d guest(s) waiting)",
                    peer.room_code, HOST_REJOIN_WINDOW_SECONDS, len(room.peers),
                )
                for remaining_peer in room.peers.values():
                    try:
                        await remaining_peer.websocket.send(json.dumps({
                            "type": "host_paused",
                        }))
                    except websockets.exceptions.ConnectionClosed:
                        pass
            else:
                logger.info("Host left room %s, no guests waiting, closing room", peer.room_code)
                del self.rooms[peer.room_code]
        else:
            # Guest disconnected - notify remaining peers
            for remaining_peer in room.peers.values():
                try:
                    await remaining_peer.websocket.send(json.dumps({
                        "type": "peer_disconnected",
                        "peer_id": peer.peer_id,
                    }))
                except websockets.exceptions.ConnectionClosed:
                    pass

            # If room is empty, clean it up
            if not room.peers:
                del self.rooms[peer.room_code]

        logger.info("Peer %d disconnected from room %s", peer.peer_id, peer.room_code)

    async def _send_error(self, websocket: ServerConnection, message: str) -> None:
        """Send an error message to a client."""
        try:
            await websocket.send(json.dumps({
                "type": "error",
                "message": message,
            }))
        except websockets.exceptions.ConnectionClosed:
            pass

    async def cleanup_expired_rooms(self) -> None:
        """Background task: remove rooms older than ROOM_EXPIRY_SECONDS."""
        while True:
            await asyncio.sleep(60)
            now = time.monotonic()
            expired = [
                code for code, room in self.rooms.items()
                if now - room.created_at > ROOM_EXPIRY_SECONDS
            ]
            for code in expired:
                room = self.rooms.get(code)
                if room:
                    logger.info("Room %s expired, closing", code)
                    for peer in list(room.peers.values()):
                        self.connections.pop(peer.websocket, None)
                        try:
                            await peer.websocket.send(json.dumps({
                                "type": "error",
                                "message": "Room expired",
                            }))
                            await peer.websocket.close(4408, "Room expired")
                        except websockets.exceptions.ConnectionClosed:
                            pass
                    del self.rooms[code]

    async def check_heartbeats(self) -> None:
        """Background task: disconnect peers that missed heartbeats."""
        while True:
            await asyncio.sleep(10)
            now = time.monotonic()
            timed_out = []
            for ws, peer in list(self.connections.items()):
                if now - peer.last_heartbeat > HEARTBEAT_TIMEOUT_SECONDS:
                    timed_out.append(ws)

            for ws in timed_out:
                logger.info("Heartbeat timeout for peer")
                try:
                    await ws.close(4408, "Heartbeat timeout")
                except websockets.exceptions.ConnectionClosed:
                    pass

            await self._close_abandoned_rooms()

    async def _close_abandoned_rooms(self) -> list[str]:
        """Tear down rooms whose host dropped and did not rejoin within the window.

        Returns the list of closed room codes (for tests). Guests waiting in such a
        room are told the host did not return and their sockets are closed.
        """
        now = time.monotonic()
        abandoned = [
            code for code, room in self.rooms.items()
            if room.host_disconnected_at > 0.0
            and now - room.host_disconnected_at > HOST_REJOIN_WINDOW_SECONDS
        ]
        for code in abandoned:
            room = self.rooms.get(code)
            if not room:
                continue
            logger.info("Room %s host did not return in %ds, closing", code, HOST_REJOIN_WINDOW_SECONDS)
            for guest in list(room.peers.values()):
                self.connections.pop(guest.websocket, None)
                try:
                    await guest.websocket.send(json.dumps({
                        "type": "error",
                        "message": "Host did not return",
                    }))
                    await guest.websocket.close(4000, "Host did not return")
                except websockets.exceptions.ConnectionClosed:
                    pass
            del self.rooms[code]
        return abandoned


async def main(host: str = "0.0.0.0", port: int = 8765,
               certfile: str = None, keyfile: str = None) -> None:
    """Start the relay server."""
    server = RelayServer()

    ssl_context = None
    if certfile and keyfile:
        ssl_context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        ssl_context.load_cert_chain(certfile, keyfile)

    async with websockets.serve(
        server.handle_connection,
        host,
        port,
        ssl=ssl_context,
        max_size=MAX_MESSAGE_SIZE,
        ping_interval=20,
        ping_timeout=30,   # Raised for GLB load times (main thread blocks during R2 downloads)
    ) as ws_server:
        logger.info("Relay server started on %s:%d", host, port)

        # Start background tasks
        cleanup_task = asyncio.create_task(server.cleanup_expired_rooms())
        heartbeat_task = asyncio.create_task(server.check_heartbeats())

        try:
            await asyncio.Future()  # Run forever
        finally:
            cleanup_task.cancel()
            heartbeat_task.cancel()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Niemandsland Relay Server")
    parser.add_argument("--host", default="0.0.0.0", help="Bind address")
    parser.add_argument("--port", type=int, default=8765, help="Port")
    parser.add_argument("--certfile", help="TLS certificate file")
    parser.add_argument("--keyfile", help="TLS private key file")
    args = parser.parse_args()

    asyncio.run(main(args.host, args.port, args.certfile, args.keyfile))
