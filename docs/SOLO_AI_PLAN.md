# Solo / Co-Op AI — Implementation Plan

> **Status:** playable Solo v1 assembled on `feat/solo-ai` — M1 skeleton, M2 combat brain, the headless
> self-play sim (goal 003) with terrain/walls/movement + mirror-fairness proof, **P3** (the sim's pure
> modules wired into the real game — see the P3 section) and **P2** (in-game auto-game: alternating
> activation, objective auto-seize, 4-round match + scoring — see the P2 section). NOT merge-ready until
> the maintainer field-tests the assembled flow. Branch: `feat/solo-ai`.
> See [`ROADMAP.md`](ROADMAP.md) for where this sits in the backlog and
> [`docs/ARCHITECTURE.md`](ARCHITECTURE.md) for the system map.

Niemandsland is currently a **manual sandbox**: players move minis by hand and resolve
dice themselves. A Solo/AI opponent automates one side. This plan follows OnePageRules'
**official Solo & Co-Op Rules v3.5.0** (free, one PDF per game system; AoF:R uses the
Age of Fantasy PDF) so every AI behaviour cites an OPR reference, per
[`CODING_STANDARDS.md`](CODING_STANDARDS.md).

## Design decisions (locked 2026-06-30)

| Decision | Choice | Rationale |
|---|---|---|
| **AI brain** | **Hybrid:** official OPR decision trees as the policy; a **utility score breaks ties** instead of the rules' "roll a die" | Rule-faithful *and* less random than pure RNG on equally-valid choices. The trees are the law; utility only refines indifference. |
| **Combat in MVP** | **Semi-manual first:** AI moves + *declares* charge/shoot (highlighted); the human rolls dice + applies wounds. Full auto-resolution lands in Phase 2 | Matches the current manual paradigm, slashes MVP size, ships a playable opponent fast. |
| **Target system** | **Engine-agnostic foundation first** (Phase 0 system-neutral); pick GF vs AoF/AoF:R at the decision layer | The turn engine, AI-slot and move-intent API don't depend on the ruleset; commit to a system only when wiring the trees. |
| **Turn enforcement** | **Strict:** the turn engine is authoritative; the human may only activate/move on their turn (input layer gates on `TurnManager.can_activate`) | Rule-faithful alternating activation; the AI needs to know whose turn it is, and strict gating keeps both sides honest. (Off-turn input is blocked, not silently dropped.) |

## How the official OPR AI works (v3.5.0, sourced)

**It is a deterministic decision tree per unit archetype — NOT a dice "AI table" and NOT
a scoring system.** Dice are rolled only for randomness (which section/unit) and genuine
ties. (A point/score system exists *only* in the separate **Horde Mode**, not in standard
Solo rules.)

### Activation & round structure
- Normal OPR **alternating activation** stays (one unit per side, in turn). Solo rules only
  decide *which* AI unit acts and *what* it does.
- **Which unit:** split the table into **2 sections** along the AI's deployment edge. Per
  activation: D6 → `1–3 = section 1`, `4–6 = section 2` (no eligible unit there → rotate
  clockwise), then D6 → a random eligible unit in that section. *(One system PDF phrases the
  section pick as "roll a D3" — functionally the same 2-section split.)*
- **Order exceptions:** *Shaken* units activate **last** and stay idle (to recover);
  *Counter* units activate **after** all non-Counter units in their section.

### Archetype classification (pre-game, from weapons)
Each unit is exactly one of:
- **Melee** — no ranged weapons.
- **Shooting** — ranged better than melee.
- **Hybrid** — melee better than ranged.

### Decision trees (resolve Hold/Advance/Rush/Charge + action)
**MELEE** — aggressive, objective-first:
1. Uncontrolled objective exists? yes→2 / no→3
2. Enemies "in the way"? yes → Charge if possible, else Rush toward objective / no → Rush toward objective
3. Enemies in charge range? yes → Charge / no → Rush toward enemy

