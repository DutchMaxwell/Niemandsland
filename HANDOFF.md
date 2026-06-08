# Handoff — Niemandsland codebase

**For the next agent taking over the game codebase.** This is the entry-point briefing.
Read this first, then `CLAUDE.md`, then [`PROJECT_STATUS.md`](PROJECT_STATUS.md) for the
living detail (what works / in progress / roadmap).

## What you're inheriting

**Niemandsland** — a desktop tabletop wargaming simulator (Godot 4.6, GDScript) for
OnePageRules, at **`0.3.1-alpha` (Alpha Release Candidate)**. A 3D table with full
object/unit handling, an OPR Army-Forge importer, a map-layout editor, and
**internet multiplayer** through a Fly.io WebSocket relay. Miniature 3D models are
delivered on demand from Cloudflare R2 (not bundled).

- **`main` is the source of truth and is up to date** — every shipped feature
  (the multiplayer + UI work, on-demand R2 model delivery, the 0.3.1 docs) is on it.
  Work on a `claude/*` branch and fast-forward to `main`.
- **Tests: gdUnit4 255 green / 37 suites**, freshly verified. No known failures.
- **Working tree is clean.** The only uncommitted thing you may see is the maintainer's
  local Model Forge content work (see *Scope* below) — not your concern.

## Scope — what's yours, what isn't

| Area | Owner |
|---|---|
| Game code: `scripts/`, `scenes/`, `test/`, `addons/`, `project.godot`, `relay/` | **You** |
| `tools/model_forge/` (offline OPR→image→TRELLIS→R2 content pipeline) | **Maintainer** — leave it |

The running game never imports `tools/model_forge/`; it only reads
`assets/model_manifest.json` and fetches GLBs from R2. You should not need to touch the
Model Forge tree. Its secrets and heavy scratch are gitignored.

## First 10 minutes

```bash
GODOT="flatpak run --filesystem=home org.godotengine.Godot"   # no bare binary on PATH
$GODOT --headless --path "$PWD" --import                       # 1. re-import (avoids stale-cache false errors)
$GODOT --headless --editor --quit --path "$PWD" 2>&1 \         # 2. compile-check the WHOLE project
  | grep -iE "Fehler bei|nicht ableiten|Parse Error|SCRIPT ERROR|Cannot infer"   # expect none
$GODOT --headless --path "$PWD" -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a test --ignoreHeadlessMode   # 3. tests
```

Full build/run/export details: [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md). Architecture
map: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Conventions (non-negotiable — from `CLAUDE.md`)

- Reply to the maintainer in **German**; keep everything in the codebase **English**.
- **Never commit without being asked.** Conventional commits (`feat:`/`fix:`/`chore:`/…).
- This repo is sometimes worked by more than one agent — check for in-flight changes
  before committing shared files.
- GDScript: explicit types, **no warnings** (treated as errors), no magic numbers, no
  TODO/dead code, enums over strings for states, no allocations in `_process`, every game
  rule cites its OPR reference. Don't use `:=` on a Variant-returning call (e.g. a method
  on a `Node`-typed reference) — annotate the type.

## The one open feature item

- **Host-drop reconnect (relay).** Guests already auto-rejoin after a relay blip, but if
  the **host** drops, the room dies. Full spec: [`relay/HOST_RECONNECT.md`](relay/HOST_RECONNECT.md).
  **Deploy-gated** — it needs a relay-server change + a Fly.io redeploy (`flyctl` is not
  installed here) and a local two-player test before touching the live relay
  (`wss://niemandsland-relay.fly.dev`). Don't deploy blind.

Smaller follow-ups (OPR rule-description persistence for loaded saves; pre-release IP
review) are in [`PROJECT_STATUS.md`](PROJECT_STATUS.md).

## Gotchas that will bite you (don't re-introduce)

1. **Headless editor re-saves mutate two tracked files.** A `--editor --quit` run (e.g. the
   compile-check above) can rewrite:
   - `project.godot` — drops `renderer/rendering_method.web="gl_compatibility"` under
     `[rendering]`. **That line is required for the Web/itch.io export** and is harmless to
     desktop — if it vanishes, restore it.
   - `scenes/map_layout.tscn` — churns it (regenerated `uid://`, per-node `unique_id=`,
     `Color(1.0,…)`→`Color(1,…)`, default props dropped). No design intent.

   If you see either as an unexplained working-tree diff, `git checkout` it — it's an
   editor artifact, not a change.
2. **German locale:** Godot prints errors in German — *"Fehler bei (1969,23): … kann den
   Typ nicht ableiten"*, not "Parse Error". Grep for **both** (step 2 above does).
3. **gdUnit4 never loads `main.gd`** — a `main.tscn` scene-script parse error passes a green
   test run. Always also run the `--editor --quit` compile-check.
4. **Real visuals can't render headless** (dummy renderer) — validate logic with
   tests/compile-check and eyeball UI changes in an actual build.

## Doc map

`HANDOFF.md` (this) · `CLAUDE.md` (project guide) ·
[`PROJECT_STATUS.md`](PROJECT_STATUS.md) (what works / roadmap) ·
[`CHANGELOG.md`](CHANGELOG.md) (history) ·
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) · [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md) ·
[`docs/ASSET_DELIVERY.md`](docs/ASSET_DELIVERY.md) (R2 model delivery).
