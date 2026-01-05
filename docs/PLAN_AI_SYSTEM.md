# AI System - OPR Solo & Co-Op Rules Implementation

## Overview

This document describes the AI opponent system for OpenTTS, implementing the OnePageRules Solo & Co-Op Rules v3.5.0.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        AIManager                                 │
│  Central controller for AI turns, combat, missions, signals      │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────────┐    ┌──────────────────┐                   │
│  │ AIUnitClassifier │    │  AIDecisionTree  │                   │
│  │ - Hybrid         │───▶│ - Hybrid/Shoot/  │                   │
│  │ - Shooting       │    │   Melee Trees    │                   │
│  │ - Melee          │    └────────┬─────────┘                   │
│  └──────────────────┘             │                              │
│                                   │                              │
│  ┌──────────────────┐    ┌────────▼─────────┐                   │
│  │ AITargetSelector │    │    AIContext     │                   │
│  │ - Priority Rules │◀───│ - Game State     │                   │
│  │ - Weapon Bonuses │    │ - Objectives     │                   │
│  └──────────────────┘    └──────────────────┘                   │
│                                                                  │
│  ┌──────────────────┐    ┌──────────────────┐                   │
│  │   AICombat       │    │    AITerrain     │                   │
│  │ - Shooting       │    │ - Cover Check    │                   │
│  │ - Melee          │    │ - Difficult      │                   │
│  │ - Dice Rolling   │    │ - Dangerous      │                   │
│  │ - Casualties     │    │ - Pathfinding    │                   │
│  └──────────────────┘    └──────────────────┘                   │
│                                                                  │
│  ┌──────────────────┐    ┌──────────────────┐                   │
│  │   AIMission      │    │    AIMorale      │                   │
│  │ - Objectives     │    │ - Morale Tests   │                   │
│  │ - Seize/Contest  │    │ - Shaken/Rout    │                   │
│  │ - Win Condition  │    │ - Fearless       │                   │
│  │ - Round Mgmt     │    │ - Fear Bonus     │                   │
│  └──────────────────┘    └──────────────────┘                   │
│                                                                  │
│  ┌──────────────────┐    ┌──────────────────┐                   │
│  │ AISpecialRules   │    │ AIObjectiveSetup │                   │
│  │ - Ambush/Scout   │    │ - 6-Square Grid  │                   │
│  │ - Transport      │    │ - Random Place   │                   │
│  │ - Artillery      │    │ - Validation     │                   │
│  └──────────────────┘    └──────────────────┘                   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Files

| File | Description |
|------|-------------|
| `ai_manager.gd` | Central AI controller, turn management, action execution |
| `ai_unit_classifier.gd` | Classifies units as Hybrid/Shooting/Melee |
| `ai_decision_tree.gd` | Implements the three decision trees |
| `ai_context.gd` | Game state container for AI decisions |
| `ai_target_selector.gd` | Target prioritization with weapon rules |
| `ai_special_rules.gd` | Special rule behaviors (Ambush, Scout, etc.) |
| `ai_objective_setup.gd` | Objective placement according to rules |

## Unit Classification

Units are classified based on their weapons:

| Type | Condition | Behavior |
|------|-----------|----------|
| **Melee** | No ranged weapons | Rush toward objectives/enemies, charge when possible |
| **Shooting** | Ranged better than melee | Advance + shoot, stay at range |
| **Hybrid** | Melee better than ranged | Flexible - charge when close, shoot when far |

### Weapon Scoring

Weapons are scored to determine "better":
```
score = attacks * (1 + AP/6) + special_bonuses
```

Special bonuses:
- Deadly: +2.0
- Blast: +1.5
- Rending: +1.0
- Poison: +0.5

## Decision Trees

### Hybrid Decision Tree