**SHOOTING** — holds distance / kites:
1. Uncontrolled objective? yes→2 / no→3
2. Does Advance bring enemies into shooting range? yes → Advance toward objective + shoot / no → Rush toward objective
3. Does Advance bring enemies into shooting range? yes → Advance toward enemy + shoot / no → Rush toward enemy

**HYBRID** — objective-seeking with charge:
1. Uncontrolled objective? yes→2 / no→5
2. Enemies in the way? yes → Charge if possible, else Advance+shoot toward objective, else Rush / no→3
3. Objective in Rush- but not Advance-range? yes → Rush / no→4
4. Does Advance bring enemies into shooting range? yes → Advance+shoot toward objective / no → Rush
5. Enemies in charge range? yes → Charge / no→6
6. Does Advance bring enemies into shooting range? yes → Advance+shoot toward enemy / no → Rush toward enemy

### Target & destination
- **Target:** nearest valid target → **prioritise not-yet-activated units** over activated →
  **target in the open over a target in cover**. Weapon overrides redefine "valid": **AP** →
  highest-Defense target first; **Deadly** → single-model/highest-Tough first, finishing the
  lowest remaining total Tough. **Caster** casts after moving (random spell, D3 + caster level).
- **Destination:** objective-first (every tree opens on "uncontrolled objective?"). "In the
  way" = an enemy **within 6"** of the straight line from unit to objective. Shooters that
  don't head for an objective **kite**: move away from the nearest enemy just enough to stay
  in shooting range. Units prefer cover; an objective is taken by ending **within 3"**.

### Objective control & difficulty
- **Controlled by the AI** when **more non-Shaken AI units than enemy units are within 3"**.
  The AI prioritises **uncontrolled** objectives; only once all are held does it hunt enemies.
- **No difficulty tiers.** One optional lever — **Challenge Bonus** (rubber-band): at round
  start, if the AI holds *fewer* objectives than the players, all AI units get **+1 to hit**
  (and **+1 to defense** if it holds *none* relative to them) until end of round.

### AoF:R caveat
The official Solo rules treat units **generically** — no facing, frontage, formations,
wheeling or charge arcs. There is **no official template** for a Regiments-aware AI. Our
**auto-face-on-move** (already shipped) covers facing automatically when the AI moves a
regiment; any deeper rank-and-flank AI would be homebrew (deferred).

## The hybrid policy: trees + utility tie-break
- The decision tree is evaluated first and is authoritative.
- Where the tree (or target rule) yields **multiple equally-valid options** — the rules say
  "roll a die" — we instead compute a small **utility score** per candidate and pick the max
  (ties within utility fall back to a seeded random for determinism/replay). Candidate utility
  blends, e.g.: distance-to-objective progress, expected exposure (enemies that could shoot/
  charge us next turn via LoS + range), and target softness (low remaining Tough / in the
  open). Utility is **advisory only** — it never overrides a tree branch, only ranks within one.
- This keeps us rule-faithful (the OPR tree decides Hold/Advance/Rush/Charge and the target
  *class*) while playing smarter than pure RNG on the indifferent choices.

## Movement — `MovementPlanner` (steering-first + local A* fallback)

**Design decision (maintainer, 2026-07-10):** *steering-first with a local A* fallback*, built as a **shared,
pure `MovementPlanner` module** (`scripts/solo/movement_planner.gd`) in the same family as `AiDecision` /
`TerrainRules` (static, no scene deps, deterministic, sim-shareable). Wired into the **headless sim first**
(AI moves); the real game's move-enforcement may reuse it later. It **replaces the rigid-block formation
slide** for AI moves.

**What shipped (in the sim):**
- **Individual-model steering.** Each model steers toward its own rigid target (`model + delta`); the unit is
  kept **in coherency**. The coherency predicate mirrors `coherency_checker.gd` (1" model-to-model link, 9"
  max spread) — since sim models are points, a nominal base allowance (`BASE_CONTACT_IN`, the sim's
  base-contact centre distance) is folded into centre-to-centre thresholds, so the 1"/9" numbers are *not*
  forked. After sliding, a monotonic wall-checked pull restores coherency.
