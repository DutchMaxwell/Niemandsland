"""Tests for the Niemandsland Relay Server."""

import asyncio
import json
import struct
import time
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
import websockets

from relay_server import (
    RelayServer,
    CODE_ALPHABET,
    CODE_LENGTH,
    MAX_CONNECTIONS_PER_IP,
    MAX_MESSAGE_SIZE,
    MAX_PEERS_PER_ROOM,
    MAX_ROOMS,
    RATE_LIMIT_MESSAGES_PER_SECOND,
    HOST_REJOIN_WINDOW_SECONDS,
)


# ============================================================================
# Helper: Start a real relay server for integration tests
# ============================================================================


@pytest.fixture
async def relay():
    """Start a relay server on a random port and yield (server, url)."""
    server = RelayServer()
    ws_server = await websockets.serve(
        server.handle_connection,
        "127.0.0.1",
        0,  # Random available port
        max_size=MAX_MESSAGE_SIZE,
        process_request=server.process_request,  # serve GET /stats like production
    )
    port = ws_server.sockets[0].getsockname()[1]
    url = f"ws://127.0.0.1:{port}"
    yield server, url
    ws_server.close()
    await ws_server.wait_closed()


async def http_get(url: str, path: str = "/stats") -> tuple:
    """Minimal HTTP/1.1 GET against the relay's port (the same listener serves WS + /stats).

    Returns (status_line, headers_text, body_text). Dependency-free: raw asyncio streams.
    """
    host_port = url.split("://", 1)[1]
    host, port = host_port.split(":")
    reader, writer = await asyncio.open_connection(host, int(port))
    writer.write(
        f"GET {path} HTTP/1.1\r\nHost: {host}\r\nConnection: close\r\n\r\n".encode()
    )
    await writer.drain()
    raw = await asyncio.wait_for(reader.read(), timeout=2.0)
    writer.close()
    head, _, body = raw.partition(b"\r\n\r\n")
    head_text = head.decode("utf-8", "replace")
    status_line, _, headers_text = head_text.partition("\r\n")
    return status_line, headers_text, body.decode("utf-8", "replace")


async def create_room(url: str) -> tuple:
    """Helper: connect and create a room, return (ws, code, peer_id)."""
    ws = await websockets.connect(url)
    await ws.send(json.dumps({"type": "create_room"}))
    resp = json.loads(await ws.recv())
    assert resp["type"] == "room_created"
    return ws, resp["code"], resp["peer_id"]


async def join_room(url: str, code: str) -> tuple:
    """Helper: connect and join a room, return (ws, peer_id)."""
    ws = await websockets.connect(url)
    await ws.send(json.dumps({"type": "join_room", "code": code}))
    resp = json.loads(await ws.recv())
    assert resp["type"] == "room_joined"
    return ws, resp["peer_id"]


async def create_public_room(url: str) -> tuple:
    """Helper: connect and create a PUBLIC room, return (ws, code, peer_id)."""
    ws = await websockets.connect(url)
    await ws.send(json.dumps({"type": "create_room", "public": True}))
    resp = json.loads(await ws.recv())
    assert resp["type"] == "room_created"
    return ws, resp["code"], resp["peer_id"]


async def list_rooms(url: str) -> list:
    """Helper: connect, request the room list, close, return the rooms array."""
    ws = await websockets.connect(url)
    await ws.send(json.dumps({"type": "list_rooms"}))
    resp = json.loads(await ws.recv())
    assert resp["type"] == "rooms_list"
    await ws.close()
    return resp["rooms"]


# ============================================================================
# Step 1: Room Code Generation
# ============================================================================


class TestRoomCodeGeneration:
    """Tests for cryptographically secure room code generation."""

    def setup_method(self):
        self.server = RelayServer()

    def test_code_length_is_six(self):
        code = self.server.generate_room_code()
        assert len(code) == 6

    def test_code_uses_only_allowed_characters(self):
        code = self.server.generate_room_code()
        for char in code:
            assert char in CODE_ALPHABET, f"'{char}' not in allowed alphabet"

    def test_code_has_no_ambiguous_characters(self):
        """Codes must not contain 0, O, 1, I, L to avoid confusion."""
        ambiguous = set("0OoIi1Ll")
        for _ in range(100):
            code = self.server.generate_room_code()
            for char in code:
                assert char not in ambiguous, f"Ambiguous char '{char}' found"

    def test_generated_codes_are_unique_over_1000_runs(self):
        codes = set()
        for _ in range(1000):
            code = self.server.generate_room_code()
            codes.add(code)
        # With 729M possibilities, 1000 codes should all be unique
        assert len(codes) == 1000

    def test_code_generation_retries_on_collision(self):
        """If a generated code already exists as a room, retry."""
        self.server.rooms["AAAAAA"] = MagicMock()
        with patch("relay_server.secrets") as mock_secrets:
            mock_secrets.token_bytes.side_effect = [
                bytes([0] * CODE_LENGTH),  # Maps to AAAAAA
                bytes([1] * CODE_LENGTH),  # Maps to BBBBBB
            ]
            code = self.server.generate_room_code()
            assert code != "AAAAAA"
            assert len(code) == CODE_LENGTH


# ============================================================================
# Step 2: Room Management
# ============================================================================