```
1. Valid objectives not under AI control?
   ├─ Yes → 2
   └─ No  → 5

2. Enemies in the way?
   ├─ Yes → Charge if possible, else Advance+Shoot, else Rush objective
   └─ No  → 3

3. Objective in Rush range but not Advance?
   ├─ Yes → Rush toward objective
   └─ No  → 4

4. Advance will put enemies in shooting range?
   ├─ Yes → Advance toward objective + Shoot
   └─ No  → Rush toward objective

5. Enemies in Charge range?
   ├─ Yes → Charge enemy
   └─ No  → 6

6. Advance will put enemies in range?
   ├─ Yes → Advance toward enemy + Shoot
   └─ No  → Rush toward enemy
```

### Shooting Decision Tree

```
1. Valid objectives not under AI control?
   ├─ Yes → 2
   └─ No  → 3

2. Advance will put enemies in shooting range?
   ├─ Yes → Advance toward objective + Shoot
   └─ No  → Rush toward objective

3. Advance will put enemies in shooting range?
   ├─ Yes → Advance toward enemy + Shoot
   └─ No  → Rush toward enemy
```

### Melee Decision Tree

```
1. Valid objectives not under AI control?
   ├─ Yes → 2
   └─ No  → 3

2. Enemies in the way?
   ├─ Yes → Charge if possible, else Rush objective
   └─ No  → Rush toward objective

3. Enemies in Charge range?
   ├─ Yes → Charge enemy
   └─ No  → Rush toward enemy
```

## Activation Order

1. Divide table into 3 sections along AI deployment edge
2. Roll D3 for section to activate from
3. Activate random unit in that section
4. If no units in section, move clockwise to next
5. Shaken units activate last (Idle to remove Shaken)

### Special Activation Rules

- **Counter**: Activates after other units in section
- **Transport**: Activates before cargo on round 1
- **Ambush**: Deploys at start of round 2

## Target Priority

### Default Priority

1. Nearest valid target
2. Units that haven't activated yet (+5)
3. Targets in the open (not cover) (+3)

### Weapon-Specific Priority

| Rule | Priority Bonus |
|------|----------------|
| **AP** | +0.5 per AP vs Defense 4+ |
| **Deadly** | +10 vs single Tough, +5 vs any Tough |
| **Takedown** | +15 vs Heroes |
| **Unstoppable** | +20 vs Aircraft |

## Special Rules Implementation

### Movement Modifiers

| Rule | Effect |
|------|--------|
| **Flying** | Ignores all terrain |
| **Strider** | Ignores difficult terrain |
| **Aircraft** | Always moves 30", follows Shooting behavior |

### Behavior Modifiers

| Rule | Behavior |
|------|----------|
| **Artillery** | Deploy on high ground, Hold+Shoot |
| **Indirect** | Hold+Shoot when in range |
| **Relentless** | Hold+Shoot when in range |
| **Caster** | Cast spell after moving (D3+level) |
| **Ambush** | Deploy at round 2 start |
| **Scout** | Deploy after all other units |
| **Transport** | Fill with random units, activate before cargo |

## Terrain Behavior

### Cover Terrain

- AI units move into/behind cover
- Shooting/Hybrid stay in cover to shoot
- Skip cover if also difficult AND moving to objective

### Difficult Terrain

AI only enters if:
- Objective is inside
- Enemy is in charge range inside
- Has Strider or Flying

### Dangerous Terrain

AI only enters if:
- Objective is inside
- Has Flying

## Challenge Bonus (Optional)

At round start:
- AI holding ≥ player objectives: +1 to hit
- AI holding < player objectives: +1 to hit AND +1 to defense

## AI Deployment

1. Divide AI units into 3 equal groups
2. Roll D3 for each group's section (re-roll if all same)
3. Deploy units as close as possible to nearest objective
4. Avoid difficult/dangerous terrain (unless Strider/Flying)
5. Scout units deploy last

## Objective Placement

1. Divide objective area into 6 equal squares (2x3 grid)
2. Roll D6 for random square
3. Place objective at center of square
4. If invalid (too close to other), roll for another square
5. Move toward new square just enough to be valid

## Integration Points

### With GameUnit

