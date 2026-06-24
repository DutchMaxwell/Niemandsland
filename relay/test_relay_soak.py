"""Churn / soak / stress tests for the Niemandsland Relay Server.

These cover the documented gaps the base suite (test_relay_server.py) does not:
guest-churn cascades, host-drop -> rejoin loops, rate-limit fire + recovery,
IP-limit churn, broadcast ordering under burst, and heartbeat under load.

They focus on RELAY-side invariants. The client-side timing causes of sporadic
reconnects (main-loop stalls, framedrops) are exercised by the headless 2-client
soak harness (test/mp/), not here.
"""

import asyncio
import json
import struct
from unittest.mock import MagicMock

import pytest
import websockets

from relay_server import (
    RelayServer,
    Room,
    Peer,
    MAX_CONNECTIONS_PER_IP,
    MAX_MESSAGE_SIZE,
    RATE_LIMIT_MESSAGES_PER_SECOND,
    HOST_REJOIN_WINDOW_SECONDS,
)


# ---------------------------------------------------------------------------
# Local copies of the base suite's fixture + helpers (kept self-contained so
# this file can run independently; identical to test_relay_server.py).
# ---------------------------------------------------------------------------


@pytest.fixture
async def relay():
    """Start a relay server on a random port and yield (server, url)."""
    server = RelayServer()
    ws_server = await websockets.serve(
        server.handle_connection, "127.0.0.1", 0, max_size=MAX_MESSAGE_SIZE
    )
    port = ws_server.sockets[0].getsockname()[1]
    url = f"ws://127.0.0.1:{port}"
    yield server, url
    ws_server.close()
    await ws_server.wait_closed()


async def create_room(url: str) -> tuple:
    ws = await websockets.connect(url)
    await ws.send(json.dumps({"type": "create_room"}))
    resp = json.loads(await ws.recv())
    assert resp["type"] == "room_created"
    return ws, resp["code"], resp["peer_id"]


async def join_room(url: str, code: str) -> tuple:
    ws = await websockets.connect(url)
    await ws.send(json.dumps({"type": "join_room", "code": code}))
    resp = json.loads(await ws.recv())
    assert resp["type"] == "room_joined"
    return ws, resp["peer_id"]


async def join_room_token(url: str, code: str, token: str) -> tuple:
    ws = await websockets.connect(url)
    await ws.send(json.dumps({"type": "join_room", "code": code, "token": token}))
    resp = json.loads(await ws.recv())
    assert resp["type"] == "room_joined"
    return ws, resp["peer_id"]


async def drain(ws, timeout: float = 0.3) -> None:
    """Consume any pending messages on a socket without asserting their content."""
    try:
        while True:
            await asyncio.wait_for(ws.recv(), timeout=timeout)
    except (asyncio.TimeoutError, websockets.exceptions.ConnectionClosed):
        return


# ============================================================================
# Guest churn: repeated join/drop must not corrupt peer-id accounting or leak
# ============================================================================


