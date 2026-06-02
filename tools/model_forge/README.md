# Model Forge — 3D miniature pipeline

Turns OPR unit data into game-ready 3D miniatures for Niemandsland: image generation →
TRELLIS mesh → optimized GLB + `units.json`. Covers all **38 Grimdark Future
factions / 855 unit overrides** with real OPR v3.5.x stats.

This is an **offline content tool**, not part of the running game. It produces the
GLBs the game imports (`assets/miniatures/<faction>/`).

```
OPR share-link or Design Language YAML
        → PromptEngine (unit data + faction aesthetic + IP-compliance block)
        → image generation (HuggingFace Spaces / Gemini)
        → 2D review & approval
        → TRELLIS 3D conversion
        → GLB optimize + export to Niemandsland
```

## Setup

```bash
cd tools/model_forge
python3 -m venv venv && source venv/bin/activate
pip install -r requirements.txt
```

Secrets (git-ignored, never committed):

| File | Contents |
|---|---|
| `.gemini_key` | Google Gemini API key (image gen + quality gate) |
| `.hf_token` | HuggingFace token, **write** scope (needed to wake/restart the Space) |
| `.trellis_space` | TRELLIS Space ID, e.g. `DutchyMaxwell/TRELLIS.2` (note the dot) |

## Review UI (current) — Flask, `review_app.py`

The primary review workflow. Generate images headless with the CLI, then review and
convert in the browser.

```bash
PYTHONPATH=../../assets/3d_pipeline:. ./venv/bin/python review_app.py
# → http://localhost:5070
```

| Route | Purpose |
|---|---|
| `/` | Session list; **TRELLIS wake panel** (status + timeline), "3D umwandeln" (gated until the Space is RUNNING), "Export" |
| `/<sid>/2d` | 2D image review — approve/reject, **`N` = re-roll**; with text in the feedback box it does a true Gemini **image edit** (changes only what you asked), empty = fresh generation |
| `/<sid>/3d` | 3D GLB review (`<model-viewer>`); approve/reject |
| `/diag` | Browser/WebGL self-test |

Notes:
- Open it in a browser with working WebGL. On the dev machine, Flatpak LibreWolf
  cannot render WebGL (sandbox) — use native Firefox.
- `debug=False`, so **template changes require a server restart**.
- Port 5070 (not 5061 — that's SIP-blocked by browsers).
- **TRELLIS auto-recovery:** a mesh-extraction crash wedges the A100 backend (every
  later call fails in seconds while it still reports RUNNING). `trellis_bridge.convert_batch`
  detects this, calls `restart_space`, waits for RUNNING, and retries the unit
  (`MAX_RESTARTS` / `MAX_ATTEMPTS_PER_UNIT` caps).

> `app.py` (Gradio, `localhost:7860`) is the **legacy** UI and is no longer the
> maintained path; prefer `review_app.py` + the CLI.

## Headless bulk generation — `batch_generate.py`

```bash
python batch_generate.py --faction alien_hives        # one faction (hero-first + quality gate + GLB optimize)
python batch_generate.py --all                        # all 38 (runs for days due to HF quota)
python batch_generate.py --faction alien_hives --skip-trellis   # images only
python batch_generate.py --faction wormhole_daemons_of_war --max-attempts 5
```

Per faction: pick a hero mini → generate it (quality-gate loop) and persist as
`_reference.webp` → generate the rest with that image as a style anchor → quality-gate
each (technical + GW-IP) with re-roll on FAIL → TRELLIS → optimize (light mesh
decimation + 2048² texture; quality-first — see docs/ASSET_DELIVERY.md) → export to
`assets/miniatures/<faction>/glb/<NN>_<Name>.glb`. Already
present GLBs are skipped (resume); sessions live under `state/<faction>_<timestamp>/`
(git-ignored).

## Design languages

YAML files in `design_languages/` define each faction's visual identity and game
stats. **Two modes:** *Army Forge* (unit data from the OPR API, YAML supplies the
look) or *Design Language only* (`create_army_from_design_language()` builds a full
`OPRArmy` straight from the YAML).

```yaml
unit_overrides:
  hive_warriors:
    extra_details: "chitinous armor, insectoid features"
    pose: "swarming forward aggressively"
    game_stats:
      quality: 4        # hit roll
      defense: 4        # save roll
      cost: 100
      size: 5           # models per unit
      base: 25          # mm round, or "60x35" oval
      rules: ["Fearless"]
      weapons:
        - { name: "Razor Claws", range: 0, attacks: 2, rules: ["AP(1)"] }
```

New faction: copy `_template.yaml`, fill aesthetic/colors, add unit overrides.

## IP compliance

Every prompt includes the `IP_COMPLIANCE_BLOCK` from `prompt_engine.py` (excludes
concrete GW designs — Aquila, skull-cog, Custodes helms, …). `quality_gate.py` then
checks each image via Gemini Vision for technical criteria (single mini, no base,
white bg) and GW-IP violations; an image with `ip_concerns` is re-rolled.

## Modules

| File | Role |
|---|---|
| `review_app.py` | **Flask review UI** (:5070) + TRELLIS wake/convert/export |
| `batch_generate.py` | Headless bulk CLI |
| `prompt_engine.py` | `DesignLanguage`, `PromptEngine`, IP-compliance block |
| `opr_client.py` | OPR API client + data classes (`OPRWeapon/Unit/Army`) |
| `image_generator.py` | Gemini/HF image gen; reference pinning; **image-edit mode** |
| `quality_gate.py` | Vision-LLM quality + IP check |
| `hero_workflow.py` | Hero/class-anchor selection + reference persistence + unit classification |
| `trellis_bridge.py` | Bridge to `assets/3d_pipeline/trellis_core.py` + convert auto-recovery |
| `glb_optimizer.py` | Light mesh decimation + texture resize, 2048² quality-first (`bin/gltfpack-linux`) |
| `pipeline_state.py` | Session + unit state (`state/`) |
| `exporter.py` | Export approved GLBs + `units.json` to Niemandsland |
| `terrain_*.py` | Experimental terrain-piece generation |

## Image models

| Model | Space |
|---|---|
| Nano Banana (default, Gemini) | `gemini-2.5-flash-image` |
| Z-Image-Turbo | `mrfakename/Z-Image-Turbo` |
| FLUX.1-schnell | `black-forest-labs/FLUX.1-schnell` |

## Tests

```bash
source venv/bin/activate && python -m pytest tests/ -v
```

## Known limits

- HuggingFace GPU quota; TRELLIS converts sequentially (no parallel 3D).
- TRELLIS extract-GLB crashes are transient — handled by the auto-recovery above.
- HF Space API signatures can change.
