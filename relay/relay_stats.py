#!/usr/bin/env python3
"""Print the relay's anonymous usage stats (totals + peaks, no IPs/codes/names).

Connects, asks the relay for its stats, prints them, disconnects.

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
    print(f"  peer connections     : {stats.get('peer_connections', 0)}  (incl. reconnects)")
    print(f"  peak players at once : {stats.get('peak_concurrent_peers', 0)}")
    print(f"  peak rooms at once   : {stats.get('peak_concurrent_rooms', 0)}")
    print(f"  live now             : {stats.get('rooms_open', 0)} room(s), {stats.get('peers_connected', 0)} peer(s)")
    print(f"  last updated         : {stats.get('last_updated') or 'n/a'}")


if __name__ == "__main__":
    main()
