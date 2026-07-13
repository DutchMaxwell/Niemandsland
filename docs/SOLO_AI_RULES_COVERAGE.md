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

## Final package — rule-true, glass-clear AI movement (real game, 2026-07-10)

The maintainer's five field-feedback guarantees, each verified against GF Advanced Rules v3.5.1
(General Movement p.7, difficult terrain p.11, dangerous p.12, consolidation p.9; AoF identical):

1. **Base-width swept corridor** — every AI model's move draws a stadium-shaped corridor exactly one
   base-width wide (outer base edges as bright lines, translucent fill, semicircle caps), fading after
   the move (`main._solo_spawn_move_corridor`). Oval bases sweep their circumscribed (long-axis) circle.
2. **Hard no-clip** — the planner inflates walls by the moving base's radius (+0.1" epsilon) and routes
   difficult/impassable cells AROUND (solo overlay p.57: AI units "must always move around" difficult
   terrain) via base-aware `MovementPlanner` opts (clearance / zones / avoid_cells — all opt-in; the SIM
   passes none and stays byte-identical). **Consistency fix:** difficult terrain is a **6" CAP** on the
   whole move (p.11: "may not move more than 6” for that movement") — the former ×0.5 halving matched
   the rule only for a 12" band. The cap now triggers off the ACTUAL planned polyline (goes around at
   the full band when possible; capped + re-planned through when the destination lies inside), and
   Dangerous tests count models whose actual route crossed (p.12).
3. **Distance truth** — budgets come from `movement_range_controller.move_bands_for_props` (single
   source, incl. Fast/Slow); each model's polyline arc is measured and trimmed to the granted budget
   (p.7: "no part of their bases move further than the total movement distance"), and a corridor label
   shows `actual" / budget"`.
4. **Followable pacing** — models GLIDE along their corridors (teleporting removed); the Fast-AI toggle
   accelerates the glide by 1/PACE_FAST_SCALE instead of skipping it.
5. **1" unit separation** — EVERY other unit's models (friendly AND enemy — p.7: "Models may never be
   within 1” of models from OTHER UNITS, unless they are taking a Charge action, and may never move
   through other models or units (friendly or enemy), even if they are taking a Charge action") become
   no-go circles (base radius + 1" + the mover's radius); only the moving unit's own models are exempt.
   Paths neither cross nor end inside a zone. On a Charge, the exception applies ONLY toward the charge
   TARGET, whose models become BODY-ONLY obstacles (both radii, no 1" buffer): the charge ends at base
   contact but can never move THROUGH a model, and all other units keep their full zones.
   **Post-melee separation** (p.9): "the charging unit must move back by 1” (if possible)" — the AI
   charger backs off automatically (visible corridor); when the PLAYER charged, the rule is surfaced as
   a battle-log reminder (the automation never moves the player's models).

**Shared distance module**: the zone radii derive from `scripts/separation_checker.gd`
(feat/proximity-hint `9f1f1c1`, taken verbatim with its 26-case test suite): `shape_for_model` →
`bounding_radius()` is the single base-size truth (round exact; oval/rect circumscribed — the planner's
circle zones are conservative for elongated bases, flagged). API gap noted for the coordinator: none —
bounding_radius + the constants covered the planner's needs; `edge_distance` itself would only be needed
for a future non-circular zone shape.

**Flagged, not guessed** (documented gaps): regiments keep the rigid tray slide (not obstacle-planned);
the winner's OPTIONAL "may move by up to 3”" consolidation (p.9) is not automated; oval/rect bases sweep
their circumscribed circle in zones and corridors (conservative, never permissive).

## Capstone — rule inventory, EV decisions, developer mode (real game, 2026-07-10)

- **Army rule inventory at handoff**: designating an AI army battle-logs every special rule it carries,
  classified RESOLVED (derived from `main.gd SOLO_MODELED_RULES` — no second hand-maintained list),
  marked *decision-aware* (`SOLO_DECISION_RULES`: overlays, Hold/activation-order/movement rules and
  every EV input) or NOT AUTOMATED (which keeps flowing through the once-per-session manual notes).
  Pure classifier: `SoloController.classify_rule_inventory` (prefix-matched, occurrence counts).
- **The EV metric** (`scripts/solo/ai_ev.gd`): expected wounds computed from the SAME `AiCombatMath`
  helpers as the dice resolution — one math, no second truth. Fills exactly the undefined points:
  (a) the archetype "better than" (Solo v3.5.0 p.1: `AiEv.classify` vs a documented neutral reference
  defender; the SIM keeps the frozen `AiArchetype.classify`, its fairness oracle untouched), and
  (b) GENUINE ties in the official targeting keys — distances compare in 1" bands (tabletop measuring
  precision, a documented convention), and a tie is ranked by EV instead of the rules' die roll (the
  shipped hybrid policy). AP/Blast/Deadly/Reliable/Rending/Bane/Relentless/Surge/Furious/Thrust/Impact/
  Stealth/Evasive/Shielded/Cover/Regeneration flow through automatically; the charge tie-break score
  weighs Furious/Thrust/Impact in, the defender's Counter down (strike-first attrition + Impact
  reduction) and halves the taken-wounds weight for a Fearless attacker (p.13 morale re-roll —
  advisory heuristic, tie-breaks only). Deterministic: probabilities, never dice.
