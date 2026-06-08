# Niemandsland — Housekeeping Plan

> Definitive, sequenced cleanup plan for the Niemandsland repo (v0.3.1-alpha).
> Synthesized from 8 dimension audits + an adversarial verification of the
> irreversible git operations. Every figure below was re-derived against the
> live repo at HEAD `85b5f0b`.

## Executive summary

The repo is **functionally and code-hygienically healthy** — no orphaned
scripts, no commented-out code, no stale references to the removed AI/battle
system, 37 green gdUnit suites. The debt is concentrated in three places: (1) a
**1.2 GB `.git` directory that is 96.5% dead history-only media** (committed-then-removed GLBs + companion images, now served on-demand from Cloudflare R2); (2)
**~21.9 GB of gitignored working-tree scratch**, of which ~19.5 GB is safely
reclaimable today; and (3) **stale docs** (three overlapping handoff files, two
shipped "plan" docs, and two delivery docs that still describe GitHub Releases
instead of the live R2 channel). The plan is phased strictly by risk and
reversibility: P0 and P1/P2 are safe to start now; **P3 (the irreversible
history rewrite) is gated on an explicit maintainer GO** and only makes sense if
a public/MIT release is actually imminent — otherwise the conscious "skip the
rewrite" decision from prior sessions still stands and a plain `git gc` is the
correct move.

### Headline metrics — current vs target

| Metric | Current | Target (post-plan) | Driver |
|---|---|---|---|
| `.git` directory | **1.2 GB** (993 MiB pack) | **~63 MB** (empirically measured) | P3 history rewrite |
| Working tree on disk | **~22 GB** | **~2.5 GB** | P0 scratch reclamation (~19.5 GB) |
| Tracked files | 1073 | ~1060 | P0/P1/P2 small removals |
| Root-level tracked files | 14 | 14 (cleaner; dead scratch is untracked) | P0 (disk-only) |
| Live docs in `docs/` | 17 | ~12 live + `docs/archive/` | P1 doc consolidation |
| GDScript warning config | **none** | enforced (`treat_warnings_as_errors`) | P2 |

**Empirical proof for P3:** a throwaway `git clone --mirror` + filter-repo strip
took the pack from **1.2 GB → 63.19 MiB (94.7% reduction)**, with the dice GLB,
the web-export line, and both tags surviving intact. The benefit is measured, not
theoretical.

---

## DO NOT TOUCH — load-bearing invariants

These were independently confirmed and must survive every phase:

1. **`project.godot:91` `renderer/rendering_method.web="gl_compatibility"`** —
   required for the web/itch.io export. A headless `godot --editor --quit` run
   **silently strips it**. Never let the editor re-save `project.godot`; edit it
   by hand. Verified to survive the P3 rewrite. (Agreed across the *git history*,
   *disk*, *code hygiene*, and *CI* dimensions.)
2. **`scenes/map_layout.tscn` editor churn** — re-saving regenerates uids; it is
   not a real change. Do not commit that churn.
3. **The `tools/model_forge/` boundary** — the maintainer's offline content
   pipeline; the running game never imports it (it only reads
   `assets/model_manifest.json` and fetches R2). Its git-tracked files and disk
   hygiene are in scope; its *runtime isolation* is not to be broken.
4. **OPR data** — must never be bundled or MIT-licensed. It is already correct at
   HEAD (API-only, gitignored, absent from the `.pck`). The only residual is in
   **git history** (P3).
5. **`assets/model_manifest.json` (R2, `https://assets.akesberg.de/`)** — the
   live content-addressed delivery source. Keep the `assets/miniatures/*/glb/`
   gitignore rules so runtime-downloaded models stay untracked.
6. **`assets/models/dice/d6_dice.glb`** — a real, tracked, *used* game asset.
   A bare `*.glb` glob in P3 would destroy it; directory-scoped globs do not.

---

## PHASE 0 — Trivial & fully reversible (start now, no approval needed)

All P0 items are disk-only or gitignored scratch. None touches tracked git
content except where noted. Net reclaim: **~19.5 GB**.

