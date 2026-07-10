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
| **Impact(X)** (X auto hits on charge) | ⏳ sim / ✅ **real game** | `AiCombatMath.impact_hits` + `main._solo_charge_impact` (X dice per charging model, 2+ = a hit, before the normal strikes, skipped if fatigued; saves at the Shielded-adjusted Defense), both charge directions. Wave 3: total dice reduced by the defender's Counter models (`AiCombatMath.impact_total_dice`, rulebook example pinned by test). Sim wiring open. |
| **Counter** (strikes first when charged; −Impact) | ⏳ sim / ✅ **real game** | Wave 3: the charged defender's Counter weapons resolve as a phase BEFORE the charger's attacks (incl. Impact) — `main._solo_melee_strike_phase` with a Counter/non-Counter profile filter, both directions (the human defender gets ONE strike-back choice covering the whole melee; the AI always strikes back, solo p.57). Impact reduction via `AiCombatMath.impact_total_dice`; the activation-order overlay (Counter last in section) in `SoloController._select_ai_unit`. Ordering note: the PDF does not pin Counter vs Impact — we resolve Counter first ("strikes first"; its Impact reduction presumes the counter-attack precedes), a documented reading. Sim wiring open. |
| **Fearless** (re-roll a failed morale on 4+) | ⏳ sim / ✅ **real game** | `AiCombatMath.fearless_recovers` in `main._solo_morale_test` (shared by both directions) — a failed test re-rolls one real tray die, 4+ passes. Present on the whole test army. Sim wiring open. |
| **Fear(X)** (+X wounds for who-won-melee) | ⏳ sim / ✅ **real game** | `AiCombatMath.fear_adjusted_wounds` in both melee-winner comparisons (`_run_ai_melee` / `_run_human_attack`). Comparison-only; never changes wounds applied. Sim wiring open. |
| **Bane / Lacerate** (target re-rolls unmodified block 6s) | ⏳ sim / ✅ **real game (Bane)** | `AiCombatMath.blocks_with_bane` + `main._solo_save_batch` — the defender re-rolls its unmodified Defense 6s once (extra tray dice), respecting the melee/shooting Bane variants; auras excluded. Regeneration-bypass facet was already wave-1. Lacerate is an army-specific name (not in the core PDF) → its re-roll facet stays logged, regen-bypass only. Sim wiring open. |
| **Thrust** (+1 hit & AP(+1) in melee on charge) | ⏳ sim / ✅ **real game** | `AiCombatMath.thrust_to_hit` + `main._solo_thrust_profile` — charging melee gets +1 to hit (fatigue's unmodified-6 overrides it) and AP(+1), both charge directions. Sim wiring open. |
| **Stealth** (−1 to hit, shot >9") | ⏳ sim / ✅ **real game** | Wave 3: `AiCombatMath.shooting_hit_modifier` → both shooting directions; "units where all models have this rule" honoured incl. attached heroes (`main._solo_rule_on_all_models`); battle log names the modifier. Sim wiring open. |
| **Evasive** (−1 to hit, any attack) | ⏳ sim / ✅ **real game** | Army-book rule (official Army Forge rule text carried by the field list — NOT in the core PDF): "Enemies get -1 to hit rolls when attacking units where all models have this rule." Shooting AND melee, both directions (`shooting_hit_modifier` / `melee_hit_modifier`). Sim wiring open. |
| **Shielded** (+1 Defense vs non-spell hits) | ⏳ sim / ✅ **real game** | Army-book rule (Army Forge text): `AiCombatMath.shielded_defense`, folded into EVERY save site (shooting, melee, Impact; Blast ignores cover but not Shielded) — prompts/logs show the modified threshold. No spell system → every hit qualifies. Sim wiring open. |
| **Defense(+X)** (army-specific stat bump) | ⏳ | not in the core PDF; stays logged as un-automated. |
| **Regeneration / Regeneration Aura** (ignore each wound on 5+) | 🆕 | `SoloSim._apply_regeneration` — **this is the Battle Brothers "Medical Training" medic** (the item grants Regeneration Aura). |
| **Mend** (active: remove D3 wounds from a friendly Tough model) | ⏳ | not in the test army; needs an activation-phase heal step (pick friendly Tough model within 3", remove D3). Distinct from the passive Regeneration medic above. |
| **Fast / Slow** (±move) | ⏳ sim / ✅ **real game** | the real AI's move bands come from `movement_range_controller.move_bands_for_props` (Fast +2"/+4", Slow −2"/−4", negation-aware). Sim import still fixed 6"/12" (open). |
| **Immobile / Artillery** (Hold only; Artillery ±to-hit >9") | ⏳ sim / ✅ **real game** | Wave 3: `SoloController.forces_hold` overrides the tree to HOLD (still shoots in range — Artillery solo overlay p.57); Artillery's +1 to hit (shooter, >9") and −2 to hit (as target, >9") via `shooting_hit_modifier`, both directions. Artillery's deploy-high overlay facet is NOT modeled (flagged). Sim wiring open. |
| **Limited** (once per game) | ➖ | 4-round sim rarely exhausts it; ammo tracking is low value here. |
| **Caster** (cast a random spell after moving) | ⏳ | spell system unmodelled; Solo rule: D3+level random spell after move. |
| **Aircraft / Flying / Strider / Ambush / Scout** | ➖/⏳/✅ | Ambush/Scout deployment ✅ (real game). Wave 3: **Strider** ignores the Difficult-halving and **Flying** additionally skips Dangerous tests on the real AI's moves (`SoloController._execute_move`, core p.13/14 + solo overlay p.57). Aircraft stays out of scope (➖). |
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
| **Indirect / Artillery → Hold and shoot when in range** | ⏳ / ✅ **Artillery (real game)** | Artillery: Hold-only + shoot (`SoloController.forces_hold`) with the ±to-hit facets modeled (Wave 3); its deploy-high facet stays open. Indirect (−1 after moving + ignore LOS/cover) remains deliberately out — its damage facets are unmodelled. |
| Caster / Counter / Ambush / Scout / Aircraft ordering | ⏳/✅ | Wave 3: **Counter last in section** implemented in the real game's pick (`SoloController._select_ai_unit`); Shaken-last was already in. Ambush/Scout deployment ✅. Caster/Aircraft remain out of scope. |

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
Aura** 🆕 (the medic), as of **Wave 2** — **Fearless** ✅, **Blast** ✅, **Reliable** ✅ — and as of
**Wave 3** — **Shielded** ✅, **Evasive** ✅, **Artillery** ✅ (all in the real game). The remaining honest
gap for this army is **Battleborn** (Shaken→4+ recover at round start — an army-specific rule, no core-PDF
definition, still logged) plus the aura/faction one-offs. Combat lethality changes both sides symmetrically.

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
needs no re-run**. Sim wiring stays open (⏳). Army-specific rules with no core-PDF definition (Battleborn,
Destructive, Shred, Lacerate's re-roll, Royal-Legion/faction rules) remain logged.

## Wave 3 — target-side modifiers, Counter, Hold-only, terrain-exempt movement (real game, 2026-07-10)

The sweep that closes the core-PDF combat backlog for the real game (same precedent: real game only, SIM
untouched, fairness oracle byte-identical):

- **To-hit modifiers**, composed via `AiCombatMath.modified_hit_target` (bounded [2,6] — natural 1/6, core
  p.1) on top of Reliable ("Reliable only changes the Quality value, so the roll can still be modified",
  p.14), applied in BOTH directions with the tray showing the modified target and a battle-log line naming
  the reason: **Stealth** (−1, shot >9", core p.14), **Artillery** (+1 shooting >9" / −2 shot at >9", core
  p.13), **Evasive** (−1, any attack — army-book rule, official Army Forge text).
- **Shielded** (+1 Defense, army-book text): folded into every save site both directions — shooting
  (Cover stacks; Blast ignores cover but not Shielded), melee, and Impact saves; prompts show the
  modified threshold.
- **Counter** (core p.13): strike-first as a pre-phase (`_solo_melee_strike_phase` + Counter/non-Counter
  profile filter — no restructure of the await-driven melee was needed), Impact-roll reduction
  (`impact_total_dice`, rulebook example pinned), and the solo activation-order overlay (Counter last in
  section, `_select_ai_unit`).
- **Immobile / Artillery Hold-only** (core p.13): `SoloController.forces_hold` overrides the decision tree
  (still shoots in range, per Artillery's solo overlay p.57).
- **Strider / Flying** movement (core p.13/14 + solo overlay p.57): the real AI's moves skip the
  Difficult-halving (both) and the Dangerous tests (Flying).

**Explicitly out of scope for this release** (kept truthfully in the un-automated log): Caster/spells,
Mend, Indirect (damage facets), Artillery's deploy-high placement, Aircraft, Limited (per-weapon ammo
state), Takedown's snipe-damage facet, Defense(+X) and all army-specific non-core rules (Battleborn,
Destructive, Shred, Lacerate's re-roll, faction rules). After Wave 3 no core-PDF rule that is both common
in the field armies and additive-implementable remains un-automated in the real game.

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
