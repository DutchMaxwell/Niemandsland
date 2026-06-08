# Host-side reconnect (relay room preservation) — design + deploy plan

**Status:** specced, NOT yet implemented/deployed. Task #43.

## Why this is separate from the client reconnect (already shipped)

Guest reconnect already works without any relay change: a guest whose link drops
auto-rejoins the same room and the host re-syncs full game state
(`RelayMultiplayerPeer.attempt_reconnect` → version handshake → `_sync_state_to_peer`).

The missing piece is the **host** dropping. Today the relay deletes the room and boots
all guests the moment the host's socket closes (`relay_server.py` `_remove_connection`,
`peer_id == 1` branch). So a host whose Wi-Fi blips ends the game for everyone, and
`RelayMultiplayerPeer.attempt_reconnect` deliberately refuses for hosts
(`"host cannot rejoin"`), because the room is already gone.

This is a **two-sided protocol change** (relay server + client) that **must be tested
live** before deploying — the relay at `wss://niemandsland-relay.fly.dev` is the shared
service a second player is actively using, and an untested redeploy breaks MP for
everyone. It is intentionally not shipped blind.

## Server changes (`relay/relay_server.py`)

1. `const HOST_REJOIN_WINDOW_SECONDS = 20`.
2. `Room`: add `host_disconnected_at: float = 0.0` (0 = host present).
3. `_remove_connection`, host branch: instead of deleting the room + closing guest
   sockets, **preserve** the room when guests remain:
   - `room.host_disconnected_at = time.monotonic()`
   - send each guest `{"type":"host_paused"}` (new) — keep their sockets OPEN.
   - if no guests remain, delete the room as before.
4. `_handle_join_room`, **rehost detection** (additive): if `room.host_disconnected_at`
   is set and peer_id 1 is free, assign the joiner **peer_id 1**, clear
   `host_disconnected_at`, reply `{"type":"room_rejoined_host","peer_id":1}` (new), and
   send the guests `{"type":"peer_connected","peer_id":1}`. Otherwise the normal guest
   join is unchanged.
5. Faster expiry for an abandoned room: in `check_heartbeats` (runs every 10 s) delete
   any room with `host_disconnected_at > 0 and now - host_disconnected_at >
   HOST_REJOIN_WINDOW_SECONDS`, closing the remaining guests with a clear reason.

## Client changes (`scripts/relay_multiplayer_peer.gd` + `internet_lobby.gd` + `main.gd`)

1. Allow a host to rejoin: in `attempt_reconnect`, drop the `_is_server_relay()` refusal;
   reconnect and send `join_room` with the stored room code (the server decides rehost
   vs normal join from `host_disconnected_at`).
2. Handle `room_rejoined_host` like `room_created` (we are host again, peer_id 1) →
   `multiplayer.multiplayer_peer = relay_peer`; main re-syncs full state to the waiting
   guests via the existing `peer_version_validated` → `_sync_state_to_peer` path
   (lossless for the guests, who were never booted).
3. Handle `host_paused` on the guest: show "Host disconnected — waiting for reconnect…"
   (yellow) instead of treating it as a full disconnect; clear it when peer 1 returns.
4. Keep the `RECONNECT_TIMEOUT` abort so a host whose room already expired falls back to
   `relay_reconnect_failed`.

## Local test procedure (do this BEFORE deploying to fly.dev)

```
cd relay
python3 -m venv venv && ./venv/bin/pip install -r requirements.txt
./venv/bin/python relay_server.py            # local relay on ws://localhost:8765
```
Run two game instances, both pointed at `ws://localhost:8765` (the Join/Host dialog
takes a custom relay URL). Host + join, then:
- Kill the host instance's network (or the host process briefly) and restart/reconnect
  within 20 s → the guest should show "waiting for host", then resume with state intact.
- Wait >20 s → the guest should be cleanly dropped with "host did not return".
- Repeat the guest-drop case to confirm it still works.

## Deploy (only after the local test passes)

`fly deploy -c relay/fly.toml` (needs `flyctl`; not installed in the dev sandbox — run
it from a machine that has it, or via the relay's CI if configured). Smoke-test one
host+guest session against fly.dev afterwards.