```gdscript
# Unit classification stored in properties
unit.unit_properties["ai_type"] = "Hybrid"  # or "Shooting", "Melee"

# Last action tracking
unit.unit_properties["last_action"] = "charge"
unit.unit_properties["charge_target"] = target.unit_id
```

### With Activation Tracker

```gdscript
# AI manager emits signals for UI updates
ai_manager.unit_activating.connect(_on_ai_unit_activating)
ai_manager.unit_activated.connect(_on_ai_unit_activated)
ai_manager.action_log.connect(_on_ai_action_log)
```

### With Network Manager

```gdscript
# AI actions can be synced via existing RPCs
network_manager.sync_unit_activation(unit_id, true, round)
network_manager.sync_model_wounds(...)
```

## Usage Example

```gdscript
# Setup
var ai = AIManager.new()
add_child(ai)
ai.initialize(army_manager)

# Set game state
ai.set_enemy_units(player_units)
ai.set_objectives(objective_positions)
ai.set_table_dimensions(48, 72)  # 4x6 foot table

# Load AI army
ai.setup_ai_army(ai_controlled_units)

# Start AI turn
ai.start_ai_turn(current_round)

# Connect signals
ai.ai_turn_ended.connect(_on_ai_turn_ended)
ai.action_log.connect(_on_ai_log)
```

## Status

- [x] Unit Classification (Hybrid/Shooting/Melee)
- [x] Decision Trees (all 3 types)
- [x] Target Selection with priority rules
- [x] Activation Order (section-based)
- [x] Special Rules (Ambush, Scout, Transport, etc.)
- [x] Objective Placement
- [x] Terrain Avoidance (basic)
- [x] Combat Resolution (AICombat with full GDF rules)
- [x] Full Terrain Integration (AITerrain)
- [x] Mission System (AIMission with objectives)
- [x] Morale System (AIMorale with Shaken/Rout)
- [x] Battle Simulator (AI vs AI with step-by-step control)

## Additional Files (v2)

| File | Description |
|------|-------------|
| `ai_combat.gd` | Full combat resolution (shooting + melee) |
| `ai_terrain.gd` | Terrain interaction (cover, difficult, dangerous) |
| `ai_mission.gd` | Mission objectives and game structure |
| `ai_morale.gd` | Morale tests (Shaken, Rout, Fearless) |

## Combat System (AICombat)

Based on GDF v3.5.1 rules:

**Shooting Sequence:**
1. Determine Attacks (sum weapon attacks in range)
2. Roll to Hit (Quality tests with modifiers)
3. Roll to Block (Defense tests with AP/cover)
4. Remove Casualties (Deadly, Tough handling)

