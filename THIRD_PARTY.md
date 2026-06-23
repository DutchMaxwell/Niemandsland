# Third-party components & licenses

Niemandsland's **own source code is MIT-licensed** (see [`LICENSE`](LICENSE)). This file
lists the third-party software, fonts, assets and data the project uses, with their
licenses — the canonical notice for an open-source release.

> **Game data note:** One Page Rules (OPR) unit stats / army lists are **not**
> bundled or redistributed. They are loaded **only at runtime via the Army Forge
> API**.

## Summary

| Component | License | Bundled? | Where / notes |
|---|---|---|---|
| Niemandsland code | MIT | — | this repo (`LICENSE`) |
| Godot Engine 4.6 | MIT | no (runtime) | the engine the game runs on |
| gdUnit4 | MIT | yes (dev only) | `addons/gdUnit4/` (test framework; `LICENSE` present) |
| Inter (font) | SIL OFL 1.1 | yes | `assets/ui_glassmorphism/fonts/Inter.ttf` + `Inter-LICENSE.txt` |
| Source Code Pro (font) | SIL OFL 1.1 | yes | `assets/ui_glassmorphism/fonts/SourceCodePro.ttf` + `SourceCodePro-LICENSE.txt` (RFN "Source") |
| Orbitron (font) | SIL OFL 1.1 | yes | `assets/ui_glassmorphism/fonts/Orbitron.ttf` + `Orbitron-LICENSE.txt` (title wordmark; RFN "Orbitron") |
| Phosphor Icons | MIT | yes | `assets/ui_glassmorphism/icons/` + `Phosphor-LICENSE.txt` (UI icons, SVG, bold style) |
| 3D dice (own W6) | MIT | yes | `scripts/dice_tray.gd`, `scripts/dice_d6.gd` (replaced the former AGPL addon) |
| App icon | CC-BY-SA 4.0 | yes | `icon.png` — the Niemandsland "N" monogram (project original) |
| Bundled textures | CC-BY-SA 4.0 | yes | `assets/terrain/table_surface_default.png`, `assets/terrain/props/ruins_wall.webp`, `assets/sandbox_floor_base.webp`, `assets/sandbox_floor_platform.webp`, `assets/sandbox_forest_floor.webp` (project-generated) |
| Miniature GLBs | CC-BY-SA 4.0 (AI-generated) | on-demand | see *Generated assets* below |
| CC0 battlefield ambience | CC0 | on-demand (R2) | freesound.org recordings; manifest `assets/ambience_manifest.json`, see `scripts/ambience_library.gd` |
| Microsoft TRELLIS | MIT | no (dev tool) | image→3D model generation (asset-pipeline repo); GLB outputs are ours |
| `model-viewer` (Google) | Apache-2.0 | no (dev tool) | 3D preview in the Model Forge review UI |
| gltfpack (meshoptimizer) | MIT | no (dev tool) | GLB optimization (asset-pipeline repo) |
| OPR unit data | OPR content | **no — API only** | never bundled; fetched from Army Forge at runtime |

## Generated assets (miniature models)

The miniature GLBs are **AI-generated** by the offline Model Forge pipeline
(in the separate asset-pipeline repo, not part of this repo or the shipped game): image generation → **Microsoft
TRELLIS** (MIT; outputs are ours) → optimized GLB. They are delivered **on-demand**
from a CDN (see [`docs/ASSET_DELIVERY.md`](docs/ASSET_DELIVERY.md)), not bundled in
the build. These generated visual assets (miniatures, terrain textures, app icon) are
released under **CC-BY-SA 4.0**.

## Dev-only tooling (separate asset-pipeline repo)

These are authoring tools, **not shipped** with the game (verified: not present in
the exported `.pck`). They use TRELLIS (MIT), `model-viewer` (Apache-2.0), and image
generation via **Google Gemini** and **HuggingFace Spaces** — whose terms of service
govern commercial use / redistribution of generated content.
