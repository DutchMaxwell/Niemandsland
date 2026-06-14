> ⛔ **INTERNAL — maintainer's control board.** Private to you. Remove before the repo
> goes public (it lives in `_internal/`, which the history scrub purges). Keeps your
> strategy/IP tasks off the public roadmap.

# Niemandsland — Maintainer Board

Your single overview of everything on the plate: **your tasks** + the dev queue. The
public, player-facing feature plan lives in [`../docs/ROADMAP.md`](../docs/ROADMAP.md);
the click-by-click for the release tasks is in
[`GOING_PUBLIC_CONTROLS.md`](GOING_PUBLIC_CONTROLS.md).

Lifecycle: `💡 Idea → 🔍 Triage → 📋 Next → 🔨 In progress → ✅ Done`. You tick your
boxes; the agent works the ROADMAP Now/Next and updates both on merge.

## 🧑‍✈️ Your tasks — before going public

- [ ] **Merge PR #51 → `main`** (consolidate the go-public + Regiments work; CI is green)
- [ ] **Register a neutral domain + bind R2**, then change the one `AssetCDN.HOST`
      constant in `scripts/asset_cdn.gd` (drops the surname from the running game)
- [ ] **Git-history scrub** — purge `_internal/`, the old `tools/model_forge/`, and the
      surname from history (one-shot `git filter-repo`, right before flipping public)
- [ ] **IP-lawyer review** — your declared blocker (AI-generated + OPR-derived assets)
- [ ] **GitHub settings** — branch protection on `main`, private vulnerability reporting,
      Discussions on (see `GOING_PUBLIC_CONTROLS.md` §B for exact clicks)
- [ ] **Tag `v0.3.2-alpha`** release (the in-app update checker compares against it)
- [ ] **Flip repo public** + soft-launch (invite a handful of alpha testers, quietly)

## 🔎 Your tasks — interactive verification (in the running game)

These can't be checked headless here (no display; Army Forge is blocked by the sandbox
egress policy), so they're yours:

- [ ] **Regiment import** — `aofr` units appear as ranked blocks on **square bases**;
      base sizes look right against a real Army Forge list
- [ ] **Regiment handling** — select / drag / rotate the block feels right; casualties
      close the rear rank
- [ ] **Two-client multiplayer** — lobby / chat / names + the relay (room browser, host
      reconnect) across two real clients
- [ ] **Save/load** — a mid-game save with regiments reloads identically

## 🛠️ Dev queue (mine to build) — authoritative list in `docs/ROADMAP.md`

At a glance (the ROADMAP is the source of truth):

- 🔨 **Now:** Regiments **M5** — facing arrow + front-arc + "LOS toward front" aid (display only)
- 📋 **Next:** verify AoFR import vs a real list · two-client MP test · Regiments polish
  (frontage cycle, wheel) · units-as-LOS-blockers · UI sound bus

## Notes

- When you toss me a request in chat, I file it into `docs/ROADMAP.md` (Next/Ideas) so it
  isn't lost.
- This board is for **you**; the public sees only `docs/ROADMAP.md` + GitHub issues.
