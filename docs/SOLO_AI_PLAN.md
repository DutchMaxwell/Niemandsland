# Solo / Co-Op AI — Implementation Plan

> **Status:** M1 (Phase 0) shipped on `feat/solo-ai`; M2 (Phase 1) in progress. M2 slice 1 —
> the pure combat "brain" — landed: `AiArchetype` (Melee/Shooting/Hybrid classifier), `AiDecision`
> (per-archetype hold/advance/rush/charge tree) and `AiCombatMath` (OPR to-hit / AP-save / wounds /
> morale), all gdUnit-tested. M2 slice 2 (integration: AI rolls real tray dice, shooting → human-save
> prompt → wounds, charge/melee/strike-back/fatigue, morale tests, AI-army toggle UI, battle-log lines,
> render evidence of a full AI turn) is the next step. NOT merge-ready until the maintainer field-tests
> via F11. Branch: `feat/solo-ai`.
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

**Fairness:** the mandatory mirror oracle (no walls) is **unchanged vs baseline** (byte-identical fast path).
A bonus mirror *with* the symmetric wall layer showed the walls **amplify a pre-existing second-player skew**
(the oracle already sat well off 50/50 on HEAD before this work), independent of the steering — so walls are
deliberately kept **out of the fairness oracle** and live only in the trace + tests. Tests:
`test/movement_planner_test.gd` (geometry incl. corners/gaps, coherency, fast-path exactness, wall
avoidance, allowance clamp, U-pocket A* rescue). **Not yet** wired into the real game (that is P3).

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