@pytest.mark.asyncio
class TestRoomManagement:
    """Tests for creating, joining, and leaving rooms."""

    async def test_create_room_returns_code(self, relay):
        server, url = relay
        ws, code, peer_id = await create_room(url)
        assert len(code) == 6
        assert code in server.rooms
        await ws.close()

    async def test_create_room_assigns_peer_id_one(self, relay):
        server, url = relay
        ws, code, peer_id = await create_room(url)
        assert peer_id == 1
        await ws.close()

    async def test_create_room_reuses_free_requested_code(self, relay):
        # Recovery: a host whose relay link was lost (machine idle-stopped + restarted with empty
        # in-memory rooms) re-creates its room with the SAME code, so guests auto-rejoin the code
        # they already hold. A well-formed, free requested code is reused verbatim.
        server, url = relay
        want = CODE_ALPHABET[0] * CODE_LENGTH  # well-formed and currently free
        ws = await websockets.connect(url)
        await ws.send(json.dumps({"type": "create_room", "code": want}))
        resp = json.loads(await ws.recv())
        assert resp["type"] == "room_created"
        assert resp["code"] == want
        assert want in server.rooms
        await ws.close()

    async def test_create_room_falls_back_when_requested_code_taken(self, relay):
        # If the requested code is already taken, fall back to a fresh one (no hijacking).
        server, url = relay
        host_ws, code, _ = await create_room(url)
        ws2 = await websockets.connect(url)
        await ws2.send(json.dumps({"type": "create_room", "code": code}))
        resp = json.loads(await ws2.recv())
        assert resp["type"] == "room_created"
        assert resp["code"] != code
        await host_ws.close()
        await ws2.close()

    async def test_join_room_with_valid_code(self, relay):
        server, url = relay
        host_ws, code, _ = await create_room(url)
        guest_ws, guest_id = await join_room(url, code)
        assert guest_id == 2
        assert len(server.rooms[code].peers) == 2
        await host_ws.close()
        await guest_ws.close()

    async def test_join_room_with_invalid_code_returns_error(self, relay):
        server, url = relay
        ws = await websockets.connect(url)
        await ws.send(json.dumps({"type": "join_room", "code": "XXXXXX"}))
        resp = json.loads(await ws.recv())
        assert resp["type"] == "error"
        assert "not found" in resp["message"].lower()
        await ws.close()

    async def test_join_room_notifies_host_of_new_peer(self, relay):
        server, url = relay
        host_ws, code, _ = await create_room(url)
        guest_ws, guest_id = await join_room(url, code)
        # Host should receive peer_connected notification
        host_msg = json.loads(await host_ws.recv())
        assert host_msg["type"] == "peer_connected"
        assert host_msg["peer_id"] == guest_id
        await host_ws.close()
        await guest_ws.close()

    async def test_join_room_assigns_incrementing_peer_ids(self, relay):
        server, url = relay
        host_ws, code, _ = await create_room(url)
        guest1_ws, guest1_id = await join_room(url, code)
        # Consume peer_connected on host
        await host_ws.recv()
        guest2_ws, guest2_id = await join_room(url, code)
        assert guest1_id == 2
        assert guest2_id == 3
        await host_ws.close()
        await guest1_ws.close()
        await guest2_ws.close()

    async def test_max_peers_per_room_enforced(self, relay):
        server, url = relay
        # Raise IP limit for this test (all from localhost)
        server.ip_connection_counts.clear()
        old_limit = MAX_CONNECTIONS_PER_IP
        import relay_server
        relay_server.MAX_CONNECTIONS_PER_IP = 20

        host_ws, code, _ = await create_room(url)
        guests = []
        # Fill up to max (host is 1, so MAX_PEERS_PER_ROOM - 1 guests)
        for i in range(MAX_PEERS_PER_ROOM - 1):
            ws, _ = await join_room(url, code)
            guests.append(ws)
            # Drain notifications on host
            await host_ws.recv()
            # Drain notifications on previous guests (each gets a peer_connected)
            for prev in guests[:-1]:
                await prev.recv()

        # Next join should fail
        overflow_ws = await websockets.connect(url)
        await overflow_ws.send(json.dumps({"type": "join_room", "code": code}))
        resp = json.loads(await overflow_ws.recv())
        assert resp["type"] == "error"
        assert "full" in resp["message"].lower()

        relay_server.MAX_CONNECTIONS_PER_IP = old_limit
        await host_ws.close()
        for ws in guests:
            await ws.close()
        await overflow_ws.close()

    async def test_max_rooms_enforced(self, relay):
        server, url = relay
        # Raise IP limit for this test (all from localhost)
        import relay_server
        old_limit = relay_server.MAX_CONNECTIONS_PER_IP
        relay_server.MAX_CONNECTIONS_PER_IP = 200

        hosts = []
        for i in range(MAX_ROOMS):
            ws, code, _ = await create_room(url)
            hosts.append(ws)

        # Next create should fail
        overflow_ws = await websockets.connect(url)
        await overflow_ws.send(json.dumps({"type": "create_room"}))
        resp = json.loads(await overflow_ws.recv())
        assert resp["type"] == "error"
        assert "full" in resp["message"].lower() or "server" in resp["message"].lower()

        relay_server.MAX_CONNECTIONS_PER_IP = old_limit
        for ws in hosts:
            await ws.close()
        await overflow_ws.close()

    async def test_host_disconnect_with_guest_preserves_room(self, relay):
        """Host drop is no longer fatal: the room is preserved and the guest is told
        the host paused, so the host can rejoin (HOST_RECONNECT.md)."""
        server, url = relay
        host_ws, code, _ = await create_room(url)
        guest_ws, _ = await join_room(url, code)
        await host_ws.recv()   # Host: peer_connected for guest
        await guest_ws.recv()  # Guest: peer_connected for host

        await host_ws.close()
        await asyncio.sleep(0.1)

        # Room preserved, host slot freed, marked disconnected.
        assert code in server.rooms
        assert 1 not in server.rooms[code].peers
        assert server.rooms[code].host_disconnected_at > 0.0

        # Guest is told the host paused (not booted).
        msg = json.loads(await guest_ws.recv())
        assert msg["type"] == "host_paused"
        await guest_ws.close()

    async def test_host_disconnect_with_no_guests_closes_room(self, relay):
        """With nobody to rejoin to, a host drop still tears the room down."""
        server, url = relay
        host_ws, code, _ = await create_room(url)
        await host_ws.close()
        await asyncio.sleep(0.1)
        assert code not in server.rooms

    async def test_host_can_rejoin_and_reclaim_peer_id_one(self, relay):
        """After a host drop, the HOST (matched by its reconnect token) reclaims peer_id 1 and
        resumes hosting; the waiting guest is told the host returned."""
        server, url = relay
        host_token = "host-reconnect-token"
        host_ws = await websockets.connect(url)
        await host_ws.send(json.dumps({"type": "create_room", "token": host_token}))
        code = json.loads(await host_ws.recv())["code"]
        guest_ws, guest_id = await join_room(url, code)
        await host_ws.recv()
        await guest_ws.recv()

        await host_ws.close()
        await asyncio.sleep(0.1)
        assert json.loads(await guest_ws.recv())["type"] == "host_paused"

        # The HOST rejoins the preserved room (matching token) and resumes hosting.
        rehost_ws = await websockets.connect(url)
        await rehost_ws.send(json.dumps({"type": "join_room", "code": code, "token": host_token}))
        resp = json.loads(await rehost_ws.recv())
        assert resp["type"] == "room_rejoined_host"
        assert resp["peer_id"] == 1
        assert server.rooms[code].host_disconnected_at == 0.0
        assert 1 in server.rooms[code].peers

        # The rejoined host is told about the waiting guest (so it can re-sync).
        msg = json.loads(await rehost_ws.recv())
        assert msg["type"] == "peer_connected"
        assert msg["peer_id"] == guest_id

        # Guest learns the host is back.
        msg = json.loads(await guest_ws.recv())
        assert msg["type"] == "peer_connected"
        assert msg["peer_id"] == 1

        await rehost_ws.close()
        await guest_ws.close()

    async def test_abandoned_room_expires_after_window(self, relay):
        """A preserved room whose host never returns is closed past the window, and
        the waiting guest is told the host did not return."""
        server, url = relay
        host_ws, code, _ = await create_room(url)
        guest_ws, _ = await join_room(url, code)
        await host_ws.recv()
        await guest_ws.recv()

        await host_ws.close()
        await asyncio.sleep(0.1)
        await guest_ws.recv()  # drain host_paused

        # Simulate the host having dropped longer than the rejoin window.
        server.rooms[code].host_disconnected_at = (
            time.monotonic() - HOST_REJOIN_WINDOW_SECONDS - 1
        )
        closed = await server._close_abandoned_rooms()
        assert code in closed
        assert code not in server.rooms

        msg = json.loads(await guest_ws.recv())
        assert msg["type"] == "error"
        assert "did not return" in msg["message"].lower()
        await guest_ws.close()

    async def test_guest_disconnect_notifies_host(self, relay):
        server, url = relay
        host_ws, code, _ = await create_room(url)
        guest_ws, guest_id = await join_room(url, code)
        # Drain peer_connected
        await host_ws.recv()

        # Guest disconnects
        await guest_ws.close()
        await asyncio.sleep(0.1)

        # Host should get notified
        msg = json.loads(await host_ws.recv())
        assert msg["type"] == "peer_disconnected"
        assert msg["peer_id"] == guest_id

        # Room should still exist (host still connected)
        assert code in server.rooms
        await host_ws.close()

    async def test_join_code_is_case_insensitive(self, relay):
        server, url = relay
        host_ws, code, _ = await create_room(url)
        # Join with lowercase code
        guest_ws, guest_id = await join_room(url, code.lower())
        assert guest_id == 2
        await host_ws.close()
        await guest_ws.close()


