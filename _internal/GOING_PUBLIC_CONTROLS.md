> ⛔ **INTERNAL — DO NOT SHIP PUBLICLY.** Operational checklist for the maintainer.
> Remove this `_internal/` folder before the repo goes public (the pre-release
> history scrub purges it).

# Keeping control when the repo goes public

Going public means people can **read** the code and **propose** changes. It does
**not** give anyone write access, a vote, or a claim on your time. You stay the sole
owner and maintainer. This file is the checklist to lock that in.

## A. Already done in the repo

- `.github/CODEOWNERS` → you are the required reviewer for every path.
- `CONTRIBUTING.md` → "How this project is run": maintainer-curated, discuss-before-PR,
  no obligation/SLA.
- `SECURITY.md` → private vulnerability reporting (no personal email exposed).
- Issue templates (Bug / Feedback) channel input.

## B. GitHub Settings to click (web UI — not in the code)

Repo → **Settings**:

1. **Branch protection** — *Branches → Add branch ruleset (or Add rule)* for `main`:
   - ✅ *Require a pull request before merging* (blocks direct pushes to `main`).
   - ✅ *Require status checks to pass* → select the CI checks (gdUnit4 Tests, the
     Export jobs) so nothing merges red.
   - ✅ *Require review from Code Owners* (uses the CODEOWNERS file).
   - ⚠️ As a **solo** maintainer, set *Required approvals* to **0** — GitHub does not
     let you approve your own PR, so a value ≥1 would lock you out of merging your own
     work. (Raise it later if you add collaborators.)
   - Leave *Do not allow bypassing* **off** so you can still merge/push in a pinch.
2. **Private vulnerability reporting** — *Settings → Code security → enable*. Matches
   `SECURITY.md`.
3. **Discussions** (optional, recommended) — *Settings → General → Features → enable
   Discussions*. A softer channel than Issues for "what do you think of…"; keeps the
   Issue tracker for actual bugs/tasks.
4. **Issues** — keep enabled (templates are in place). You can disable them entirely
   later if it ever gets noisy.
5. **Interaction limits** (only if there's ever a spike) — *Settings → Moderation →
   Interaction limits*: temporarily restrict commenting to prior contributors.
6. **Tidy features** — disable the **Wiki** and **Projects** if you don't use them
   (*Settings → General → Features*), so there are fewer channels to watch.

## C. Recommended soft-launch sequence

1. Finish the pre-public tasks in §D.
2. Flip the repo to **public quietly** — no announcement.
3. Share the link with a **handful of alpha testers** (or a small Discord). You
   control who shows up and how fast.
4. Widen the audience only once it feels comfortable.

## D. Pre-public tasks still outstanding (do these before flipping)

- **Register a neutral domain + rebind R2**, then change the one `AssetCDN.HOST`
  constant in `scripts/asset_cdn.gd` (drops the surname from the running game).
- **Git-history scrub** (`git filter-repo`) — removes `_internal/`, the old
  `tools/model_forge/` tree, and the surname from CHANGELOG history. The runbook is in
  the model-forge bundle/handover. One-shot; do it right before going public.
- **IP review — consciously skipped (risk accepted).** A paid IP lawyer is out of
  budget, so we are not getting one. The residual exposure is reduced: the
  GW-referencing material (design-language avoid-lists, reference images) moved to the
  private pipeline repo; OPR data is API-only and never bundled; our code is MIT; the
  minis are AI-generated. Remaining risk = AI outputs that resemble copyrighted minis —
  mitigated by the pipeline's IP-compliance prompts, not legally vetted. Mitigation if
  challenged: take-down/replace the specific asset (R2 is content-addressed, swap is cheap).
- Tag a **`v0.3.2-alpha`** GitHub Release (the in-app update checker compares against
  the latest release tag).

## E. Panic buttons (it's all reversible)

- **Make private again** — *Settings → General → Danger Zone → Change visibility*.
- **Archive** (read-only, stays visible) — *Danger Zone → Archive*.
- **Disable Issues** — *Settings → General → Features*.
- **Lock a thread** / **block a user** / **report abuse** — per-issue and per-user
  controls.

Bottom line: outsiders can only ever *suggest*. Merging, direction and scope stay
yours.
