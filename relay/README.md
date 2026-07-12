# Niemandsland Relay Server

A lightweight WebSocket relay that enables **internet multiplayer** without players
needing port forwarding. It forwards game messages between peers in the same room and
deliberately understands **no game logic** — it only routes bytes.

The game connects to it through `scripts/relay_multiplayer_peer.gd` (a custom Godot
`MultiplayerPeer`). One peer creates a room and becomes host (`peer_id = 1`); others
join with the room code.

## Design

- **Rooms** with cryptographically random codes (`secrets`); host is peer 1.
- **Room expiration** after 4 hours; **rate limiting** on connections.
- Stateless w.r.t. gameplay — pure message relay (`create_room` / `join_room`
  control messages, then opaque payload forwarding).
- **Per-peer send queues** — each broadcast fan-out is enqueued to a per-peer queue drained by one
  writer task, so a slow consumer's back-pressure never parks the shared recv loop (which must keep
  acking heartbeats). Without this, one stalled peer false-dropped the whole room (see
  [`HOST_RECONNECT.md`](HOST_RECONNECT.md), 0.3.7 hardening).
- **Host reconnect** preserves the room briefly and lets ONLY the host's identity token reclaim peer 1
  (a guest can't seize the host slot); see [`HOST_RECONNECT.md`](HOST_RECONNECT.md).

## Usage stats (aggregate, no PII)

The relay counts how much it is used — the project keeps **no client telemetry**, so the relay's own
room metadata is the only usage signal. Everything is **anonymous and aggregate**: totals, peaks and
coarse histograms only — **never** IPs, room codes or player identities.

Counters (in `Stats`): rooms created, games played (rooms that reached ≥2 peers), peer connections,
server starts, join failures by reason (`room_full` / `room_not_found` / `server_full` /
`already_in_room` / `bad_code_format`), peak concurrent rooms & peers, a room-lifetime histogram
(`<10m` / `10–45m` / `45–120m` / `>120m`) and a peak-peers-per-room histogram. They persist to the
Fly volume (`RELAY_STATS_PATH`) so they survive scale-to-zero.

`games_played` is counted **live** the first time a room reaches ≥2 concurrent peers (once per room),
so it does not depend on the room ever closing. The two close-time histograms (room-lifetime and
peers-per-room) are recorded at **every** room-end path: a last-peer disconnect, the idle-expiry
reaper, the host-abandon reaper, **and** graceful server shutdown — the last of which folds any
still-open rooms into the histograms before exit, because on Fly a scale-to-zero / redeploy stop,
not a clean disconnect, is the dominant way a room ends. The only rooms still lost are those open at
a **hard** kill (`SIGKILL` / OOM / power loss), which runs no shutdown code.

Three ways to read them, all returning the same blob:

- **`GET /stats`** — public JSON over HTTPS (same listener as the WebSocket; no auth, like
  `list_rooms`): `curl https://niemandsland-relay.fly.dev/stats`.
- **`get_stats`** WebSocket control message — used by `relay_stats.py` (`python relay_stats.py`).
- **Hourly `STATS` log line** — one JSON line at INFO, prefixed `STATS`, captured by Fly's log
  stream so history survives restarts. `stats_digest.py` turns a captured log into a weekly digest:

  ```bash
  fly logs -a niemandsland-relay > relay.log
  python stats_digest.py relay.log
  ```

## Run locally

```bash
cd relay
python -m pip install -r requirements.txt   # websockets>=12.0
python relay_server.py --port 8765
```

Listens on port `8765`. Point the game's internet-lobby relay URL at
`ws://<host>:8765` (or `wss://` behind TLS).

## Tests

```bash
cd relay && python -m pytest        # pytest.ini sets asyncio_mode=auto
```

## Deploy

**Docker:**
```bash
docker build -t niemandsland-relay .
docker run -p 8765:8765 niemandsland-relay
```

**Fly.io** (`fly.toml`, app `niemandsland-relay`, internal port 8765, TLS-terminated):
```bash
fly deploy
```

## Files

| File | Purpose |
|---|---|
| `relay_server.py` | The relay (asyncio + `websockets`) — routing, rooms, `Stats`, `/stats` |
| `relay_stats.py` | CLI: query a relay's aggregate stats over WebSocket and print them |
| `stats_digest.py` | Parse captured `STATS` log lines into a weekly usage digest |
| `requirements.txt` | `websockets>=12.0` |
| `Dockerfile` | `python:3.11-slim`, runs `relay_server.py --port 8765` |
| `fly.toml` | Fly.io deployment config |
| `test_relay_server.py`, `conftest.py`, `pytest.ini` | Test suite |