# ============================================================================
# Step 3: Security
# ============================================================================


@pytest.mark.asyncio
class TestSecurity:
    """Tests for security features: rate limiting, size limits, validation."""

    async def test_oversized_message_rejected(self, relay):
        server, url = relay
        host_ws, code, _ = await create_room(url)
        # Send a message larger than MAX_MESSAGE_SIZE
        # The websockets library enforces max_size on the server side
        # so the connection should be closed
        try:
            big_msg = b"\x00" * (MAX_MESSAGE_SIZE + 1000)
            await host_ws.send(big_msg)
            # Wait for close
            await asyncio.sleep(0.1)
            # Connection should be closed
            assert host_ws.closed
        except (websockets.exceptions.ConnectionClosed, Exception):
            pass  # Expected

    async def test_invalid_json_disconnects_peer(self, relay):
        server, url = relay
        ws = await websockets.connect(url)
        await ws.send("not valid json {{{")
        await asyncio.sleep(0.1)
        # Connection should be closed after invalid JSON
        try:
            # Try to receive - should get close or error
            await asyncio.wait_for(ws.recv(), timeout=1.0)
            assert False, "Should have been disconnected"
        except (websockets.exceptions.ConnectionClosed, asyncio.TimeoutError):
            pass

    async def test_unknown_message_type_rejected(self, relay):
        server, url = relay
        ws = await websockets.connect(url)
        await ws.send(json.dumps({"type": "hack_the_planet"}))
        resp = json.loads(await ws.recv())
        assert resp["type"] == "error"
        assert "unknown" in resp["message"].lower()
        await ws.close()

    async def test_double_create_room_rejected(self, relay):
        server, url = relay
        ws, code, _ = await create_room(url)
        # Try to create another room on same connection
        await ws.send(json.dumps({"type": "create_room"}))
        resp = json.loads(await ws.recv())
        assert resp["type"] == "error"
        assert "already" in resp["message"].lower()
        await ws.close()

    async def test_max_connections_per_ip(self, relay):
        server, url = relay
        connections = []
        for i in range(MAX_CONNECTIONS_PER_IP):
            ws = await websockets.connect(url)
            connections.append(ws)

        # Next connection should be rejected
        try:
            overflow_ws = await websockets.connect(url)
            # Try to interact - should fail because server closes it
            await overflow_ws.send(json.dumps({"type": "heartbeat"}))
            await asyncio.wait_for(overflow_ws.recv(), timeout=1.0)
            assert False, "Should have been disconnected"
        except (websockets.exceptions.ConnectionClosed,
                websockets.exceptions.ConnectionClosedError,
                asyncio.TimeoutError):
            pass  # Expected - server rejected the connection

        for ws in connections:
            await ws.close()

    async def test_heartbeat_ack_sent(self, relay):
        server, url = relay
        ws, code, _ = await create_room(url)
        await ws.send(json.dumps({"type": "heartbeat"}))
        resp = json.loads(await ws.recv())
        assert resp["type"] == "heartbeat_ack"
        await ws.close()


