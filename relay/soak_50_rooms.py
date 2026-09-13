#!/usr/bin/env python3
"""50-room relay soak: CPU room-cost, RSS and throughput of the relay process.

Starts relay_server.py on a free loopback port, opens 50 rooms x 2 peers (100
sockets) over 11 loopback IPs (<= 10 per IP), drives 20 msg/s per room for
--seconds, then samples /proc CPU ticks + VmRSS and /stats. Prints ONE JSON
line; exit 0 = every room kept 2 peers.

Usage: cd relay && python soak_50_rooms.py [--seconds 30]
"""

import argparse
import asyncio
import json
import os
import queue
import socket
import struct
import subprocess
import sys
import threading
import time
import urllib.request

import websockets

ROOMS = 50
PEERS_PER_ROOM = 2
SOURCE_IPS = [f"127.0.0.{i}" for i in range(1, 12)]
MSGS_PER_SECOND_PER_ROOM = 20


def free_port() -> int:
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def cpu_ticks(pid: int) -> int:
    """utime + stime (fields 14/15 of /proc/<pid>/stat, after the last ')')."""
    with open(f"/proc/{pid}/stat", "rb") as handle:
        fields = handle.read().decode().rpartition(")")[2].split()
    return int(fields[11]) + int(fields[12])


def rss_kib(pid: int) -> int:
    with open(f"/proc/{pid}/status") as handle:
        return next((int(line.split()[1]) for line in handle if line.startswith("VmRSS:")), 0)


def fetch_stats(port: int) -> dict:
    with urllib.request.urlopen(f"http://127.0.0.1:{port}/stats", timeout=10) as response:
        return json.loads(response.read())


def start_relay(port: int) -> subprocess.Popen:
    process = subprocess.Popen(
        [sys.executable, "relay_server.py", "--host", "127.0.0.1", "--port", str(port)],
        cwd=os.path.dirname(os.path.abspath(__file__)),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    lines: queue.Queue = queue.Queue()

    def pump() -> None:
        for line in process.stdout:
            lines.put(line)

    threading.Thread(target=pump, daemon=True).start()
    deadline = time.monotonic() + 10.0
    while time.monotonic() < deadline:
        if process.poll() is not None:
            raise RuntimeError(f"relay exited during startup rc={process.returncode}")
        try:
            line = lines.get(timeout=0.1)
        except queue.Empty:
            continue
        if "Relay server started" in line:
            return process
    process.kill()
    raise RuntimeError("relay did not print 'Relay server started' within 10 s")


async def open_pair(port: int, ip: str) -> tuple:
    """One room: host creates it, a guest joins -- both from source IP ``ip``."""
    host = await websockets.connect(f"ws://127.0.0.1:{port}", local_addr=(ip, 0))
    await host.send(json.dumps({"type": "create_room"}))
    code = json.loads(await host.recv())["code"]
    guest = await websockets.connect(f"ws://127.0.0.1:{port}", local_addr=(ip, 0))
    await guest.send(json.dumps({"type": "join_room", "code": code}))
    response = json.loads(await guest.recv())
    assert response["type"] == "room_joined", response
    return host, guest


async def count_incoming(ws, counter: list) -> None:
    try:
        async for _message in ws:
            counter.append(1)
    except websockets.exceptions.ConnectionClosed:
        pass


async def drive(host, guest, seconds: float, sent: list) -> None:
    """Alternate host/guest sends at 20 msg/s per room (same frame shape as the burst test)."""
    interval = 1.0 / MSGS_PER_SECOND_PER_ROOM
    deadline = time.monotonic() + seconds
    sequence = 0
    while time.monotonic() < deadline:
        peer = host if sequence % 2 == 0 else guest
        await peer.send(struct.pack(">i", 0) + struct.pack(">i", sequence))
        sent.append(1)
        sequence += 1
        await asyncio.sleep(interval)


async def run_soak(port: int, pid: int, seconds: float) -> dict:
    pairs, sent, received, readers = [], [], [], []
    try:
        for index in range(ROOMS):
            pairs.append(await open_pair(port, SOURCE_IPS[index % len(SOURCE_IPS)]))
        readers = [asyncio.create_task(count_incoming(ws, received)) for pair in pairs for ws in pair]
        stats_before = fetch_stats(port)
        ticks_before, rss_before = cpu_ticks(pid), rss_kib(pid)
        started = time.monotonic()
        await asyncio.gather(*(drive(host, guest, seconds, sent) for host, guest in pairs))
        elapsed = time.monotonic() - started
        ticks_after, rss_after = cpu_ticks(pid), rss_kib(pid)
        stats_after = fetch_stats(port)

        return {
            "rooms": ROOMS,
            "peers_per_room": PEERS_PER_ROOM,
            "source_ips": len(SOURCE_IPS),
            "seconds": round(elapsed, 3),
            "messages_sent": len(sent),
            "messages_received": len(received),
            "msgs_per_second": round(len(sent) / elapsed, 1),
            "cpu_ticks_delta": ticks_after - ticks_before,
            "cpu_percent_one_core": round((ticks_after - ticks_before) / os.sysconf("SC_CLK_TCK") / elapsed * 100, 2),
            "rss_kib_before": rss_before,
            "rss_kib_after": rss_after,
            "stats_before": stats_before,
            "stats_after": stats_after,
            "rooms_lost": stats_before["rooms_open"] - stats_after["rooms_open"],
            "peers_lost": stats_before["peers_connected"] - stats_after["peers_connected"],
            "complete": stats_after["rooms_open"] == ROOMS and stats_after["peers_connected"] == ROOMS * PEERS_PER_ROOM,
        }
    finally:
        for task in readers:
            task.cancel()
        for host, guest in pairs:
            for ws in (host, guest):
                await ws.close()
        await asyncio.gather(*readers, return_exceptions=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seconds", type=float, default=30.0, help="traffic duration (default 30)")
    args = parser.parse_args()

    port = free_port()
    process = start_relay(port)
    try:
        result = asyncio.run(run_soak(port, process.pid, args.seconds))
    finally:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()

    print(json.dumps(result, sort_keys=True))
    return 0 if result["complete"] else 1


if __name__ == "__main__":
    sys.exit(main())