**Melee Sequence:**
- Same as shooting + Impact + Counter + Fatigue
- Strike back (AI always strikes back)
- Fear bonus for wound comparison
- Consolidation move (3") after destroying enemy

**Weapon Rules:**
- AP(X), Blast(X), Deadly(X), Rending
- Indirect, Relentless, Thrust, Furious
- Regeneration, Bane, Unstoppable

## Terrain System (AITerrain)

- Cover: +1 Defense (majority in cover)
- Difficult: 6" max move (Strider ignores)
- Dangerous: Roll 1 = wound (Flying ignores)
- LOS blocking checks
- Pathfinding around obstacles
- Artillery deployment on high ground

## Mission System (AIMission)

- D3+2 objectives (3-5 markers)
- 9" minimum distance
- Seize within 3" (no enemies)
- Contested = neutral
- 4 rounds, most objectives wins
- Strategic stance (aggressive/defensive)

## Morale System (AIMorale)

- Test at half strength
- Non-melee fail = Shaken
- Melee fail + half = Rout
- Shaken: idle only, can't seize
- Fearless: 4+ reroll
- Fear(X): +X wounds in comparison

## Battle Simulator (AI vs AI)

A step-by-step battle simulation mode where two AI-controlled armies fight each other.
Every action requires user confirmation via click, providing full control and visibility.

### Files

| File | Description |
|------|-------------|
| `battle_simulator.gd` | Core battle logic, step generation, execution |
| `battle_simulator_ui.gd` | UI for army loading, step controls, battle log |

### Features

- **Load two army lists** - Use OPR Army Forge import for both players
- **Step-by-step execution** - Each action (deploy, move, shoot, melee) is a discrete step
- **Click to advance** - User confirms each action before execution
- **Auto-advance mode** - Optional automatic step advancement with delay
- **Skip controls** - Jump to specific phases (deployment, round end)
- **Visual feedback** - Unit highlighting (green = active, red = target)
- **Battle log** - Complete action history with color-coded entries
- **Score tracking** - Objectives controlled, casualties inflicted

### Battle Phases

1. **SETUP** - Initialize armies and mission
2. **DEPLOYMENT** - Place units in deployment zones
3. **ROUND_START** - Begin new round, reset activations
4. **ACTIVATION** - Unit activation sequence
5. **MOVEMENT** - Charge/Rush/Advance movement
6. **SHOOTING** - Ranged attacks with full combat resolution
7. **MELEE** - Close combat with counter-attacks
8. **MORALE** - Morale tests when triggered
9. **ROUND_END** - Check objectives, prepare next round
10. **GAME_OVER** - Determine winner

### Step Types

| Type | Description |
|------|-------------|
| `deploy` | Unit deployment to starting position |
| `round_start` | Round initialization |
| `activation_start` | Unit begins activation |
| `charge` | Charge movement (12" + melee) |
| `rush` | Rush movement (12", no shooting) |
| `advance` | Advance movement (6", can shoot) |
| `hold` | Hold position (no movement) |
| `idle` | No action (Shaken units) |
| `shoot` | Ranged attack resolution |
| `melee` | Melee combat resolution |
| `morale` | Morale test |
| `activation_end` | Unit finishes activation |
| `round_end` | Round completion |

### Usage Example

```gdscript
# From main scene - Battle Simulator is auto-initialized

# Manual usage:
var simulator = BattleSimulator.new()
add_child(simulator)
simulator.initialize(army_manager)

# Setup armies (already loaded via OPR import)
simulator.setup_loaded_armies()

# Setup mission
var table_bounds = Rect2(-0.6, -0.6, 1.2, 1.2)
simulator.setup_mission(table_bounds)

# Start battle
simulator.start_battle()

# Connect to step signals
simulator.step_ready.connect(_on_step_ready)
simulator.step_executed.connect(_on_step_executed)

# Advance step on user click
func _on_click():
    simulator.advance_step()
```

### UI Layout

```
┌─────────────────────────────────────────────────────────┐
│  Battle Simulator                                    [X]│
├──────────┬──────────────────────────────┬───────────────┤
│ Controls │      Step Display            │  Battle Log   │
│          │                              │               │
│ Army 1   │  "Unit A charges!"           │  [Log entry]  │
│ [Load]   │                              │  [Log entry]  │
│          │  Details: Charging Unit B    │  [Log entry]  │
│ Army 2   │  (12" move + melee)          │  [Log entry]  │
│ [Load]   │                              │               │
│          │  Result: 3 hits, 2 wounds    │               │
│          │                              │               │
│ [Start]  │  [  CLICK TO EXECUTE  ]      │  [Clear]      │
│ [Stop]   │                              │               │
│          │  [x] Auto-advance  [Skip...] │               │
├──────────┴──────────────────────────────┴───────────────┤
│  Phase: Melee | Round: 2/4 | Score: P1: 2 | P2: 1       │
└─────────────────────────────────────────────────────────┘
```

### Integration with Main Scene

The Battle Simulator is accessible via button in the left panel:
1. Click "Battle Simulator" button
2. Load Army 1 (Player 1 - Blue)
3. Load Army 2 (Player 2 - Red)
4. Click "Start Battle"
5. Click to advance through each step
6. Watch the battle unfold with full combat resolution

---

*Basiert auf OPR Solo & Co-Op Rules v3.5.0 + Grimdark Future v3.5.1*
*Erstellt: 2026-01-05*
*Aktualisiert: 2026-01-05 - Combat, Terrain, Mission, Morale, Battle Simulator*
