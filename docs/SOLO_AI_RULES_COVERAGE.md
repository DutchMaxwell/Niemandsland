# Solo-AI — Special-Rule Coverage Matrix

Systematic inventory of the OPR special rules that touch **combat / AI behaviour**, and whether the
headless self-play sim (`scripts/solo/`) models each one. This is the M2/M3 backlog driver: the sim now
**logs any unit rule it does not model, once per game** (see `SoloSim._log_unmodeled_rules`), so field tests
and the phone review app *show* the gaps instead of hiding them.

## Sources (authoritative — verified against the PDFs, not memory/web)

- **GF – Advanced Rules v3.5.1** — `<local rulebooks>/GF_-_Advanced_Rules_v3_5_1.pdf`
  (weapon/model special-rule definitions; melee "Who Can Strike"; Deadly clarification).
- **GF – Solo & Co-Op Rules v3.5.0** — same folder — the AI decision trees + the target/action **overlays**.
- **Test army** — the real *Battle Brothers* Army-Forge list (`bb.json`), the union of rules actually
  fielded (incl. rules granted by upgrades/items, which AF nests under `content`).

Mount was available on 2026-07-09; every rule below was read from the PDFs/army data.

## Legend

- ✅ **IMPLEMENTED** — modelled in the sim (pre-existing).
- 🆕 **THIS CHUNK** — added in the M2 combat chunk (2" melee · split fire · AP/Deadly/Takedown/Relentless · Medic).
- ⏳ **NOT YET** — recognised (and logged) but not modelled; the note says what it would take.
- ➖ **N/A here** — not combat-relevant to the point-sim (deployment/transport/campaign), tracked for completeness.

---

## A. Core combat / weapon rules (GF Advanced Rules v3.5.1)

| Rule | Status | Where / what it'd take |
|---|---|---|
| Quality / Defense tests, 6-hits-always, 1-misses-always | ✅ | `DiceRules`, `AiCombatMath` |
| **AP(X)** (–X to the target's block rolls) | ✅ | `AiCombatMath.save_target` (Defense+AP) |
| **Tough(X)** (wound pool per model) | ✅ | `SoloSim.alive_models` / `_apply_wounds` |
| LOS / Cover / Difficult / Dangerous terrain | ✅ | `TerrainRules` (shared with `terrain_overlay.gd`) |
| 1" enemy spacing · Fatigue · Shaken · morale/Rout | ✅ | `SoloSim` |
| **Melee "Who Can Strike" — only models within 2"** | 🆕 | `SoloSim._striking_models` / `_effective_melee_attacks` (p.9; base-contact folded into centre distance) |
| **Split fire** (weapon types → different targets) | 🆕 | `SoloSim._resolve_shooting_split` (p.8) |
| **Deadly(X)** (×X to one model, Tough-capped, overkill lost) | 🆕 | `AiCombatMath.deadly_multiplier` + `_resolve_volley`/`_strike`. Pooled-sim note: exact only when X ≥ Tough (the common case); a Deadly hit with X < Tough may pool onto the next model rather than strictly losing overkill. |
| **Relentless** (>9" shooting: unmodified 6 → +1 hit) | 🆕 | `AiCombatMath.relentless_bonus_hits` in `_resolve_volley` |
| **Takedown** (snipe a model as a unit of [1]) | ⏳ | targeting overlay done (§B); the *damage* facet (resolve one model as unit-of-1, ignore other models' LOS/cover) needs per-model wound tracking — the pooled sim assigns to the unit. |
| **Surge / Furious / Rending** (unmodified 6-to-hit bonuses) | ⏳ | add a per-face bonus like Relentless: Surge = +1 hit any range; Furious = +1 hit on charge; Rending = AP(+4) on 6s. Hook: `_resolve_volley`/`_strike` after `count_hits`. |
| **Reliable** (weapon shoots at Quality 2+) | ⏳ sim / ✅ **real game** | `AiCombatMath.reliable_quality` — wired into both real shooting directions (2026-07-10 game-feel wave). Sim wiring: clamp per profile in `_resolve_volley` (still open). |
| **Blast(X)** (each hit ×X up to models in target) | ⏳ sim / ✅ **real game** | `AiCombatMath.blast_hits` (rulebook example pinned by test) + cover-ignore per profile — both real directions, with a visible battle-log line. Sim wiring still open. |
| **Impact(X)** (X auto-ish hits on charge) | ⏳ | roll X dice on charge, 2+ = a hit, before the normal strike (skip if fatigued). |
| **Counter** (strikes first when charged; −Impact) | ⏳ | reorder `_resolve_melee` so a Counter defender strikes before the charger. |
| **Fearless** (re-roll a failed morale on 4+) | ⏳ | in `_morale`, on a fail roll one die, 4+ = pass. Present on the whole test army. |
| **Fear(X)** (+X wounds for who-won-melee) | ⏳ | add X to the striker's caused-wounds only for the melee winner comparison. |
| **Bane / Lacerate** (target re-rolls unmodified block 6s) | ⏳ | re-roll defender save faces of 6 once in `AiCombatMath.wounds`. |
| **Thrust** (+1 hit & AP(+1) in melee on charge) | ⏳ | charge-only to-hit/AP bump in `_strike`. |
| **Stealth / Evasive / Shielded / Defense(+X)** (−to-hit / +Defense) | ⏳ | per-target defensive modifiers in `_resolve_volley` (like Cover). Shielded/Evasive present on other HDF units. |
| **Regeneration / Regeneration Aura** (ignore each wound on 5+) | 🆕 | `SoloSim._apply_regeneration` — **this is the Battle Brothers "Medical Training" medic** (the item grants Regeneration Aura). |
| **Mend** (active: remove D3 wounds from a friendly Tough model) | ⏳ | not in the test army; needs an activation-phase heal step (pick friendly Tough model within 3", remove D3). Distinct from the passive Regeneration medic above. |
| **Fast / Slow** (±move) | ⏳ | read into `advance_in`/`rush_in` at import (currently fixed 6"/12"). |
| **Immobile** (Hold only) | ⏳ | force HOLD in `_activate` (like the Relentless overlay). |
| **Limited** (once per game) | ➖ | 4-round sim rarely exhausts it; ammo tracking is low value here. |
| **Caster** (cast a random spell after moving) | ⏳ | spell system unmodelled; Solo rule: D3+level random spell after move. |
| **Aircraft / Flying / Strider / Ambush / Scout** | ➖/⏳ | movement/deployment facets; the Solo overlays (§B) are the AI-relevant part. |
| **Transport(X) / Unstoppable** | ➖ | transports & aircraft-only targeting are out of the point-sim's scope. |

## B. Solo & Co-Op AI overlays (Solo & Co-Op Rules v3.5.0, p.2)

These change **which target** a weapon picks or **which action** a unit takes (not the damage math).

| Overlay | Status | Where / what it'd take |
|---|---|---|
| Base target priority: nearest, **not-activated first**, **open over cover** | ✅/🆕 | `AiTargeting.best_index` (Overlay.NONE); open-over-cover added this chunk |
| **AP → highest-Defense target first** | 🆕 | `AiTargeting` Overlay.AP |
| **Deadly → single-model Tough first, then Tough (lowest remaining)** | 🆕 | `AiTargeting` Overlay.DEADLY |
| **Takedown → heroes first** | 🆕 (partial) | `AiTargeting` Overlay.TAKEDOWN. **Flagged:** the rules' "models with upgrades, most expensive first" tier is **not representable** — the sim has no per-model upgrade cost, so only *heroes-first* is honoured. |
| **Relentless → Hold and shoot when in range** | 🆕 | `SoloSim._forces_hold_and_shoot` |
| **Indirect / Artillery → Hold and shoot when in range** | ⏳ | same overlay as Relentless, but each also has damage/deployment facets (Indirect: −1 after moving + ignore LOS/cover; Artillery: deploy high, +1 >9") that need modelling before wiring the action, so they are deliberately left out this chunk. |
| Caster / Counter / Ambush / Scout / Aircraft ordering | ⏳/➖ | activation-order & deployment overlays; Counter/Shaken ordering partly handled by the turn engine. |

### Ambiguities flagged (not guessed)

- **Overlay precedence** when one weapon carries several (e.g. AP + Deadly): the Solo rules don't define it.
  We pick the most specific — **Takedown > Deadly > AP** — documented in `AiTargeting.weapon_overlay`, not an
  official rule.
- **Takedown upgrade tier** and **Takedown/Deadly single-model *sniping* damage**: not representable in the
  pooled point-sim (no per-model identity / upgrade cost). Only the parts that map cleanly are implemented.

## C. Present in the current test army (Battle Brothers `bb.json`)

Runtime unknown-rule log from the 1000-game mirror (game 1) after this chunk:

```
⚠ unmodeled special rule: Battleborn   (Shaken→4+ recover at round start)  → ⏳
⚠ unmodeled special rule: Fearless     (re-roll failed morale on 4+)        → ⏳
⚠ unmodeled special rule: Blast        (each hit ×X, ignores cover)         → ⏳
⚠ unmodeled special rule: Reliable     (shoots at Quality 2+)               → ⏳
```

Modelled for this army: **AP** ✅, **Tough** ✅, **Relentless** 🆕 (HMG), **Medical Training → Regeneration
Aura** 🆕 (the medic). The four rules above are the honest, visible gaps for the next chunk — none of them
break mirror fairness (both sides field them), but they change absolute lethality.

## Real-game visibility of the gaps

The REAL game now mirrors the sim's unknown-rule logging (2026-07-10): the first time a unit acts in solo
combat, every combat-relevant special rule the automation does not model is noted ONCE per session in the
battle log ("Note: \"Fearless\" is not automated in solo — apply it manually"). The modeled list lives in
`main.gd SOLO_MODELED_RULES`.

## Fairness (mandatory re-run — combat change)

Mirror oracle, Battle Brothers vs itself, symmetric terrain, no walls:

- 1000 games (seeds 1000–1999): **P0 45.2% / P1 53.8% / 1.0% draw** — inside 55/45.
- 2000 games (seeds 1000–2999): **P0 47.0% / P1 51.6% / 1.4% draw** — the 1000-game figure was partly
  seed-range variance; the wider sample settles near the known residual lean.

All changes are reflection-symmetric, so the mirror stays fair; combat is simply **less lethal / more
objective-decided** now (2" melee + Regeneration → ~67% of games decided on objectives). No tuning applied.
