# Battlefield Atmosphere

One-click battlefield moods plus optional war-torn dressing, orchestrated by
`scripts/atmosphere_controller.gd` (created by `main.gd`, surfaced in the Settings
window's ATMOSPHERE section). Everything is a **per-player preference** (like the
lighting panel, not multiplayer-synced); state persists to `user://atmosphere.cfg`.

## Presets

Each atmosphere preset bundles a lighting preset (`lighting_controller.gd` stays the
single source of truth for light values — including the new "Night" and "Storm"
entries) with sky mood, ground-mist tint/density and the rain/lightning/audio layers.
Switching blends lighting + sky + mist over 2 s (`TRANSITION_SECONDS`); rain and rain
audio fade internally; grabbing a lighting slider cancels a running blend.

| Preset | Lighting | Sky (stars/nebula) | Mist | Rain | Lightning + thunder |
|---|---|---|---|---|---|
| Day | Default | 1.2 / 0.35 | white, ×1.0 | – | – |
| Sunset | Warm Sunset | 1.8 / 0.55 | warm, ×1.0 | – | – |
| Night | Night | 3.2 / 0.7 | cool, ×1.1 | – | – |
| Overcast | Cool Overcast | 0.8 / 0.3 | grey, ×1.3 | – | – |
| Rain | Storm | 0.5 / 0.25 | dark grey, ×1.5 | ✓ | every 8–25 s, thunder 0.5–3 s later |

Rain is one table-sized `GPUParticles3D` box (`scripts/rain_effect.gd`), resized via
the `table_resized` flow; drop count scales with table area and quality tier (and is
halved on web). Lightning flashes a **dedicated** `DirectionalLight3D` — never the sun,
so a flash cannot corrupt a running preset blend; the matching thunder plays after the
flash-to-thunder delay, quieter the longer the delay.

## War-torn fires (toggle)

`terrain_overlay.set_fires_enabled(true)` dresses ~22 % of ruin wall cells with a
`FireProp` (`scripts/fire_prop.gd`): additive flame particles (~1.5 cm), a rising smoke
column and a flickering warm OmniLight. **Determinism contract**: the per-segment pick
(`TerrainOverlay.segment_has_fire`) uses a *fresh* RNG seeded from the synced segment
identity XOR `_RUIN_SEED_SALT_FIRE` — it must never consume draws from the panel RNG,
or every window/doorway pick would change (pinned by `test/fire_placement_test.gd`).
All clients therefore see fires at the same cells whenever their local toggle is on.
Placement reuses the walls' own `_segment_world_placement` math, so fires can never
drift from their walls.

## Audio: CC0 recordings with a procedural fallback

The soundscape prefers **real CC0 recordings** (freesound.org, exact sources +
licenses documented in `tools/model_forge/fetch_ambience_audio.py`): two artillery
and two machine-gun one-shots, two thunders, a rain loop and a campfire crackle loop,
delivered on demand from R2 (`assets/ambience_manifest.json` + `ambience_library.gd`,
cache `user://ambience_cache`) and hot-swapped in once cached. Until then (or
offline) `scripts/ambience_synth.gd` provides procedural stand-ins as 16-bit mono
`AudioStreamWAV` (seed-deterministic, tested). `scripts/war_ambience.gd` plays
everything on the **Ambience bus** (existing volume slider applies): distant war
one-shots every 20–60 s (first one 2–6 s after enabling) from a random direction on
a 7 m ring (`AudioStreamPlayer3D`, the camera is the listener), plus up to 4
positional crackle emitters parked on the first fires (refreshed on `fires_rebuilt`).

CC0 sources: "R12-31-Artillery Guns Firing" + "S20-23 distant Bren machine gun"
(craigsmith), "Explosion Distant" (Johnnyfarmer), "Distant Machine Gun Firing"
(qubodup), "Long Rumbling Thunder" (billgrip), "thunder rumble 1" (FenrirFangs),
"Soft Rain Loop" (_lynks), "Campfire 01" (HECKFRICKER) — all CC0 1.0, no attribution
required (credited anyway).

## Quality gating

| Tier | Fires | Fire lights | Smoke | Rain drops |
|---|---|---|---|---|
| PERFORMANCE | none | 0 | – | ×0.25 |
| LOW | ✓ | 4 | – | ×0.5 |
| MEDIUM | ✓ | 8 | ✓ | ×1.0 |
| HIGH / ULTRA | ✓ | 12 | ✓ | ×1.25 |

Re-gated live via `GraphicsSettings.settings_applied`. Flames stay readable without
glow (opaque bright core; PERFORMANCE/LOW disable glow).

## Future

- Multiplayer sync: `apply_atmosphere(name)` is the single entry point — broadcasting
  the preset name over one RPC makes the mood host-shared if ever wanted.
- More layers per preset (wind-driven mist drift, snow for tundra, embers).
