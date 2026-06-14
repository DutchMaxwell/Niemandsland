# Model Forge extraction — lossless handoff to the private repo

**For the model-forge agent**, before `tools/model_forge/` (+ `assets/3d_pipeline/`) is
removed from this public repo by PR #51 ("Go-public cleanup").

The game never imports the pipeline — it only reads `assets/model_manifest.json` and
streams GLBs from R2 — so removing it does not affect the game. The risk is purely on
**your** side: moving the pipeline into the new private `model-forge` repo **without
losing work**.

## ⚠️ The one trap: "git-tracked" ≠ "everything"

A subtree split / filter-repo / PR-diff view only ever carries the **142 git-tracked**
files. The bulk of the real pipeline is **git-ignored** and is therefore invisible to
anyone who only looks at tracked files or the PR. Audited 2026-06-14 on `main` @
`9988faf`:

### MUST be copied separately into the private repo (git won't move these)

| Item | Path(s) | Why it matters |
|---|---|---|
| **Secrets (4)** | `tools/model_forge/.gemini_key`, `.hf_token`, `.r2_credentials`, `.trellis_space` | API keys/credentials; the pipeline can't run without them. Never commit to a public repo — keep them gitignored in the private one (or a secrets manager). |
| **33 working scripts** | `tools/model_forge/_*.py` (`_ah_*`, `_bb_publish`, `_hl_*`, `_glb_*`, `_reproject_*`, `_studio_render`, `_overnight` …) | Excluded by the `.gitignore` pattern `_*.py` → **never committed**. The subtlest loss: "move my git changes" misses all 33. Triage which to keep, copy them in. |
| **`rework_flags.json`** | `tools/model_forge/rework_flags.json` | Your R2-browser rework/debase flag tracking. Small — take it. |
| **`state/` (decide)** | `tools/model_forge/state/` — **7.1 GB**, 87 per-faction session dirs + logs | Intermediate sessions/scratch. The **final models are already safe on R2** (532 GLBs in `assets/model_manifest.json`), so this is only needed if you want the sessions/intermediates. Back up or discard deliberately. |
| reproducible | `venv/`, `__pycache__/`, `.bbtmp/`, `state/*.log` | ~230 MB, regenerable → skip. |

### git-tracked (safe — carry with history)

- 142 files under `tools/model_forge/` + `assets/3d_pipeline/`.
- Use a **history-preserving** export, e.g. `git subtree split -P tools/model_forge -b model-forge-export` (and likewise for `assets/3d_pipeline/`), then push that branch into the new repo — so the pipeline's commit history isn't flattened.

## Order of operations (lossless)

1. Finish/settle any in-flight model_forge work first (no new untracked files mid-export).
2. Copy the **git-ignored** items above into the private repo (secrets + the 33 `_*.py` + `rework_flags.json`; decide on `state/`).
3. History-preserving export of the **tracked** files (subtree split) → push to the private repo.
4. **Verify in the private repo**: the pipeline runs end-to-end (secrets present, scripts present).
5. Only then is it safe for the public repo to drop the tree (PR #51 merge).

## Notes / current state

- The "preservation bundle" mentioned in PR #51's body is from **2026-06-12** — it predates the latest tracked work (High-Elf fixes, `debase_flagged.py`) **and** does not contain any of the git-ignored items above. Re-export from the **current** `main`, don't rely on that bundle.
- `main` is clean and fully pushed as of this note; nothing is uncommitted.
- After your extraction is confirmed complete, the game-codebase agent will rebase PR #51 onto current `main` (resolving the one `PROJECT_STATUS.md` conflict) and it becomes merge-ready. This note can be deleted as part of that merge.

*Audited by the game-codebase agent, 2026-06-14. Source: `git ls-files` / `git status --ignored` / `du -sh` over `tools/model_forge/`.*
