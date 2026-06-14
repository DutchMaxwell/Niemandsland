> ⛔ **INTERNAL — DO NOT SHIP PUBLICLY.** This file describes the private asset
> pipeline, the CDN domain, and IP-sensitive material. Remove it before the repo
> goes public (the planned git-history scrub purges this whole `_internal/` folder).
> It lives here only so the handover travels with the repo while it is still private.

# Handover — set up the private "Model Forge" pipeline repository

**For:** an autonomous coding agent (or a developer) with a local machine, git, and
GitHub auth.
**Goal:** create a new **private** GitHub repository that holds the offline 3D asset
pipeline that was just removed from the public `DutchMaxwell/openTTS` game repo, get
it building/testing, without committing any secrets.

---

## 0. Context (why this exists)

`openTTS` (the Godot game) is being prepared to go public. The offline asset
pipeline ("Model Forge") was split out because (a) the game only ever consumes its
**outputs** (GLB/WebP files delivered on demand from Cloudflare R2), and (b) it
concentrates IP-adjacent material (OnePageRules faction names, GW-referencing design
notes) that should not sit in a public repo. This handover stands the pipeline back
up in its own private home.

**The pipeline turns OPR unit data → images (Gemini / HuggingFace TRELLIS Space) →
3D GLB → optimized GLB, plus terrain/ambience generators, and publishes the results
+ JSON manifests to Cloudflare R2.**

## 1. Where the content is (no external file needed)

The full pipeline content **still lives in this repo's git history** — it was only
removed from the tip of the `openTTS` go-public branch, not from history. So an agent
working in a clone of `openTTS` can reconstruct everything with one command; the
`niemandsland-private-extract.tar.gz` tarball is just an offline convenience copy of
the same tracked files.

