# Pre-Release Licensing & Open-Source Checklist

Goal: eventually release OpenTTS as **open source under the MIT license** (for our
own code), with third-party dependencies, assets and data kept under their own
terms. **This file is the durable record of decisions + open items so nothing is
lost between work sessions.**

> Not legal advice. Have an IP lawyer review before any public release, given the
> AI-generated and OPR-derived assets.

## Decisions made

- **Our GDScript code → MIT.** Original work; an MIT `LICENSE` is already at the root.
- **OPR data → API only, never bundled.** OPR unit stats / army lists are OPR's
  content and are *not* MIT-licensable. ✅ Done: removed the bundled `units.json`,
  `assets/opr_samples/`, and `examples/*.json`; the game now loads OPR data
  exclusively from the Army Forge API at runtime (or a user-supplied export at
  import time). `.gitignore` blocks re-committing them.
- **Model Forge pipeline = dev tool, not the product.** `tools/model_forge/` and
  `assets/3d_pipeline/` are offline authoring tools; the game does not reference
  them and they do not ship in the export (verified: 0 occurrences in the build
  `.pck`).
- **Miniature models = AI-generated.** Microsoft TRELLIS (MIT; commercial use OK;
  outputs are ours) from generated images. Tool license is clear; the image-gen
  ToS + the derivative-IP question still need verifying.
- **Design languages: keep the creative vision, strip OPR identifiers.** The
  `tools/model_forge/design_languages/*.yaml` capture *our* art direction (colors,
  materials, style, creature type) — **keep them, that vision must not be lost.**
  Before public release, remove the OPR-specific identifiers (faction file/field
  names like "Battle Brothers"; comments like "Basiert auf GF - …",
  "OPR-Aequivalent zu …") and rename to our own generic names, **preserving all
  aesthetic content.** (Capture any useful OPR→design mapping privately first.)

## Open action items

### 🔴 Blockers (before any public / MIT release)
- [x] **Replaced the AGPL `dice_roller` addon** — removed `addons/dice_roller/` and
      its `project.godot` plugin entry; the game uses our own MIT W6 physics dice
      (`scripts/dice_tray.gd` + `scripts/dice_d6.gd`). ✅
- [ ] **Scrub git history** of the removed OPR data (e.g. `git filter-repo`).
      `git rm` only removed it from HEAD; the stats are still in the history.

### 🟡 Verify / restructure
- [ ] **Move `tools/model_forge/` + `assets/3d_pipeline/` to a separate repo** so
      the public game repo carries none of the pipeline (and none of its OPR
      faction-name references). The game only needs the GLB outputs — which will be
      delivered on-demand from a CDN, not bundled (see `docs/ASSET_DELIVERY.md`).
- [ ] **Neutralize OPR identifiers in `design_languages/*.yaml`** (file names +
      `faction_name` + OPR comments) → our own generic names; keep the aesthetics.
- [ ] **Verify image-generation ToS** (Gemini / HuggingFace Spaces) permit
      commercial use + redistribution of the generated images/models.
- [x] **Document model provenance** (AI-generated via TRELLIS, MIT) — in `THIRD_PARTY.md`. ✅

### 🟢 Attribution / housekeeping
- [x] **Bundle the SIL OFL license text** for the fonts (Inter, Source Code Pro) —
      added next to the fonts. ✅
- [x] **Added `THIRD_PARTY.md`** listing every dependency + asset and its license. ✅
- [ ] **Verify SVG icon / texture provenance**; attribute third-party sources.
- [ ] **IP-lawyer review** before public release.

## Reference: licenses found so far

| Component | License | Notes |
|---|---|---|
| Our code | MIT | root `LICENSE` |
| gdUnit4 (test) | MIT | LICENSE present; dev-only dependency |
| ~~`dice_roller` (vokimon)~~ | AGPL-3.0 | ✅ removed — replaced by our own MIT dice |
| Inter, Source Code Pro (fonts) | SIL OFL 1.1 | ✅ OFL text bundled next to the fonts |
| Microsoft TRELLIS | MIT | model outputs are ours |
| OPR stats / army data | OPR content | API only; never bundle or MIT-license |