class TestGuestChurn:
    async def test_repeated_join_drop_keeps_peer_ids_monotonic(self, relay):
        """A guest that joins and drops many times: each join gets a fresh,
        strictly increasing peer_id; the room survives; nothing leaks."""
        server, url = relay
        host_ws, code, _ = await create_room(url)

        last_id = 1
        for _ in range(15):
            guest_ws, guest_id = await join_room(url, code)
            assert guest_id > last_id, "peer ids must be strictly increasing"
            last_id = guest_id
            await drain(host_ws)  # host sees peer_connected
            await guest_ws.close()
            await asyncio.sleep(0.05)
            await drain(host_ws)  # host sees peer_disconnected

        # Room still alive, host still present, only the host remains.
        assert code in server.rooms
        assert list(server.rooms[code].peers.keys()) == [1]
        await host_ws.close()

    async def test_returning_guest_reclaims_its_peer_id(self, relay):
        """A guest that drops and rejoins with the SAME identity token reclaims its old
        peer_id (stable transport id across a reconnect); a different token gets a fresh id."""
        server, url = relay
        host_ws, code, _ = await create_room(url)

        guest_ws, first_id = await join_room_token(url, code, "tok-A")
        await drain(host_ws)
        await guest_ws.close()
        await asyncio.sleep(0.05)
        await drain(host_ws)  # relay records the departed (token -> id)

        # Same token within the rejoin window -> the SAME peer_id back.
        guest_ws2, reused_id = await join_room_token(url, code, "tok-A")
        assert reused_id == first_id, "a returning guest must reclaim its old peer_id"
        await drain(host_ws)
        await guest_ws2.close()
        await asyncio.sleep(0.05)
        await drain(host_ws)

        # A DIFFERENT token -> a fresh id (never reuse across identities).
        guest_ws3, other_id = await join_room_token(url, code, "tok-B")
        assert other_id != first_id, "a different token must get a fresh id"
        await guest_ws3.close()
        await host_ws.close()

    async def test_simultaneous_guests_then_all_drop(self, relay):
        """Several guests connected at once, then all leave: room collapses to
        just the host, peer dict stays consistent."""
        server, url = relay
        host_ws, code, _ = await create_room(url)
        guests = []
        for _ in range(5):
            gws, gid = await join_room(url, code)
            guests.append((gws, gid))
        await drain(host_ws)
        assert len(server.rooms[code].peers) == 6  # host + 5

        for gws, _ in guests:
            await gws.close()
        await asyncio.sleep(0.2)
        await drain(host_ws)
        assert list(server.rooms[code].peers.keys()) == [1]
        await host_ws.close()


# ============================================================================
# Host drop -> rejoin cascade: repeated, must reclaim peer_id 1 each time
# ============================================================================


class TestHostRejoinCascade:
    async def test_host_drops_and_rejoins_repeatedly(self, relay):
        """Host drops and a fresh connection reclaims the room (peer_id 1) over
        and over. The room must persist and never leak across cycles."""
        server, url = relay
        host_ws, code, _ = await create_room(url)
        guest_ws, guest_id = await join_room(url, code)
        await drain(host_ws)
        await drain(guest_ws)

        for _ in range(8):
            await host_ws.close()
            await asyncio.sleep(0.1)
            # Guest is told the host paused.
            assert json.loads(await guest_ws.recv())["type"] == "host_paused"

            # New connection reclaims peer_id 1.
            host_ws = await websockets.connect(url)
            await host_ws.send(json.dumps({"type": "join_room", "code": code}))
            resp = json.loads(await host_ws.recv())
            assert resp["type"] == "room_rejoined_host"
            assert resp["peer_id"] == 1
            assert server.rooms[code].host_disconnected_at == 0.0
            await drain(host_ws)
            await drain(guest_ws)

        assert len(server.rooms) == 1
        assert 1 in server.rooms[code].peers
        await host_ws.close()
        await guest_ws.close()

    async def test_room_dies_if_host_misses_window(self, relay):
        """If the host does not return within the rejoin window, the room is
        cleaned up and the waiting guest is told."""
        server, url = relay
        host_ws, code, _ = await create_room(url)
        guest_ws, _ = await join_room(url, code)
        await drain(host_ws)
        await drain(guest_ws)

        await host_ws.close()
        await asyncio.sleep(0.1)
        await drain(guest_ws)  # host_paused

        server.rooms[code].host_disconnected_at = (
            asyncio.get_event_loop().time() - HOST_REJOIN_WINDOW_SECONDS - 1
        )
        closed = await server._close_abandoned_rooms()
        assert code in closed
        assert code not in server.rooms
        await guest_ws.close()


# ============================================================================
# Rate limit: firing closes the peer (4429), and the server recovers
# ============================================================================