Removed paths (all recoverable from history):
- `tools/model_forge/` — the whole pipeline (this is the repo's main content).
- `assets/3d_pipeline/` — the TRELLIS GUI/client (`trellis_core.py`, `trellis_gui.py`).
- Internal docs (`PRE_RELEASE_LICENSING.md`, `runbooks/*.md`, `HOUSEKEEPING_PLAN.md`,
  `GO_PUBLIC_PLAN.md`, `HANDOFF*.md`, `docs/archive/*`, `VISION_AND_ROADMAP.md`) —
  keep as **private reference docs**; NOT public material.

**Recover the pipeline tree from history** (run in a clone of `openTTS`). `origin/main`
still has the full content while this PR is unmerged; or use the removal commit's
parent, which works regardless of merge/rebase:

```bash
# Option A — from origin/main (works while the go-public PR is unmerged):
SRC=origin/main
# Option B — robust even after merge: the commit BEFORE the removal:
SRC=$(git log --grep='split out the asset pipeline' --format='%H' -n1)^

mkdir -p /tmp/forge-src
git archive "$SRC" tools/model_forge assets/3d_pipeline | tar -x -C /tmp/forge-src
# (optionally also grab the internal docs:)
git archive "$SRC" docs/PRE_RELEASE_LICENSING.md docs/runbooks docs/HOUSEKEEPING_PLAN.md \
  docs/GO_PUBLIC_PLAN.md HANDOFF.md docs/HANDOFF_RUIN_WALLS.md docs/HANDOFF_RUIN_WALLS_FINISH.md \
  docs/archive docs/VISION_AND_ROADMAP.md 2>/dev/null | tar -x -C /tmp/forge-src || true
```

`/tmp/forge-src/tools/model_forge` is now the complete pipeline (142 files incl. the
4 MB `bin/gltfpack-linux` binary). The git-ignored **secrets are NOT in history** (by
design — recreate them per §5/§6). This recovery source disappears once the planned
pre-public history scrub runs, so do the extraction before that.

## 2. Target repository

- **Name (suggested):** `niemandsland-model-forge` (or your preference).
- **Visibility: PRIVATE.** Non-negotiable — it carries OPR/GW-adjacent material.
- **License:** internal/none (it is not for public release). Do not add MIT.

## 3. Layout to create

Put the pipeline at the repo root (it currently lives under `tools/model_forge/`).
Suggested final structure:

```
<repo-root>/
├── README.md                 # already exists (tools/model_forge/README.md) — move to root
├── requirements.txt          # already exists
├── .gitignore                # reuse tools/model_forge/.gitignore (see §5)
├── *.py                      # the pipeline scripts
├── design_languages/*.yaml   # 39 faction art-direction files
├── references/               # style-reference images (IP-sensitive — see §7)
├── bin/gltfpack-linux        # vendored binary (MIT)
├── tests/                    # pytest suite
├── engine_comparison/        # R&D notes (optional to keep)
├── trellis/ (from assets/3d_pipeline/)  # TRELLIS GUI/client
└── docs/                     # the removed internal docs, as private reference
```

Moving `assets/3d_pipeline/` in: place its files under e.g. `trellis/` and fix the
one import if needed (`trellis_core.py` is referenced by the pipeline).

## 4. Steps

```bash
# 1. Create the private repo on GitHub (gh example)
gh repo create niemandsland-model-forge --private --description "Niemandsland offline 3D asset pipeline (private)"

# 2. Assemble the working tree (SRC = /tmp/forge-src from §1, or the extracted tarball)
mkdir niemandsland-model-forge && cd niemandsland-model-forge
cp -a /tmp/forge-src/tools/model_forge/. .                 # pipeline at root
mkdir -p trellis && cp -a /tmp/forge-src/assets/3d_pipeline/. trellis/ 2>/dev/null || true
mkdir -p docs && cp -a /tmp/forge-src/docs/. docs/ 2>/dev/null || true   # private reference docs
cp -a /tmp/forge-src/HANDOFF.md docs/ 2>/dev/null || true
rm -f .gdignore                                            # only mattered inside the Godot project

# 3. Verify NO secrets are present (only the .example template may exist)
ls -la .hf_token .gemini_key .trellis_space .r2_credentials 2>/dev/null \
  && echo "STOP: a real secret file is present — delete before committing" || echo "OK: no secret files"

# 4. First commit
git init -b main
git add -A
git commit -m "init: import Niemandsland model-forge pipeline (private)"
git remote add origin git@github.com:<owner>/niemandsland-model-forge.git
git push -u origin main
```

## 5. .gitignore (already in the bundle — keep it)

`tools/model_forge/.gitignore` already ignores the right things; reuse it verbatim at
the root. It ignores: `venv/`, `state/`, `output/`, `_tools/`, `__pycache__/`,
`rework_flags.json`, scratch `_*.py`, and the **secrets**: `.hf_token`, `.gemini_key`,
`.trellis_space`, `.r2_credentials`. Also drop the `.gdignore` file (it only mattered
inside the Godot project).

## 6. Get it running / verify

```bash
python3 -m venv venv && source venv/bin/activate
pip install -r requirements.txt          # flask, gradio, google-genai, Pillow, boto3, pyyaml, ...
python -m pytest tests/ -q                # should pass; test_image_generator needs google-genai (+ a
                                          # working cffi backend) — skip/xfail if the env can't import it
```

Definition of done: repo is private, pushed, `pytest tests/` green (modulo the
optional image-gen test), and **no secret files committed** (`git log -p | grep -iE
'R2_SECRET|gemini|hf_[a-z0-9]{20}'` returns nothing).

Secrets to recreate locally (from `.r2_credentials.example` + the README table), never
committed:
- `.gemini_key`, `.hf_token` (write scope), `.trellis_space` (e.g. `DutchyMaxwell/TRELLIS.2`)
- `.r2_credentials` (R2_ACCESS_KEY_ID / R2_SECRET_ACCESS_KEY / R2_ENDPOINT / R2_BUCKET=niemandsland-models)

## 7. Cleanup decisions for the agent (flag, don't silently drop)

- **Scratch scripts:** `_ah_convert.py`, `_ah_debase.py`, `_ah_overview.py`,
  `_ah_reconvert.py`, `_final_render.py` are one-off experiments (the repo's own
  convention git-ignores `_*.py`; these were force-added). Recommend deleting them.
- **IP-sensitive filenames:** `references/battle_brothers/` contains images named e.g.
  `iter_v1_STILL_SPACE_MARINE.png`, `iter_v2_aquila_primaris_helmet.png`. Even in a
  private repo, consider renaming these (the README in that folder explains the
  IP-avoidance reasoning and is worth keeping). Faction folders/YAMLs use OPR names
  (`battle_brothers`, etc.) — fine to keep privately; just be aware.

## 8. Cross-repo contract (IMPORTANT — keep in sync with openTTS)

The CDN host is the one coupling between the two repos:

- **openTTS:** `scripts/asset_cdn.gd` → `const HOST := "https://assets.akesberg.de"`
- **model-forge:** `cdn_config.py` → `HOST = "https://assets.akesberg.de"`

Manifests store a `{cdn}` token, not the literal host. When the domain is moved
(planned: a neutral domain to drop the maintainer's surname), **both** HOST constants
change to the same value. The pipeline writes manifests with the token via
`cdn_config.base_url(...)`; the game expands it via `AssetCDN.expand(...)`.

The pipeline publishes to R2 and produces the `*_manifest.json` files; those manifests
are then committed **into openTTS** when going live (the game consumes them). Nothing
else from this repo ships in the game.

## 9. Do NOT

- Do not push any of this content back into `DutchMaxwell/openTTS`.
- Do not commit real secret files.
- Do not make this repo public.
