# Third-party components & licenses

Niemandsland's **own source code is MIT-licensed** (see [`LICENSE`](LICENSE)). This file
lists the third-party software, fonts, assets and data the project uses, with their
licenses — the canonical notice for an open-source release.

> **Game data note:** One Page Rules (OPR) unit stats / army lists are **not**
> bundled or redistributed. They are loaded **only at runtime via the Army Forge
> API** (see [`docs/PRE_RELEASE_LICENSING.md`](docs/PRE_RELEASE_LICENSING.md)).

## Summary

| Component | License | Bundled? | Where / notes |
|---|---|---|---|
| Niemandsland code | MIT | — | this repo (`LICENSE`) |
| Godot Engine 4.6 | MIT | no (runtime) | the engine the game runs on |
| gdUnit4 | MIT | yes (dev only) | `addons/gdUnit4/` (test framework; `LICENSE` present) |
| Inter (font) | SIL OFL 1.1 | yes | `assets/ui_glassmorphism/fonts/Inter.ttf` + `Inter-LICENSE.txt` |
| Source Code Pro (font) | SIL OFL 1.1 | yes | `assets/ui_glassmorphism/fonts/SourceCodePro.ttf` + `SourceCodePro-LICENSE.txt` (RFN "Source") |
| Orbitron (font) | SIL OFL 1.1 | yes | `assets/ui_glassmorphism/fonts/Orbitron.ttf` + `Orbitron-LICENSE.txt` (title wordmark; RFN "Orbitron") |
| Kenney UI Pack(s) | CC0 | yes | `assets/kenney_ui/` (UI themes) |
| Phosphor Icons | MIT | yes | `assets/ui_glassmorphism/icons/` + `Phosphor-LICENSE.txt` (UI icons, 256px, bold/fill) |
| 3D dice (own W6) | MIT | yes | `scripts/dice_tray.gd`, `scripts/dice_d6.gd` (replaced the former AGPL addon) |
| Miniature GLBs | project-internal (AI-generated) | on-demand | see *Generated assets* below |
| Microsoft TRELLIS | MIT | no (dev tool) | image→3D model generation in `tools/model_forge/` |
| `model-viewer` (Google) | Apache-2.0 | no (dev tool) | 3D preview in the Model Forge review UI |
| gltfpack (meshoptimizer) | MIT | no (dev tool) | `tools/model_forge/bin/gltfpack-linux` (GLB optimization) |
| OPR unit data | OPR content | **no — API only** | never bundled; fetched from Army Forge at runtime |

## Generated assets (miniature models)

The miniature GLBs are **AI-generated** by the offline Model Forge pipeline
(`tools/model_forge/`, not part of the shipped game): image generation → **Microsoft
TRELLIS** (MIT; outputs are ours) → optimized GLB. They are delivered **on-demand**
from a CDN (see [`docs/ASSET_DELIVERY.md`](docs/ASSET_DELIVERY.md)), not bundled in
the build.

## Dev-only tooling (`tools/model_forge/`, `assets/3d_pipeline/`)

These are authoring tools, **not shipped** with the game (verified: not present in
the exported `.pck`). They use TRELLIS (MIT), `model-viewer` (Apache-2.0), and image
generation via **Google Gemini** and **HuggingFace Spaces** — whose terms of service
govern commercial use / redistribution of generated content.

## Verification still pending (before public release)

Tracked in [`docs/PRE_RELEASE_LICENSING.md`](docs/PRE_RELEASE_LICENSING.md):

- **Image-generation ToS** — researched (see `docs/PRE_RELEASE_LICENSING.md`): Gemini
  output is user-owned + commercial-OK (use the paid tier; AI-only output may not be
  copyrightable); TRELLIS is MIT. Final call with the lawyer.
- ~~SVG icon provenance~~ — ✅ resolved: UI icons are **Phosphor Icons** (MIT),
  license bundled. (Other textures, e.g. the table surface, are project-internal.)
- **Git-history scrub** — previously-bundled OPR data and the removed AGPL addon still
  exist in history; scrub before any public/MIT release.
- **IP-lawyer review** — given the AI-generated and OPR-derived assets.
- **Confirm these attribution rows before release:** the **Kenney UI Pack** row lists
  `assets/kenney_ui/` as bundled, but no Kenney files are currently in the tree (the UI
  is now the bundled glassmorphism theme) — confirm whether any Kenney-derived asset
  still ships and correct the row. The **`model-viewer`** minified bundle includes
  third-party deps under BSD/MIT alongside its Apache-2.0 project license (dev-only, not
  shipped). Verify **gdUnit4** is fully excluded from the exported `.pck`
  (`strings build/linux/*.pck | grep -c GdUnit` should be 0; disable the editor plugin
  for the export if not).