# ============================================================================
# Step 4: Message Forwarding
# ============================================================================


@pytest.mark.asyncio
class TestMessageForwarding:
    """Tests for binary game data routing between peers."""

    async def test_binary_message_forwarded_to_target_peer(self, relay):
        server, url = relay
        host_ws, code, _ = await create_room(url)
        guest_ws, guest_id = await join_room(url, code)
        # Drain peer_connected notifications
        await host_ws.recv()  # Host gets peer_connected for guest
        await guest_ws.recv()  # Guest gets peer_connected for host

        # Host sends binary message targeting guest (peer_id=2)
        payload = b"hello from host"
        msg = struct.pack(">i", guest_id) + payload
        await host_ws.send(msg)

        # Guest should receive it with host's peer_id prepended
        received = await asyncio.wait_for(guest_ws.recv(), timeout=2.0)
        assert isinstance(received, bytes)
        source_id = struct.unpack(">i", received[:4])[0]
        assert source_id == 1  # From host
        assert received[4:] == payload

        await host_ws.close()
        await guest_ws.close()

    async def test_broadcast_reaches_all_other_peers(self, relay):
        server, url = relay
        host_ws, code, _ = await create_room(url)
        guest1_ws, guest1_id = await join_room(url, code)
        await host_ws.recv()  # peer_connected
        guest2_ws, guest2_id = await join_room(url, code)
        await host_ws.recv()  # peer_connected
        await guest1_ws.recv()  # peer_connected for host
        await guest1_ws.recv()  # peer_connected for guest2
        await guest2_ws.recv()  # peer_connected for host
        await guest2_ws.recv()  # peer_connected for guest1

        # Host broadcasts (target=0)
        payload = b"broadcast from host"
        msg = struct.pack(">i", 0) + payload
        await host_ws.send(msg)

        # Both guests should receive it
        r1 = await asyncio.wait_for(guest1_ws.recv(), timeout=2.0)
        r2 = await asyncio.wait_for(guest2_ws.recv(), timeout=2.0)
        assert r1[4:] == payload
        assert r2[4:] == payload

        await host_ws.close()
        await guest1_ws.close()
        await guest2_ws.close()

    async def test_message_not_echoed_to_sender(self, relay):
        server, url = relay
        host_ws, code, _ = await create_room(url)
        guest_ws, guest_id = await join_room(url, code)
        await host_ws.recv()  # peer_connected
        await guest_ws.recv()  # peer_connected for host

        # Host broadcasts
        payload = b"should not echo"
        msg = struct.pack(">i", 0) + payload
        await host_ws.send(msg)

        # Guest receives it
        await asyncio.wait_for(guest_ws.recv(), timeout=2.0)

        # Host should NOT receive it back (no echo)
        with pytest.raises(asyncio.TimeoutError):
            await asyncio.wait_for(host_ws.recv(), timeout=0.3)

        await host_ws.close()
        await guest_ws.close()

    async def test_message_to_nonexistent_peer_silently_ignored(self, relay):
        server, url = relay
        host_ws, code, _ = await create_room(url)
        guest_ws, guest_id = await join_room(url, code)
        await host_ws.recv()  # peer_connected
        await guest_ws.recv()  # peer_connected for host

        # Host sends to non-existent peer 99
        msg = struct.pack(">i", 99) + b"nobody home"
        await host_ws.send(msg)

        # No crash, no error - message silently dropped
        # Verify connection is still alive
        await host_ws.send(json.dumps({"type": "heartbeat"}))
        resp = json.loads(await host_ws.recv())
        assert resp["type"] == "heartbeat_ack"

        await host_ws.close()
        await guest_ws.close()