class TestRateLimitRecovery:
    def test_rate_limit_logic_fires_then_recovers(self):
        """The sliding-window limiter allows up to the cap within 1 s, blocks the
        next, and recovers once the old timestamps age out (deterministic)."""
        server = RelayServer()
        peer = MagicMock()
        peer.peer_id = 1
        peer.message_timestamps = []

        for _ in range(RATE_LIMIT_MESSAGES_PER_SECOND):
            assert server._check_rate_limit(peer) is True
        # One past the cap within the same window -> blocked.
        assert server._check_rate_limit(peer) is False

        # Age every recorded timestamp past the 1 s window -> allowed again.
        peer.message_timestamps = [t - 2.0 for t in peer.message_timestamps]
        assert server._check_rate_limit(peer) is True

    # NOTE: the end-to-end "flood -> 4429 close" path is covered indirectly: the
    # limiter logic is verified above, the identical `close(4429, ...)` call is
    # verified at connect-time in TestIpLimitChurn, and server recovery after a
    # peer drop is verified in TestGuestChurn / TestHostRejoinCascade. A direct
    # self-flood e2e is intentionally omitted — under a client that floods without
    # reading, the WebSocket close handshake can't complete, which tests the
    # client library's backpressure, not the relay.


# ============================================================================
# IP connection limit: at capacity, then recovers after one drops
# ============================================================================


class TestIpLimitChurn:
    async def test_at_capacity_then_slot_frees_after_drop(self, relay):
        """Exactly MAX_CONNECTIONS_PER_IP succeed; the next is rejected (4429);
        after one drops, a new connection succeeds again."""
        server, url = relay
        conns = []
        for _ in range(MAX_CONNECTIONS_PER_IP):
            conns.append(await websockets.connect(url))
        await asyncio.sleep(0.1)
        assert server.ip_connection_counts.get("127.0.0.1") == MAX_CONNECTIONS_PER_IP

        # One over the limit: accepted at TCP, then closed with 4429.
        over = await websockets.connect(url)
        close_code = None
        try:
            await drain(over, timeout=1.0)
        except websockets.exceptions.ConnectionClosed as exc:
            close_code = exc.code
        if close_code is None:
            close_code = over.close_code
        assert close_code == 4429

        # Free one slot -> a fresh connection succeeds.
        await conns.pop().close()
        await asyncio.sleep(0.1)
        assert server.ip_connection_counts.get("127.0.0.1") == MAX_CONNECTIONS_PER_IP - 1
        recovered = await websockets.connect(url)
        await recovered.send(json.dumps({"type": "create_room"}))
        assert json.loads(await recovered.recv())["type"] == "room_created"

        await recovered.close()
        for ws in conns:
            await ws.close()


# ============================================================================
# Broadcast ordering under burst: all messages arrive, in order, no loss
# ============================================================================


class TestBroadcastOrdering:
    async def test_burst_broadcast_preserves_order_and_count(self, relay):
        """The host fires a rapid burst of broadcasts; the guest receives all of
        them, in order, with none dropped or reordered."""
        server, url = relay
        host_ws, code, _ = await create_room(url)
        guest_ws, _ = await join_room(url, code)
        await drain(host_ws)
        await drain(guest_ws)

        count = 300
        for i in range(count):
            await host_ws.send(struct.pack(">i", 0) + struct.pack(">i", i))

        received = []
        for _ in range(count):
            frame = await asyncio.wait_for(guest_ws.recv(), timeout=2.0)
            received.append(struct.unpack(">i", frame[4:8])[0])

        assert received == list(range(count)), "messages lost or reordered"
        await host_ws.close()
        await guest_ws.close()


# ============================================================================
# Heartbeat survives a message burst (not starved by game traffic)
# ============================================================================