- **Walls = Impassable.** A thin wall-segment layer (the sim's mirror of `terrain_overlay.gd`
  `_last_wall_segments`, a list of `[a, b]` pairs) blocks paths via segment-vs-path intersection; models
  **slide/steer around** locally. `SoloSim.default_walls()` adds a symmetric demo layer (a short barrier
  short of each objective, mirrored) that the trace/tests exercise.
- **Allowance clamp + 1" enemy spacing preserved.** No model travels past its move allowance (path-length
  bounded). The shipped 1" non-charge spacing clamp and Difficult/Dangerous handling stay in `SoloSim`
  (unchanged); a **Charge** is exempt from spacing. When **no wall is in the path the planner returns the
  exact rigid translation** — so open-field play, and the mirror-match fairness oracle, are byte-identical to
  the pre-planner behaviour.
- **Stuck → local A* rescue.** When walls stop the steering from making real progress toward the goal, a
  local **A\*** on the existing 3" sim grid (walls as blocked cell-edges, `CONTAINER` cells impassable) finds
  a corridor; the unit then **resumes steering** toward the farthest visible corridor waypoint (string-pull).
  A\* is the **rescue**, not the default.

## M2 combat rules — the next sim chunk (shipped)

On top of movement, the sim's combat resolution now models the OPR core melee/shooting special rules the
Battle Brothers list actually fields, each verified against the GF Advanced Rules v3.5.1 + Solo & Co-Op
Rules v3.5.0 PDFs (see [`SOLO_AI_RULES_COVERAGE.md`](SOLO_AI_RULES_COVERAGE.md) for the full per-rule matrix):

- **Melee "only models within 2" strike"** (p.9): a unit's melee attacks scale by the models actually in
  reach of an enemy, not the whole unit — `SoloSim._striking_models` (base contact folded into centre
  distance, as coherency/movement already do).
- **Split fire** (p.8): each ranged weapon **type** picks its own target and rolls as its own volley —
  `SoloSim._resolve_shooting_split`.
- **Weapon target overlays** (Solo rules p.2), a new pure `AiTargeting` module: **AP** → highest-Defense
  target, **Deadly** → single-model Tough then lowest-remaining-Tough, **Takedown** → heroes first
  (upgrade-cost tier flagged as not representable), plus base nearest / not-activated / open-over-cover.
- **Deadly(X)** damage (p.13 + p.10 clarification): each unsaved wound ×X, Tough-capped, assigned to one
  model — `AiCombatMath.deadly_multiplier`.
- **Relentless** (p.14 + Solo p.2): the AI Holds-and-shoots when in range, and >9" shooting turns each
  unmodified 6-to-hit into an extra hit — `_forces_hold_and_shoot` + `AiCombatMath.relentless_bonus_hits`.
- **Medic** = the Battle Brothers **Medical Training** item, which grants **Regeneration Aura**: each wound
  a unit takes is ignored on a 5+ — `SoloSim._apply_regeneration` (visible in the review app as regen dice).
- **Unknown-rule visibility**: any special rule a unit carries that the combat math does not model is now
  **logged once per game** (`_log_unmodeled_rules`) — the M2/M3 backlog driver. Current test-army gaps:
  Fearless, Battleborn, Blast, Reliable (all tracked in the coverage matrix).

Tests: `test/ai_targeting_test.gd` (overlays) + new cases across `solo_sim_test`, `ai_combat_math_test`,
`ai_shooting_test` (2" reach, split fire, Deadly, Regeneration, Relentless-hold, unknown-rule log, nested-
rule import). Full solo suite green (117 cases). **Mandatory fairness re-run** (combat change): Battle
Brothers mirror **47.0% / 51.6% / 1.4% draw** over 2000 games (inside 55/45) — all changes are
reflection-symmetric; combat is simply less lethal / more objective-decided (~67% decided on objectives).

