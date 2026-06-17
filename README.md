# Niemandsland — A Fan-Made Tabletop Simulator for OnePageRules Game Systems

A desktop tabletop simulator focused on miniature wargames, with first-class
support for [OnePageRules](https://onepagerules.com/) (Grimdark Future / Age of
Fantasy). Built in Godot.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Godot](https://img.shields.io/badge/Godot-4.6-blue.svg)](https://godotengine.org/)
[![Status](https://img.shields.io/badge/Status-0.3.5.2--alpha-orange.svg)]()

> **Status: alpha (on the Road to Alpha `0.3.6`).** The tabletop sandbox, OPR army
> import, multiplayer and the 3D-model pipeline work; rules automation (turn/combat
> resolution, terrain gameplay effects) is **not** implemented. See
> [`PROJECT_STATUS.md`](PROJECT_STATUS.md) for the honest done / in-progress /
> planned breakdown, and [`docs/ROAD_TO_ALPHA.md`](docs/ROAD_TO_ALPHA.md) for the
> `0.3.6` release plan.

## Features

What the code actually does today:

- **3D tabletop** — variable table sizes (4×4, 6×4, custom), orbit/pan/zoom camera.
- **Object handling** — click / Alt-click / box select, drag, rotate, copy / paste /
  duplicate, formation arrangement (rows `1`–`9`, arrow `A`) with constant base-edge
  spacing across base sizes.
- **Dice** — physics dice (D4–D100) via our own MIT dice scripts (`dice_tray.gd` /
  `dice_d6.gd`), rendered in a scaled SubViewport (see [Scaling](#scaling-conventions)).
- **Measurement** — distance measuring in inches.
- **Map layout editor** — top-down 3″ grid, terrain pieces (ruins / forest /
  container / dangerous), front-line + custom-polygon deployment zones, objectives,
  auto-generate, 3D overlay, save/load layouts. (Terrain is currently visual; it has
  **no** gameplay effect yet.)
- **OPR units** — import Army Forge lists via the OPR API, per-model wounds, caster
  points, unit coherency check + visualizer, radial context menu, docked unit info
  card, unit-wide status tokens (Fatigue / Shaken / Activated).
- **Multiplayer** — ENet over LAN, or over the internet via a WebSocket relay
  (see [`relay/`](relay/README.md)); full state sync (models, terrain, table size),
  shared dice log, player avatars/cursors, save/load.
- **Import / export** — Tabletop Simulator import (Steam CDN + local cache),
  custom models (glTF / STL / OBJ), `.nml` save format with OS file association,
  Wargaming Simulator (WGS) import/export.
- **Asset pipeline** — the offline pipeline that generates the 3D miniatures
  (image generation → TRELLIS mesh) lives in a separate private repository; the
  game consumes only its R2-delivered outputs.
- **Presentation** — Kenney UI themes, lighting presets (`F1`–`F4`), graphics
  quality presets, SSAO, glow.

## Quick start

### Play (Windows / Linux)

Download the latest build from the [**Releases**](../../releases) page, unzip and run it
(`Niemandsland.exe` on Windows; the `.x86_64` next to its `.pck` on Linux) — no install. The
start menu shows the version; the first log line is `[Boot] Niemandsland <version> build <hash>`.

- **Host or join** a multiplayer game from the start menu — the host shares a room code, the guest
  enters it. **Both players must run the same version** (the exact-match handshake won't connect
  otherwise).
- **Import an army** from the menu by pasting an [Army Forge](https://army-forge.onepagerules.com/)
  list link. A faction's 3D models download on first use (cached afterwards) — internet required.
- Honest alpha caveats are in [`docs/KNOWN_ISSUES.md`](docs/KNOWN_ISSUES.md); hit **"Report a
  problem"** in the start menu to send an anonymised bug report.

### From source (developers)

Requires **[Godot 4.6](https://godotengine.org/download)** (Forward+ renderer).

```bash
git clone https://github.com/DutchMaxwell/openTTS.git
cd openTTS
godot --path . --editor      # open in the editor, then F5 to run
# or run directly:
godot --path .
```

Main scene: `scenes/startup_menu.tscn`. For headless build/run/test commands (incl. the Flatpak
invocation and the gdUnit4 test runner), see [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md).

## Controls

| Camera | |
|---|---|
| Rotate | Right-drag |
| Pan | Middle-drag |
| Zoom | Mouse wheel |
| Reset | `Home` |

| Objects | |
|---|---|
| Select / multi-select | Left-click / `Alt`+Left-click |
| Box select | Left-drag on table |
| Move / rotate | Left-drag / `R` |
| Delete | `Del` / `Backspace` |
| Copy / paste / duplicate | `Ctrl`+`C` / `V` / `D` |
| Arrange (multi-select) | `1`–`9` rows, `A` arrow |

| Other | |
|---|---|
| Roll dice | `Space` |
| Lighting presets | `F1`–`F4` |

## Project layout

```
Niemandsland/
├── scenes/            # startup_menu.tscn (main), main.tscn, dialogs
├── scripts/           # ~48 GDScript files (see docs/ARCHITECTURE.md)
├── addons/            # gdUnit4 (tests)
├── test/              # gdUnit4 test suites
├── assets/            # models, miniatures, terrain, UI
├── relay/             # WebSocket relay server for internet multiplayer
└── docs/              # architecture, development, design docs
```

Autoloads: `ThemeManager`, `GraphicsSettings`, `AudioManager`.

## Scaling conventions

1 Godot unit = 1 metre. Tables and movement use real-world scale (a 4×4 ft table is
1.22 m). Miniatures are ~16–60 mm. Because Godot's physics is unreliable at that
scale, **dice run in a separate scaled SubViewport** (our own MIT `dice_tray.gd` /
`dice_d6.gd`), and table dice are display-only. Conversions: `INCHES_TO_METERS = 0.0254`,
`MM_TO_METERS = 0.001`.

## Documentation

- [`PROJECT_STATUS.md`](PROJECT_STATUS.md) — current status & roadmap
- [`docs/ROAD_TO_ALPHA.md`](docs/ROAD_TO_ALPHA.md) — the `0.3.6` Alpha release plan & checklist
- [`docs/KNOWN_ISSUES.md`](docs/KNOWN_ISSUES.md) — honest alpha limitations & caveats
- [`docs/ROADMAP.md`](docs/ROADMAP.md) — curated feature backlog (Now / Next / Ideas / Shipped)
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — systems & code map
- [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md) — build, run, test
- [`docs/WGS_INTEGRATION.md`](docs/WGS_INTEGRATION.md) — Wargaming Simulator integration

## Security note

This repo contains no secrets or hardcoded credentials. The separate asset-pipeline
repository holds its own API tokens (git-ignored there).

## Feedback & contributing

This is an early alpha — **feedback is the most valuable thing right now.** Found a
bug or have an idea? [Open an issue](../../issues/new/choose) and pick the 🐞 **Bug
report** or 💡 **Feedback / idea** template.

Curious what's planned? See the **[roadmap](docs/ROADMAP.md)** (and how requests flow
from idea to shipped).

Want to contribute code? See **[`CONTRIBUTING.md`](CONTRIBUTING.md)** for the dev
setup, the test workflow and the PR flow. In short: Godot 4.6, branch off `main`,
conventional commits, gdUnit4 + relay tests green, then open a PR. Coding standards:
[`.claude/AAA_CODING_STANDARDS.md`](.claude/AAA_CODING_STANDARDS.md).

## Credits & license

MIT — see [`LICENSE`](LICENSE). UI themes by [Kenney](https://kenney.nl) (CC0);
dice are our own MIT implementation. Full third-party attributions in
[`THIRD_PARTY.md`](THIRD_PARTY.md).
