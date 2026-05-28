# OpenTTS — Open-Source Wargaming Tabletop Simulator

A desktop tabletop simulator focused on miniature wargames, with first-class
support for [OnePageRules](https://onepagerules.com/) (Grimdark Future / Age of
Fantasy). Built in Godot.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Godot](https://img.shields.io/badge/Godot-4.6-blue.svg)](https://godotengine.org/)
[![Status](https://img.shields.io/badge/Status-0.2.0--alpha-orange.svg)]()

> **Status: early alpha.** The tabletop sandbox, OPR army import, multiplayer and
> the 3D-model pipeline work; rules automation (turn/combat resolution, terrain
> gameplay effects) is **not** implemented. See
> [`PROJECT_STATUS.md`](PROJECT_STATUS.md) for the honest done / in-progress /
> planned breakdown.

## Features

What the code actually does today:

- **3D tabletop** — variable table sizes (4×4, 6×4, custom), orbit/pan/zoom camera.
- **Object handling** — click / Alt-click / box select, drag, rotate, copy / paste /
  duplicate, formation arrangement (rows `1`–`9`, arrow `A`) with constant base-edge
  spacing across base sizes.
- **Dice** — physics dice (D4–D100) via the `dice_roller` addon, rendered in a
  scaled SubViewport (see [Scaling](#scaling-conventions)).
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
  custom models (glTF / STL / OBJ), `.otts` save format with OS file association,
  Wargaming Simulator (WGS) import/export.
- **Model Forge** — a Python pipeline that turns OPR unit data into 3D miniatures
  (image generation → TRELLIS mesh) with a Flask review UI. See
  [`tools/model_forge/README.md`](tools/model_forge/README.md).
- **Presentation** — Kenney UI themes, lighting presets (`F1`–`F4`), graphics
  quality presets, SSAO, glow.

## Quick start

Requires **[Godot 4.6](https://godotengine.org/download)** (Forward+ renderer).

```bash
git clone git@github.com:DutchMaxwell/openTTS.git
cd openTTS
godot --path . --editor      # open in the editor, then F5 to run
# or run directly:
godot --path .
```

Main scene: `scenes/startup_menu.tscn`.

For headless build/run/test commands (incl. the Flatpak invocation used in
development and the gdUnit4 test runner), see
[`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md).

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
openTTS/
├── scenes/            # startup_menu.tscn (main), main.tscn, dialogs
├── scripts/           # ~48 GDScript files (see docs/ARCHITECTURE.md)
├── addons/            # dice_roller, gdUnit4 (tests)
├── test/              # gdUnit4 test suites
├── assets/            # models, miniatures, 3d_pipeline, opr_samples
├── relay/             # WebSocket relay server for internet multiplayer
├── tools/model_forge/ # 3D miniature generation pipeline (Python)
└── docs/              # architecture, development, design docs
```

Autoloads: `ThemeManager`, `GraphicsSettings`, `AudioManager`.

## Scaling conventions

1 Godot unit = 1 metre. Tables and movement use real-world scale (a 4×4 ft table is
1.22 m). Miniatures are ~16–60 mm. Because Godot's physics is unreliable at that
scale, **dice run in a separate scaled SubViewport** via the `dice_roller` addon, and
table dice are display-only. Conversions: `INCHES_TO_METERS = 0.0254`,
`MM_TO_METERS = 0.001`.

## Documentation

- [`PROJECT_STATUS.md`](PROJECT_STATUS.md) — current status & roadmap
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — systems & code map
- [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md) — build, run, test
- [`docs/WGS_INTEGRATION.md`](docs/WGS_INTEGRATION.md) — Wargaming Simulator integration
- [`docs/OPR_API_Research_Report.md`](docs/OPR_API_Research_Report.md) — OPR Army Forge API notes
- [`tools/model_forge/README.md`](tools/model_forge/README.md) — model pipeline

## Security note

API tokens for the Model Forge (`tools/model_forge/.hf_token`, `.gemini_key`,
`.trellis_space`) are **git-ignored** and never committed. Nothing in this repo
contains hardcoded credentials.

## Contributing

```bash
git checkout -b feature/my-change
# make changes; validate (see docs/DEVELOPMENT.md):
#   compile-check + gdUnit4 tests must pass
git commit -m "feat: ..." && git push origin feature/my-change   # open a PR
```

Coding standards: [`.claude/AAA_CODING_STANDARDS.md`](.claude/AAA_CODING_STANDARDS.md).

## Credits & license

MIT — see [`LICENSE`](LICENSE). UI themes by [Kenney](https://kenney.nl) (CC0);
dice via the Godot Dice Roller addon (MIT). Asset attributions in
[`docs/ASSETS.md`](docs/ASSETS.md).
