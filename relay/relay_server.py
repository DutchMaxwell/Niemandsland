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
import os
import secrets
import ssl
import struct
import time
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Optional

import websockets
from websockets.asyncio.server import ServerConnection

# --- Configuration ---
MAX_ROOMS = 100
MAX_PEERS_PER_ROOM = 8
ROOM_EXPIRY_SECONDS = 14400  # 4 hours

# Per-peer outbound queue depth. Sized to comfortably hold a legitimate burst (a join-time full
# state sync, or the recv loop enqueuing a buffered batch before the writer task gets to run) at the
# relay's rate ceiling, so healthy peers never lose a frame. Only a peer that stays >~1 s behind
# (a genuine slow/stuck consumer) overflows — then frames are DROPPED rather than blocking the relay
# (the host re-broadcasts full state, so a drop self-heals). See _enqueue / _peer_writer.
SEND_QUEUE_MAX = 2048
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
GUEST_REJOIN_WINDOW_SECONDS = 20  # a returning guest reclaims its old peer_id within this window

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger("relay")


@dataclass
class Peer:
    """Represents a connected player."""
    websocket: ServerConnection
    peer_id: int
    room_code: str
    ip_address: str
    token: str = ""  # stable per-install reconnect key; lets a rejoin reclaim its old peer_id
    last_heartbeat: float = field(default_factory=time.monotonic)
    message_timestamps: list = field(default_factory=list)
    # A per-peer outbound queue drained by a single writer task (see _enqueue/_peer_writer). A slow
    # consumer's WebSocket backpressure then parks only ITS writer, never the shared recv loop that
    # must keep reading heartbeats — fixing the head-of-line block that false-dropped whole rooms.
    send_queue: "asyncio.Queue" = field(default_factory=lambda: asyncio.Queue(maxsize=SEND_QUEUE_MAX))
    writer_task: Optional[asyncio.Task] = None


@dataclass
class Room:
    """Represents a game room with connected peers."""
    code: str
    peers: dict[int, Peer] = field(default_factory=dict)
    created_at: float = field(default_factory=time.monotonic)
    next_peer_id: int = 2  # Host is always peer_id 1
    host_disconnected_at: float = 0.0  # >0 = host dropped; room preserved until rejoin or window expiry
    is_public: bool = False  # listed in the room browser; private rooms join by code only
    host_token: str = ""  # the host's reconnect token; ONLY a matching token may reclaim peer_id 1
    # token -> (peer_id, disconnected_at): a recently-departed guest, so a rejoin within the
    # window can reclaim its OLD peer_id (stable transport id across a drop).
    departed: dict = field(default_factory=dict)


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


class Stats:
    """Anonymous, aggregate relay-usage counters — totals + peaks only, NEVER IPs, room codes or
    player names — so 'how much is it used' is visible without identifying anyone. Persisted to
    `path` (a Fly volume) so the counts survive the scale-to-zero machine stops; with an empty
    path it stays in-memory only (local/dev/test). Persistence failures degrade gracefully to
    in-memory and never crash the relay.
    """

    FIELDS = ("rooms_created", "peer_connections", "server_starts",
              "peak_concurrent_peers", "peak_concurrent_rooms")

    def __init__(self, path: str = ""):
        self.path = path
        self.rooms_created = 0
        self.peer_connections = 0
        self.server_starts = 0
        self.peak_concurrent_peers = 0
        self.peak_concurrent_rooms = 0
        self.first_seen = ""
        self.last_updated = ""
        self._load()

    def _load(self) -> None:
        if not self.path:
            return
        try:
            with open(self.path) as f:
                data = json.load(f)
            for key in self.FIELDS:
                setattr(self, key, int(data.get(key, 0)))
            self.first_seen = str(data.get("first_seen", ""))
        except (OSError, ValueError, TypeError):
            pass  # first run / unreadable / corrupt -> start fresh, never crash the relay

    def _save(self) -> None:
        if not self.path:
            return
        self.last_updated = _utc_now_iso()
        try:
            tmp = self.path + ".tmp"
            with open(tmp, "w") as f:
                json.dump(self.snapshot(), f)
            os.replace(tmp, self.path)  # atomic so a crash mid-write can't corrupt the file
        except OSError:
            pass  # volume unavailable -> in-memory only

    def boot(self) -> None:
        """Count one server start (≈ one play session, since the relay scales to zero)."""
        self.server_starts += 1
        if not self.first_seen:
            self.first_seen = _utc_now_iso()
        self._save()

    def room_created(self, rooms_open: int) -> None:
        self.rooms_created += 1
        self.peak_concurrent_rooms = max(self.peak_concurrent_rooms, rooms_open)
        self._save()

    def peer_connected(self, peers_connected: int) -> None:
        self.peer_connections += 1
        self.peak_concurrent_peers = max(self.peak_concurrent_peers, peers_connected)
        self._save()

    def snapshot(self) -> dict:
        snap = {key: getattr(self, key) for key in self.FIELDS}
        snap["first_seen"] = self.first_seen
        snap["last_updated"] = self.last_updated
        return snap