# ============================================================================
# Integration Tests
# ============================================================================


@pytest.mark.asyncio
class TestEndToEnd:
    """Full end-to-end scenarios with real WebSocket connections."""

    async def test_full_host_join_message_roundtrip(self, relay):
        server, url = relay
        # Host creates room
        host_ws, code, host_id = await create_room(url)
        assert host_id == 1

        # Guest joins
        guest_ws, guest_id = await join_room(url, code)
        assert guest_id == 2

        # Drain notifications
        await host_ws.recv()
        await guest_ws.recv()

        # Host sends to guest
        host_payload = b"game state from host"
        await host_ws.send(struct.pack(">i", guest_id) + host_payload)
        r = await asyncio.wait_for(guest_ws.recv(), timeout=2.0)
        assert struct.unpack(">i", r[:4])[0] == 1
        assert r[4:] == host_payload

        # Guest sends back to host
        guest_payload = b"move from guest"
        await guest_ws.send(struct.pack(">i", host_id) + guest_payload)
        r = await asyncio.wait_for(host_ws.recv(), timeout=2.0)
        assert struct.unpack(">i", r[:4])[0] == 2
        assert r[4:] == guest_payload

        await host_ws.close()
        await guest_ws.close()

    async def test_guest_disconnect_and_host_continues(self, relay):
        server, url = relay
        host_ws, code, _ = await create_room(url)
        guest_ws, guest_id = await join_room(url, code)
        await host_ws.recv()  # peer_connected
        await guest_ws.recv()

        # Guest disconnects
        await guest_ws.close()
        await asyncio.sleep(0.1)

        # Host notified
        msg = json.loads(await host_ws.recv())
        assert msg["type"] == "peer_disconnected"

        # Host can still use the room (e.g., new guest joins)
        guest2_ws, guest2_id = await join_room(url, code)
        assert guest2_id == 3  # Increments from previous
        await host_ws.close()
        await guest2_ws.close()

    async def test_host_disconnect_notifies_guest(self, relay):
        server, url = relay
        host_ws, code, _ = await create_room(url)
        guest_ws, _ = await join_room(url, code)
        await host_ws.recv()
        await guest_ws.recv()

        # Host disconnects
        await host_ws.close()
        await asyncio.sleep(0.1)

        # Guest is told the host paused (room preserved for rejoin), not booted.
        msg = json.loads(await guest_ws.recv())
        assert msg["type"] == "host_paused"
        await guest_ws.close()

    async def test_multiple_rooms_are_isolated(self, relay):
        server, url = relay
        # Create two rooms
        host1_ws, code1, _ = await create_room(url)
        host2_ws, code2, _ = await create_room(url)
        guest1_ws, g1_id = await join_room(url, code1)
        guest2_ws, g2_id = await join_room(url, code2)

        # Drain notifications
        await host1_ws.recv()
        await guest1_ws.recv()
        await host2_ws.recv()
        await guest2_ws.recv()

        # Host1 sends message - should only reach guest1
        payload = b"room1 only"
        await host1_ws.send(struct.pack(">i", 0) + payload)
        r = await asyncio.wait_for(guest1_ws.recv(), timeout=2.0)
        assert r[4:] == payload

        # Guest2 should NOT receive it
        with pytest.raises(asyncio.TimeoutError):
            await asyncio.wait_for(guest2_ws.recv(), timeout=0.3)

        await host1_ws.close()
        await host2_ws.close()
        await guest1_ws.close()
        await guest2_ws.close()


# ============================================================================
# Room listing (room browser discovery)
# ============================================================================