### P0.1 — Delete the stale Godot import cache (`.godot/`, 7.5 GB)

The single largest disk hog (2221 files), fully regenerable and largely *stale*
(holds `.scn`/`.ctex` for GLBs no longer on disk).

- **Risk:** low · **Reversible:** y · **Effort:** trivial · **Approval:** no

```bash
rm -rf /home/andreaskesberg/openTTS/.godot
# rebuild cache WITHOUT an editor save (never use --editor --quit here):
godot --headless --import --path /home/andreaskesberg/openTTS
grep -n 'rendering_method.web' /home/andreaskesberg/openTTS/project.godot  # must still print line 91
```

### P0.2 — Delete regenerable export/build/study scratch (~3.4 GB)

`dist/` (797 MB, v0.3.0 builds — a version behind) + `build/` (701 MB) +
`engine_comparison/` heavy scratch (691 MB; tracked `.md` conclusions are
preserved by its own `.gitignore`) + `venv/` (373 MB) + `_tools/realesrgan`
(56 MB) + `renders/` + `reports/` + all `__pycache__/`.

- **Risk:** low · **Reversible:** y · **Effort:** trivial · **Approval:** no

```bash
rm -rf /home/andreaskesberg/openTTS/dist /home/andreaskesberg/openTTS/build
rm -rf /home/andreaskesberg/openTTS/tools/model_forge/venv \
       /home/andreaskesberg/openTTS/tools/model_forge/_tools
git -C /home/andreaskesberg/openTTS clean -xnd tools/model_forge/engine_comparison/   # preview
git -C /home/andreaskesberg/openTTS clean -xfd tools/model_forge/engine_comparison/    # execute
rm -rf /home/andreaskesberg/openTTS/renders /home/andreaskesberg/openTTS/reports
find /home/andreaskesberg/openTTS -name __pycache__ -type d -not -path '*/.godot/*' -prune -exec rm -rf {} +
```

### P0.3 — Delete loose conversion logs in `state/` (433 MB)

`state/_ah_reconvert.log` (222 MB), `_ah_convert.log` (136 MB), `_ah_convert2.log`
(95 MB) — one-off alien_hives run logs; alien_hives is fully on R2.

- **Risk:** none · **Reversible:** n (logs) · **Effort:** trivial · **Approval:** no

```bash
rm -f /home/andreaskesberg/openTTS/tools/model_forge/state/_ah_*.log
```

### P0.4 — Delete root/working-tree litter (gitignored, untracked)

Confirmed orphans flagged by **four** dimensions (structure, dead-code, asset,
CI/test) — high confidence:

- `test_nodename_probe.gd.uid` (orphan `.uid`, its `.gd` is gone)
- `dao_union_gallery{,_v2,_v3}.png` + `.import` siblings (~5.7 MB review montages)
- `assets/startup_background.png.import` (orphan import descriptor, source gone)

- **Risk:** none · **Reversible:** n · **Effort:** trivial · **Approval:** no

```bash
rm -f /home/andreaskesberg/openTTS/test_nodename_probe.gd.uid \
      /home/andreaskesberg/openTTS/dao_union_gallery*.png \
      /home/andreaskesberg/openTTS/dao_union_gallery*.png.import \
      /home/andreaskesberg/openTTS/assets/startup_background.png.import
```

### P0.5 — `state/` dead scratch (~840 MB) — needs a one-line maintainer OK

Maintainer's own naming marks these dead: `_archived_*`, `_discarded_*`,
`_samurai_test`, `_overnight_done_*` sentinels.

- **Risk:** low · **Reversible:** n · **Effort:** trivial · **Approval:** YES (confirm no `_archived_*` is a rollback target)

```bash
rm -rf /home/andreaskesberg/openTTS/tools/model_forge/state/_archived_* \
       /home/andreaskesberg/openTTS/tools/model_forge/state/_discarded_* \
       /home/andreaskesberg/openTTS/tools/model_forge/state/_samurai_test \
       /home/andreaskesberg/openTTS/tools/model_forge/state/_overnight_done_*
```