**Fairness:** the mandatory mirror oracle (no walls) is **unchanged vs baseline** (byte-identical fast path),
and now sits at **P0 48.7% / P1 49.6% / 1.7% draw** over 1000 games (Battle Brothers mirror, seeds 1000–1999).
The "second-player skew" flagged during the MovementPlanner work (the oracle sat at ~42/57 on HEAD, well off
50/50) was **root-caused and fixed** — it was **not** rules-faithful and **not** the steering. It was
introduced by the 1" spacing commit (`d601e38`): casualty removal (`_apply_wounds`) used `pop_back`, dropping
the highest-index model, which is geometrically the **northern-most** model for **both** players. That strips
player 0's enemy-facing **front** rank (player 0 faces +y) but player 1's **rear** rank (player 1 faces −y) —
a mirror asymmetry. It stayed invisible until 1" spacing made objective grip position-sensitive, at which
point it handed player 1 a systematic objective-control edge (fewer wipes, more objective-decided games
exposed it). Fix: remove the **rear-most** model (nearest the unit's own deployment edge), symmetric per side.
The bonus mirror *with* the symmetric wall layer still shows walls amplify any residual imbalance, so walls
stay **out of the fairness oracle** and live only in the trace + tests. Tests: `test/movement_planner_test.gd`
(geometry incl. corners/gaps, coherency, fast-path exactness, wall avoidance, allowance clamp, U-pocket A*
rescue).

## P3 — the sim's brain wired into the real game (shipped)

The real in-game Solo AI (F11 → `SoloController` + `main.gd`) now runs the SAME pure modules the headless sim
proved, instead of the old ad-hoc logic. Real table state feeds the modules; module outputs drive real game
actions (moves on the real broadcast paths, dice on the REAL visible tray, battle-log lines on the existing
seams). Wired:

- **Decision**: `SoloController._act` uses the full objective-driven `AiDecision.decide_solo` (was the legacy
  enemy-only `decide`) + the Relentless Hold-and-shoot overlay. Real objectives + owners come from
  `terrain_overlay` (`get_objectives` / `get_objective_owner`); the AI heads for the nearest objective it does
  not control, else the enemy.
- **Movement/terrain**: loose units steer around real walls via `MovementPlanner` (walls from a new
  `terrain_overlay.get_wall_segments_world()`, run in the planner's inch frame); regiments keep the rigid block
  slide. Difficult (Forest) halves the move and Dangerous is tested on the real tray — both via `TerrainRules`
  predicates against real overlay data.
- **Combat** (`main.gd`, shared pure-module helpers): **dead models no longer attack** (attacks scale by
  alive/max — the maintainer's melee bug, previously fixed only in the sim at `22e86d4`); **2" "Who Can Strike"**
  reach scales melee attacks; **split fire** (each weapon type picks its own target via `AiTargeting` overlays:
  AP→best Defense, Deadly→Tough, Takedown→hero); **Cover** (+1 Defense), **Relentless** (>9" 6s add hits),
  **Deadly(X)** (Tough-capped multiply) and the **Regeneration/Medic** save all resolve on the real tray.
- **Tests**: `SoloController.effective_attacks` / `striking_models` + an objective-decision integration case
  (`test/solo_controller_test.gd`); the full solo suite stays green (117) and the sim is untouched (its fairness
  proof stands). Field-tested headless on the real Battle Brothers list via `tools/solo_field_test.gd`.
- **Remaining / stubbed** (honest gaps): the 1" enemy-spacing clamp is NOT applied on the real table yet (the
  sim's point-fold spacing does not map cleanly to real base geometry); the in-game shooting/melee dice + human
  saves are interactive (the visual tray + save prompts), so the headless field test resolves the identical
  modules on a seeded RNG rather than the live tray.
- **Field-test hardening wave (2026-07-10, six maintainer findings)**: AP(X) survives every Army Forge rule
  shape (label-only ratings + int-rating crash in the file importer — `_rule_to_string`), and every save site
  logs the MODIFIED threshold; attached heroes are one unit with their host (never a separate activation,
  move together, targeted through the host); **per-model shooting** (p.8 "Who Can Shoot"): attacks scale by
  the models with range + LOS both directions, the targeting line shows "7/10 sight" (throttled), valid-target
  = any model sighted; the OPR **auto-tail** plays the AI's remaining activations automatically once the human
  side is exhausted (paced, with a status banner; pure `alternation_next` machine); the human defender's
  **Regeneration** (5+, AP-independent; bypassed by Bane/Rending/Lacerate/Unstoppable per the PDF, detected
  down to model-level item rules) is rolled visibly; and solo wounds tick the REAL wound tokens + MP broadcast
  via the manual-play seams (`apply_wounds_to_models` core, unit-tested).

## P2 — the in-game auto-game (shipped): alternating activation, auto-seize, scoring

The last brick for "playable solo v1". A solo game now RUNS ITSELF once an army is marked for the AI:

- **Alternating activation** (OPR-faithful): each time the human activates a unit via the radial menu
  (`unit_activated` seam), the AI answers with exactly ONE activation. An exhausted side lets the other
  finish (the OPR tail); re-entrant human activations queue as pending replies. The AI's unit pick is the
  official D6 2-section roll (west/east half, rotate on empty, random within — seedable; the field-test
  harness seeds it for reproducible traces) with **Shaken last**;
  a Shaken AI unit spends its activation idle and recovers (state via the radial seam). **F11 is now the
  debug fallback**: it runs the whole remaining AI side at once.
- **Round flow**: when both sides are out of eligible units the round ends automatically — objectives
  seize/contest, then the round advances (same bookkeeping/broadcast as the Next-Round button, which stays a
  manual override). OPR's alternating opener: the AI opens the even rounds (round parity, stateless).
- **Objective auto-seize** (closes the P3 gap above): at every round end each marker goes to the single side
  with a non-Shaken model within 3" (persistent owner; both sides → contested/neutral; Shaken can neither
  seize nor contest). Pure logic in `SoloController.seize_objectives` (boundary-tested, inclusive 3"); owners
  write through the SAME overlay + MP-broadcast seam as the manual radial pick, which therefore remains an
  override. Battle-log lines per seize/contest.
- **Match length + scoring**: `SOLO_GAME_ROUNDS = 4` (OPR standard). After round 4 the game ends with a
  battle-log summary block + a results dialog (objectives held per side → "You win" / "The AI wins" / Draw;
  with no markers on the table, surviving models break the tie — documented fallback, not an OPR mission).
- **AI-army toggle** (maintainer's locked decision): the left-panel Solo section (one CheckButton per
  imported army + "Deploy AI army") designates the AI's army; with no designation the AI defaults to
  player 2 (backward compat). Pre-dated P2; the label/tooltip now explains the alternation and F11's debug
  role.
- **Tests**: the pure alternation machine (`test/turn_manager_test.gd`, 7 cases), seize logic incl. the 3"
  boundary + Shaken exclusion, Shaken-idle activation and Shaken-last ordering (`test/solo_controller_test.gd`);
  full solo suite green (140 cases across 14 suites). Field-tested headless: a COMPLETE 4-round auto-game on the
  real Battle Brothers list (`tools/solo_field_test.gd -- <list> <seed> autogame`) showing alternation, the AI
  opening rounds 2/4, seizes, and the final scoring.

## Architecture

An **`SoloAIController`** that owns a `player_id` **slot locally** (not a faked network peer)
and drives units through the **same local mutators the human uses**, reusing the broadcast/sync
layer so a watching MP guest still sees the AI's moves. Layers:

1. **Perception** (reuse existing — see table) — read board state.
2. **Turn engine** (new) — section split, random eligible unit, alternating activation,
   Shaken-last / Counter-after ordering, "round over when all activated".
3. **Decision layer** (new) — archetype classify → tree → `{action, target, destination}`,
   with the utility tie-break.
4. **Move-intent API** (new) — "move unit U to world-pos P" honouring Advance/Rush range and
   coherency; MVP = straight line + the "enemy within 6\" of path" test; obstacle-aware
   pathfinding later.
5. **Combat** — MVP: declare + highlight, human resolves. Phase 2: auto-resolve.
6. **Objective rule** (new, small) — auto-evaluate the "more units within 3\"" control test.

### EXISTS vs MISSING (from the codebase inventory)
| Capability | Status | Where |
|---|---|---|
| Unit/model stats + live wounds | **EXISTS** | `game_unit.gd`, `model_instance.gd`, `opr_api_client.gd` (`OPRUnit`/`OPRWeapon`, `range_value==0 ⇒ melee`) |
| Apply-wound / kill primitives | **EXISTS** | `model_instance.gd:apply_damage`, `regiment.gd` pooled wounds, wound-action path |
| LoS (models + terrain) | **EXISTS** | `los_rules.gd:units_block_line`, `terrain_overlay.gd:has_line_of_sight` |
| Range/move constants + distance | **EXISTS** | `movement_range_controller.gd` (Advance 6"/Rush 12" + rule modifiers), `range_ring_controller.gd`, `INCHES_TO_METERS` |
| Objective positions + ownership state | **EXISTS** | `map_layout.gd:mission_objectives`, `terrain_overlay.gd:set/get_objective_owner`, 3" seize-ring geometry |
| Round counter + activation flags | **EXISTS (state only)** | `game_unit.gd:is_activated/activate`, `opr_army_manager.gd:advance_round` |
| Low-level "set position + sync" | **EXISTS** | `object_manager.gd:arrange_*` + `_broadcast_arrange_positions`, `undo_manager.gd:MoveAction` |
| **Turn/activation ENGINE** | **MISSING** | — |
| **Automated combat (hit/wound/AP/morale)** | **MISSING** | dice are display-only (`dice_rules.gd`) |
| **Move-intent API / pathfinding** | **SIM (shared, pure)** | `move_intent.gd` (rigid clamp) + `movement_planner.gd` (individual steering, walls, local A*) — sim-wired; game-wired at P3 |
| **Auto-seize / objective control rule** | **MISSING** | capture is a manual radial-menu pick |

## Phased roadmap

- **Phase 0 — Foundation (engine-agnostic).** Turn/activation engine + AI `player_id` slot +
  move-intent API. Proof: a dummy AI that walks its nearest unit toward the nearest objective,
  synced + undoable. No rules yet. *Deliverable: the skeleton runs a "round".*
- **Phase 1 — Decision trees (movement, semi-manual combat).** Archetype classify + the 3
  trees + target/destination rules + utility tie-break + the 3" objective-control rule. AI
  positions correctly and **declares** charge/shoot (highlight + log); human rolls + applies
  wounds. *Deliverable: a playable, rule-faithful solo opponent.*
- **Phase 2 — Combat automation.** Auto-resolve shooting/melee (to-hit by Quality, AP vs
  Defense, wounds via `apply_damage`), morale/Shaken, fully hands-off. *Deliverable: hands-off
  solo game.*
- **Phase 3 — Polish.** Challenge Bonus, cover/kiting refinements, AP/Deadly target overrides,
  Caster behaviour, randomised setup (army/objective/deployment), **terrain-grid pathfinding — the
  `MovementPlanner` steering + local A* now exists and is proven in the sim; Phase 3 wires it into the real
  game's move-enforcement**, Co-Op (AI runs all enemy units for 2+ humans), Horde Mode scoring.

## Open questions / risks
- **Movement legality vs simulation freedom** — the sandbox doesn't enforce ranges/terrain
  today; the AI must self-limit. How strict (e.g. block illegal AI moves but still let humans
  free-move)?
- **Coherency & regiments** — moving a multi-model unit/regiment as a block while keeping
  coherency; regiment block-move + auto-face already exist and should be reused.
- **Determinism/replay** — seed all AI randomness so a solo game is reproducible (helps tests).
- **Difficulty** — only Challenge Bonus is official; do we want extra (homebrew) knobs later?
- **Testing** — perception + trees + utility are pure/headless-testable (gdUnit); the turn
  engine needs a headless harness like the MP soak tests.

## References (OPR official, free)
- Resources hub — https://onepagerules.com/resources
- Age of Fantasy — Solo & Co-Op Rules v3.5.0 (used by AoF:R)
- Grimdark Future: Firefight — Solo & Co-Op Rules v3.5.0
- Horde Mode v3.5.0 (the only OPR mode with a scoring system)
- AoF:R Core Rules v3.5.1 · https://onepagerules.com/games/age-of-fantasy-regiments