- **Developer mode** ("AI reasoning (dev)" toggle beside Fast AI, default off): every AI decision builds
  a STRUCTURED record at decision time (`SoloController.decision_log`, ring-capped at 200 — kind/unit/
  rule-citation/candidates-with-EV/chosen/why/data) covering deployment spots, the D6-section activation
  pick (Shaken/Counter ordering), the tree action (incl. Hold-overlay overrides), target selection with
  all candidate EVs, the move (band/difficult-cap/actual arc) and post-melee separation. Rendering
  (`SoloController.render_decision`) happens ONLY while the toggle is on — off costs no string
  formatting. The records are the introspection foundation for future smarter AI.

Example rendered lane (dev toggle on):

```
AI [pick] HDF Storm Troopers — rule: Solo v3.5.0: D6 section roll, random eligible; … — chose HDF Storm Troopers — (section roll) — [west=2, east=1, rolled_west=true, eligible=3]
AI [action] HDF Storm Troopers — rule: Solo v3.5.0 decision tree (archetype branch; EV fills the p.1 'better than') — chose advances — (decision tree) — [arch=1, objective=true, …]
AI [target] HDF Storm Troopers — rule: Solo v3.5.0 p.2: nearest/not-activated/open + weapon overlay — options: Squad B EV 2.40, Squad A EV 1.10 — chose Squad B — (ev tie-break) — [overlay=1, weapon=Heavy Rifle, considered=2]
AI [move] HDF Storm Troopers — rule: GF v3.5.1 p.7 move bands; p.11 difficult 6" cap; … — (around difficult) — [band_in=6.0, budget_in=6.0, arc_in=5.8, dangerous_models=0]
```

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

## Field-test round 2 — seven fixes (real game, 2026-07-10)

The maintainer's second field test surfaced seven issues; each is fixed in the solo layer (SIM untouched,
fairness oracle byte-identical) and cited against the PDFs:

1. **Slow ignored** (GF/AoF v3.5.1 p.13 — Slow: "-2" Advance, -4" Rush/Charge"): the AI band computation
   fell back to a hardcoded 6"/12" whenever no `MovementRangeController` was injected (e.g. the field
   harness), silently dropping Fast/Slow. Now the AI reads bands from the SAME source as the human's reach
   rings — `SoloController.move_bands_for_unit` → `bands_for_model` (aura/base-aware) or the STATIC
   `MovementRangeController.move_bands_for_props` (Fast/Slow-aware) — never a hardcoded default. A Slow unit
   advances ≤ 4". (`move_bands_for_props` and its helpers are now `static`.)
3. **Deployment inside blocking terrain** (deployment placement): the last-resort "must deploy" fallback
   bypassed the terrain check; it now relaxes only the 1" spacing while STILL rejecting blocking/impassable
   terrain, and the footprint check samples the unit's diagonal corners (not just cardinals). Blocking
   terrain is rejected for the whole footprint; the section-centre placement is a true last resort only when
   no legal cell exists anywhere.
