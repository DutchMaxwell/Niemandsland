# Runbook — scrub the git history (repo-size + pre-release licensing)

**Purpose:** retroactively delete from the **entire git history** content that was
only removed from the current tree (`git rm`), to shrink `.git` and clear
licensing residue before the repo goes public / MIT:

- on-demand **GLBs** (miniatures + terrain), now delivered from R2 — pure size win;
- **OPR data** (stats/lists are OPR content, not MIT-licensable);
- the former **AGPL `dice_roller` addon** (copyleft), replaced by the MIT dice scripts.

> ⚠️ **Destructive and one-shot.** `git filter-repo` rewrites **every commit SHA**.
> A force-push is required; **all existing clones/forks become incompatible** and must
> be re-cloned. Run only when the repo is consolidated (open PRs merged/closed, work on
> `claude/*` branches merged to `main` or intentionally dropped).
>
> This runbook reflects the scrub performed 2026-06-08 (`.git` 1.2 GB → 64 MB). The
> footguns called out below are ones that actually bit during that run.

## 0. Prerequisites
```bash
# Single-file install (avoids Fedora's externally-managed-pip restriction):
curl -fsSL https://raw.githubusercontent.com/newren/git-filter-repo/main/git-filter-repo \
  -o /tmp/git-filter-repo && chmod +x /tmp/git-filter-repo
python3 /tmp/git-filter-repo --version
```
- Remote is **`git@github.com:DutchMaxwell/openTTS.git`** (SSH, repo *openTTS* — **not**
  "Niemandsland"). `gh auth status` should be logged in.
- Disable GitHub **branch protection** on `main` for the force-push if it is enabled
  (it was not, 2026-06-08).
- `/tmp` here is a small tmpfs — do all mirror work under `/home` (hundreds of GB free).

## 1. Backup mirror (untouched rollback — never modify it)
```bash
git clone --mirror git@github.com:DutchMaxwell/openTTS.git ~/scrub-backup.git
```

## 2. Fresh work mirror — and DO NOT pre-edit its refs
```bash
git clone --mirror ~/scrub-backup.git ~/scrub.git     # local clone is fast
cd ~/scrub.git
```
> 🔴 **Footgun:** do **not** manually delete `refs/pull/*` or branches with
> `update-ref` *before* running filter-repo. Doing so left the work mirror with a
> wrong `main` tip and an ineffective strip. Run filter-repo on the **pristine** mirror
> and handle unwanted refs only at push time (Step 5).

## 3. Strip the paths from the ENTIRE history
```bash
python3 /tmp/git-filter-repo --invert-paths \
  --path-glob 'assets/miniatures/*/glb/*' \
  --path-glob 'assets/terrain/grimdark_industrial/*' \
  --path-glob 'assets/miniatures/*/units.json' \
  --path 'assets/opr_samples' \
  --path-glob 'examples/*.json' \
  --path 'addons/dice_roller' \
  --path 'assets/tyras.json'
```
> 🔴 **Footgun:** use the **directory-scoped** globs above. A bare `*.glb` glob would
> also delete `assets/models/dice/d6_dice.glb` — keep dice GLBs out of the strip set.
> (As of 2026-06-08 those dead dice files were already removed from the tree, but the
> rule stands.)

## 4. Verify the stripped mirror BEFORE pushing
```bash
du -sh .                                                   # expect ~64 MB
git cat-file -p main:project.godot | grep rendering_method.web   # web export line MUST survive
git cat-file -e main:docs/HOUSEKEEPING_PLAN.md && echo HEAD-OK   # recent work present
for p in 'miniatures/[^/]+/glb/' 'terrain/grimdark_industrial/' 'addons/dice_roller' \
         'miniatures/[^/]+/units.json' 'assets/opr_samples' 'assets/tyras.json'; do
  echo "$p : $(git rev-list --objects --all | grep -cE "$p")"   # all must be 0
done
git ls-tree -r models-v1 | grep -cE '/glb/.*\.(glb|webp)$'       # expect 0
git fsck --full                                                  # clean
```

## 5. Push explicitly — NOT `--mirror`
```bash
URL=git@github.com:DutchMaxwell/openTTS.git
git push --force "$URL" main:refs/heads/main
git push --force "$URL" refs/tags/models-v1 refs/tags/v0.3.0-alpha   # tags re-pointed
git push "$URL" --delete claude/3d-graphics-overhaul claude/fix-model-lighting-47Qp0
```
> 🔴 **Footgun:** `git push --force --mirror` fails here — a `--mirror` clone pulls in
> ~46 GitHub-managed `refs/pull/*` refs that are **read-only**, so a mirror push tries
> to delete them and is rejected. Push the refs you actually own (main, tags, branch
> deletes) explicitly instead.

## 6. Reconcile every local working copy
```bash
cd /path/to/openTTS
git fetch origin --prune                 # force-updates origin/main, prunes deleted branches
git checkout main && git reset --hard origin/main
git branch -D <every other local branch>           # they sit on the old history
git tag -d models-v1 v0.3.0-alpha && git fetch origin --tags   # 🔴 fetch does NOT update existing tags
git reflog expire --expire=now --all
git gc --prune=now --aggressive          # only now does local .git drop to ~64 MB
```
> 🔴 **Footgun:** old **tags** were the last refs holding the 1.2 GB alive locally —
> `git fetch --prune` does not move existing tags, so delete and re-fetch them, then gc.
> Gitignored scratch (`tools/model_forge/state/`, `.godot/`, …) is untracked and survives.

## 7. Aftermath
- Re-enable branch protection on `main`.
- Re-clone any **other** working copy; old clones are incompatible.
- **GitHub-side residue:** the old blobs remain reachable on GitHub via the closed-PR
  `refs/pull/*` refs and via any forks, so a normal `git clone` is clean (~64 MB) but
  GitHub's stored copy is not fully purged. For complete deletion, contact GitHub
  Support to run gc and check for forks.
- Optionally delete the `models-v1` GitHub **release** (its release-asset GLBs are
  orphaned now that R2 serves models — independent of the git tag).

## Linked checklist
Ticks the "scrub git history" item in [`../PRE_RELEASE_LICENSING.md`](../PRE_RELEASE_LICENSING.md).
