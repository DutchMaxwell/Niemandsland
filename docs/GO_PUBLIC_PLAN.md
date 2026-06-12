# Go-Public Plan — making `main` safe to publish

One-pager for taking the repo public and opening the alpha. Audit date: 2026-06-12.

## Where we stand (audited)

| Area | Status |
|---|---|
| Secrets / API keys | ✅ Clean — all credentials git-ignored or env-based; nothing hardcoded, nothing in history |
| OPR data / AGPL addon | ✅ Purged from the **entire history** (scrub of 2026-06-08, re-verified today) |
| Licensing | ✅ MIT `LICENSE`, `THIRD_PARTY.md` complete, font/icon licenses bundled |
| README / docs | ✅ Presentable for a public alpha |
| Personal data | ⚠️ Real name exposed — see below |

The stale checkbox "Scrub git history" in `PRE_RELEASE_LICENSING.md` can be
ticked; the scrub is done and verified (no `opr_samples`, `units.json`,
`addons/dice_roller`, or bundled GLBs anywhere in history).

## The one real finding: personal name in the repo

1. **`/home/user/...` paths** (67 hits in 4 files):
   `docs/HOUSEKEEPING_PLAN.md`, `docs/VISION_AND_ROADMAP.md`,
   `docs/archive/AAA_UI_PLAYBOOK.md`,
   `tools/model_forge/engine_comparison/trellis/result.json`. Easy fix: replace
   with `$REPO_ROOT` / relative paths, or drop the internal docs entirely.
2. **`<legacy-cdn-host>`** as the runtime asset CDN (22 files: all asset
   manifests, publish tools, several docs). **Decision needed:** the shipped
   game contacts this domain anyway, so the repo going public reveals nothing
   new — but if you want the project decoupled from your surname, switch to a
   neutral domain (R2 custom domain / `*.r2.dev`) *before* publishing, since
   every manifest and client build bakes it in.
3. Both also live in **old commits**. If (and only if) the name should go, do
   one final history rewrite right before flipping public — cheap now (no
   forks), impossible later. Otherwise accept and skip.

## Plan

**Phase 1 — Decide (you, 10 min):**
D1: keep `<legacy-cdn-host>` or move to a neutral domain?
D2: keep internal working docs (`HOUSEKEEPING_PLAN`, `HANDOFF_*`,
`docs/archive/`) public, or prune them?
D3: keep `tools/model_forge/` in-repo or split it out (open item in
`PRE_RELEASE_LICENSING.md` — it carries the OPR faction-name references)?

**Phase 2 — Clean (1–2 h):**
Remove `/home/user` paths; prune docs per D2; neutralize OPR
identifiers in `design_languages/*.yaml` (open 🟡 item); tick the stale scrub
checkbox; if D1 = move, swap the domain in manifests + tools. If anything
name-related changed, run the final history rewrite
(`docs/runbooks/history-scrub.md` pattern, or a fresh orphan squash).

**Phase 3 — Gate (external):**
IP-lawyer review — your own declared 🔴 blocker in `PRE_RELEASE_LICENSING.md`
(AI-generated minis + OPR-derived design languages). Plus a fresh-clone
read-through as final self-check.

**Phase 4 — Flip public + open the alpha (1 h):**
Enable secret scanning + push protection and branch protection on `main`;
set repo description/topics; add issue templates or a feedback discussion;
publish a `v0.2.0-alpha` GitHub Release with builds (the in-game update
checker already points at the GitHub Releases API); then
Settings → Danger Zone → make public, and invite the alpha testers.

## Bottom line

No secrets, no license residue, history already scrubbed — the repo is closer
to publishable than it feels. The only genuinely open question is whether your
surname (domain + old paths) may be public. Decide that, spend the 1–2 h of
Phase 2, get the lawyer sign-off, flip the switch.
