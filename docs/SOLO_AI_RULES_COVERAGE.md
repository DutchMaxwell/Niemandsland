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
| **Surge** (unmodified 6-to-hit → +1 hit, any range) | ⏳ sim / ✅ **real game** | `AiCombatMath.surge_bonus_hits` in `main._solo_hits` (both directions). Sim wiring open. |
| **Furious** (charging melee: unmodified 6-to-hit → +1 hit) | ⏳ sim / ✅ **real game** | `AiCombatMath.furious_bonus_hits` (unit rule stamped onto melee profiles) in `main._solo_hits`, charge sites only. Sim wiring open. |
| **Rending** (unmodified 6-to-hit → AP(+4) on those hits) | ⏳ sim / ✅ **real game** | `AiCombatMath.rending_ap_hits` + `main._solo_resolve_saves` (a separate AP(+4) save batch), both directions. Regeneration-bypass facet was already wave-1. Sim wiring open. Blast×Rending on one weapon: the AP(+4) count is capped at the post-Blast hits (documented edge; the field armies never carry both on one weapon). |
| **Reliable** (weapon shoots at Quality 2+) | ⏳ sim / ✅ **real game** | `AiCombatMath.reliable_quality` — wired into both real shooting directions (2026-07-10 game-feel wave). Sim wiring: clamp per profile in `_resolve_volley` (still open). |
| **Blast(X)** (each hit ×X up to models in target) | ⏳ sim / ✅ **real game** | `AiCombatMath.blast_hits` (rulebook example pinned by test) + cover-ignore per profile — both real directions, with a visible battle-log line. Sim wiring still open. |
| **Impact(X)** (X auto hits on charge) | ⏳ sim / ✅ **real game** | `AiCombatMath.impact_hits` + `main._solo_charge_impact` (X dice per charging model, 2+ = a hit, before the normal strikes, skipped if fatigued; saves at plain Defense), both charge directions. Does NOT yet subtract Counter models (Counter deferred). Sim wiring open. |
| **Counter** (strikes first when charged; −Impact) | ⏳ **deferred** | Would reorder the interactive melee flow so a Counter defender strikes BEFORE the charger (and subtract 1 Impact roll per Counter model). Deferred this wave: the strike-first reorder restructures the await-driven melee, higher regression risk than the additive rules; still logged as un-automated. |
| **Fearless** (re-roll a failed morale on 4+) | ⏳ sim / ✅ **real game** | `AiCombatMath.fearless_recovers` in `main._solo_morale_test` (shared by both directions) — a failed test re-rolls one real tray die, 4+ passes. Present on the whole test army. Sim wiring open. |
| **Fear(X)** (+X wounds for who-won-melee) | ⏳ sim / ✅ **real game** | `AiCombatMath.fear_adjusted_wounds` in both melee-winner comparisons (`_run_ai_melee` / `_run_human_attack`). Comparison-only; never changes wounds applied. Sim wiring open. |
| **Bane / Lacerate** (target re-rolls unmodified block 6s) | ⏳ sim / ✅ **real game (Bane)** | `AiCombatMath.blocks_with_bane` + `main._solo_save_batch` — the defender re-rolls its unmodified Defense 6s once (extra tray dice), respecting the melee/shooting Bane variants; auras excluded. Regeneration-bypass facet was already wave-1. Lacerate is an army-specific name (not in the core PDF) → its re-roll facet stays logged, regen-bypass only. Sim wiring open. |
| **Thrust** (+1 hit & AP(+1) in melee on charge) | ⏳ sim / ✅ **real game** | `AiCombatMath.thrust_to_hit` + `main._solo_thrust_profile` — charging melee gets +1 to hit (fatigue's unmodified-6 overrides it) and AP(+1), both charge directions. Sim wiring open. |
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
Aura** 🆕 (the medic), and — as of **Wave 2** — **Fearless** ✅, **Blast** ✅, **Reliable** ✅ in the real
game. The remaining honest gap for this army is **Battleborn** (Shaken→4+ recover at round start — an
army-specific rule, no core-PDF definition, still logged). Wave-2 combat lethality changes both sides
symmetrically.

## Wave 2 — combat special rules (real game, 2026-07-10)

Ranked by real frequency across the two field-test army books (GF *Battle Brothers* `bb.json` + an AoF
*Royal Legion* book: AP 47/23, Rending 9, Bane 9, Fear 7, Thrust 6, Impact 5, Fast 4, Counter 3, Fearless
6+3), the following combat rules are now automated in the **real game** (`main.gd`) both directions (AI
attacks human AND human attacks AI, including the human-defender save prompts), each backed by a pure,
unit-tested `AiCombatMath` helper and verified verbatim against the GF/AoF Advanced Rules v3.5.1 PDFs:

- **Fearless** (p.13) — failed morale re-rolls once, 4+ passes (`_solo_morale_test`).
- **Surge** (p.14) — +1 hit per unmodified 6, any range; **Furious** (p.14) — +1 hit per unmodified 6 in a
  charging melee (`_solo_hits`).
- **Rending** (p.14) — unmodified 6-to-hit save at AP(+4) (`_solo_resolve_saves`, a separate save batch).
- **Bane** (p.13) — the defender re-rolls unmodified Defense 6s once (`_solo_save_batch`), completing the
  wave-1 regen-bypass facet.
- **Impact(X)** (p.13) — X charge dice per model, 2+ = a hit, before the normal strikes, skipped if
  fatigued (`_solo_charge_impact`).
- **Thrust** (p.14) — charging melee +1 to hit and AP(+1) (`_solo_thrust_profile` + `thrust_to_hit`).
- **Fear(X)** (p.13) — +X wounds for the who-won-melee check only (both melee comparisons).

Following the wave-1 Blast/Reliable precedent, these are wired into the **real game only** (the SIM's
`_resolve_volley`/`_strike` are untouched), so the **mirror-fairness oracle is byte-identical to before and
needs no re-run**. Sim wiring stays open (⏳). **Deferred:** Counter (strike-first reorder of the interactive
melee), Stealth/Evasive/Shielded (−to-hit target modifiers), Caster, Mend, Indirect/Artillery deploy
facets — all still logged as un-automated. Army-specific rules with no core-PDF definition (Battleborn,
Destructive, Shred, Lacerate's re-roll, Royal-Legion/faction rules) remain logged.

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
