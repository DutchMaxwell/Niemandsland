# Documentation index

Start with the repo entry points: [`../HANDOFF.md`](../HANDOFF.md) (agent onboarding) ·
[`../README.md`](../README.md) (project overview) ·
[`../PROJECT_STATUS.md`](../PROJECT_STATUS.md) (what works / roadmap) ·
[`../CHANGELOG.md`](../CHANGELOG.md) (history). This folder holds the deeper technical docs.

## Core

| Doc | Contents |
|---|---|
| [`../PROJECT_STATUS.md`](../PROJECT_STATUS.md) | What works / in progress / planned |
| [`ARCHITECTURE.md`](ARCHITECTURE.md) | Systems, scripts, data flow, networking, scaling |
| [`DEVELOPMENT.md`](DEVELOPMENT.md) | Build, run, test (Godot 4.6 / Flatpak / gdUnit4) |
| [`../.claude/AAA_CODING_STANDARDS.md`](../.claude/AAA_CODING_STANDARDS.md) | Coding standards |

## Strategy

| Doc | Contents |
|---|---|
| [`VISION_AND_ROADMAP.md`](VISION_AND_ROADMAP.md) | North-star Zielmarke + 0.4 → 1.0 roadmap |
| [`HOUSEKEEPING_PLAN.md`](HOUSEKEEPING_PLAN.md) | Sequenced, risk-rated repo cleanup (P0–P3) |

## Reference

| Doc | Contents | Status |
|---|---|---|
| [`ASSET_DELIVERY.md`](ASSET_DELIVERY.md) | On-demand 3D models via Cloudflare R2 | Live |
| [`PRE_RELEASE_LICENSING.md`](PRE_RELEASE_LICENSING.md) | IP/licensing gate before any public release | Reference |
| [`WEB_EXPORT.md`](WEB_EXPORT.md) | Web / HTML5 + itch.io export notes | Reference |
| [`WGS_INTEGRATION.md`](WGS_INTEGRATION.md) | Wargaming Simulator integration | Implemented |
| [`WGS_API_REQUIREMENTS.txt`](WGS_API_REQUIREMENTS.txt) | WGS server endpoint spec | Reference |
| [`OPR_API_RESEARCH_REPORT.md`](OPR_API_RESEARCH_REPORT.md) | Army Forge API (reverse-engineered) | Reference |
| [`ASSETS.md`](ASSETS.md) | Asset sources & licenses | Reference |

## Runbooks

| Doc | Contents |
|---|---|
| [`runbooks/asset-release.md`](runbooks/asset-release.md) | Publish miniature models to Cloudflare R2 |
| [`runbooks/history-scrub.md`](runbooks/history-scrub.md) | Strip large/licensing blobs from git history |

## Archive

Superseded design docs, kept for history — their shipped content now lives in the code
plus `ARCHITECTURE.md` / `PROJECT_STATUS.md`:

- [`archive/AAA_UI_PLAYBOOK.md`](archive/AAA_UI_PLAYBOOK.md) — Tactical-HUD redesign (shipped)
- [`archive/PLAN_UNIT_SYSTEM.md`](archive/PLAN_UNIT_SYSTEM.md) — unit-system architecture (implemented)
- [`archive/UI_MODERNIZATION_PLAN.md`](archive/UI_MODERNIZATION_PLAN.md) — early glassmorphism UI draft (superseded)

## Tools

| Doc | Contents |
|---|---|
| [`../tools/model_forge/README.md`](../tools/model_forge/README.md) | 3D miniature pipeline (OPR → image → TRELLIS → GLB) |
| [`../relay/README.md`](../relay/README.md) | WebSocket relay for internet multiplayer |

## External

- [Godot docs](https://docs.godotengine.org/en/stable/) ·
  [GDScript style guide](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_styleguide.html)
- [OnePageRules](https://onepagerules.com/) ·
  [Army Forge](https://army-forge.onepagerules.com/) ·
  [Wargaming Simulator](https://udos3dworld.com/WargamingSimulator/)
