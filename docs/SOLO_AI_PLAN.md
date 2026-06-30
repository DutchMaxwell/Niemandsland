# Solo / Co-Op AI — Implementation Plan

> **Status:** scoping / design (2026-06-30). No code yet. This is the living design
> doc for the Solo/AI opponent feature. Branch: `feat/solo-ai`.
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
| **Move-intent API / pathfinding** | **MISSING** | only drag + centroid `arrange_*`; no AStar/Navigation |
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
  Caster behaviour, randomised setup (army/objective/deployment), terrain-grid pathfinding,
  Co-Op (AI runs all enemy units for 2+ humans), Horde Mode scoring.

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
