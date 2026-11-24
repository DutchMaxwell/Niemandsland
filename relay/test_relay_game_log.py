"""The anonymous per-game log (PRIVACY.md): one host `game_meta` per played game becomes one JSON
line in RELAY_GAMES_PATH with exactly ts / system / factions / players / version."""

import json
import re
from datetime import datetime, timedelta, timezone

import relay_server
from test_relay_server import create_room, join_room, relay  # noqa: F401  (fixture reused)

LINE_KEYS = {"ts", "system", "factions", "players", "version"}


def _meta(**over):
    msg = {"type": "game_meta", "system": "gf", "factions": ["orc_marauders", "alien_hives"],
           "players": 2, "version": "0.3.16.0"}
    msg.update(over)
    return msg


async def send_and_settle(ws, msg):
    """Send a control message, then a heartbeat; its ack proves the relay handled the first one."""
    await ws.send(json.dumps(msg))
    await ws.send(json.dumps({"type": "heartbeat"}))
    while json.loads(await ws.recv())["type"] != "heartbeat_ack":
        pass


async def played_room(url):
    host_ws, code, _ = await create_room(url)
    guest_ws, _ = await join_room(url, code)
    return host_ws, guest_ws, code


def read_lines(path):
    return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []


class TestGameMetaLine:
    async def test_host_meta_writes_exactly_one_line_with_the_allowed_keys(self, relay, tmp_path):
        server, url = relay
        server.games_path = str(tmp_path / "games.jsonl")
        host_ws, guest_ws, _ = await played_room(url)
        await send_and_settle(host_ws, _meta())

        lines = read_lines(tmp_path / "games.jsonl")
        assert len(lines) == 1
        assert set(lines[0]) == LINE_KEYS
        assert lines[0]["factions"] == ["alien_hives", "orc_marauders"]  # sorted
        assert (lines[0]["system"], lines[0]["players"], lines[0]["version"]) == ("gf", 2, "0.3.16.0")
        assert re.fullmatch(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}\+00:00", lines[0]["ts"]), lines[0]["ts"]
        assert server.stats.game_meta_rejected == 0
        await host_ws.close()
        await guest_ws.close()

    async def test_invalid_or_unauthorised_meta_is_dropped_and_counted(self, relay, tmp_path):
        server, url = relay
        server.games_path = str(tmp_path / "games.jsonl")
        lone_ws, _, _ = await create_room(url)
        await send_and_settle(lone_ws, _meta())  # a room nobody joined: not a played game
        host_ws, guest_ws, _ = await played_room(url)
        for bad in (_meta(name="someone"), _meta(winner="gf"), _meta(players=9), _meta(players=True),
                    _meta(factions=["two words"]), _meta(factions=["x"] * 9), _meta(factions="gf"),
                    _meta(system=""), _meta(version=3)):
            await send_and_settle(host_ws, bad)
        await send_and_settle(guest_ws, _meta())  # only the host reports
        assert read_lines(tmp_path / "games.jsonl") == []
        await send_and_settle(host_ws, _meta())
        await send_and_settle(host_ws, _meta())  # once per room
        assert len(read_lines(tmp_path / "games.jsonl")) == 1
        assert server.stats.game_meta_rejected == 12
        for ws in (lone_ws, host_ws, guest_ws):
            await ws.close()

    def test_lines_older_than_365_days_are_pruned_on_append(self, tmp_path):
        path = tmp_path / "games.jsonl"
        now = datetime(2026, 11, 24, 18, 7, 31, tzinfo=timezone.utc)
        record = relay_server._game_meta_record(_meta())
        for age in (366, 365, 3):
            relay_server.append_game_line(str(path), record, now=now - timedelta(days=age))
        relay_server.append_game_line(str(path), record, now=now)
        assert [line["ts"] for line in read_lines(path)] == [
            "2025-11-24T18:07+00:00", "2026-11-21T18:07+00:00", "2026-11-24T18:07+00:00"]

    def test_the_log_defaults_next_to_the_stats_file(self, monkeypatch):
        monkeypatch.delenv("RELAY_GAMES_PATH", raising=False)
        monkeypatch.setenv("RELAY_STATS_PATH", "/nonexistent-volume/stats.json")
        assert relay_server.RelayServer().games_path == "/nonexistent-volume/games.jsonl"


def test_games_digest_counts_days_versions_systems_and_factions():
    import games_digest

    lines = [json.dumps({"ts": "2026-11-24T18:07+00:00", "system": "gf", "players": 2,
                         "factions": ["alien_hives", "orcs"], "version": "0.3.16.0"}), "not json",
             json.dumps({"ts": "2026-11-25T09:00+00:00", "system": "aof", "players": 3,
                         "factions": ["orcs"], "version": "0.3.16.0"})]
    counts = games_digest.digest(lines)
    assert counts["days"] == {"2026-11-24": 1, "2026-11-25": 1}
    assert counts["versions"] == {"0.3.16.0": 2}
    assert counts["systems"] == {"gf": 1, "aof": 1}
    assert counts["factions"] == {"orcs": 2, "alien_hives": 1}
