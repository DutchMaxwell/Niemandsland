"""Privacy baseline tests for the relay (plan §4 row 09-19 / §9 R11).

Pins the privacy contract:
- IPs may be held in memory for per-IP connection limiting, but must never reach the log
  stream and never be persisted; the retention bound is IP_RETENTION_DAYS (PRIVACY.md).
- A connected peer can ask for deletion of its IP data with {"type": "delete_data"} and
  gets {"type": "data_deleted"} back; an unknown caller gets a clean error, never a crash.
- The aggregate stats payload and the rooms_list browser reply carry no PII.
"""

import asyncio
import json
import logging
import re
from pathlib import Path

import websockets

from test_relay_server import (  # noqa: F401  (the relay fixture is reused on purpose)
    create_public_room,
    create_room,
    join_room,
    list_rooms,
    relay,
)

PII_KEY_PATTERN = re.compile(r"ip|address|name|token", re.IGNORECASE)
FORBIDDEN_IP_STRINGS = ("127.0.0.1", "::1")


def _all_keys(obj):
    """Yield every dict key in obj, recursively."""
    if isinstance(obj, dict):
        for key, value in obj.items():
            yield key
            yield from _all_keys(value)


def _relay_log_text(caplog) -> str:
    """The formatted messages of every record emitted by the relay logger."""
    return "\n".join(
        record.getMessage() for record in caplog.records if record.name == "relay"
    )


class TestNoPiiInLogs:
    """IPs may back the in-memory per-IP limit, but must never be logged."""

    async def test_logs_never_contain_peer_ip(self, relay, caplog):
        _server, url = relay
        host_token = "privacy-test-host-token"
        with caplog.at_level(logging.INFO, logger="relay"):
            host_ws = await websockets.connect(url)
            await host_ws.send(json.dumps({"type": "create_room", "token": host_token}))
            code = json.loads(await host_ws.recv())["code"]
            guest_ws, _guest_id = await join_room(url, code)
            await host_ws.recv()   # host: peer_connected(guest)
            await guest_ws.recv()  # guest: peer_connected(host)

            # Host drop + token rejoin exercise the third IP-bearing log line.
            await host_ws.close()
            await asyncio.sleep(0.1)
            assert json.loads(await guest_ws.recv())["type"] == "host_paused"
            rehost_ws = await websockets.connect(url)
            await rehost_ws.send(
                json.dumps({"type": "join_room", "code": code, "token": host_token})
            )
            assert json.loads(await rehost_ws.recv())["type"] == "room_rejoined_host"
            await rehost_ws.close()
            await guest_ws.close()

        text = _relay_log_text(caplog)
        assert text, "create + join + rejoin must have produced relay log records"
        for forbidden in FORBIDDEN_IP_STRINGS:
            assert forbidden not in text, f"peer IP leaked into the log stream: {forbidden!r}"


class TestAnonymousAggregates:
    """Stats payload and room browser replies are aggregate-only."""

    async def test_stats_payload_and_list_json_have_no_pii(self, relay, caplog):
        server, url = relay
        leaked = [key for key in _all_keys(server._stats_payload())
                  if PII_KEY_PATTERN.search(key)]
        assert leaked == [], f"PII-looking key(s) in stats payload: {leaked}"

        ws, code, _ = await create_public_room(url)
        caplog.clear()
        with caplog.at_level(logging.INFO, logger="relay"):
            rooms = await list_rooms(url)
            assert any(room["code"] == code for room in rooms)
            server.log_stats_line()  # the periodic aggregate line, emitted here on purpose
        text = _relay_log_text(caplog)
        assert text, "the STATS log line must be emitted"
        assert "rooms_list" not in text
        assert code not in text
        await ws.close()


class TestDeleteData:
    """The delete_data control message removes the caller's IP from every in-memory record."""

    async def test_delete_data_endpoint(self, relay):
        server, url = relay
        host_ws, code, _ = await create_room(url)
        guest_ws, _guest_id = await join_room(url, code)
        await host_ws.recv()   # host: peer_connected(guest)
        await guest_ws.recv()  # guest: peer_connected(host)

        caller_ip = next(iter(server.ip_connection_counts))
        assert any(peer.ip_address == caller_ip for peer in server.connections.values())

        await guest_ws.send(json.dumps({"type": "delete_data"}))
        reply = json.loads(await guest_ws.recv())
        assert reply == {"type": "data_deleted"}

        assert caller_ip not in server.ip_connection_counts
        assert all(peer.ip_address == "" for peer in server.connections.values())

        # An unknown caller (never joined a room) gets a clean error, not a crash.
        stranger = await websockets.connect(url)
        await stranger.send(json.dumps({"type": "delete_data"}))
        error = json.loads(await stranger.recv())
        assert error["type"] == "error"
        assert error.get("reason") == "no_data"

        await stranger.close()
        await host_ws.close()
        await guest_ws.close()


class TestRetentionBound:
    """The IP retention bound exists, is documented, and no IP reaches disk."""

    def test_ip_retention_bounded(self, tmp_path):
        import relay_server

        assert relay_server.IP_RETENTION_DAYS == 30

        policy = Path(__file__).with_name("PRIVACY.md")
        assert policy.is_file(), "relay/PRIVACY.md must document the privacy baseline"
        text = policy.read_text(encoding="utf-8")
        assert "30" in text
        assert "delete_data" in text
        readme = Path(__file__).with_name("README.md").read_text(encoding="utf-8")
        assert "PRIVACY.md" in readme

        stats_path = tmp_path / "stats.json"
        stats = relay_server.Stats(str(stats_path))
        stats.boot()
        stats.room_created(rooms_open=1)
        stats.peer_connected(peers_connected=2)
        saved = json.loads(stats_path.read_text(encoding="utf-8"))
        assert "ip" not in saved
        assert not any("ip" in key.lower() or "address" in key.lower()
                       for key in _all_keys(saved))