#!/usr/bin/env python3
"""Print the relay's anonymous usage stats (totals, peaks + histograms; no IPs/codes/names).

Connects, asks the relay for its stats, prints them, disconnects. (For a machine-readable pull
without a WebSocket, GET https://niemandsland-relay.fly.dev/stats returns the same aggregates.)

Usage:
  python relay_stats.py                       # the public relay (wss://niemandsland-relay.fly.dev)
  python relay_stats.py ws://127.0.0.1:8765   # a local relay
"""
import asyncio
import json
import sys

import websockets

DEFAULT_URL = "wss://niemandsland-relay.fly.dev"


async def fetch_stats(url: str) -> dict:
    async with websockets.connect(url) as ws:
        await ws.send(json.dumps({"type": "get_stats"}))
        while True:
            reply = json.loads(await ws.recv())
            if reply.get("type") == "stats":
                return reply


def main() -> None:
    url = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_URL
    try:
        stats = asyncio.run(fetch_stats(url))
    except Exception as exc:  # noqa: BLE001 — a CLI tool: report any failure plainly
        print(f"Could not reach the relay at {url}: {exc}")
        sys.exit(1)
    print(f"Relay usage — {url}")
    print(f"  first seen           : {stats.get('first_seen') or 'n/a'}")
    print(f"  server starts        : {stats.get('server_starts', 0)}  (~ sessions; relay scales to zero)")
    print(f"  rooms created        : {stats.get('rooms_created', 0)}")
    print(f"  games played (>=2)   : {stats.get('games_played', 0)}  (rooms that reached 2+ peers)")
    print(f"  peer connections     : {stats.get('peer_connections', 0)}  (incl. reconnects)")
    print(f"  peak players at once : {stats.get('peak_concurrent_peers', 0)}")
    print(f"  peak rooms at once   : {stats.get('peak_concurrent_rooms', 0)}")

    join_failures = stats.get("join_failures", {}) or {}
    if sum(join_failures.values()):
        detail = ", ".join(f"{k} {v}" for k, v in sorted(join_failures.items()) if v)
        print(f"  join failures        : {sum(join_failures.values())}  ({detail})")

    lifetimes = stats.get("room_lifetime_buckets", {}) or {}
    if sum(lifetimes.values()):
        labels = [("lt_10min", "<10m"), ("10_45min", "10-45m"),
                  ("45_120min", "45-120m"), ("gt_120min", ">120m")]
        detail = ", ".join(f"{label} {lifetimes.get(key, 0)}" for key, label in labels)
        print(f"  room lifetimes       : {detail}")

    peers_per_room = stats.get("peers_per_room", {}) or {}
    if sum(peers_per_room.values()):
        detail = ", ".join(f"{v}x{k}p" for k, v in sorted(peers_per_room.items(), key=lambda kv: int(kv[0])) if v)
        print(f"  peers/room (peak)    : {detail}")

    print(f"  live now             : {stats.get('rooms_open', 0)} room(s), {stats.get('peers_connected', 0)} peer(s)")
    print(f"  last updated         : {stats.get('last_updated') or 'n/a'}")


if __name__ == "__main__":
    main()
