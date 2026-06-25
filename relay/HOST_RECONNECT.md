# Host-side reconnect (relay room preservation) — design + deploy plan

**Status:** ✅ IMPLEMENTED + DEPLOYED to Fly.io. **HARDENED in 0.3.7-alpha (2026-06-25)** after a
real 2-PC game collapsed into a reconnect storm + desync — see the **0.3.7 hardening** section below,
which **supersedes** the "first joiner reclaims" rule described in the original design.

The server + client match the design below: a host drop preserves the room for
`HOST_REJOIN_WINDOW_SECONDS` and sends each guest `host_paused`; the host reclaims peer id 1 via
`room_rejoined_host`, the relay re-announces every peer to the rejoined host, and the existing
version-handshake → `_sync_state_to_peer` path re-syncs full state to the waiting guests. An abandoned
room is torn down past the window with "Host did not return". Both host and guest auto-rejoin on a drop.

## 0.3.7 hardening (2026-06-25) — reconnect-storm + desync fix

Diagnosed from both players' diagnostics dumps of a real game (relay build 56b8bba). Causal chain:
relay head-of-line block → bilateral heartbeat false-drops → reconnect storm → host lost peer 1 → desync.

1. **Trigger — relay head-of-line block (the big one).** The relay serviced each socket in ONE
   coroutine that also `await`-ed every broadcast fan-out inline, so a single slow consumer's WebSocket
   `drain()` back-pressure parked that coroutine → it stopped reading heartbeats → no `heartbeat_ack` →
   both sides false-dropped at the 35 s timeout despite a live link. **Fix:** the fan-out now ENQUEUES
   to a per-peer `asyncio.Queue` drained by one writer task per peer (`_enqueue` / `_peer_writer`,
   `SEND_QUEUE_MAX`), so a slow peer parks only its own writer, never the shared recv loop. Client side:
   `_last_ack_ms` is refreshed by ANY inbound frame, not only `heartbeat_ack`.
2. **Host reclaim is now TOKEN-GATED (supersedes "first joiner reclaims").** The old rule let the FIRST
   rejoiner — possibly a racing guest — seize peer 1 + the host role, demoting the real host to a guest
   and orphaning the authoritative state = the desync. Now the host's reconnect token is stored as
   `Room.host_token` (threaded through `create_room`), and ONLY a matching token reclaims peer 1; a
   lingering half-open old peer-1 socket is evicted so the real host reclaims at once. A room created by
   a **legacy 0.3.6.0 host** (no token → `host_token == ""`) falls back to the old first-joiner path, so
   deploying this relay never breaks in-flight old-client sessions (cross-version play is already blocked
   by the version handshake).
3. **Version-kick guard.** `enforce_version_handshake_timeout` never kicks a SUPERSEDED peer id (its slot
   rebound to a new id) — stopping the kick-cascade amplifier.

Regression coverage: a relay head-of-line unit test (a wedged peer must not block the recv loop), a
"non-host token cannot seize the host slot" test, and a legacy-tokenless-host-rejoin test.

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

First, the unit tests (already passing — run them after any further change):
```
cd relay
python3 -m venv venv && ./venv/bin/pip install -r requirements.txt pytest pytest-asyncio
./venv/bin/python -m pytest -q                # expect 38 passed
```
Then the manual two-instance test against a local relay:
```
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
