# OpenTTS Relay Server

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
docker build -t opentts-relay .
docker run -p 8765:8765 opentts-relay
```

**Fly.io** (`fly.toml`, app `opentts-relay`, internal port 8765, TLS-terminated):
```bash
fly deploy
```

## Files

| File | Purpose |
|---|---|
| `relay_server.py` | The relay (asyncio + `websockets`) |
| `requirements.txt` | `websockets>=12.0` |
| `Dockerfile` | `python:3.11-slim`, runs `relay_server.py --port 8765` |
| `fly.toml` | Fly.io deployment config |
| `test_relay_server.py`, `conftest.py`, `pytest.ini` | Test suite |