### P0.6 — Close the `.gitignore` terrain gap (prevents re-bloat)

`.gitignore:81` ignores `assets/miniatures/*/glb/` but **not** the terrain tree.
Independently confirmed: `git check-ignore` does NOT ignore
`assets/terrain/grimdark_industrial/trees/mutated_pine.glb`. Without this, a
regeneration run re-adds the bloat and the P3 scrub is wasted. **Do this before
P3.** (Agreed by the *git history* dimension and the adversarial verifier.)

- **Risk:** none · **Reversible:** y · **Effort:** trivial · **Approval:** no

```bash
printf '\n# Terrain GLBs + companion images are R2-delivered, never commit them\nassets/terrain/grimdark_industrial/\n' \
  >> /home/andreaskesberg/openTTS/.gitignore
git -C /home/andreaskesberg/openTTS check-ignore assets/terrain/grimdark_industrial/trees/mutated_pine.glb  # must now print the path
```

### P0.7 — Plain `git gc` baseline (non-destructive)

1466 loose objects (223 MiB), 45 prune-packable, 3 packs. A plain repack folds
them into one pack. Changes no history/SHAs/refs. **If P3 is NOT approved, this
is the correct stopping point for git size.**

- **Risk:** none · **Reversible:** y · **Effort:** trivial · **Approval:** no

```bash
git -C /home/andreaskesberg/openTTS gc
git -C /home/andreaskesberg/openTTS count-objects -vH
```

> ⚠️ **Never run `git clean -xfd` at the repo root** — it would delete secrets
> (`.r2_credentials`, `.hf_token`, `.gemini_key`), `venv/`, the R2 download cache,
> and the entire `state/` tree **including the one unpublished faction (P-DEC-1)**.
> Always scope `git clean` to a named subdirectory.

---

## PHASE 1 — Structure & documentation consolidation (low risk, mostly reversible)

### ⚠️ Move-safety blocker (read before any P1 `git mv`)

Every script/shader/material is referenced by **hardcoded `res://` path**, not by
`uid://`, and the `.gd.uid` sidecars are gitignored. `git grep -n 'res://scripts/'`
shows **57 path references** across `.tscn`/`.gd`/`project.godot` autoloads. A plain
`git mv` of any script silently breaks Godot's resolution. **Rule:** for each move,
`git grep -l` the old path, sed-replace in all `.tscn`/`.tres`/`.gd`/`project.godot`
in the same commit, headless-import, run gdUnit4. Move 5–10 files per commit, never
big-bang. This gates P1.3 and makes deep `scripts/` re-foldering **deferred /
optional** (high effort, high risk — recommend NOT doing it now).

### P1.1 — Consolidate the three overlapping handoff docs → two