class TestHeartbeatUnderLoad:
    async def test_heartbeat_acked_after_burst(self, relay):
        """After a burst of game messages (below the rate limit), a heartbeat is
        still acknowledged -- the control path is not starved."""
        server, url = relay
        host_ws, code, _ = await create_room(url)
        guest_ws, _ = await join_room(url, code)
        await drain(host_ws)
        await drain(guest_ws)

        for i in range(200):
            await host_ws.send(struct.pack(">i", 0) + struct.pack(">i", i))

        await host_ws.send(json.dumps({"type": "heartbeat"}))
        got_ack = False
        try:
            for _ in range(250):  # skip any echoed game frames, find the ack
                msg = await asyncio.wait_for(host_ws.recv(), timeout=2.0)
                if isinstance(msg, str) and json.loads(msg).get("type") == "heartbeat_ack":
                    got_ack = True
                    break
        except asyncio.TimeoutError:
            pass
        assert got_ack, "heartbeat was not acked after a game-message burst"
        await host_ws.close()
        await guest_ws.close()


# ============================================================================
# Head-of-line block: a wedged slow consumer must not starve others' heartbeats
# (the live-game collapse root cause — relay must not await fan-out sends inline)
# ============================================================================


class _WedgedWS:
    """A websocket whose send() never completes — a fully back-pressured (wedged) slow consumer.
    Reproducing real TCP backpressure on loopback is unreliable (the client library reads ahead into
    its own queue and OS buffers are large), so we model the worst case directly: a send that parks
    forever, exactly what drain() does when a peer stops reading."""

    async def send(self, data) -> None:
        await asyncio.Event().wait()  # never set -> parks the caller forever


class _SinkWS:
    """A websocket that accepts and discards sends instantly (a healthy fast consumer)."""

    async def send(self, data) -> None:
        return


class TestSlowConsumerHeadOfLine:
    async def test_broadcast_does_not_await_a_wedged_peer(self, relay):
        """Fan-out must NOT block the relay's per-connection recv loop on a slow consumer's send —
        that head-of-line block starved heartbeat_acks and collapsed a live game (a 2-PC playtest game).
        With the per-peer send queue, _handle_binary_message enqueues and returns immediately even
        though one peer's socket never drains; the old inline `await peer.websocket.send()` hangs here."""
        server, _ = relay
        room = Room(code="HOLTST")
        host = Peer(websocket=_SinkWS(), peer_id=1, room_code="HOLTST", ip_address="h")
        wedged = Peer(websocket=_WedgedWS(), peer_id=2, room_code="HOLTST", ip_address="w")
        room.peers = {1: host, 2: wedged}
        server.rooms["HOLTST"] = room

        # A broadcast from the host fans out to the wedged peer. It must return promptly (the wedged
        # peer's writer task parks alone) rather than hang the shared recv loop.
        frame = struct.pack(">i", 0) + b"state-update"
        await asyncio.wait_for(server._handle_binary_message(host, frame), timeout=2.0)

        if wedged.writer_task is not None:
            wedged.writer_task.cancel()


class TestSlowConsumerLiveHeartbeat:
    async def test_wedged_guest_does_not_starve_host_heartbeat_live(self, relay):
        """End-to-end companion to the unit test above: with a guest whose read pump is throttled
        (max_queue=1) and never reads, the host's heartbeat is still acked over a real socket."""
        server, url = relay
        host_ws, code, _ = await create_room(url)
        slow_ws = await websockets.connect(url, max_queue=1)
        await slow_ws.send(json.dumps({"type": "join_room", "code": code}))
        assert json.loads(await slow_ws.recv())["type"] == "room_joined"
        await drain(host_ws)

        big = b"z" * 131072
        for i in range(40):
            await host_ws.send(struct.pack(">i", 0) + struct.pack(">i", i) + big)

        await host_ws.send(json.dumps({"type": "heartbeat"}))
        got_ack = False
        try:
            for _ in range(20):
                msg = await asyncio.wait_for(host_ws.recv(), timeout=2.0)
                if isinstance(msg, str) and json.loads(msg).get("type") == "heartbeat_ack":
                    got_ack = True
                    break
        except asyncio.TimeoutError:
            pass
        assert got_ack, "a wedged slow consumer starved the host's heartbeat_ack"

        await host_ws.close()
        await slow_ws.close()