5. **Ambush = deployment, not activation** (GF/AoF v3.5.1 p.13 — "May be set aside before deployment. At
   the start of any round after the first, may be deployed anywhere over 9" away from enemy units … Units
   that deploy via Ambush can't seize or contest objectives on the round they deploy."): reserve units are
   now flagged off-table and are NOT activatable while held (they used to be eligible in round 1); arriving
   clears the flag WITHOUT marking the unit activated (it may still act that round) and stamps the arrival
   round so `seize_objectives` skips it for objective seize/contest that round. Arrival is retried at the
   start of ANY round after the first (not only round 2). Arrival stays > 9" from enemies.
6. **Forest cover** (GF/AoF v3.5.1 p.11 — "If the majority of models in a unit are fully inside a piece of
   cover terrain … they get +1 to Defense rolls when blocking hits from shooting attacks."; Forests =
   Difficult + Cover): the damage resolution already applied cover both directions via
   `AiCombatMath.covered_defense` + `_solo_majority_in_cover` (Forests/Ruins via `TerrainRules.gives_cover`,
   which is the cover — not the LOS — classifier). The remaining gap was the EV: `nearest_human_unit`'s
   tie-break passed a constant `false`. It now reads real terrain via `SoloController.majority_in_cover`, so
   the EV devalues a defender whose majority sits in woods/ruins.

(Findings 2 movement-gather, 4 ambush pacing and 7 activation choreography are presentation/planner fixes
without rule-coverage claims; see the commit series and `docs/SOLO_AI_PLAN.md`.)

## Wave 4 — army-book weapon/unit rules IMPLEMENTED (real game, 2026-07-10)

Every special rule across the three 0.3.9 field books is now mechanically applied, not just inventoried
(the maintainer's directive: "ALL rules the unit has … the AI must notice AND apply"). Source of truth is
the official Army Forge rule TEXT embedded in each book's `specialRules` (the wave-3 precedent); core-PDF
rules are verified against the PDFs. Same discipline as waves 1–3 — a pure `AiCombatMath`/profile helper,
both combat directions, human prompts show the modified values, the EV picks it up, a unit test + citation.

| Rule (source) | Effect (official AF text) | Where | Test |
|---|---|---|---|
| **Destructive** (weapon; Robot Legions, Mummified) | "On unmodified results of 6 to hit, those hits get AP(+4)." (= Rending's AP(+4), but NO Regeneration bypass) | `AiShooting._profile` flag → `main._solo_resolve_saves` AP(+4)-on-6 sub-batch (shared `rending_ap_hits`); `AiEv.profile_ev` | `test_destructive_flag_is_parsed_onto_the_profile`, `test_destructive_raises_ev_like_rending_via_ap4_on_sixes` |
| **Self-Repair** (unit; Robot Legions) | "When a unit where all models have this rule takes wounds, roll one die for each. On a 6+ it is ignored." (Regeneration-family, 6+, all models) | `main._solo_regen_target`/`_solo_apply_regeneration`; `AiEv._regen_target`/`profile_ev`/`impact_ev` | `test_self_repair_regen_target_is_six_and_devalues_shooting` |
| **Battleborn** (unit; Battle Brothers) | "If a unit where all models have this rule is Shaken at the beginning of the round, roll one die. On a 4+, it stops being Shaken." | `AiCombatMath.battleborn_recovers`; `main._solo_battleborn_recovery` (round start, AI rolls, human reminded) | `test_battleborn_recovers_on_4plus` |
| **Unpredictable Fighter** (unit; Mummified) | "When in melee, roll one die … on a 1-3 they get AP(+1), and on a 4-6 they get +1 to hit rolls instead." | `AiCombatMath.unpredictable_fighter_effect`; `main._solo_melee_strike_phase` (one roll/melee, both directions) | `test_unpredictable_fighter_effect_split` |
| **Royal Legion** (unit; Mummified) | "This model gets +4" range when shooting and moves +2" when using Charge actions." | +4" range: `SoloController.shooting_range_bonus` → AI shoot decision + reach, human validate + preview. +2" Charge: `MovementRangeController.move_bands_for_props` (Rush/Charge band) | `test_royal_legion_shooting_range_bonus`, `test_move_bands_royal_legion_charge_bonus_only` |

**Left un-automated (justified, one sentence each):**

- **Caster(X)** (Mummified) — grants spell tokens to cast random spells; the solo automation has no
  spell/magic subsystem, so casting stays a manual, once-per-session-logged action.
- **Unique** (Robot Legions, Mummified) — a list-building constraint ("may only be taken once per army"),
  not an in-game combat/AI rule, so there is nothing to apply at play time.

### Per-army rule coverage (distinct rule types), before → after wave 4

| Book | Before | After | Remainder |
|---|---|---|---|
| **Battle Brothers** | 5/6 (Battleborn missing) | **6/6 = 100%** | — |
| **Robot Legions** | 8/10 (Self-Repair, Destructive missing; Slow buggy) | **10/10 = 100%** | — |
| **Mummified Undead** | 11/16 | **14/16 — 100% of combat/AI rules** | Caster (spells) + Unique (list-building) — neither a play-time combat rule |

The inventory reclassifies these automatically because `SOLO_MODELED_RULES` is derived, not hand-listed;
the once-per-session un-automated log now only flags Caster/Unique (and truly unknown army rules).

## Fairness (wave-4 + round-2 fixes)

All engine-behaviour changes live in the solo layers / the planner's opt-in `opts` path; the SIM passes no
opts and calls `plan_unit_step` only in walled scenarios (the mirror oracle is wall-free), so `SoloSim` and
the mirror-fairness oracle are byte-identical to before — no re-run required (same precedent as waves 1–3).

## Field-test round 3 — eleven fixes (real game, 2026-07-12)

The maintainer's third field test surfaced eleven issues. Each is fixed in the solo layer (`SoloSim`
untouched — the mirror-fairness oracle stays byte-identical, no re-run), verified against the PDFs, and
pinned with a gdUnit test.

1. **Deployment placed model bases in terrain** — the footprint check sampled a coarse circle of 8 points,
   and the footprint radius reached only to model CENTRES. The check now samples the EXACT per-model grid
   the drop builds (`SoloController._deploy_footprint_offsets`, mirroring `_place_unit_at`) and inflates each
   model by its real base radius (`SeparationChecker` shape truth), so EVERY base — not just the centre —
   must clear blocking terrain (`AiDeployment._blocked_at` footprint path). Test:
   `test_blocked_at_checks_every_model_of_a_footprint`, `test_best_spot_rejects_footprint_corner_in_blocking_terrain`.
2 & 6 & 11. **Line of sight is now GEOMETRIC and PER MODEL** (GF/AoF v3.5.1 p.5 "Models can't see through
   solid obstacles, including the perimeter of other units (friendly or enemy), but they can always see
   through friendly models from their own unit."; p.8 "Who Can Shoot" is per model). The AI's shooting
   target selection AND resolution AND the human's `n/m sight` display all run one truth,
   `main._solo_true_los_callable`, which blocks a shooter-model→target-model line on (a) blocking terrain
   zones (grid), (b) **wall segments** (`get_wall_segments_world`, previously ignored — the cause of the AI
   shooting through the central ruins/walls, finding 2), and (c) **any other unit's base** (`LosRules.units_block_line`,
   the unit-as-blocker engine, previously unwired — finding 11), excluding only the shooter's and target's
   own units. The AI *decision* now uses this same per-model check (`SoloController.unit_los_checker`),
   replacing the coarse unit-centre line that both let it shoot with no line (finding 2) and held it from
   firing when its models had a clear line (finding 6). Tests: the existing
   `test_sighted_models_gates_per_model_behind_a_blocker` (per-model gate) + `unit_los_blocker_test.gd` (the
   geometry).
3 & 4b. **Ambush reserve units are truly OFF-TABLE** (GF/AoF v3.5.1 p.13). Round 2 made them ineligible;
   round 3 closes the remaining leaks via one truth, `SoloController.unit_in_reserve`: a reserve unit is
   excluded from activation eligibility (already), from movement/LOS **obstacle** sets, from AI **target**
   selection, and from being a valid human target — and its models are **hidden** on deploy and **revealed**
   only on arrival, so it is never seen, targeted, or perceived as "placed" until its single arrival
   placement (no phantom pre-placement, finding 4b). Test: `test_reserve_units_never_eligible_activate_or_target`.
4. **Planner now costs Dangerous cells** — Dangerous grid cells enter the planner's `avoid_cells` set (like
   Difficult) so the AI routes AROUND them when a clear path of comparable length exists; only Flying ignores
   Dangerous (Strider ignores Difficult but NOT Dangerous — GF/AoF v3.5.1 p.13/p.14), and a destination that
   is itself Dangerous routes straight in (the model then takes its test). `SoloController._terrain_grid_in`
   + `_targets_in_dangerous`. Test: `test_terrain_grid_marks_dangerous_avoid_only_when_requested`.
5. **Human melee flow** (GF/AoF v3.5.1 p.8/p.9). (a) Melee contact is measured **base-to-base** via the
   shared `SeparationChecker` (`SoloController.nearest_melee_gap_in`), replacing the unit-centre distance that
   failed for wide/multi-model units the player had in contact. (b) **Charge snap**: on declaring a Fight
   within `MELEE_ENGAGE_IN` (1"), the whole charging unit rigidly translates so its nearest model lands in
   clean base contact — a rigid translation preserves every relative spacing, so the rest of the unit rides
   forward in coherency (`SoloController.snap_charge`; both the human's Fight and the AI's charge). (c) The
   **bring-in** is cited exactly: the CHARGER's models "move … to get into base contact … maintaining unit
   coherency" (p.8) — handled by the snap; the DEFENDER's separate pull-in ("all models from the target unit
   that are not in base contact … must move by up to 3” to get into base contact … maintaining unit
   coherency", p.9) is surfaced as a battle-log reminder (the automation never moves the opponent's models on
   the player's behalf). Who then strikes is unchanged: models within 2" (p.9). Test:
   `test_nearest_melee_gap_and_charge_snap`. (The 1"-proximity VISUALIZER lives on `feat/proximity-hint` and
   is intentionally NOT duplicated here.)
7. **Dangerous-terrain damage no longer stops shooting** (GF/AoF v3.5.1 p.12: a dangerous test neither
   consumes the activation nor prevents shooting; only a dead model is removed). The premature morale test
   was moved OUT of the dangerous step and DEFERRED to the END of the activation (`_solo_activate_one_ai`),
   after the unit has acted — so a surviving unit still shoots this turn. A CHARGE is excluded (units in
   melee use the melee wound-comparison instead — p.9).
8. **Shaken auto-fails a repeat morale test** (GF/AoF v3.5.1 p.10: "Shaken units … always fail morale
   tests"). `_solo_morale_test` now skips the Quality roll when the unit is already Shaken and applies the
   forced fail (`AiCombatMath.morale_result_shaken`): Rout at half or less, otherwise it stays Shaken (a
   Fearless re-roll can still save it — p.13). Test: `test_morale_result_shaken_auto_fails`.
9. **Reliable applied on the MELEE strike path** — the strike phase composed the to-hit from the raw
   Quality, silently dropping a melee weapon's Reliable (2+); it now sets the base Quality via
   `AiCombatMath.reliable_quality` first, exactly as both shooting paths do, then composes Thrust / Evasive /
   fatigue on top ("Reliable only changes the Quality value", p.14). Test:
   `test_reliable_sets_melee_to_hit_to_two_plus`.
10. **Overlapping Dangerous + Difficult** — the Dangerous test and the Difficult 6"-cap are evaluated
    **independently** on the actual planned route, so a path that enters difficult terrain (6" cap applies)
    AND crosses dangerous terrain still counts the dangerous crossing (`_count_dangerous_trails` runs after
    any difficult re-plan). Test: `test_route_reports_difficult_and_dangerous_independently`.
    *Honest limitation:* the shared terrain grid stores ONE `TerrainType` per 3" cell, so a **single** cell
    cannot be authored as both Difficult and Dangerous — overlapping effects must be authored as adjacent
    cells (which the route logic then handles). A per-cell multi-class terrain layer is a separate
    `terrain_overlay` change, out of scope here.

**Fairness:** every change lives in the solo game layer (`main.gd`, `SoloController`, `AiCombatMath`
additions, `AiDeployment`); `SoloSim` and the SIM's `plan_unit_step`/`_terrain_grid_in` paths are untouched,
so the mirror-fairness oracle is byte-identical — no re-run required (same precedent as waves 1–4).

## Field-test round 4 — eight findings (real game, 2026-07-12)

The maintainer's fourth field test (build `0e5fecd`) surfaced eight findings; several round-3 fixes did not
hold. Each is fixed below in the solo/game layer (`SoloSim` untouched — the mirror-fairness oracle stays
byte-identical, no re-run) and cited against the PDFs. (Pathfinding QUALITY, finding 2, is a separate
research-informed package and is not reworked here.)

1. **Deployment STILL placed bases in Blocking/Dangerous terrain.** Root cause: the round-3 footprint check
   was sound, but the "must-deploy" LAST RESORT (`SoloController.deploy_army`) still dumped the unit blindly
   at the SECTION CENTRE with no terrain check — and when a ruin sat at the section centre the whole unit
   landed inside it. The last resort now calls `AiDeployment.least_blocked_spot`, which scans the zone and
   returns the spot whose footprint has the FEWEST model bases in blocking/dangerous terrain (tie-broken
   toward the nearest objective) — so a unit lands on the clearest available ground (usually still fully
   legal), never on top of a wall when clear ground is one cell over. `blocked_normal` continues to reject
   RUINS/CONTAINER/FOREST/DANGEROUS and the wall physics-probe for the whole footprint. Tests:
   `test_least_blocked_spot_prefers_clear_ground_over_blocking`, `test_least_blocked_spot_always_returns_a_finite_spot`.
4. **AI moves ended out of coherency** (GF/AoF v3.5.1 p.7 unit coherency). The planner's best-effort
   coherency ease could leave a unit incoherent. Every non-charge AI move now ENDS coherent by construction:
   `MovementPlanner.shorten_to_coherent` blends the planned formation back toward the (coherent) start just
   enough to restore the 1"/9" chain (blend 0 = no move is always coherent, so the bisection always returns a
   coherent result — "or as close as possible"). A Charge is exempt (it must reach base contact). Applied in
   the game-only `SoloController._plan_positions`; `SoloSim` never calls it. Tests:
   `test_shorten_to_coherent_restores_a_broken_chain`, `test_shorten_to_coherent_no_op_when_already_coherent`.
5. **Ruins block MOVEMENT but must NOT block LINE OF SIGHT; ruins give COVER.** Per the v3.5.1 terrain
   guidelines: *"Buildings - Impassable + Blocking"*, *"Forests - Difficult + Cover + see into/out, not
   through"*, *"Ruins - Cover + Dangerous when using rush/charge"* — ruins are Cover and SEE-THROUGH, only
   Buildings/Containers (and Forests, through them) block sight. Two round-3 regressions removed: (a)
   `terrain_overlay.terrain_blocks_los` no longer lists RUINS (they are Ground height, see-through), so both
   the AI's and the human's per-model LOS see through ruins; (b) `main._solo_true_los_callable` no longer
   treats ruin WALL SEGMENTS as sight blockers (they remain impassable to MOVEMENT via the planner's wall
   set). Cover was already correct in both directions and the EV (`_solo_majority_in_cover` /
   `SoloController.majority_in_cover` → `TerrainRules.gives_cover(RUINS)`), so ruins still confer +1 Defense.
   **Intentional divergence:** this is a `terrain_overlay` (game) change only; `TerrainRules.blocks_los` (the
   SIM's shared classifier) still counts RUINS as a blocker — left untouched per "SIM untouched", and the sim
   stays fair because both mirror armies use the same classifier. Tests: `terrain_overlay_test.test_ruins_do_not_block_line_of_sight`,
   `terrain_los_test.test_blocking_and_height_helpers`.
6. **Models moved onto each other, even within their own unit** (GF/AoF v3.5.1 p.7: "may never move through
   other models or units, friendly or enemy"). The planner steered/eased in point space with no base-overlap
   notion. `MovementPlanner.separate_overlaps` now pushes any two of the unit's OWN bases that overlap apart
   along their centre line (split evenly, each half wall/zone-checked) until the edge gap is ≥ 0, using the
   real `SeparationChecker` base radii. Applied last in the game-only `_plan_positions` (after the coherency
   shorten, so the tiny nudge — ≤ a base radius, well under the 1" link — is the final word). `SoloSim`
   (dimensionless points) never calls it. Tests: `test_separate_overlaps_pushes_own_bases_apart`,
   `test_separate_overlaps_no_op_when_clear`, `test_separate_overlaps_splits_coincident_centres`.
7. **Two AI activations back-to-back across a round boundary** (GF/AoF v3.5.1, Rounds/Turns/Activations: *"On
   each new round the player that finished activating first on the last round gets to activate first."*). The
   solo round opener was chosen by ROUND PARITY (`current_round % 2`), which ignored who actually took the
   last activation — so the AI could take a round's LAST activation and then the next round's FIRST. The
   opener is now the side that did NOT take the last activation (`SoloController.ai_opens_next_round`, tracked
   by `main._solo_ai_took_last_activation`); if that side is wiped, the other opens. Tests:
   `test_ai_opens_next_round_never_back_to_back`, `test_ai_opens_next_round_falls_through_when_opener_is_wiped`.
8. **A legitimate charge resolved as one-sided — the charger's attacks never rolled** (GF/AoF v3.5.1 p.9
   "Who Can Strike"; Solo p.57 "melee: … always strike back"). Root cause: the charger (a walker) had NO
   melee-weapon PROFILE — a unit whose weapons are all ranged yields `AiShooting.melee_profiles == []`, so the
   strike loop produced no lines and looked skipped (the defender, which had a melee weapon, struck back). The
   `striking_models` 2" reach is symmetric between charger and defender, ruling out a reach/scaling
   asymmetry — the discriminator is the missing melee weapon. `main._solo_melee_strike_phase` now logs
   *"X has no melee weapons in reach — no strikes"* on the FULL strike phase, so a fight always shows both
   sides' resolution (a shooting-only unit legitimately makes no melee attacks). Tests:
   `test_melee_profiles_empty_for_shooting_only_unit`, `test_striking_models_is_symmetric_for_two_bases_in_contact`.
3. **Battle-log EXPORT (new feature).** An `Export` button in the Battle Log panel (and the **F8** hotkey)
   writes the full log to `user://battle_log_<timestamp>.txt` and prints/echoes the resolved ABSOLUTE path.
   When the dev "AI reasoning" toggle is on, the AI decision records are already interleaved into the log and
   any still-buffered records are appended as a trailing `--- AI decision records ---` section (the
   diagnostic gold). `BattleLog.export_text` / `export_to_file`; wired via the panel's `export_requested`
   signal to `main._on_battle_log_export`. Tests: `test_export_text_formats_entries_and_decision_records`,
   `test_export_text_without_records_omits_that_section`, `test_export_to_file_writes_and_returns_absolute_path`.

**Fairness:** every change lives in the game/solo layer (`main.gd`, `SoloController._plan_positions` +
`deploy_army`, `MovementPlanner` game-only helpers, `AiDeployment`, `terrain_overlay` LOS, `BattleLog`);
`SoloSim`, `TerrainRules`, and the SIM's `plan_unit_step`/`_terrain_grid_in` paths are untouched, so the
mirror-fairness oracle is byte-identical — no re-run required (same precedent as waves 1–4 and rounds 2–3).


## Field-test round 5 — three self-play findings (AI-vs-AI, 2026-07-12)

A data-driven AI-vs-AI self-play run (build `a7e4054`) surfaced three findings. All fixes live in the
game/solo layer (`SoloController`, `main.gd`); `SoloSim` and every shared pure module (`AiDecision`,
`AiEv`, `MoveIntent`, `MovementPlanner`) are UNTOUCHED, so the mirror-fairness oracle is byte-identical —
no re-run required.

1. **The AI never SEIZED an objective — games stalled 0-0-3.** The decision/movement toward objectives was
   correct (a reachable marker is reached, centre on the marker; proven by the pre-existing
   `test_ai_rushes_toward_an_uncontrolled_objective_over_the_enemy`), but the objective-selection ignored the
   official **"Controlling Objectives"** rule (Solo & Co-Op v3.5.0 p.2: *"objectives count as under the AI's
   control if the AI already controls them, or if more non-shaken AI units than enemy units are within 3" of
   it"*). `_nearest_uncontrolled_objective` checked ONLY the persistent round-end owner, so once an AI unit
   reached the contested centre marker, no other AI unit ever treated it as held — every unit piled onto the
   same contested marker, it went neutral (contested) at round end, and no unit peeled off to hold an open
   flank. Fix: `_nearest_uncontrolled_objective` now (a) skips a marker the AI controls by the 3"-majority
   rule — counted per UNIT, excluding the deciding unit so a lone holder never abandons its own marker — and
   (b) prefers a **holdable** marker (no enemy within 3", so it can be seized and kept) over a contested one,
   then the nearest. This makes units DISTRIBUTE across the mission instead of dog-piling one contested spot.
   The 3"-majority skip is the letter of the rule; the holdable-first ordering is a documented refinement
   (the letter — "nearest uncontrolled" — never distributes). Instrumentation added so the effect is
   measurable from the decision records: the `action` record now carries `obj_dist_in`, a per-activation
   `seize_check` record carries the unit's `obj_gap_after_in` (nearest model → nearest marker) and
   `in_seize_range`, and the round-end flip emits a `seize` record. The move narration now says "→ an
   objective" instead of the enemy's name when the unit heads for a marker. Tests:
   `test_ai_moves_into_seize_range_of_open_marker_and_seizes`,
   `test_decision_prefers_a_holdable_open_marker_over_a_contested_one`,
   `test_ai_peels_off_a_marker_another_ai_unit_already_holds`.
2. **A shooting-target EV rendered negative** (`Battle Brothers EV -1.11`). The target tie-break uses the
   charge matchup score (`AiEv.charge_score`) for melee-capable units — a NET dealt-minus-taken utility that
   can dip below zero for an unfavourable matchup. It is only ever a ranking key (the negative option is
   correctly never chosen), but surfacing a negative "expected wounds" in the dev log is misleading. The
   recorded/rendered candidate EV is now floored at 0 (`nearest_human_unit`'s record + `render_decision` as
   the final display guard); the raw score still drives the ranking, so selection — and the EV rule-sensitivity
   tests (`ai_ev_test`) — are unchanged. Test: `test_render_decision_floors_negative_target_ev`.
3. **A charge within the band fell short of base contact** (band 12", used ~8.4", short ~2.2"). The charge
   aimed the rigid move at the enemy CENTRE and capped it at the Rush band; for a wide/offset unit that closed
   the centre gap but left the nearest bases short, and the melee gate (`MELEE_ENGAGE_IN` = 1") then ruled the
   charge short. Fix (GF/AoF v3.5.1 p.8 *"Charging models must move … to get into base contact with an enemy
   model"*): the charge decision now gates on the REAL base-to-base gap (`nearest_melee_gap_in`) rather than
   the coarse centre-to-centre distance (never declare a charge whose true gap exceeds the band), and
   `_charge_move` measures the gap and the nearest-pair direction (the same `SeparationChecker` geometry as
   `snap_charge`, factored into a shared `nearest_charge_vector`) and rigid-moves exactly that far along that
   line, capped at the band — so the nearest models land in contact. Tests:
   `test_charge_within_band_reaches_base_contact`, `test_target_beyond_charge_band_is_not_charged`.

## Field-test findings — AI movement, placement & activation hardening (real game)

A Windows build of the solo stack surfaced seven behaviour findings. All are in the **real-game controller
path** (`solo_controller.gd` / `main.gd`); the headless **SIM (`solo_sim.gd`) and `MovementPlanner` are
byte-identical** (the mirror-fairness oracle is untouched — the controller path adds its guarantees on top,
gated so the sim never runs them). Every rule cites the official rulebook PDFs (GF/AoF Advanced Rules
v3.5.1; Solo & Co-Op v3.5.0). Self-play audit (2 fixed seeds, the real board + real armies) before → after:

| Audit class (self-play) | Before (s424242 / s777) | After |
|---|---|---|
| `coherency_broken` | 12 / 12 | **0 / 0** |
| `base_overlap_inter_unit` | 2 / 2 | **0 / 0** |
| `base_overlap_intra_unit` | 0 / 4 | **0 / 0** |
| `model_in_impassable_terrain` | 1 / 0 | **0 / 0** |
| `model_in_dangerous_terrain` | 0 / 0 | **0 / 0** |
| `shoot_without_centre_los` | 1 / 0 | **0 / 0** |
| **total violations** | **17 / 18** | **0 / 0** |

1. **Movement "looks strange" + show the distance.** Route evidence (per-move `arc_in` vs `band_in` dumped
   from self-play): the Theta*/funnel route is already taut — `arc` never exceeds the granted band and equals
   it only when routing *around* terrain, i.e. no zig-zag and no over-budget truncation. So the "seltsam"
   look was NOT the route geometry; it was the concrete causes fixed below — the end-state-leaking
   presentation (finding 2), broken coherency (finding 6) and stacking (finding 3). **Multi-candidate routing
   was therefore NOT adopted** (it would not measurably improve an already-taut, within-band route);
   the concrete causes were fixed instead. The corridor **distance label** (`"9.4\" / 12\""`) was verified to
   spawn for every move that produces a planned path (auto-fades, no leak) and is now computed from the
   pre-gate route arc so it stays the truthful planned distance.
2. **Presentation order (end state appeared first).** The controller applies + broadcasts the final model
   positions immediately (state authority + MP), so the nodes showed the END. Fix (`main._solo_present_move_start`
   via the pure `SoloController.presentation_start_positions`): the model nodes are returned to their route
   START *before* the camera focus + announce beat, so the choreography reads (1) highlight the unit at its
   start → (2) show the planned corridors while it is still there → (3) glide. Test:
   `test_presentation_start_positions_returns_route_starts`.
3. **Models stacked (AI placement) — the HARD no-overlap gate.** A ported, escape-scan-guaranteed
   `SeparationResolver.resolve_overlaps` (shared `separation_checker` base geometry) runs after the formation
   solver: every base is pushed off EVERY other base — same unit, other units, enemies (GF/AoF v3.5.1 p.7
   "may never move through other models or units"). Applied to every AI **move** (per-model, terrain-aware)
   AND at **deploy** (`_resolve_deploy_overlaps` — internal grid packing separated to contact, then the whole
   unit rigid-shifted off other units so it never spreads out of coherency). Invariant achieved: **zero
   overlapping bases** after every AI move/deploy (both seeds). Tests: `separation_resolver_test.gd`.
4. **Unplaced Ambush units must NOT demand activation.** Reserves are already excluded from activation
   eligibility (`is_eligible` / `eligible_units_for`) and the alternation counts; the residual path
   (`_enemy_in_way` counting an off-table reserve as blocking the AI's route to an objective) was fixed —
   an Ambush-reserve unit blocks no path (it is off-table).
5. **The human's Ambush units — the game must ASK.** The human's Ambush-rule units are now set aside into
   reserve at deployment (`set_aside_human_ambush`, symmetric to the AI, p.13 "May be set aside before
   deployment"). At the start of any round ≥ 2 the game **prompts** the human (`_solo_prompt_human_ambush`)
   to deploy them via guided placement (>9" from enemies, near an objective, terrain-legal — the same legal
   core as the AI arrival) or keep waiting; the AI's world-model already counts them as existing-but-off-table
   everywhere. Tests: `test_should_prompt_human_ambush_*`, `test_set_aside_human_ambush_*`.
6. **AI broke coherency — the HARD coherency gate.** If, after the terrain + overlap passes, the unit is not
   coherent (measured with the audit's own `CoherencyChecker` thresholds — 1" links, single chain, ≤ 9"/6"
   spread), the whole move is shortened back along its taut line toward the coherent START (bisection) until
   coherency holds (GF/AoF v3.5.1 p.7 "or as close as possible"). The shorten is overlap- AND terrain-aware,
   so pulling back never re-introduces a stack or a terrain rest. Composed order per move: terrain → overlap →
   coherency-shorten, applied AFTER the distance-truth trim (so the trim can never cut a shortened endpoint).
   Self-play `coherency_broken`: **12 → 0** (both seeds).
7. **AI activated two units back-to-back with initiative.** Root cause: `_solo_pending_replies` (owed AI
   replies) was a member that could carry an UNDELIVERABLE reply across the round boundary (the human took a
   round's last activation while the AI was already exhausted); the opener's own grant then stacked on top.
   Fix: the fresh-round count is DERIVED (`pending_replies_at_round_start`), never incremented — the opener
   grants exactly one AI activation (one-for-one alternation; a one-sided tail after exhaustion stays legal).
   Tests: `test_pending_replies_at_round_start_is_derived_fresh_not_carried`,
   `test_round_boundary_grants_ai_exactly_one_opener_activation`.