class TestRoomListing:
    """list_rooms returns only joinable public rooms, and works before joining."""

    async def test_public_room_is_listed(self, relay):
        _server, url = relay
        ws, code, _ = await create_public_room(url)
        rooms = await list_rooms(url)
        assert any(r["code"] == code and r["players"] == 1 for r in rooms)
        await ws.close()

    async def test_private_room_is_not_listed(self, relay):
        _server, url = relay
        ws, code, _ = await create_room(url)  # default is private
        rooms = await list_rooms(url)
        assert all(r["code"] != code for r in rooms)
        await ws.close()

    async def test_full_room_is_excluded(self, relay):
        server, url = relay
        # All sockets come from localhost, so lift the per-IP cap for this test
        # (host + MAX_PEERS_PER_ROOM-1 guests + the listing socket > the default 5).
        import relay_server
        old_limit = relay_server.MAX_CONNECTIONS_PER_IP
        relay_server.MAX_CONNECTIONS_PER_IP = MAX_PEERS_PER_ROOM + 5
        server.ip_connection_counts.clear()
        host_ws, code, _ = await create_public_room(url)
        guests = []
        try:
            # Fill to capacity: host (1) + (MAX_PEERS_PER_ROOM - 1) guests.
            for _ in range(MAX_PEERS_PER_ROOM - 1):
                gws, _pid = await join_room(url, code)
                await host_ws.recv()  # drain the peer_connected notification
                guests.append(gws)
            rooms = await list_rooms(url)
            assert all(r["code"] != code for r in rooms)
        finally:
            relay_server.MAX_CONNECTIONS_PER_IP = old_limit
            await host_ws.close()
            for gws in guests:
                await gws.close()

    async def test_host_paused_room_is_excluded(self, relay):
        server, url = relay
        host_ws, code, _ = await create_public_room(url)
        # Simulate the host having dropped (room preserved during the rejoin window).
        server.rooms[code].host_disconnected_at = time.monotonic()
        rooms = await list_rooms(url)
        assert all(r["code"] != code for r in rooms)
        await host_ws.close()

    async def test_list_rooms_works_on_fresh_connection_without_consuming_a_slot(self, relay):
        server, url = relay
        ws, code, _ = await create_public_room(url)
        # A listing connection never registers as "in a room": it gets a valid
        # reply and leaves rooms/connections untouched.
        rooms_before = len(server.rooms)
        conns_before = len(server.connections)
        rooms = await list_rooms(url)
        assert any(r["code"] == code for r in rooms)
        # Give the server a moment to process the listing socket close.
        await asyncio.sleep(0.05)
        assert len(server.rooms) == rooms_before
        assert len(server.connections) == conns_before
        await ws.close()


# ============================================================================
# Anonymous usage stats (Stats counters + get_stats query)
# ============================================================================


class TestStats:
    """Stats: aggregate counters + peaks, persistence across restarts, and the get_stats query."""

    def test_counters_start_at_zero_in_memory(self):
        from relay_server import Stats
        s = Stats()  # no path -> in-memory only
        assert s.rooms_created == 0
        assert s.peer_connections == 0
        assert s.server_starts == 0
        assert s.peak_concurrent_peers == 0

    def test_increments_and_tracks_peaks(self):
        from relay_server import Stats
        s = Stats()
        s.boot()
        s.room_created(rooms_open=1)
        s.peer_connected(peers_connected=1)
        s.peer_connected(peers_connected=2)
        s.peer_connected(peers_connected=1)  # a later dip must NOT lower the peak
        assert s.server_starts == 1
        assert s.rooms_created == 1
        assert s.peer_connections == 3
        assert s.peak_concurrent_peers == 2
        assert s.peak_concurrent_rooms == 1

    def test_persists_and_reloads_across_restart(self, tmp_path):
        from relay_server import Stats
        path = str(tmp_path / "stats.json")
        s = Stats(path)
        s.boot()
        s.room_created(rooms_open=3)
        s.peer_connected(peers_connected=5)
        # A fresh instance on the same file resumes the totals/peaks (survives scale-to-zero).
        s2 = Stats(path)
        assert s2.rooms_created == 1
        assert s2.peak_concurrent_rooms == 3
        assert s2.peak_concurrent_peers == 5
        assert s2.first_seen != ""
        s2.boot()  # a second start increments server_starts on top of the persisted one
        assert s2.server_starts == 2

    def test_unwritable_path_degrades_without_crashing(self, tmp_path):
        from relay_server import Stats
        s = Stats(str(tmp_path / "missing_dir" / "stats.json"))
        s.room_created(rooms_open=1)  # save fails silently
        assert s.rooms_created == 1   # counter still updated in memory

    async def test_get_stats_reports_rooms_and_peers(self, relay):
        server, url = relay
        host_ws, code, _ = await create_room(url)
        guest_ws, _ = await join_room(url, code)
        probe = await websockets.connect(url)
        await probe.send(json.dumps({"type": "get_stats"}))
        reply = json.loads(await probe.recv())
        assert reply["type"] == "stats"
        assert reply["rooms_created"] == 1
        assert reply["peer_connections"] == 2      # host + guest
        assert reply["rooms_open"] == 1
        assert reply["peers_connected"] == 2
        assert reply["peak_concurrent_peers"] >= 2
        await host_ws.close()
        await guest_ws.close()
        await probe.close()


# ============================================================================
# Extended aggregate stats: games, join failures, lifetimes, /stats, log line
# ============================================================================