class RelayServer:
    """WebSocket relay server for Niemandsland multiplayer."""

    def __init__(self):
        self.rooms: dict[str, Room] = {}
        self.connections: dict[ServerConnection, Peer] = {}
        self.ip_connection_counts: dict[str, int] = {}
        self.stats = Stats(os.environ.get("RELAY_STATS_PATH", ""))

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
            requested = msg.get("code", "")
            host_token = msg.get("token", "")
            await self._handle_create_room(
                websocket, ip, msg.get("public", False) is True,
                requested if isinstance(requested, str) else "",
                host_token if isinstance(host_token, str) else "")
        elif msg_type == "join_room":
            code = msg.get("code", "")
            if not isinstance(code, str):
                await self._send_error(websocket, "Invalid code format")
                return
            token = msg.get("token", "")
            if not isinstance(token, str):
                token = ""
            await self._handle_join_room(websocket, code, ip, token)
        elif msg_type == "list_rooms":
            await self._handle_list_rooms(websocket)
        elif msg_type == "get_stats":
            await self._handle_get_stats(websocket)
        elif msg_type == "heartbeat":
            if peer:
                peer.last_heartbeat = time.monotonic()
            await websocket.send(json.dumps({"type": "heartbeat_ack"}))
        else:
            await self._send_error(websocket, f"Unknown message type: {msg_type}")

    async def _handle_create_room(
        self, websocket: ServerConnection, ip: str, is_public: bool = False,
        requested_code: str = "", token: str = ""
    ) -> None:
        """Create a new room and assign the creator as host (peer_id=1).

        If requested_code is a well-formed, currently-free code, reuse it. This lets a host whose
        relay link was lost (e.g. the machine idle-stopped and restarted with empty in-memory rooms)
        re-create its room with the SAME code, so guests auto-rejoin the code they already hold.
        Falls back to a fresh code if it is taken or malformed.
        """
        # Check if this connection already has a room
        if websocket in self.connections:
            await self._send_error(websocket, "Already in a room")
            return

        # Check room limit
        if len(self.rooms) >= MAX_ROOMS:
            await self._send_error(websocket, "Server full, try again later")
            return

        code = requested_code.upper().strip()
        if not (len(code) == CODE_LENGTH and all(c in CODE_ALPHABET for c in code)
                and code not in self.rooms):
            code = self.generate_room_code()
        room = Room(code=code, is_public=is_public, host_token=token)
        peer = Peer(
            websocket=websocket,
            peer_id=1,
            room_code=code,
            ip_address=ip,
            token=token,
        )
        room.peers[1] = peer
        self.rooms[code] = room
        self.connections[websocket] = peer
        self.stats.room_created(len(self.rooms))
        self.stats.peer_connected(len(self.connections))

        await websocket.send(json.dumps({
            "type": "room_created",
            "code": code,
            "peer_id": 1,
        }))
        logger.info("Room %s created by %s", code, ip)

    async def _handle_join_room(
        self, websocket: ServerConnection, code: str, ip: str, token: str = ""
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

        # Rehost: the host dropped but the room was preserved (HOST_RECONNECT.md). ONLY the real host
        # — the joiner whose reconnect token matches the room's host_token — reclaims peer_id 1 and
        # resumes hosting. A guest reconnecting during the host's absence must NOT seize the host slot
        # (that demoted the real host to a guest and orphaned the authoritative state = the live-game
        # async). Any lingering old peer-1 socket (a half-open drop) is evicted so the real host
        # reclaims id 1 without waiting for the stale socket to be reaped.
        if room.host_disconnected_at > 0.0 and token and token == room.host_token:
            room.host_disconnected_at = 0.0
            old_host = room.peers.pop(1, None)
            if old_host is not None:
                self.connections.pop(old_host.websocket, None)
                if old_host.writer_task is not None:
                    old_host.writer_task.cancel()
                try:
                    await old_host.websocket.close(4000, "Replaced by host reconnect")
                except websockets.exceptions.ConnectionClosed:
                    pass
            peer = Peer(websocket=websocket, peer_id=1, room_code=code, ip_address=ip, token=token)
            room.peers[1] = peer
            self.connections[websocket] = peer
            self.stats.peer_connected(len(self.connections))
            await websocket.send(json.dumps({
                "type": "room_rejoined_host",
                "peer_id": 1,
            }))
            for guest in list(room.peers.values()):
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

        # A returning guest reclaims its OLD peer_id (within the rejoin window) so its transport
        # id is STABLE across the drop. With a fresh id, SceneMultiplayer's RPC routing for the new
        # id stays stale and the host kicks the guest on the version-handshake timeout (reconnect
        # cascade). Reuse is safe: next_peer_id only ever increments, so the old id is free.
        reused_id = None
        if token:
            entry = room.departed.pop(token, None)
            if entry is not None:
                old_id, departed_at = entry
                if (time.monotonic() - departed_at <= GUEST_REJOIN_WINDOW_SECONDS
                        and old_id not in room.peers):
                    reused_id = old_id
        if reused_id is not None:
            peer_id = reused_id
            logger.info("Guest reclaimed peer_id %d in room %s (reconnect)", peer_id, code)
        else:
            peer_id = room.next_peer_id
            room.next_peer_id += 1

        peer = Peer(
            websocket=websocket,
            peer_id=peer_id,
            room_code=code,
            ip_address=ip,
            token=token,
        )
        room.peers[peer_id] = peer
        self.connections[websocket] = peer
        self.stats.peer_connected(len(self.connections))

        # Notify the joiner
        await websocket.send(json.dumps({
            "type": "room_joined",
            "peer_id": peer_id,
        }))

        # Notify existing peers about the new peer
        for existing_peer in list(room.peers.values()):
            if existing_peer.peer_id != peer_id:
                try:
                    await existing_peer.websocket.send(json.dumps({
                        "type": "peer_connected",
                        "peer_id": peer_id,
                    }))
                except websockets.exceptions.ConnectionClosed:
                    pass

        # Notify joiner about existing peers
        for existing_peer in list(room.peers.values()):
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

    async def _handle_get_stats(self, websocket: ServerConnection) -> None:
        """Reply with anonymous, aggregate usage stats (NO IPs / room codes / player names) — the
        persisted totals + peaks plus the live open-rooms / connected-peers counts. Works on a
        connection that has not joined a room (like list_rooms)."""
        await websocket.send(json.dumps({
            "type": "stats",
            "rooms_open": len(self.rooms),
            "peers_connected": len(self.connections),
            **self.stats.snapshot(),
        }))

    def _enqueue(self, peer: Peer, data) -> None:
        """Queue an outbound frame for a peer WITHOUT ever awaiting its socket. A single per-peer
        writer task (_peer_writer) drains the queue, so a slow consumer's backpressure parks only
        that writer — never this coroutine, which must keep reading the room's heartbeats. If the
        peer falls too far behind (queue full) the frame is DROPPED: the host re-broadcasts full
        state continuously so a drop self-heals, whereas blocking starves heartbeat_acks and
        false-drops the whole room (the live-game collapse root cause)."""
        if peer.writer_task is None:
            peer.writer_task = asyncio.create_task(self._peer_writer(peer))
        try:
            peer.send_queue.put_nowait(data)
        except asyncio.QueueFull:
            pass

    async def _peer_writer(self, peer: Peer) -> None:
        """Drain one peer's outbound queue in FIFO order (per-peer frame order preserved). Runs
        until the peer is removed (writer_task.cancel() in _remove_connection) or its socket closes."""
        try:
            while True:
                data = await peer.send_queue.get()
                try:
                    await peer.websocket.send(data)
                except websockets.exceptions.ConnectionClosed:
                    return
        except asyncio.CancelledError:
            return

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
            # Broadcast to all peers except sender. ENQUEUED (never awaited here) so a slow
            # consumer can't park this coroutine and starve the room's heartbeat acks.
            for peer in list(room.peers.values()):
                if peer.peer_id != sender.peer_id:
                    self._enqueue(peer, forwarded)
        else:
            # Send to a specific peer (same non-blocking enqueue).
            target = room.peers.get(target_peer_id)
            if target:
                self._enqueue(target, forwarded)

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

        # Stop the peer's outbound writer task — its socket is gone.
        if peer.writer_task is not None:
            peer.writer_task.cancel()

        # Remember a guest's id keyed by its reconnect token so a rejoin within the window can
        # reclaim it (stable transport id). Host (id 1) reuse is handled by the rehost path above.
        if peer.peer_id != 1 and peer.token:
            room.departed[peer.token] = (peer.peer_id, time.monotonic())

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
                for remaining_peer in list(room.peers.values()):
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
            for remaining_peer in list(room.peers.values()):
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
    server.stats.boot()  # count this start (≈ one session, since the relay scales to zero)

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