`HANDOFF.md`, `docs/SESSION_HANDOFF.md`, `PROJECT_STATUS.md` were all written in
the same commit (`6059b1e`) and are ~90% identical (same version, same `255 green
/ 37 suites`, same validation block, same two gotchas, same boundary table, same
open item #43). **Delete `docs/SESSION_HANDOFF.md`** (every line lives elsewhere);
keep `HANDOFF.md` (onboarding briefing) + `PROJECT_STATUS.md` (status/roadmap).
The validation block's single home is `docs/DEVELOPMENT.md`.

- **Risk:** low · **Reversible:** y · **Effort:** small · **Approval:** no

```bash
git -C /home/andreaskesberg/openTTS grep -n 'SESSION_HANDOFF' -- '*.md'  # find back-refs first
git -C /home/andreaskesberg/openTTS rm docs/SESSION_HANDOFF.md
# then edit HANDOFF.md lines 4 + 94 to drop the dead pointer; fold the OPR
# rule-descriptions-not-persisted bullet into PROJECT_STATUS "Known issues".
```

### P1.2 — Archive shipped "plan" docs

Both self-declare completion and are verified done in code:

- `docs/AAA_UI_PLAYBOOK.md` (37 KB) — HudTokens/HudFrame/ui_motion exist; UiPolish
  delegates to HudTokens; checkbox focus ring fixed; Orbitron MSDF=true.
  **Before archiving, lift the one unbuilt item** (`scripts/ui_sound.gd` / UiSound
  autoload + UI audio bus) into `PROJECT_STATUS.md` "Planned".
- `docs/PLAN_UNIT_SYSTEM.md` (49 KB, German) — "VOLLSTÄNDIG IMPLEMENTIERT"; live
  unit model is documented in English in `ARCHITECTURE.md`. (This also clears the
  stale `# TODO` pseudocode at line 570 flagged by the dead-code dimension.)

- **Risk:** low · **Reversible:** y · **Effort:** small · **Approval:** no

```bash
mkdir -p /home/andreaskesberg/openTTS/docs/archive
git -C /home/andreaskesberg/openTTS mv docs/AAA_UI_PLAYBOOK.md docs/archive/AAA_UI_PLAYBOOK.md
git -C /home/andreaskesberg/openTTS mv docs/PLAN_UNIT_SYSTEM.md docs/archive/PLAN_UNIT_SYSTEM.md
```

### P1.3 — Delete/archive the superseded UI draft

`docs/UI_MODERNIZATION_PLAN.md` (16 KB, German "ENTWURF") is the predecessor of
the now-shipped playbook; proposes rejected choices (JetBrains Mono). Delete (or
archive if early-design history is wanted).

- **Risk:** low · **Reversible:** y · **Effort:** trivial · **Approval:** no

```bash
git -C /home/andreaskesberg/openTTS rm docs/UI_MODERNIZATION_PLAN.md  # or: git mv ... docs/archive/
```

### P1.4 — Fix the GitHub-Releases-vs-R2 contradiction (highest-value content fix)

A new agent following these would re-publish to the **wrong host**:

- `docs/ASSET_DELIVERY.md` — titled "(plan)/pending", names "GitHub Releases".
- `docs/runbooks/asset-release.md` — walks through `gh release create models-v1`.

Reality (live manifest + CHANGELOG): **Cloudflare R2, `assets.akesberg.de`,
content-addressed `sha256.glb`, 113 models, `publish_manifest.py --upload-r2`.**
Rewrite both to R2 (translate the runbook to English in the same pass). Also fix
the stale **`ARCHITECTURE.md` "Planned" R2 blockquote** to present tense.

- **Risk:** low/none · **Reversible:** y · **Effort:** medium · **Approval:** no

```bash
python3 -c "import json;print(json.load(open('/home/andreaskesberg/openTTS/assets/model_manifest.json'))['base_url'])"  # source of truth
grep -n 'Planned' /home/andreaskesberg/openTTS/docs/ARCHITECTURE.md
```

### P1.5 — Rebuild `docs/README.md` index

Last updated 2026-05-28; omits `ASSET_DELIVERY`, `PRE_RELEASE_LICENSING`,
`WEB_EXPORT`, `AAA_UI_PLAYBOOK`, runbooks; lists now-archived docs as live. Rebuild
after P1.1–P1.4 land, with a one-line purpose per surviving doc.

- **Risk:** none · **Reversible:** y · **Effort:** small · **Approval:** no

### P1.6 — Dead/duplicate folders (need maintainer OK — `tools/` is their domain)

- `examples/` — only `examples/README.md`, which documents a JSON that is
  gitignored and absent. Remove the folder or rewrite the README (English) +
  commit one real sample. **(P-DEC-3)**
- `tools/3d-generation/` — German README + Colab notebook; superseded by
  `tools/model_forge/`. Nothing references it. Delete or annotate. **(P-DEC-4)**

- **Risk:** low · **Reversible:** y · **Effort:** trivial/small · **Approval:** YES

```bash
git -C /home/andreaskesberg/openTTS rm -r examples/         # P-DEC-3
git -C /home/andreaskesberg/openTTS rm -r tools/3d-generation  # P-DEC-4
```

### P1.7 — Smaller structure/doc fixes (no approval)

- **`serve_web.py` doc fix:** `docs/WEB_EXPORT.md:70` tells users `python3 -m
  http.server 8060`, which omits the COOP/COEP headers; the project's own
  `serve_web.py` provides them. Change the doc to `python3 serve_web.py` and
  mention it in `DEVELOPMENT.md`. (Keep `serve_web.py` at root.)
- **Group loose `tools/` runners** into `tools/dev_runners/` (render_*,
  hud_prototype*, gltf_loadtest) and `tools/os_integration/` (.desktop, .mime.xml,
  .reg). Only 4 `res://tools/*.gd` refs (sibling `_runner.tscn`) need fixing in the
  same commit. Nothing else references `res://tools/`.
- **Rename** `docs/OPR_API_Research_Report.md` → `OPR_API_RESEARCH_REPORT.md`
  (cosmetic consistency; fix any links first).
- **Translate surviving German docs to English** (CLAUDE.md mandate): keep set =
  `WGS_INTEGRATION.md`, `OPR_API_RESEARCH_REPORT.md`, `ASSETS.md`,
  `WGS_API_REQUIREMENTS.txt`, both runbooks. (Archived/deleted German docs need no
  translation.) — **Effort: large; can be incremental.**
- **`default_bus_layout.tres`** is Godot-implicit-loaded and load-bearing — **do
  not move it**; document it in `ARCHITECTURE.md` so it's not mistaken for clutter.

---

## PHASE 2 — Code & build hygiene (low risk, reversible)

### P2.1 — Enable GDScript warning enforcement (root cause)

`project.godot` has **no `gdscript/warnings` config at all** (confirmed), so the
"zero-warning" policy is unenforced and the shadow warnings compile silently. Add
under a `[debug]` block. **Edit by hand — do not let the editor re-save** (P0
invariant #1).

- **Risk:** low · **Reversible:** y · **Effort:** small · **Approval:** no

```ini
[debug]
gdscript/warnings/exclude_addons=true
gdscript/warnings/treat_warnings_as_errors=true
```

### P2.2 — Fix the ~12 genuine parameter/local shadowing warnings

These are the "parameter shadowing" PROJECT_STATUS mentions. Rename the
identifier (not the member): `owner`→`owner_id`/`player_id`, `rotation`→`rot_deg`,
`size`→`dims`/`footprint`, `position`→`screen_pos`. Confirmed sites:
`radial_menu.gd:280`; `map_layout.gd:850,856,866`; `map_layout_grid.gd:796`;
`hud/state_panel.gd:39`; `terrain_overlay.gd:1072,1080,1132,1322,1417,1546`;
`network_manager.gd:505,655`; `main.gd:2685,2964`; `radial_menu_controller.gd:306`;
`save_manager.gd:80`. **Do NOT touch the documented false positives** (inner-class
RefCounted members in `opr_api_client.gd`/`save_manager.gd`, static func in
`glassmorphism_theme.gd:361`). Do this together with P2.1 so regressions are caught.

- **Risk:** low · **Reversible:** y · **Effort:** small · **Approval:** no

### P2.3 — Remove the dead `roll_attack` feature

`scripts/radial_menu_controller.gd` — dispatch branch (265–266), stub
`_roll_attack()` (491–499), and the only real `# TODO` in `scripts/`. The
`action_id "roll_attack"` is never produced; combat resolution is explicitly
out-of-scope (PROJECT_STATUS). If wanted later, file an issue.

- **Risk:** low · **Reversible:** y · **Effort:** trivial · **Approval:** no

### P2.4 — Remove the unused `theme_changed` signal

`scripts/theme_manager.gd:5` — declared, never emitted, never connected
(whole-repo confirmed).

- **Risk:** none · **Reversible:** y · **Effort:** trivial · **Approval:** no

### P2.5 — Triage 264 bare `print()` debug statements

Violate the gated-logging standard. Start with `main.gd` perf-test/boot traces
(~70) and `object_manager.gd` (49). Convert to a gated logger or delete. Keep
`push_warning`/`push_error`. (Lower priority than P2.1–P2.4.)

- **Risk:** low · **Reversible:** y · **Effort:** medium · **Approval:** no

### P2.6 — Tracked-asset trims (small, mechanical)

- `git rm` 5 orphaned `dao_union/_reference*_preprocessed.png` (~2.5 MB,
  pipeline intermediates excluded by the pipeline itself) + add ignore rule.
- `git rm` 3 dead `assets/models/dice/d6_dice.{obj,fbx,glb}` (~71 KB, zero refs;
  dice are procedural via `scripts/dice_d6.gd`). **NOTE:** this is a *different*
  GLB than the in-use one; confirm via `git grep d6_dice` first.
- `git rm --cached assets/3d_pipeline/__pycache__/trellis_core.cpython-311.pyc`
  (stale tracked bytecode; `.gitignore` already blocks re-add).

- **Risk:** low/none · **Reversible:** y · **Effort:** trivial · **Approval:** no

### P2.7 — CI hardening

- **Add a test gate to `web-itch.yml`** (or add `claude/**` to `build.yml`
  triggers). Today **active `claude/**` branches run ZERO tests** yet auto-deploy
  to itch.io. Cleanest: extract the gdUnit step into a `workflow_call`.
- **Make the compile-check real:** both workflows mask import errors with
  `|| true` and never grep for `SCRIPT ERROR|Parse Error`. gdUnit never
  instantiates `main.gd`, so a scene parse error ships green today.
- **Guard the web line:** add `grep -q 'renderer/rendering_method.web="gl_compatibility"' project.godot || exit 1` early in CI (and ideally a pre-commit hook).
- **Drop the nonexistent `develop` trigger** from `build.yml`.
- **Fix `export_presets.cfg`:** macOS `bundle_identifier="niemandsland"` is
  invalid (needs reverse-DNS, e.g. `de.akesberg.niemandsland`); add
  `assets/miniatures/*/_reference*` to `exclude_filter` so ~17.3 MB of pipeline
  inputs stop shipping. (`relay/` + `model_forge/` pytest suites are mock-based and
  CI-ready but run nowhere — optional add.)

- **Risk:** low · **Reversible:** y · **Effort:** small/medium · **Approval:** no

### P2.8 — Licensing-attribution fixes in `THIRD_PARTY.md` (do BEFORE any public release)

- **model-viewer** is **BSD-3-Clause** (its own header), not Apache-2.0 as listed;
  add the BSD notice next to the bundled `.js`.
- **Kenney CC0** is listed as bundled but **no Kenney files exist** anywhere —
  remove the phantom row.
- **gltfpack** (`tools/model_forge/bin/gltfpack-linux`, meshoptimizer MIT) has **no
  attribution** — add a row (version 1.1 + upstream URL) and bundle the MIT text.
- **gdUnit4 leaks into the shipped `.pck`** (765 `GdUnit` strings via the packed
  global class cache) despite `exclude_filter` — disable the gdUnit4 editor plugin
  before export and re-verify with `strings build/linux/Niemandsland.pck | grep -c GdUnit` (expect 0).
- Fix stale `README.md`/`CLAUDE.md` lines claiming dice come from the `dice_roller`
  addon — they are now MIT `scripts/dice_*.gd`.

- **Risk:** none/low · **Reversible:** y · **Effort:** small · **Approval:** no (but **required gate for any public release**)

---

## PHASE 3 — IRREVERSIBLE git-history rewrite + branch/tag pruning

> **GATE:** Do NOT start P3 without an explicit maintainer GO (**P-DEC-5**). A
> prior session *consciously skipped* this rewrite (builds were already slim,
> force-push risk on a shared branch). **That decision still stands unless a
> public/MIT release is imminent** — the runbook's stated trigger. If no release
> is planned, stop at **P0.7 (`git gc`)**.

The adversarial verification empirically confirmed the benefit (**1.2 GB → 63 MB**)
and the safety of the directory-scoped approach, but caught **three blockers the
size-only audit missed**. All three are folded in below.

### P3 pre-conditions (must all be true)

1. **`git-filter-repo` is NOT installed** — `pip install git-filter-repo` first.
2. **Resolve `origin/claude/fix-model-lighting-47Qp0` FIRST** — it has **3
   UNMERGED commits** (`2032a0a`, `fcd6e4d`, `53af100`: two-sided GLB lighting in
   `object_manager.gd`, touching no stripped paths). **Do NOT delete it** (the
   size-audit's "delete if stale" is WRONG). Merge/rebase it to `main` before the
   scrub, and keep it through the `--mirror` push. **(P-DEC-2)**
3. **P0.6 terrain `.gitignore` rule must already be committed** (else re-bloat).
4. **Correct remote URL** — it is `git@github.com:DutchMaxwell/openTTS.git`
   (SSH, repo **openTTS**). The size-audit AND the existing runbook both use the
   wrong `https://github.com/DutchMaxwell/Niemandsland.git` — **every URL in the
   plan and runbook must be corrected** or the push hits a nonexistent repo.
5. **Decide the strip scope (P-DEC-6):** if this is a public-release scrub, the
   size-only globs are **insufficient** — they omit the runbook's **licensing**
   paths (OPR `units.json`, `assets/opr_samples`, `examples/*.json`) and the
   **AGPL `addons/dice_roller`** tree. Both must be merged in (below).
6. **Branch protection on `main` must be disabled** for the force-push.
7. **No open PRs** (confirmed: `gh pr list --state open` → `[]`).

### P3.1 — Branch pre-pruning (cheap, shrinks the ref surface)

- `backup/cloud-3d3441b` — 0 unique commits, ancestor of `main`. **Delete.**
- Local `claude/3d-graphics-overhaul` — byte-identical to `main` (0/0); checkout
  `main` first, then delete locally. (Cosmetic.)

- **Reversible:** n (but content is fully on `main`) · **Approval:** yes (bundle with P3)

```bash
git -C /home/andreaskesberg/openTTS checkout main
git -C /home/andreaskesberg/openTTS branch -D backup/cloud-3d3441b
```

### P3.2 — The rewrite (corrected, combined size + licensing strip)

```bash
# 0. Resolve the lighting branch FIRST — do NOT lose its 3 commits (P-DEC-2)
gh pr create ... && gh pr merge claude/fix-model-lighting-47Qp0   # or rebase onto main

# 1. Untouched rollback mirror — NEVER modify this
git clone --mirror git@github.com:DutchMaxwell/openTTS.git /tmp/scrub-backup.git

# 2. Work copy + dry-run analysis
git clone --mirror git@github.com:DutchMaxwell/openTTS.git /tmp/scrub.git
cd /tmp/scrub.git && pip install git-filter-repo && git filter-repo --analyze
less .git/filter-repo/analysis/path-all-sizes.txt

# 3. Strip — directory-scoped globs ONLY (NO bare *.glb glob).
#    Includes licensing paths IF this is a public-release scrub (P-DEC-6).
git filter-repo --invert-paths \
  --path-glob 'assets/miniatures/*/glb/*' \
  --path-glob 'assets/terrain/grimdark_industrial/*' \
  --path-glob 'assets/miniatures/*/units.json' \
  --path 'assets/opr_samples' --path-glob 'examples/*.json' \
  --path 'addons/dice_roller' --path 'assets/tyras.json'

# 4. Verify the load-bearing survivors
git cat-file -e HEAD:assets/models/dice/d6_dice.glb && echo DICE-OK
git cat-file -p HEAD:project.godot | grep rendering_method.web   # must print the web line
git ls-tree -r v0.3.0-alpha | grep -c '\.glb$'                   # expect 0
git ls-tree -r models-v1     | grep -c '/glb/.*\.glb$'           # expect 0

# 5. Compact (the step missing from the current runbook), then push
git reflog expire --expire=now --all && git gc --prune=now --aggressive && du -sh .
# disable branch protection on main, then:
git push --force --mirror git@github.com:DutchMaxwell/openTTS.git
```

**Tags:** filter-repo auto-re-points `models-v1` and `v0.3.0-alpha` (verified:
rewritten trees carry 0 GLBs); `--mirror` carries them on push. Separately decide
whether to delete the **GitHub release** under `models-v1` (R2 now serves models;
the release-asset GLBs are orphaned delivery infra — a GitHub-release deletion,
independent of the git tag). **(P-DEC-7)**

**After the push:** re-clone every working copy; the old history is incompatible.

- **Risk:** high · **Reversible:** y (only via the untouched `/tmp/scrub-backup.git`) · **Effort:** medium · **Approval:** YES

**Rollback:**
```bash
cd /tmp/scrub-backup.git && git push --force --mirror git@github.com:DutchMaxwell/openTTS.git
```

### P3.3 — Update `docs/runbooks/history-scrub.md`

The runbook is a sound foundation but must be corrected/extended: fix the remote
URL (lines 26/53); add the terrain glob; add the bare-`*.glb`-deletes-the-dice
footgun warning; add the OPR/AGPL licensing paths; add the tag-repoint note; add
the `reflog expire` + `gc --prune=now --aggressive` post-step; refresh the stale
"viele `claude/*`-Branches" language; translate to English.

- **Risk:** none · **Reversible:** y · **Effort:** small · **Approval:** no

---

## Decisions needed from the maintainer

Crisp yes/no questions. P3 cannot start until P-DEC-1, P-DEC-2, P-DEC-5, P-DEC-6
are answered.

- **P-DEC-1 — Publish `high_elf_fleets` before any `state/` purge?**
  `state/` holds exactly **one irreplaceable item**: the finalized-but-unpublished
  `high_elf_fleets_20260607_011707` faction (26 GLBs, **443 MB** in `glb_final/`),
  which `faction_publish.py` stages from. The other ~150 off-R2 GLBs are
  non-finalized scratch. **May I run
  `python3 tools/model_forge/faction_publish.py high_elf_fleets_20260607_011707`
  to R2 first, then treat the redundant on-R2 session dirs as deletable?**
  (Yes/No)

- **P-DEC-2 — How to preserve the 3 unmerged lighting commits on
  `origin/claude/fix-model-lighting-47Qp0`?** They are real, unmerged work.
  **Merge/rebase them to `main` before the P3 scrub (recommended), or keep the
  branch through the rewrite — but not delete it.** (Merge / Keep)

- **P-DEC-3 — Delete the dead `examples/` folder?** Its README documents a JSON
  that is gitignored and absent; no code references it. (Yes/No — delete vs rewrite)

- **P-DEC-4 — Delete `tools/3d-generation/`?** Stale Colab predecessor of
  `tools/model_forge/`; nothing references it. (Yes/No)

- **P-DEC-5 — Run the P3 history rewrite at all?** It is irreversible (force-push)
  and only worthwhile if a **public/MIT release is imminent**. Otherwise the prior
  "skip the rewrite, just `git gc`" decision stands. **Is a public release planned
  now?** (Yes → P3 / No → stop at P0.7)

- **P-DEC-6 — Public-release strip scope?** If P3 runs for release, include the
  **licensing** paths (OPR `units.json`, `assets/opr_samples`, `examples/*.json`)
  and **AGPL `addons/dice_roller`** in the same pass? (Yes, strongly recommended /
  No — size-only)

- **P-DEC-7 — Delete the `models-v1` GitHub *release*?** Its release-asset GLBs are
  orphaned now that R2 serves models. (Yes/No — independent of the git tag)

---

## Cross-dimension agreement (higher confidence)

These findings surfaced independently in multiple audits — treat as high-confidence:

- **`.git` bloat = committed-then-removed R2-delivered media.** (git history,
  asset, licensing dimensions + adversarial verifier — *empirically measured*.)
- **The orphan `test_nodename_probe.gd.uid`.** (structure, dead-code, asset, CI.)
- **The web `gl_compatibility` strip-on-editor-save gotcha.** (git history, disk,
  code, CI — and verified to survive the rewrite.)
- **Terrain `.gitignore` gap → re-bloat risk.** (git history dimension + verifier.)
- **Dice GLB footgun** (directory globs safe, bare `*.glb` fatal). (git history +
  verifier, both with empirical strip tests.)
- **R2 is the live delivery channel; GitHub-Releases docs are stale.** (docs +
  licensing dimensions.)