class TestAggregateStats:
    """The added aggregates: games (>=2 peers), join-failure reasons, room-lifetime + peers-per-room
    histograms, the GET /stats HTTP endpoint, and the periodic STATS log line."""

    def test_new_counters_and_dicts_start_empty(self):
        from relay_server import Stats, JOIN_FAILURE_REASONS, ROOM_LIFETIME_BUCKETS
        s = Stats()
        assert s.games_played == 0
        assert s.join_failures == {r: 0 for r in JOIN_FAILURE_REASONS}
        assert s.room_lifetime_buckets == {b: 0 for b in ROOM_LIFETIME_BUCKETS}
        assert set(s.peers_per_room) == {str(n) for n in range(1, MAX_PEERS_PER_ROOM + 1)}
        assert all(v == 0 for v in s.peers_per_room.values())

    def test_join_failed_ignores_unknown_reason(self):
        from relay_server import Stats
        s = Stats()
        s.join_failed("room_full")
        s.join_failed("not-a-real-reason")  # must be dropped, never trusted into the dict
        assert s.join_failures["room_full"] == 1
        assert "not-a-real-reason" not in s.join_failures

    def test_room_closed_buckets_lifetime_and_peak_peers(self):
        from relay_server import Stats
        s = Stats()
        s.room_closed(5 * 60, peak_peers=2)        # <10min
        s.room_closed(30 * 60, peak_peers=4)       # 10-45min
        s.room_closed(200 * 60, peak_peers=99)     # >120min, peak clamped to MAX
        assert s.room_lifetime_buckets["lt_10min"] == 1
        assert s.room_lifetime_buckets["10_45min"] == 1
        assert s.room_lifetime_buckets["gt_120min"] == 1
        assert s.peers_per_room["2"] == 1
        assert s.peers_per_room["4"] == 1
        assert s.peers_per_room[str(MAX_PEERS_PER_ROOM)] == 1

    def test_dict_histograms_persist_across_restart(self, tmp_path):
        from relay_server import Stats
        path = str(tmp_path / "stats.json")
        s = Stats(path)
        s.join_failed("room_not_found")
        s.room_closed(90 * 60, peak_peers=3)  # 45-120min
        s2 = Stats(path)
        assert s2.join_failures["room_not_found"] == 1
        assert s2.room_lifetime_buckets["45_120min"] == 1
        assert s2.peers_per_room["3"] == 1

    async def test_game_counted_once_when_room_reaches_two_peers(self, relay):
        server, url = relay
        host_ws, code, _ = await create_room(url)
        assert server.stats.games_played == 0  # solo room is not a game yet
        guest_ws, _ = await join_room(url, code)
        await host_ws.recv()
        assert server.stats.games_played == 1  # reached 2 peers
        guest2_ws, _ = await join_room(url, code)
        await host_ws.recv()
        await guest_ws.recv()
        assert server.stats.games_played == 1  # a third peer must NOT re-count the same game
        await host_ws.close()
        await guest_ws.close()
        await guest2_ws.close()

    async def test_join_failure_room_not_found_counted(self, relay):
        server, url = relay
        ws = await websockets.connect(url)
        await ws.send(json.dumps({"type": "join_room", "code": "ZZZZZZ"}))
        resp = json.loads(await ws.recv())
        assert resp["type"] == "error"
        assert server.stats.join_failures["room_not_found"] == 1
        await ws.close()

    async def test_join_failure_room_full_counted(self, relay):
        server, url = relay
        import relay_server
        old = relay_server.MAX_PEERS_PER_ROOM
        relay_server.MAX_PEERS_PER_ROOM = 1  # host alone already fills the room
        try:
            host_ws, code, _ = await create_room(url)
            ws = await websockets.connect(url)
            await ws.send(json.dumps({"type": "join_room", "code": code}))
            resp = json.loads(await ws.recv())
            assert resp["type"] == "error"
            assert "full" in resp["message"].lower()
            assert server.stats.join_failures["room_full"] == 1
            await ws.close()
            await host_ws.close()
        finally:
            relay_server.MAX_PEERS_PER_ROOM = old

    async def test_join_failure_server_full_counted(self, relay):
        server, url = relay
        import relay_server
        old = relay_server.MAX_ROOMS
        relay_server.MAX_ROOMS = 1
        try:
            host_ws, _, _ = await create_room(url)
            ws = await websockets.connect(url)
            await ws.send(json.dumps({"type": "create_room"}))
            resp = json.loads(await ws.recv())
            assert resp["type"] == "error"
            assert server.stats.join_failures["server_full"] == 1
            await ws.close()
            await host_ws.close()
        finally:
            relay_server.MAX_ROOMS = old

    async def test_room_close_records_lifetime_and_peers_histogram(self, relay):
        server, url = relay
        host_ws, code, _ = await create_room(url)
        guest_ws, _ = await join_room(url, code)  # peak peers = 2
        await host_ws.recv()
        await guest_ws.recv()
        # Guest leaves (room preserved, host remains), then host leaves with no guests -> room closed.
        await guest_ws.close()
        await asyncio.sleep(0.05)
        await host_ws.recv()  # peer_disconnected
        await host_ws.close()
        await asyncio.sleep(0.1)
        assert code not in server.rooms
        assert server.stats.room_lifetime_buckets["lt_10min"] == 1  # short-lived test room
        assert server.stats.peers_per_room["2"] == 1                # peaked at 2 peers

    async def test_get_stats_includes_new_aggregates(self, relay):
        server, url = relay
        host_ws, code, _ = await create_room(url)
        guest_ws, _ = await join_room(url, code)
        probe = await websockets.connect(url)
        await probe.send(json.dumps({"type": "get_stats"}))
        reply = json.loads(await probe.recv())
        assert reply["games_played"] == 1
        assert isinstance(reply["join_failures"], dict)
        assert isinstance(reply["room_lifetime_buckets"], dict)
        assert isinstance(reply["peers_per_room"], dict)
        await host_ws.close()
        await guest_ws.close()
        await probe.close()

    async def test_http_stats_endpoint_returns_aggregate_json(self, relay):
        server, url = relay
        host_ws, code, _ = await create_room(url)
        guest_ws, _ = await join_room(url, code)
        status, headers, body = await http_get(url, "/stats")
        assert "200" in status
        assert "application/json" in headers.lower()
        data = json.loads(body)
        assert data["rooms_created"] == 1
        assert data["games_played"] == 1
        assert data["rooms_open"] == 1
        assert data["peers_connected"] == 2
        assert "join_failures" in data and "peers_per_room" in data
        # No PII leaks: the payload is only the known aggregate keys (no ip/code/token/name).
        safe_keys = {
            "rooms_open", "peers_connected", "rooms_created", "peer_connections",
            "server_starts", "games_played", "peak_concurrent_peers", "peak_concurrent_rooms",
            "join_failures", "room_lifetime_buckets", "peers_per_room", "first_seen", "last_updated",
        }
        assert set(data) <= safe_keys
        await host_ws.close()
        await guest_ws.close()

    async def test_http_stats_matches_get_stats_ws(self, relay):
        server, url = relay
        host_ws, code, _ = await create_room(url)
        _status, _headers, body = await http_get(url, "/stats")
        http_data = json.loads(body)
        probe = await websockets.connect(url)
        await probe.send(json.dumps({"type": "get_stats"}))
        ws_reply = json.loads(await probe.recv())
        ws_reply.pop("type")
        # last_updated is a wall-clock field that can differ by a save between the two reads.
        http_data.pop("last_updated", None)
        ws_reply.pop("last_updated", None)
        assert http_data == ws_reply
        await host_ws.close()
        await probe.close()

    async def test_http_non_stats_path_does_not_serve_stats(self, relay):
        server, url = relay
        status, _headers, _body = await http_get(url, "/")
        # A bare GET / is not a WS upgrade and is not /stats: it must NOT return our 200 JSON.
        assert "200" not in status

    def test_log_stats_line_emits_parseable_stats(self, caplog):
        import logging
        import stats_digest
        server = RelayServer()
        server.stats.boot()
        with caplog.at_level(logging.INFO, logger="relay"):
            server.log_stats_line()
        stats_lines = [
            r.getMessage() for r in caplog.records if r.getMessage().startswith("STATS ")
        ]
        assert len(stats_lines) == 1
        records = list(stats_digest.iter_stats_records(stats_lines))
        assert len(records) == 1
        assert records[0]["server_starts"] == 1
        assert "ts" in records[0]


