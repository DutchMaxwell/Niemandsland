# Documentation index

Start with the repo entry points: [`../README.md`](../README.md) (project overview) ·
[`../PROJECT_STATUS.md`](../PROJECT_STATUS.md) (what works) ·
[`ROADMAP.md`](ROADMAP.md) (what's planned) ·
[`../CHANGELOG.md`](../CHANGELOG.md) (history). This folder holds the deeper technical docs.

## Core

| Doc | Contents |
|---|---|
| [`../PROJECT_STATUS.md`](../PROJECT_STATUS.md) | What works / in progress |
| [`ROADMAP.md`](ROADMAP.md) | Prioritized plan + how feature requests flow |
| [`ROAD_TO_ALPHA.md`](ROAD_TO_ALPHA.md) | The `0.3.6` Alpha release plan & checklist |
| [`KNOWN_ISSUES.md`](KNOWN_ISSUES.md) | Honest alpha limitations & caveats |
| [`ARCHITECTURE.md`](ARCHITECTURE.md) | Systems, scripts, data flow, networking, scaling |
| [`DEVELOPMENT.md`](DEVELOPMENT.md) | Build, run, test (Godot 4.6 / Flatpak / gdUnit4) |
| [`../.claude/AAA_CODING_STANDARDS.md`](../.claude/AAA_CODING_STANDARDS.md) | Coding standards |

## Reference

| Doc | Contents | Status |
|---|---|---|
| [`ASSET_DELIVERY.md`](ASSET_DELIVERY.md) | On-demand 3D models + terrain via Cloudflare R2 | Live |
| [`ATMOSPHERE.md`](ATMOSPHERE.md) | Lighting + audio ambience | Reference |
| [`UPDATE_CHECK.md`](UPDATE_CHECK.md) | In-app update checker | Reference |
| [`WGS_INTEGRATION.md`](WGS_INTEGRATION.md) | Wargaming Simulator integration | Implemented |

## Tools

| Doc | Contents |
|---|---|
| [`../relay/README.md`](../relay/README.md) | WebSocket relay for internet multiplayer |

The offline 3D asset pipeline (image-gen → TRELLIS → GLB, terrain + ambience
generators, R2 publish tools) lives in a separate private repository; this repo
consumes only its outputs, delivered on demand from Cloudflare R2 (see
[`ASSET_DELIVERY.md`](ASSET_DELIVERY.md)).

## External

- [Godot docs](https://docs.godotengine.org/en/stable/) ·
  [GDScript style guide](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_styleguide.html)
- [OnePageRules](https://onepagerules.com/) ·
  [Army Forge](https://army-forge.onepagerules.com/) ·
  [Wargaming Simulator](https://udos3dworld.com/WargamingSimulator/)