# ============================================================================
# stats_digest: parse captured STATS log lines into a weekly digest
# ============================================================================


def _stats_log_line(ts, **counters):
    """Build a relay-style STATS log line (timestamp/level prefix + JSON) for digest tests."""
    payload = {"ts": ts, "last_updated": ts, "first_seen": "2026-06-20T10:00:00+00:00", **counters}
    return f"2026-07-05 06:00:00,000 INFO STATS {json.dumps(payload, sort_keys=True)}"


class TestStatsDigest:
    """stats_digest parses only well-formed STATS lines and renders weekly totals/peaks/trends."""

    def test_iter_skips_non_stats_and_malformed_lines(self):
        import stats_digest
        lines = [
            "2026-07-05 INFO Room ABCDEF created by 1.2.3.4",   # ordinary log, no marker
            "2026-07-05 INFO STATS not-json",                   # marker but no JSON
            "2026-07-05 INFO STATS {\"no\": \"timestamp\"}",   # JSON but no ts/last_updated
            _stats_log_line("2026-07-02T09:00:00+00:00", rooms_created=5),
        ]
        records = list(stats_digest.iter_stats_records(lines))
        assert len(records) == 1
        assert records[0]["rooms_created"] == 5

    def test_render_groups_by_week_with_totals_and_deltas(self):
        import stats_digest
        lines = [
            _stats_log_line(
                "2026-06-30T09:00:00+00:00", rooms_created=10, games_played=6,
                peer_connections=30, server_starts=3,
                peak_concurrent_rooms=3, peak_concurrent_peers=5,
                join_failures={"room_full": 1, "room_not_found": 2},
                room_lifetime_buckets={"lt_10min": 3, "10_45min": 3},
                peers_per_room={"2": 4, "3": 2},
            ),
            _stats_log_line(
                "2026-07-06T18:00:00+00:00", rooms_created=25, games_played=17,
                peer_connections=70, server_starts=4,
                peak_concurrent_rooms=4, peak_concurrent_peers=7,
                join_failures={"room_full": 3, "room_not_found": 5},
                room_lifetime_buckets={"lt_10min": 6, "10_45min": 8},
                peers_per_room={"2": 9, "3": 5},
            ),
        ]
        records = list(stats_digest.iter_stats_records(lines))
        out = stats_digest.render_digest(records, source="relay.log")
        assert "2026-W27" in out      # week of 2026-06-30
        assert "2026-W28" in out      # week of 2026-07-06
        assert "+15" in out           # rooms created delta 25-10 in the second week
        assert "+11" in out           # games played delta 17-6
        assert "total 25" in out
        assert "Totals (latest snapshot)" in out
        assert "peak rooms / peers : 4 / 7" in out

    def test_render_empty_is_safe(self):
        import stats_digest
        out = stats_digest.render_digest([], source="empty.log")
        assert "No STATS records found." in out
