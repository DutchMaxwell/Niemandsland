extends RefCounted
## P4.0-10 — golden witness for the table's combat families on the OLD table path.
##
## WHY THIS EXISTS. The plan deletes table code family by family (decision D1: no field window, golden fixtures
## before each deletion). This harness captures what the table does TODAY for a small scenario grid — the volley
## family (plain, AP, Blast, cover, Deadly), the melee family (plain, AP, Impact, Furious, Counter) and the morale
## family (pass, Shaken, Rout, a spent once-buff) — and stores the final unit state plus every battle-log line the
## exchange wrote, together with the provenance that makes the recording meaningful (rules epoch, git sha, registry
## sha256). `compare()` runs the same grid again and names every difference, so a deletion that changes the table's
## result before its replacement is in place turns the companion suite red.
##
## It runs the TABLE path only: the caller clears NML_ONE_CORE_ACTIVATION, and nothing here opens a core session;
## the melee goes through main._run_ai_melee and the morale test
## through main._solo_morale_test exactly as the game drives them. No gameplay code is touched — this file and its
## CLI/ suite are test/tool code.
##
## The grid is deliberately small and seeded: 4-5 scenarios x 4 seeds per family. Determinism comes from
## main.seed_tray_rng() (the same seam the parity gate uses) and from `_solo_batch` (instant dice, zero pacing holds).

const ParityTable := preload("res://test/parity/parity_table.gd")
const ParityMelee := preload("res://test/parity/parity_table_melee.gd")

## v1 fixtures (the three P4.0-10 families) carry counts and sums only; v2 adds the per-model identity ("slots") and
## the tray RNG state after the exchange. The comparator reads either schema and compares a v2 key only when the
## fixture has it, so a v1 fixture stays valid; a fresh capture always writes v2.
const SCHEMA_V1 := "nml-golden-witness-v1"
const SCHEMA := "nml-golden-witness-v2"
const SCHEMAS := [SCHEMA_V1, SCHEMA]
## The runner a scenario without a "runner" key named: the table's AI volley, deleted (the shooting_volley fixture is frozen).
const RUNNER_AI_VOLLEY := "ai_volley"
const FAMILY := "shooting_volley"
const FIXTURE_PATH := "res://test/fixtures/one_core/golden_shoot_volley.json"
const MELEE_FAMILY := "melee"
const MELEE_FIXTURE_PATH := "res://test/fixtures/one_core/golden_melee.json"
const MORALE_FAMILY := "morale"
const MORALE_FIXTURE_PATH := "res://test/fixtures/one_core/golden_morale.json"
## The human shooting door (runner "human_volley"): the table's player volley, deleted (the human_shoot fixture is frozen).
const HUMAN_FAMILY := "human_shoot"
const HUMAN_FIXTURE_PATH := "res://test/fixtures/one_core/golden_human_shoot.json"
const RUNNER_HUMAN_VOLLEY := "human_volley"
## Split fire: one activation, two targets. The AI's own body (runner "ai_shooting" = main._run_ai_shooting) and the
## player's declared split (runner "human_split" = the split prompt's Fire!, main._solo_split_commit) share one fixture.
const SPLIT_FAMILY := "split"
const SPLIT_FIXTURE_PATH := "res://test/fixtures/one_core/golden_split.json"
const RUNNER_AI_SHOOTING := "ai_shooting"
## The Dangerous-terrain sequence of the AI body (main.gd _solo_activate_one_ai): the Dangerous roll, the volley if the
## unit can shoot, the end-of-activation morale from the Dangerous wounds. Runner "ai_dangerous".
const DANGEROUS_FAMILY := "dangerous"
const DANGEROUS_FIXTURE_PATH := "res://test/fixtures/one_core/golden_dangerous.json"
const RUNNER_AI_DANGEROUS := "ai_dangerous"
## The AI's volley into a HUMAN unit whose owner has a wound-allocation choice (a Tough model, or two loadouts): the #172
## prompt opens, and the case either answers it with a right-click (auto) or clicks model slots first. Runner
## "ai_into_human"; the volley awaits the human's save card and the click prompt, so a Timer pump answers both.
const MIXED_FAMILY := "mixed_kit"
const MIXED_FIXTURE_PATH := "res://test/fixtures/one_core/golden_mixed_kit.json"
const RUNNER_AI_INTO_HUMAN := "ai_into_human"
## P4.D-37: the move-through attacks of an AI activation (Strafing, Crossing Attack) after an executed move, resolved by the
## table's own `_solo_apply_strafing` / `_solo_apply_crossing_attack`, then (`rifle`) the activation's volley. Runner "ai_move_through".
const MOVE_THROUGH_FAMILY := "move_through"
const MOVE_THROUGH_FIXTURE_PATH := "res://test/fixtures/one_core/golden_move_through.json"
const RUNNER_AI_MOVE_THROUGH := "ai_move_through"
## P4.D-47: the melee shapes the charge/strike/strike-back family resolves outside the one `_run_ai_melee` body —
## the human charge, the bare strike-back, Impact, Counter and consolidation. One runner kind per shape.
const MELEE_SHAPES_FAMILY := "melee_shapes"
const MELEE_SHAPES_FIXTURE_PATH := "res://test/fixtures/one_core/golden_melee_shapes.json"
const RUNNER_HUMAN_CHARGE := "human_charge"
const RUNNER_STRIKE_BACK := "melee_strike_back"
const RUNNER_MELEE_IMPACT := "melee_impact"
const RUNNER_MELEE_COUNTER := "melee_counter"
const RUNNER_CONSOLIDATION := "melee_consolidation"
## P4.D-47b: Fear and a joined hero through the whole charge — the melee-result comparison, the hero's own strikes and
## wounds, the chain's consolidation — on the AI charge (`_run_ai_melee`) and the human charge, with positions recorded.
const MELEE_FEAR_HERO_FAMILY := "melee_fear_hero"
const MELEE_FEAR_HERO_FIXTURE_PATH := "res://test/fixtures/one_core/golden_melee_fear_hero.json"
const RUNNER_AI_CHARGE := "ai_charge"
## CC-2: the table's casts of an AI activation. The planner's cast dict goes through `_solo_resolve_ai_casts` (the cast die
## on the tray, the effect, the spell's own saves and morale), both seats AI. `cast_damage` = a damage spell (saves, a
## kill, the morale test); `cast_effects` = the other legs (a buff on the caster, a debuff on the enemy, a failed cast, a
## fizzle, boost + interference, a spent once-mod). Runner "ai_cast".
const CAST_DAMAGE_FAMILY := "cast_damage"
const CAST_DAMAGE_FIXTURE_PATH := "res://test/fixtures/one_core/golden_cast_damage.json"
const CAST_EFFECTS_FAMILY := "cast_effects"
const CAST_EFFECTS_FIXTURE_PATH := "res://test/fixtures/one_core/golden_cast_effects.json"
const RUNNER_AI_CAST := "ai_cast"
## Rolls of the volley before the wounds land: the to-hit batch and the defender's save batch. The click prompt needs
## _solo_batch false, the batch tray needs it true, so the flag drops after this many rolls and returns with the
## first pick (the pattern of test/e2e/e2e_volley_morale_test.gd).
const ROLLS_BEFORE_WOUNDS := 2
## Seeds whose volley lands at least two wounds on the defender (seed 101 lands none, so no prompt would open).
const PROMPT_SEEDS: Array[int] = [0, 17, 49, 225, 3, 7, 512, 999]
const RUNNER_HUMAN_SPLIT := "human_split"
## Eight seeds for the door grids: the four of the volley grid plus four more, so a rare shape (no hit, all saved,
## a wipe) is more likely to be recorded than guessed.
const WIDE_SEEDS: Array[int] = [0, 17, 49, 225, 3, 101, 512, 999]
## Four seeds per scenario: in the volley grid they cover a morale failure (0), a save-less volley (17), the
## singular forms (49) and a volley with no hit (225); the melee grid records whatever they roll.
const SEEDS: Array[int] = [0, 17, 49, 225]
## The registry system every scenario below imports under; its mechanics map hash is part of the provenance.
const REGISTRY_SYSTEM := "gf"
## Cover is painted as a (2*COVER_CELLS+1)^2 block of forest cells around the defender's centre.
const COVER_CELLS := 2

const ATTACKER := {"player": 1, "name": "Att", "models": 10, "quality": 4, "defense": 4, "tough": 1,
	"x_in": 0.0, "z_step_in": 1.2, "base_radius_in": 0.63, "game_system": "gf",
	"faction_folder": "robot_legions", "rules": []}
const DEFENDER := {"player": 2, "name": "Def", "models": 10, "quality": 4, "defense": 4, "tough": 1,
	"x_in": 8.0, "z_step_in": 1.2, "base_radius_in": 0.63, "game_system": "gf",
	"faction_folder": "robot_legions", "rules": []}
const RIFLE := {"name": "Rifle", "range_in": 24, "attacks": 1, "count": 10, "rules": []}

## The melee grid keeps the parity gate's board: the attacker stands at its post-move position (base contact,
## 6.74" against 8.0"), the defender spreads 1.3" so no centroid ties; both units strike with one attack per model.
const MELEE_ATTACKER := {"key": "att", "player": 1, "name": "Att", "models": 10, "quality": 4, "defense": 4,
	"tough": 1, "x_in": 0.0, "z_step_in": 1.2, "base_radius_in": 0.63, "game_system": "gf",
	"faction_folder": "robot_legions", "rules": []}
const MELEE_DEFENDER := {"key": "def", "player": 2, "name": "Def", "models": 8, "quality": 4, "defense": 4,
	"tough": 1, "x_in": 8.0, "z_step_in": 1.3, "base_radius_in": 0.63, "game_system": "gf",
	"faction_folder": "robot_legions", "rules": []}
const BLADE := {"name": "Blade", "range_in": 0, "attacks": 1, "count": 10, "rules": []}
const DEF_BLADE := {"name": "Blade", "range_in": 0, "attacks": 1, "count": 8, "rules": []}
const CHARGE := {"dest_x_in": 6.74}
## A joined hero: one Tough(3) model with a three-attack blade, standing in base contact beside the first model of its
## host's rank (`stand_*` is where the model goes after the unit is built; the host's own x is the post-charge one).
const ATT_HERO := {"key": "att_hero", "player": 1, "name": "AttHero", "models": 1, "quality": 3, "defense": 4,
	"tough": 3, "x_in": 0.0, "z_step_in": 1.2, "base_radius_in": 0.63, "game_system": "gf",
	"faction_folder": "robot_legions", "rules": ["Hero"], "stand_x_in": 6.74, "stand_z_in": -1.2,
	"weapon": {"name": "Hero Blade", "range_in": 0, "attacks": 3, "count": 1, "rules": []}}
const DEF_HERO := {"key": "def_hero", "player": 2, "name": "DefHero", "models": 1, "quality": 3, "defense": 4,
	"tough": 3, "x_in": 0.0, "z_step_in": 1.3, "base_radius_in": 0.63, "game_system": "gf",
	"faction_folder": "robot_legions", "rules": ["Hero"], "stand_x_in": 8.0, "stand_z_in": -1.3,
	"weapon": {"name": "Hero Blade", "range_in": 0, "attacks": 3, "count": 1, "rules": []}}
## A lone enemy far down the table: the "next target" a winner's consolidation walks toward. Without one the survivor
## has no goal and holds ("no room to move"), so the move itself would never be recorded. It never fights.
const BYSTANDER := {"key": "by", "player": 2, "name": "By", "models": 1, "quality": 4, "defense": 4, "tough": 1,
	"x_in": 20.0, "z_step_in": 1.3, "base_radius_in": 0.63, "game_system": "gf", "faction_folder": "robot_legions",
	"rules": []}

## The cast grids' board: a one-model caster at the origin (player 1) and a six-model foe 8" away (player 2); both AI seats.
const CASTER := {"key": "cst", "player": 1, "name": "Mystic", "models": 1, "quality": 4, "defense": 4, "tough": 1,
	"x_in": 0.0, "z_step_in": 1.2, "base_radius_in": 0.63, "game_system": "gf", "faction_folder": "robot_legions",
	"rules": []}
const CAST_FOE := {"key": "foe", "player": 2, "name": "Foe", "models": 6, "quality": 4, "defense": 4, "tough": 1,
	"x_in": 8.0, "z_step_in": 1.3, "base_radius_in": 0.63, "game_system": "gf", "faction_folder": "robot_legions",
	"rules": []}
const CAST_STAFF := {"name": "Staff", "range_in": 0, "attacks": 1, "count": 1, "rules": []}
const CAST_SEEDS: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7]
## The effects grid's seeds, picked from a 32-seed scan by the FIRST die (the cast die): 6, 4, 5 pass a 4+; 1, 3, 2 fail it;
## the 3 passes the 3+ of the boosted cast and the 2 does not.
const CAST_FX_SEEDS: Array[int] = [0, 1, 2, 3, 8, 11]

## The morale grid: one AI-owned unit (player 2, so no save prompt), 10 models, no weapon needed.
const MORALE_UNIT := {"player": 2, "name": "Mor", "models": 10, "quality": 2, "defense": 4, "tough": 1,
	"x_in": 0.0, "z_step_in": 1.2, "base_radius_in": 0.63, "game_system": "gf",
	"faction_folder": "robot_legions", "rules": []}


## The shooting grid: five shapes. `cover` paints forest under the defender (z_step 0.1" keeps the ten models
## inside the painted block); `weapon.rules` are the table's own weapon-rule names.
static func scenarios() -> Array:
	return [
		{"name": "plain", "note": "no weapon rule, no cover", "weapon": RIFLE,
			"attacker": ATTACKER, "defender": DEFENDER},
		{"name": "ap", "note": "AP(1) worsens the defender's save from 4+ to 5+", "weapon": _weapon(["AP(1)"]),
			"attacker": ATTACKER, "defender": DEFENDER},
		{"name": "blast", "note": "Blast(3) scales every hit by the defender's model count", "weapon": _weapon(["Blast(3)"]),
			"attacker": ATTACKER, "defender": DEFENDER},
		{"name": "cover", "note": "majority of the defender fully inside forest: +1 Defense",
			"weapon": RIFLE, "attacker": ATTACKER,
			"defender": _with(DEFENDER, {"z_step_in": 0.1}), "cover": true},
		{"name": "deadly", "note": "Deadly(3) vs Tough(3): each unsaved wound kills one model",
			"weapon": _weapon(["Deadly(3)"]), "attacker": ATTACKER,
			"defender": _with(DEFENDER, {"tough": 3})},
		{"name": "ap_marked_target", "note": "AP(1) vs a defender with 2 Piercing Tag markers: one token spent, +1 AP (P4.D-30)",
			"weapon": _weapon(["AP(1)"]), "attacker": ATTACKER,
			"defender": _with(DEFENDER, {"ledger": {"piercing_tag_markers": 2, "piercing_tag_source": ""}})},
	]


## The melee grid: the same charge, five shapes of the charge/strike/strike-back/morale path.
static func melee_scenarios() -> Array:
	return [
		{"name": "plain", "note": "no rule: both sides strike with one attack per model",
			"attacker": MELEE_ATTACKER, "defender": MELEE_DEFENDER, "charge": CHARGE,
			"weapon": BLADE, "defender_weapon": DEF_BLADE},
		{"name": "ap", "note": "AP(1) on the attacker's blade worsens the defender's save",
			"attacker": MELEE_ATTACKER, "defender": MELEE_DEFENDER, "charge": CHARGE,
			"weapon": _with(BLADE, {"rules": ["AP(1)"]}), "defender_weapon": DEF_BLADE},
		{"name": "impact", "note": "Impact(1) auto-hits before the strikes (rules 3.6 slot)",
			"attacker": _with(MELEE_ATTACKER, {"rules": ["Impact(1)"]}), "defender": MELEE_DEFENDER,
			"charge": CHARGE, "weapon": BLADE, "defender_weapon": DEF_BLADE},
		{"name": "furious", "note": "Furious: each unmodified 6 in melee adds a hit on the charge",
			"attacker": _with(MELEE_ATTACKER, {"rules": ["Furious"]}), "defender": MELEE_DEFENDER,
			"charge": CHARGE, "weapon": BLADE, "defender_weapon": DEF_BLADE},
		{"name": "counter", "note": "Counter on the defender's blade strikes first when charged",
			"attacker": MELEE_ATTACKER, "defender": MELEE_DEFENDER, "charge": CHARGE,
			"weapon": BLADE, "defender_weapon": _with(DEF_BLADE, {"rules": ["Counter"]})},
	]


## The morale grid: the four outcomes the plan names (pass, Shaken, Rout, a spent once-buff) through the table's
## real _solo_morale_test. `dead` marks models lost before the test (the at-or-below-half gate); `once_mod` places
## a one-use morale-buff record on the unit.
static func morale_scenarios() -> Array:
	return [
		{"name": "pass", "note": "full strength, Q2+: every seed rolls the pass",
			"unit": _with(MORALE_UNIT, {"quality": 2}), "melee": false, "seeds": [0, 17, 34, 36]},
		{"name": "shake", "note": "full strength, Q6+: every seed fails and turns the unit Shaken",
			"unit": _with(MORALE_UNIT, {"quality": 6}), "melee": false, "seeds": [8, 17, 49, 225]},
		{"name": "rout", "note": "4 of 10 models left and a melee test: every seed fails and Routs",
			"unit": _with(MORALE_UNIT, {"quality": 6}), "melee": true, "dead": 6, "seeds": [8, 17, 49, 225]},
		{"name": "once", "note": "a one-use +1 morale buff turns a 4 into a pass and is then spent",
			"unit": _with(MORALE_UNIT, {"quality": 5}), "melee": false, "once_mod": "Great Banner",
			"seeds": [1, 4, 13, 20]},
	]


## The human-door grid: the player (seat 1, human) fires at the AI unit (seat 2). `human_hold` is the plain volley
## at 8" (every model in range); `human_far` stands the attacker's models back one inch each ("x_step_in") so the
## range gate cuts the rear of the unit at 20" - the case errors if the log says every model (or none) fired.
static func human_scenarios() -> Array:
	return [
		{"name": "human_hold", "runner": RUNNER_HUMAN_VOLLEY, "note": "held unit, plain Rifle volley at 8\"",
			"weapon": RIFLE, "attacker": ATTACKER, "defender": DEFENDER, "seeds": WIDE_SEEDS},
		{"name": "human_far", "runner": RUNNER_HUMAN_VOLLEY, "partial": true,
			"note": "20\" away, the rear models of the column are out of Rifle range (partial volley)",
			"weapon": RIFLE, "attacker": _with(ATTACKER, {"x_step_in": 1.0}),
			"defender": _with(DEFENDER, {"x_in": 20.0}), "seeds": WIDE_SEEDS},
	]


## The split grid. Kit: 5 models carry a Rifle (24"), 5 a Pistol (12"). Target A stands 18" out, target B 10" out on
## the other side of the column (offset in z so neither blocks the other's line of sight). Plain rules pick the
## nearest open, not-yet-activated target for every weapon, so B stands activated: the Rifle (reach 24") then picks
## A and the Pistol (only B is within 12") picks B. The AI case reads the pick off its own log; the human case
## declares it (the Pistol goes to B). Either errors with "no split" unless two different targets were fired at.
static func split_scenarios() -> Array:
	var kit := [["Rifle", 5, 24], ["Pistol", 5, 12]]
	var a := {"name": "DefA", "models": 5, "x_in": 18.0, "z_off_in": -8.0}
	var b := {"name": "DefB", "models": 5, "x_in": 10.0, "z_off_in": 12.0, "activated": true}
	return [
		{"name": "ai_split", "runner": RUNNER_AI_SHOOTING, "note": "the AI's body splits Rifle/Pistol over two targets",
			"kit": kit, "attacker": _with(ATTACKER, {"player": 2}),
			"def_a": _with(_with(DEFENDER, {"player": 1}), a), "def_b": _with(_with(DEFENDER, {"player": 1}), b),
			"seeds": WIDE_SEEDS},
		{"name": "human_split", "runner": RUNNER_HUMAN_SPLIT, "note": "the player declares the Pistol on B, the Rifle on A",
			"kit": kit, "attacker": ATTACKER, "def_a": _with(DEFENDER, a), "def_b": _with(DEFENDER, b),
			"b_names": ["Pistol"], "seeds": WIDE_SEEDS},
	]


## The Dangerous grid: an AI unit that advanced across Dangerous terrain (a 5x5 block painted under it). `dead` models
## are lost beforehand (the at-or-below-half gate reads the starting size), so the Dangerous wounds can call the end
## morale test; the volley's target stands at `x_in`; `can_shoot` false = the body skips the volley.
static func dangerous_scenarios() -> Array:
	var att := _with(ATTACKER, {"player": 2})
	var foe := _with(DEFENDER, {"player": 1, "x_in": 18.0, "models": 5})
	return [
		{"name": "dangerous_advance", "runner": RUNNER_AI_DANGEROUS, "note": "10 models, target in range: roll, volley, no morale",
			"weapon": RIFLE, "attacker": att, "defender": foe, "can_shoot": true, "seeds": WIDE_SEEDS},
		{"name": "dangerous_half", "runner": RUNNER_AI_DANGEROUS, "note": "4 of 10 models left: a wound calls the end morale",
			"weapon": RIFLE, "attacker": att, "defender": foe, "dead": 6, "can_shoot": true, "seeds": WIDE_SEEDS},
		{"name": "dangerous_no_target", "runner": RUNNER_AI_DANGEROUS, "note": "target at 40\": no volley, Dangerous + morale only",
			"weapon": RIFLE, "attacker": att, "defender": _with(foe, {"x_in": 40.0}), "dead": 6, "can_shoot": true,
			"seeds": WIDE_SEEDS},
		{"name": "dangerous_cannot_shoot", "runner": RUNNER_AI_DANGEROUS, "note": "the unit may not shoot: roll + morale only",
			"weapon": RIFLE, "attacker": att, "defender": foe, "dead": 6, "can_shoot": false, "seeds": WIDE_SEEDS},
	]


## The move-through grid: 20 defenders on a line (nudged so no casualty tie rests on a float's last bit), the bearer (10 models)
## moves `dest_in` inches along x through them: a Rush with a Crossing Strike gun, an Advance with that gun and a Rifle, and a
## Crossing Attack(2) bearer.
static func move_through_scenarios() -> Array:
	var att := _with(ATTACKER, {"player": 2})
	var foe := _with(DEFENDER, {"player": 1, "models": 20})
	var gun := _with(RIFLE, {"name": "Strafe Gun", "attacks": 2, "rules": ["Crossing Strike"]})
	return [
		{"name": "strafing_rush", "runner": RUNNER_AI_MOVE_THROUGH, "note": "Rush 11\" through the line: only the strafe fires",
			"weapon": gun, "attacker": att, "defender": _with(foe, {"x_in": 8.0}), "dest_in": 11.0},
		{"name": "strafing_advance", "runner": RUNNER_AI_MOVE_THROUGH, "note": "Advance 6\" through the line: the strafe, then the Rifle volley",
			"weapon": gun, "rifle": true, "attacker": att, "defender": _with(foe, {"x_in": 3.0}), "dest_in": 6.0},
		{"name": "crossing_attack", "runner": RUNNER_AI_MOVE_THROUGH, "note": "Crossing Attack(2) bearer, Rush 11\" through the line",
			"weapon": RIFLE, "attacker": _with(att, {"rules": ["Crossing Attack(2)"]}), "defender": _with(foe, {"x_in": 8.0}), "dest_in": 11.0},
	]


## The melee-shape grid: each shape drives ONE table function of the melee path on the parity gate's board, with
## the dice a real exchange would roll. `kill_defender` empties the defender before a consolidation case, so the
## winner branch is recorded beside the neither-destroyed back-step.
static func melee_shape_scenarios() -> Array:
	var base := {"attacker": MELEE_ATTACKER, "defender": MELEE_DEFENDER, "charge": CHARGE, "weapon": BLADE, "defender_weapon": DEF_BLADE, "seeds": SEEDS}
	return [
		_with(base, {"name": "human_charge", "runner": RUNNER_HUMAN_CHARGE,
			"note": "the player's charge through main._run_human_melee (auto intent: its consolidation runs)"}),
		_with(base, {"name": "strike_back", "runner": RUNNER_STRIKE_BACK,
			"note": "the charged defender's strike-back as its own phase"}),
		_with(base, {"name": "impact", "runner": RUNNER_MELEE_IMPACT, "attacker": _with(MELEE_ATTACKER, {"rules": ["Impact(1)"]}),
			"note": "Impact(1) on the charger: ten auto-hit dice before the strikes"}),
		_with(base, {"name": "counter", "runner": RUNNER_MELEE_COUNTER, "defender_weapon": _with(DEF_BLADE, {"rules": ["Counter"]}),
			"note": "Counter on the defender's blade: the strike-first phase alone"}),
		_with(base, {"name": "consolidation_back", "runner": RUNNER_CONSOLIDATION,
			"note": "neither unit destroyed: the charger separates 1\" back"}),
		_with(base, {"name": "consolidation_win", "runner": RUNNER_CONSOLIDATION, "kill_defender": true,
			"note": "enemy destroyed: the survivor consolidates, or holds when no goal is left"}),
	]


## The Fear / joined-hero grid (P4.D-47b). Same board as the melee shapes; every case also records where the models
## stand afterwards (`extra.pos`, inches, 2 decimals): the charge snap, pile-in and consolidation move them, and the
## older shapes only keep alive/wounds/lines. Fear(2) shifts the melee-result comparison only (never a wound), a hero
## adds its own strikes and its own Fear to the chain, and heroes take wounds after the host's models.
static func melee_fear_hero_scenarios() -> Array:
	var base := {"attacker": MELEE_ATTACKER, "defender": MELEE_DEFENDER, "charge": CHARGE, "weapon": BLADE,
		"defender_weapon": DEF_BLADE, "seeds": SEEDS, "positions": true, "runner": RUNNER_AI_CHARGE,
		"bystander": BYSTANDER}
	var fear_hero := _with(ATT_HERO, {"rules": ["Hero", "Fear(2)"]})
	var small := _with(MELEE_ATTACKER, {"models": 3})
	# Seeds picked from a 40-seed scan: each Fear grid holds seeds where the same dice WITHOUT Fear end the melee
	# another way (a loss becomes a draw, a draw a loss, the loser changes) and one where Fear changes nothing.
	var fear_seeds: Array[int] = [0, 3, 4, 9]
	var no_dice: Array[int] = [0, 17]
	return [
		_with(base, {"name": "fear_charger", "attacker": _with(MELEE_ATTACKER, {"rules": ["Fear(2)"]}), "seeds": fear_seeds,
			"note": "AI charge, Fear(2) on the charger: the enemy's tally counts two wounds more in the result"}),
		_with(base, {"name": "fear_defender", "defender": _with(MELEE_DEFENDER, {"rules": ["Fear(2)"]}),
			"seeds": [1, 4, 6, 8] as Array[int],
			"note": "AI charge, Fear(2) on the defender: the strike-back side carries the bonus"}),
		_with(base, {"name": "fear_human", "runner": RUNNER_HUMAN_CHARGE, "seeds": fear_seeds,
			"attacker": _with(MELEE_ATTACKER, {"rules": ["Fear(2)"]}),
			"note": "the player's charge with Fear(2) on the charger"}),
		_with(base, {"name": "furious_human", "runner": RUNNER_HUMAN_CHARGE,
			"attacker": _with(MELEE_ATTACKER, {"rules": ["Furious"]}),
			"note": "the player's charge with Furious: sixes add a hit on the charge"}),
		_with(base, {"name": "hero_charger", "attacker_hero": ATT_HERO,
			"note": "AI charge, a hero joined to the charger: its blade strikes with the host's"}),
		_with(base, {"name": "hero_defender", "defender_hero": DEF_HERO,
			"note": "AI charge into a host with a joined hero: the hero strikes back and soaks wounds last"}),
		_with(base, {"name": "hero_fear_chain", "attacker_hero": fear_hero, "seeds": [2, 4, 9, 12] as Array[int],
			"note": "the hero carries Fear(2), the host none: the chain's rating is the sum of the living"}),
		_with(base, {"name": "hero_human", "runner": RUNNER_HUMAN_CHARGE, "attacker_hero": ATT_HERO,
			"note": "the player's charge with a joined hero"}),
		_with(base, {"name": "consolidation_back", "runner": RUNNER_CONSOLIDATION, "attacker": small, "seeds": no_dice,
			"note": "neither destroyed, a 3-model charger (a 10-model rank does not move on this board): it separates 1\" back"}),
		_with(base, {"name": "consolidation_win", "runner": RUNNER_CONSOLIDATION, "attacker": small, "kill_defender": true,
			"seeds": no_dice, "note": "enemy destroyed, a far enemy left: the survivor consolidates up to 3\" toward it"}),
		_with(base, {"name": "hero_consolidation_back", "runner": RUNNER_CONSOLIDATION, "attacker": small,
			"attacker_hero": ATT_HERO, "seeds": no_dice,
			"note": "neither destroyed, a hero joined to the 3-model charger: where does the hero stand afterwards"}),
		_with(base, {"name": "hero_consolidation_win", "runner": RUNNER_CONSOLIDATION, "attacker": small,
			"attacker_hero": ATT_HERO, "kill_defender": true, "seeds": no_dice,
			"note": "enemy destroyed, a hero joined to the 3-model survivor: does the hero consolidate with the unit"}),
	]


## The damage-spell grid (CC-2): fixed hits, then the spell's own saves (no Shielded, no Cover) and the morale test of
## what is left. `bolt_saves` = AP(0) hits that the foe's armour mostly stops; `bolt_morale` = AP(1) hits that leave
## the six-model foe at or below half; `bolt_kill` = a three-model foe that twelve AP(4) hits wipe out (no morale test).
static func cast_damage_scenarios() -> Array:
	var bolt := func(hits: int, rules: Array) -> Dictionary:
		return {"range_in": 12, "effect": {"kind": "damage", "hits": hits, "weapon_rules": rules},
			"target": {"kind": "unit", "side": "enemy"}}
	var base := {"runner": RUNNER_AI_CAST, "seeds": CAST_SEEDS, "spell_name": "Test Bolt", "base_target": 2}
	return [
		_with(base, {"name": "bolt_saves", "spell": bolt.call(6, []),
			"note": "six AP(0) hits at Defense 4+: the saves stop about half"}),
		_with(base, {"name": "bolt_morale", "spell": bolt.call(6, ["AP(1)"]),
			"note": "six AP(1) hits (saves on 5+): the foe falls to half or less and tests morale"}),
		_with(base, {"name": "bolt_kill", "spell": bolt.call(12, ["AP(4)"]), "foe": _with(CAST_FOE, {"models": 3}),
			"note": "twelve AP(4) hits at three models: the unit is destroyed, no morale test"}),
	]


## The other cast legs (CC-2). The cast die is a 2+ in the damage grid (only a natural 1 fails); here the base is 4+, so a
## failed cast is a plain seed pick (die 1, 2 or 3). `buff_self`: a once-rule granted to the caster; `debuff_foe`: a defense malus
## on the enemy; `fizzle`: every target is gone, no die; `boost_interference`: +2 boost, -1 interference (3+);
## `casting_once`: a once-mod of +1 to casting rolls placed beforehand, spent by this roll.
static func cast_effects_scenarios() -> Array:
	var buff := {"range_in": 12, "effect": {"kind": "buff", "grants_rule": "Fearless", "duration": "once"},
		"target": {"side": "friendly", "count": 1, "kind": "unit"}}
	var debuff := {"range_in": 12, "effect": {"kind": "debuff", "modifier": {"def_mod": -1}, "duration": "round"},
		"target": {"kind": "unit", "side": "enemy"}}
	var base := {"runner": RUNNER_AI_CAST, "seeds": CAST_FX_SEEDS, "spell_name": "Warding Chant", "base_target": 4,
		"spell": buff, "on_self": true}
	return [
		_with(base, {"name": "buff_self", "note": "a buff cast on the caster itself: the token and the granted rule"}),
		_with(base, {"name": "debuff_foe", "spell_name": "Withering Gaze", "spell": debuff, "on_self": false,
			"note": "a debuff on the enemy: the token and the defense malus"}),
		_with(base, {"name": "fizzle", "kill_foe": true, "on_self": false, "spell": debuff,
			"seeds": [0, 1] as Array[int], "note": "the only target is gone: no die, one line"}),
		_with(base, {"name": "boost_interference", "boost": 2, "interference": 1, "threshold": 2,
			"note": "both sides spent tokens (both-AI): the die needs 3+ and the line states the spend"}),
		_with(base, {"name": "casting_once", "pre_mod": {"kind": "buff", "modifier": {"casting_mod": 1}, "duration": "once"},
			"note": "a once-mod of +1 to casting rolls: the net is stated and the roll spends the mod"}),
	]


## The prompt grid: 20 Rifle shots (2 attacks per model) at a human 10-model defender, so a volley lands several wounds.
## `mixed`: five Rifle bearers and five "Plasma Stub" bearers (two loadouts, every model Tough 1); `tough`: one loadout,
## every model Tough(3). Each shape is answered two ways: `auto` (right-click at once) and `click` (the owner clicks
## the model slots in "clicks" one wound each, then right-clicks the rest). The table's own casualty pick takes the
## edge models first (slots 0, 9, 1, ...), so the clicks go to middle slots: a click run cannot equal an auto run.
static func mixed_scenarios() -> Array:
	var att := _with(ATTACKER, {"player": 2})
	var rifle := _with(RIFLE, {"attacks": 2})
	var human := _with(DEFENDER, {"player": 1})
	var out: Array = []
	for shape in [["mixed", human], ["tough", _with(human, {"tough": 3})]]:
		for variant in [["auto", []], ["click", [4, 5]]]:
			out.append({"name": "%s_%s" % [shape[0], variant[0]], "runner": RUNNER_AI_INTO_HUMAN,
				"note": "%s defender, the owner answers the #172 prompt: %s" % [shape[0], variant[0]],
				"weapon": rifle, "attacker": att, "defender": shape[1], "shape": shape[0],
				"clicks": variant[1], "seeds": PROMPT_SEEDS})
	return out


static func _weapon(rules: Array) -> Dictionary:
	return _with(RIFLE, {"rules": rules})


static func _with(base: Dictionary, patch: Dictionary) -> Dictionary:
	var out := base.duplicate(true)
	return out.merged(patch, true)


## Puts a freshly booted main.tscn into the state the grid needs and proves the OLD table path is active: the
## kill switch was set by the caller (env) but CoreActivation caches its decision once, so the cache is dropped
## here. False = the one-core flag is on; the caller must not record anything then.
static func configure(main: Node) -> bool:
	CoreActivation._env = -1
	if CoreActivation.enabled():
		return false
	SoloHarness.start(main, [2])
	main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	main.opr_army_manager.current_round = 1
	SoloHarness.instant(main)
	return true


## Runs one family's whole grid on `main` (already booted, PLAYING, solo_controller ready) and returns the fixture
## shape. Await it: every exchange awaits the table's own presentation seams.
static func capture(main: Node, family: String = FAMILY) -> Dictionary:
	if family == MELEE_FAMILY:
		return await capture_melee(main)
	if family == MORALE_FAMILY:
		return await capture_morale(main)
	if family == HUMAN_FAMILY:
		return await capture_grid(main, HUMAN_FAMILY, human_scenarios())
	if family == SPLIT_FAMILY:
		return await capture_grid(main, SPLIT_FAMILY, split_scenarios())
	if family == DANGEROUS_FAMILY:
		return await capture_grid(main, DANGEROUS_FAMILY, dangerous_scenarios())
	if family == MIXED_FAMILY:
		return await capture_grid(main, MIXED_FAMILY, mixed_scenarios())
	if family == MOVE_THROUGH_FAMILY:
		return await capture_grid(main, MOVE_THROUGH_FAMILY, move_through_scenarios())
	if family == MELEE_SHAPES_FAMILY:
		return await capture_grid(main, MELEE_SHAPES_FAMILY, melee_shape_scenarios())
	if family == MELEE_FEAR_HERO_FAMILY:
		return await capture_grid(main, MELEE_FEAR_HERO_FAMILY, melee_fear_hero_scenarios())
	if family == CAST_DAMAGE_FAMILY:
		return await capture_grid(main, CAST_DAMAGE_FAMILY, cast_damage_scenarios())
	if family == CAST_EFFECTS_FAMILY:
		return await capture_grid(main, CAST_EFFECTS_FAMILY, cast_effects_scenarios())
	var out := {"schema": SCHEMA, "family": FAMILY, "provenance": provenance(), "cases": []}
	for sc in scenarios():
		for seed in SEEDS:
			out["cases"].append(await _run_case(main, sc, seed))
	return out


## A runner-dispatched family: every scenario x its own seeds (default SEEDS) through _run_case.
static func capture_grid(main: Node, family: String, scs: Array) -> Dictionary:
	var out := {"schema": SCHEMA, "family": family, "provenance": provenance(), "cases": []}
	for sc in scs:
		for seed in sc.get("seeds", SEEDS):
			out["cases"].append(await _run_case(main, sc, int(seed)))
	return out


static func capture_melee(main: Node) -> Dictionary:
	var fast: bool = main.get("_solo_fast")
	var slots: Dictionary = (main.solo_ai_slots as Dictionary).duplicate()
	SoloHarness.fast(main)   # the parity gate's fast-forward: no glide tweens
	# Both seats AI, like the parity gate: a human seat would wait for a save click on the strike-back.
	main.solo_ai_slots = {1: true, 2: true}
	var out := {"schema": SCHEMA, "family": MELEE_FAMILY, "provenance": provenance(), "cases": []}
	for sc in melee_scenarios():
		for seed in SEEDS:
			out["cases"].append(await _run_melee_case(main, sc, seed))
	main.solo_ai_slots = slots
	SoloHarness.fast(main, fast)
	return out


static func capture_morale(main: Node) -> Dictionary:
	var out := {"schema": SCHEMA, "family": MORALE_FAMILY, "provenance": provenance(), "cases": []}
	for sc in morale_scenarios():
		for seed in sc["seeds"]:
			out["cases"].append(await _run_morale_case(main, sc, int(seed)))
	return out


## What a later reader needs to know this recording is still comparable: the rules epoch moves the table's
## behaviour, the registry hash moves its data, and the git sha says which tree produced it.
static func provenance() -> Dictionary:
	var sha := ""
	var lines: Array = []
	if OS.execute("git", ["rev-parse", "HEAD"], lines, true) == 0 and not lines.is_empty():
		sha = str(lines[0]).strip_edges()
	var reg := RulesRegistry.registry_state(REGISTRY_SYSTEM)
	return {"epoch": AiActRecorder.rules_epoch, "git_sha": sha, "registry_system": REGISTRY_SYSTEM,
		"registry_sha256": str(reg.get("sha256", ""))}


## One scenario x seed through the scenario's runner, recording what it did. The units are removed again so the next
## case starts from the same table. The default runner (the table's AI volley) is gone: such a scenario records the
## "unknown runner" error, and its committed fixture stays as the frozen record.
static func _run_case(main: Node, sc: Dictionary, seed: int) -> Dictionary:
	var runner := str(sc.get("runner", RUNNER_AI_VOLLEY))
	match runner:
		RUNNER_AI_SHOOTING, RUNNER_HUMAN_SPLIT:
			return await _run_split_case(main, sc, seed)
		RUNNER_AI_DANGEROUS:
			return await _run_dangerous_case(main, sc, seed)
		RUNNER_AI_INTO_HUMAN:
			return await _run_into_human_case(main, sc, seed)
		RUNNER_AI_MOVE_THROUGH:
			return await _run_move_through_case(main, sc, seed)
		RUNNER_AI_CAST:
			return await _run_ai_cast_case(main, sc, seed)
		RUNNER_HUMAN_CHARGE, RUNNER_STRIKE_BACK, RUNNER_MELEE_IMPACT, RUNNER_MELEE_COUNTER, RUNNER_CONSOLIDATION, \
		RUNNER_AI_CHARGE:
			return await _run_melee_shape_case(main, sc, seed)
	return {"scenario": str(sc["name"]), "seed": seed, "error": "unknown runner %s" % runner}


## One split scenario x seed: a two-weapon attacker and two targets, then the runner's door. Records the three units'
## final states and the case's "extra" (the attacker's shot_round stamp, which the human split writes).
static func _run_split_case(main: Node, sc: Dictionary, seed: int) -> Dictionary:
	var kit: Array = sc["kit"]
	var att := ParityTable._make_unit(main, sc["attacker"], _kit_weapon(kit[0]))
	_kit_out(att, kit)
	var a := ParityTable._make_unit(main, sc["def_a"], {})
	var b := ParityTable._make_unit(main, sc["def_b"], {})
	for u in [[a, sc["def_a"]], [b, sc["def_b"]]]:
		_stand_back(u[0], u[1])
		(u[0] as GameUnit).is_activated = bool((u[1] as Dictionary).get("activated", false))
	main.seed_tray_rng(seed)
	var lines: Array = []
	var tap := _line_tap(lines)
	main.battle_log.entry_added.connect(tap)
	if str(sc["runner"]) == RUNNER_AI_SHOOTING:
		# Both seats AI, like the melee grid: a human defender would wait for a save click that never comes.
		var seats: Dictionary = (main.solo_ai_slots as Dictionary).duplicate()
		main.solo_ai_slots = {1: true, 2: true}
		await main._run_ai_shooting({"unit": att, "moved": false})
		main.solo_ai_slots = seats
	else:   # the player's declared split through the production Fire! button (the rules core, or a free roll)
		await SoloHarness.split_fire(main, att, a, b, sc["b_names"])
	main.battle_log.entry_added.disconnect(tap)
	var rec := {"scenario": str(sc["name"]), "seed": seed, "epoch": AiActRecorder.rules_epoch,
		"lines": lines, "final": _final([att, a, b]), "rng": _rng_state(main),
		"extra": {"shot_round": str(att.unit_properties.get("shot_round", "<none>"))}}
	if _fired_at(lines).size() < 2:
		rec = {"scenario": str(sc["name"]), "seed": seed, "error": "no split (fired at %s)" % str(_fired_at(lines))}
	_free_units(main, [att, a, b])
	await main.get_tree().process_frame
	return rec


## One Dangerous scenario x seed, in the order of the AI body: the Dangerous roll (main.gd's _run_ai_dangerous with the
## dice the production formula gives), the volley when the unit can shoot (moved = true), then the end-of-activation
## morale from the Dangerous wounds. The case errors if no Dangerous line was logged (the roll never happened).
static func _run_dangerous_case(main: Node, sc: Dictionary, seed: int) -> Dictionary:
	var att := ParityTable._make_unit(main, sc["attacker"], (sc["weapon"] as Dictionary).duplicate(true))
	var dfn := ParityTable._make_unit(main, sc["defender"], {})
	_kill_models(att, int(sc.get("dead", 0)))
	var painted := _paint_cover(main, att, main.terrain_overlay.TerrainType.DANGEROUS)
	var seats: Dictionary = (main.solo_ai_slots as Dictionary).duplicate()
	main.solo_ai_slots = {1: true, 2: true}   # both seats AI: a human defender would wait for a save click
	main.seed_tray_rng(seed)
	var dice := int(sc.get("dice", OPRArmyManager.dangerous_dice_for(att)))
	var alive_before: int = SoloController.combined_alive(att)
	var wounds_before: int = main._solo_unit_wounds_now(att)
	var lines: Array = []
	var tap := _line_tap(lines)
	main.battle_log.entry_added.connect(tap)
	await main._run_ai_dangerous(att, dice)
	if not att.is_destroyed():
		if bool(sc.get("can_shoot", true)):
			await main._run_ai_shooting({"unit": att, "moved": true})
		if not att.is_destroyed():
			await main._solo_shooting_morale(att, alive_before, main._roller_label(att), wounds_before, "Dangerous terrain")
	main.battle_log.entry_added.disconnect(tap)
	main.solo_ai_slots = seats
	var rec := {"scenario": str(sc["name"]), "seed": seed, "epoch": AiActRecorder.rules_epoch,
		"lines": lines, "final": _final([att, dfn]), "rng": _rng_state(main), "extra": {"dice": str(dice)}}
	if not lines.any(func(l: Variant) -> bool: return str(l).contains("Dangerous terrain test")):
		rec = {"scenario": str(sc["name"]), "seed": seed, "error": "no Dangerous line was logged (dice %d)" % dice}
	_unpaint_cover(main, painted)
	_free_units(main, [att, dfn])
	await main.get_tree().process_frame
	return rec


## One move-through scenario x seed: the bearer's models walk along x to `dest_in` (the planner's own `last_move_paths` shape),
## then the body's order: Strafing, Crossing Attack, and (`rifle`) the activation's volley. The case errors when nothing was
## crossed (no move-through line was logged).
static func _run_move_through_case(main: Node, sc: Dictionary, seed: int) -> Dictionary:
	var att := ParityTable._make_unit(main, sc["attacker"], (sc["weapon"] as Dictionary).duplicate(true))
	var dfn := ParityTable._make_unit(main, sc["defender"], _with(RIFLE, {"count": 20}))
	if bool(sc.get("rifle", false)):
		var w := OPRApiClient.OPRWeapon.new()
		w.name = "Rifle"
		w.range_value = 24
		w.attacks = 1
		w.count = 10
		(att.source_data as OPRApiClient.OPRUnit).weapons.append(w)
	for i in dfn.models.size():
		(dfn.models[i] as ModelInstance).node.global_position.z += float((i * 7) % 5) * 0.0001
	var seats: Dictionary = (main.solo_ai_slots as Dictionary).duplicate()
	main.solo_ai_slots = {1: true, 2: true}   # both seats AI: a human defender would wait for a save click
	main.solo_controller.ai_slot = 2
	main.solo_controller.human_slot = 1
	var legs: Array = []
	for m in att.get_alive_models():
		var from: Vector3 = (m as ModelInstance).node.global_position
		var to := Vector3(float(sc["dest_in"]) * 0.0254, from.y, from.z)
		legs.append({"model": m, "path": [from, to]})
		(m as ModelInstance).node.global_position = to
	main.solo_controller.last_move_paths = legs
	att.unit_properties["moved_round"] = 1
	main.seed_tray_rng(seed)
	var lines: Array = []
	var tap := _line_tap(lines)
	main.battle_log.entry_added.connect(tap)
	await main._solo_apply_strafing(att)
	await main._solo_apply_crossing_attack(att)
	if bool(sc.get("rifle", false)):
		await main._run_ai_shooting({"unit": att, "moved": true, "action": AiDecision.Action.ADVANCE})
	main.battle_log.entry_added.disconnect(tap)
	main.solo_ai_slots = seats
	var rec := {"scenario": str(sc["name"]), "seed": seed, "epoch": AiActRecorder.rules_epoch,
		"lines": lines, "final": _final([att, dfn]), "rng": _rng_state(main)}
	if not lines.any(func(l: Variant) -> bool: return str(l).contains("passes over") or str(l).contains("Crossing Attack")):
		rec = {"scenario": str(sc["name"]), "seed": seed, "error": "no move-through line was logged"}
	_free_units(main, [att, dfn])
	await main.get_tree().process_frame
	return rec


## One melee-shape scenario x seed: the parity gate's board, then the shape's own table function. Both seats are AI
## (a human seat would wait for a card) except the human charge, whose owner saves go through the auto-saves seam.
static func _run_melee_shape_case(main: Node, sc: Dictionary, seed: int) -> Dictionary:
	var pair: Array = ParityMelee._units(main, sc, {})
	var att := pair[0] as GameUnit
	var dfn := pair[1] as GameUnit
	var chain: Array = [att, dfn]   # every unit the case built, the heroes last: recorded and freed together
	if sc.has("attacker_hero"):
		chain.append(_join_hero(main, att, sc["attacker_hero"]))
	if sc.has("defender_hero"):
		chain.append(_join_hero(main, dfn, sc["defender_hero"]))
	var idle: Array = []   # built, never recorded: freed with the rest
	if sc.has("bystander"):
		idle.append(ParityTable._make_unit(main, sc["bystander"], {}))
	if bool(sc.get("kill_defender", false)):
		_kill_models(dfn, dfn.models.size())
	var runner := str(sc["runner"])
	var seats: Dictionary = (main.solo_ai_slots as Dictionary).duplicate()
	main.solo_ai_slots = {2: true} if runner == RUNNER_HUMAN_CHARGE else {1: true, 2: true}
	if runner == RUNNER_HUMAN_CHARGE:
		SoloHarness.auto_saves(main)   # the human charger's saves against the strike-back roll on the tray, no card
	main.seed_tray_rng(seed)
	var lines: Array = []
	var tap := _line_tap(lines)
	main.battle_log.entry_added.connect(tap)
	match runner:
		RUNNER_HUMAN_CHARGE:
			await main._run_human_melee(att, dfn, true, ParityMelee._charge_from_in(sc))
		RUNNER_STRIKE_BACK:
			await main._solo_melee_strike_phase(dfn, att, false, 0)   # 0 = SoloStrike.ALL
		RUNNER_MELEE_IMPACT:
			await main._solo_charge_impact(att, dfn, false, ParityMelee._charge_from_in(sc))
		RUNNER_MELEE_COUNTER:
			await main._solo_melee_strike_phase(dfn, att, false, 1)   # 1 = SoloStrike.COUNTER_ONLY
		RUNNER_CONSOLIDATION:
			await main._solo_consolidate_melee(att, dfn, true)
		RUNNER_AI_CHARGE:
			await main._run_ai_melee({"unit": att, "target": dfn, "charge_from_in": ParityMelee._charge_from_in(sc)})
	main.battle_log.entry_added.disconnect(tap)
	SoloHarness.auto_saves(main, false)   # only this runner raises it (unset is the game default: the card is asked)
	main.solo_ai_slots = seats
	var rec := {"scenario": str(sc["name"]), "seed": seed, "epoch": AiActRecorder.rules_epoch,
		"lines": lines, "final": _final(chain), "rng": _rng_state(main)}
	if bool(sc.get("positions", false)):
		rec["extra"] = {"pos": _positions_in(chain)}
	_free_units(main, chain + idle)
	await main.get_tree().process_frame
	return rec


## One cast scenario x seed: the planner's cast dict for a one-model caster, through the table's own
## `_solo_resolve_ai_casts` (the resolver the AI body calls after the move). Besides the lines and the final state it
## records, as text, the activation's tray rolls in order with their legs (`cast` = the die, `spell` = everything the
## effect rolls) and the spell records + tokens each unit holds afterwards (`extra.mods`).
static func _run_ai_cast_case(main: Node, sc: Dictionary, seed: int) -> Dictionary:
	var caster := ParityTable._make_unit(main, CASTER, CAST_STAFF)
	var foe := ParityTable._make_unit(main, sc.get("foe", CAST_FOE), {})
	if bool(sc.get("kill_foe", false)):
		_kill_models(foe, foe.models.size())
	if sc.has("pre_mod"):
		main._solo_record_spell_mod(caster, "Focus", sc["pre_mod"])   # the real placement path; its line is written before the tap
	var cast := {"caster": caster, "caster_unit": caster, "name": str(sc["spell_name"]), "spell": sc["spell"],
		"targets": [caster] if bool(sc.get("on_self", false)) else [foe], "boost": int(sc.get("boost", 0)),
		"interference": int(sc.get("interference", 0)), "base_target": int(sc["base_target"]),
		"threshold": int(sc.get("threshold", 1)), "owner_label": "AI (Mystic)", "interference_open": false}
	var seats: Dictionary = (main.solo_ai_slots as Dictionary).duplicate()
	main.solo_ai_slots = {1: true, 2: true}   # both seats AI: a human foe would wait for a save card
	main._solo_both_ai = true
	main.seed_tray_rng(seed)
	var lines: Array = []
	var tap := _line_tap(lines)
	main.battle_log.entry_added.connect(tap)
	CoreShadow.tap.clear()
	CoreShadow.tapping = true   # the shadow's own roll tap: kind, count, target, faces, owner and the leg of every tray roll
	await main._solo_resolve_ai_casts({"casts": [cast]})
	CoreShadow.tapping = false
	main.battle_log.entry_added.disconnect(tap)
	main.solo_ai_slots = seats
	main._solo_both_ai = false
	var rolls: Array = CoreShadow.tap.map(func(r: Dictionary) -> String: return "%s|%s|%dx%d+|%s|%s" % [
		str(r["leg"]), str(r["kind"]), int(r["count"]), int(r["target"]), str(r["owner"]),
		",".join((r["faces"] as Array).map(func(f: Variant) -> String: return str(int(f))))])
	CoreShadow.tap.clear()
	var rec := {"scenario": str(sc["name"]), "seed": seed, "epoch": AiActRecorder.rules_epoch, "lines": lines,
		"final": _final([caster, foe]), "rng": _rng_state(main), "extra": {"rolls": rolls, "mods": _spell_state(main, [caster, foe])}}
	for gu in [caster, foe]:
		main._solo_spell_mods.erase((gu as GameUnit).get_instance_id())
	main._solo_spell_tokens_active.clear()
	_free_units(main, [caster, foe])
	await main.get_tree().process_frame
	return rec


## The spell records (`_solo_spell_mods`) and the live spell tokens each unit holds, as text: [unit, [record], [token]].
static func _spell_state(main: Node, units: Array) -> Array:
	var out: Array = []
	for u in units:
		var gu := u as GameUnit
		var recs: Array = []
		for rd in main._solo_spell_mods.get(gu.get_instance_id(), []):
			var r := rd as Dictionary
			recs.append("%s|hit %d|def %d|cast %d|morale %d|grants %s|%s" % [str(r["spell"]), int(r["hit_mod"]),
				int(r["def_mod"]), int(r["casting_mod"]), int(r["morale_mod"]), str(r["grants_rule"]), str(r["duration"])])
		var toks: Array = []
		for e in main._solo_spell_tokens_active:
			if (e as Dictionary).get("unit") == gu:
				toks.append("%s|once %s" % [str(e["token"]), str(bool(e["once"]))])
		out.append([gu.get_name(), recs, toks])
	return out


## Builds the hero of `spec`, stands its model at the spec's own spot and joins it to `host` the way the army import
## does (`attached_to` on the hero, `attached_heroes` on the host); the host's chain then counts it everywhere.
static func _join_hero(main: Node, host: GameUnit, spec: Dictionary) -> GameUnit:
	var weapon: Dictionary = (spec["weapon"] as Dictionary).duplicate(true)
	var hero := ParityTable._make_unit(main, spec, weapon)
	ParityMelee._equip(hero, weapon)
	hero.unit_properties["base_size_round"] = roundi(float(spec["base_radius_in"]) * 50.8)
	var nd := (hero.models[0] as ModelInstance).node as Node3D
	nd.global_position = Vector3(float(spec["stand_x_in"]) * 0.0254, 0.0, float(spec["stand_z_in"]) * 0.0254)
	hero.unit_properties["attached_to"] = host
	host.unit_properties["attached_heroes"] = [hero]
	return hero


## Metres as inches text with 2 decimals ("-0.00" folded to "0.00"): text, not a float, so no representation noise.
static func _inch_text(metres: float) -> String:
	var v := snappedf(metres / 0.0254, 0.01)
	return "%.2f" % (0.0 if absf(v) < 0.005 else v)


## Where every model of every unit stands, in inches rounded to 2 decimals, [unit name, [[x, z] per model slot]]; a
## dead model keeps its slot (its token is where it fell), so the rows always line up with `final.slots`.
static func _positions_in(units: Array) -> Array:
	var out: Array = []
	for u in units:
		var gu := u as GameUnit
		var spots: Array = []
		for m in gu.models:
			var nd := (m as ModelInstance).node as Node3D
			if nd == null or not is_instance_valid(nd):
				spots.append([])   # the node is gone (freed with the casualty): no spot to record
				continue
			spots.append([_inch_text(nd.global_position.x), _inch_text(nd.global_position.z)])
		out.append([gu.get_name(), spots])
	return out


## One prompt scenario x seed: the AI attacker's volley through the core door at the human defender, with
## a Timer pump standing in for the player: it presses OK on the "Incoming fire!" save card and answers the wound-
## allocation prompt (clicks first, then a right-click for the rest). The case errors if the prompt never opened.
static func _run_into_human_case(main: Node, sc: Dictionary, seed: int) -> Dictionary:
	var weapon: Dictionary = (sc["weapon"] as Dictionary).duplicate(true)
	var att := ParityTable._make_unit(main, sc["attacker"], weapon)
	var dfn := ParityTable._make_unit(main, sc["defender"], {})
	for i in dfn.models.size():
		var m := dfn.models[i] as ModelInstance
		m.model_index = i
		var kit := "Rifle" if (str(sc["shape"]) == "tough" or i < dfn.models.size() / 2) else "Plasma Stub"
		m.properties["weapons"] = [{"name": kit}]
	main.seed_tray_rng(seed)
	var dist_in := float((sc["defender"] as Dictionary)["x_in"]) - float((sc["attacker"] as Dictionary)["x_in"])
	var wobj: OPRApiClient.OPRWeapon = (att.source_data as OPRApiClient.OPRUnit).weapons[0]
	var shots: Array = []
	for p in AiEv.stamp_sergeant(AiShooting.profiles_in_range([wobj], dist_in), att):
		shots.append({"member": att, "quality": int((sc["attacker"] as Dictionary)["quality"]),
			"alive": att.get_alive_count(), "max": att.models.size(), "reach": float(weapon["range_in"]),
			"profile": p})
	var st := {"rolls": 0, "ticks": 0, "opened": 0, "fed": 0, "clicks": (sc["clicks"] as Array).duplicate()}
	var on_roll := func(_total: int) -> void:
		st["rolls"] += 1
		if st["rolls"] == ROLLS_BEFORE_WOUNDS:
			SoloHarness.instant(main, false)
	var pump := Timer.new()
	pump.wait_time = 0.02
	var on_tick := func() -> void:
		for c in main.get_children():
			var card := c as PromptCard
			if card != null and card.title == "Incoming fire!":
				card.ok_button.pressed.emit()
		var prompt: Dictionary = main._solo_model_pick
		if prompt.is_empty():
			return
		var outcome: Array = prompt["outcome"]
		st["opened"] = 1
		if not outcome.is_empty():
			return   # the previous pick has not been applied yet - one at a time
		st["ticks"] += 1
		if st["ticks"] > 250 or (st["clicks"] as Array).is_empty():
			outcome.append({})   # right-click: the rest goes to the auto path (also the deadlock guard)
		else:
			outcome.append({"unit": dfn, "index": int((st["clicks"] as Array).pop_front())})
		st["fed"] += 1
		if int(st["fed"]) == 1:
			SoloHarness.instant(main)   # the morale die after the landing needs the batch tray again
	pump.timeout.connect(on_tick)
	main.add_child(pump)
	pump.start()
	main.dice_roller_control.roll_finnished.connect(on_roll)
	var lines: Array = []
	var tap := _line_tap(lines)
	main.battle_log.entry_added.connect(tap)
	# P4.D-26: the volley goes through the core door (the AI body's `run_ai`); the table's AI volley is gone.
	var ran: bool = await CoreActivation.run_ai(main, att, {"action": AiDecision.Action.HOLD}, dfn, CoreActivation.capture(main), shots)
	st["core"] = "1" if ran else "0"
	main.battle_log.entry_added.disconnect(tap)
	main.dice_roller_control.roll_finnished.disconnect(on_roll)
	pump.queue_free()
	SoloHarness.instant(main)
	var rec := {"scenario": str(sc["name"]), "seed": seed, "epoch": AiActRecorder.rules_epoch,
		"lines": lines, "final": _final([att, dfn]), "rng": _rng_state(main),
		"extra": {"prompt_opened": str(st["opened"]), "picks_fed": str(st["fed"])}}
	if st.has("core"):
		rec["core"] = str(st["core"])
	if int(st["opened"]) == 0:
		rec = {"scenario": str(sc["name"]), "seed": seed,
			"error": "the wound-allocation prompt never opened (rolls %d)" % int(st["rolls"])}
	_free_units(main, [att, dfn])
	await main.get_tree().process_frame
	return rec


## A second weapon on the attacker's OPR data, and the per-model loadout: `kit` = [[name, models, range], ...]; the
## first entry is the weapon _make_unit already built (count = its models), later entries are added here.
static func _kit_weapon(entry: Array) -> Dictionary:
	return {"name": str(entry[0]), "range_in": int(entry[2]), "attacks": 1, "count": int(entry[1]), "rules": []}


static func _kit_out(unit: GameUnit, kit: Array) -> void:
	var weapons: Array = (unit.source_data as OPRApiClient.OPRUnit).weapons
	for e in kit.slice(1):
		var w := OPRApiClient.OPRWeapon.new()
		w.name = str(e[0])
		w.range_value = int(e[2])
		w.attacks = 1
		w.count = int(e[1])
		weapons.append(w)
	var i := 0
	for e in kit:
		for _n in int(e[1]):
			(unit.models[i] as ModelInstance).properties["weapons"] = [{"name": str(e[0]), "attacks": 1}]
			i += 1


## The distinct targets the "<unit> fires <weapon> at <target> ..." lines of a volley name, in order.
static func _fired_at(lines: Array) -> Array:
	var rx := RegEx.create_from_string("fires \\w+ at (\\w+)")
	var out: Array = []
	for l in lines:
		var m := rx.search(str(l))
		if m != null and not out.has(m.get_string(1)):
			out.append(m.get_string(1))
	return out


## Places a unit's models after _make_unit: model i stands "x_step_in" inches further back (-x) than model 0, and
## the whole unit moves "z_off_in" inches in z; a spec without either key is untouched.
static func _stand_back(unit: GameUnit, spec: Dictionary) -> void:
	var step := float(spec.get("x_step_in", 0.0))
	var z_off := float(spec.get("z_off_in", 0.0))
	if step == 0.0 and z_off == 0.0:
		return
	for i in unit.models.size():
		var nd := (unit.models[i] as ModelInstance).node as Node3D
		nd.global_position.x -= step * i * 0.0254
		nd.global_position.z += z_off * 0.0254


static func _line_tap(lines: Array) -> Callable:
	return func(e: Dictionary) -> void:
		lines.append("%s|%s" % [BattleLog.Category.keys()[int(e["category"])], str(e["text"])])


## One melee scenario x seed: build the two units in base contact (the parity gate's own board and per-model
## loadout), seed the real tray, run the table's real charge/strike/strike-back/morale resolver, and record it.
static func _run_melee_case(main: Node, sc: Dictionary, seed: int) -> Dictionary:
	var pair: Array = ParityMelee._units(main, sc, {})
	var att := pair[0] as GameUnit
	var dfn := pair[1] as GameUnit
	main.seed_tray_rng(seed)
	var lines: Array = []
	var tap := func(e: Dictionary) -> void:
		lines.append("%s|%s" % [BattleLog.Category.keys()[int(e["category"])], str(e["text"])])
	main.battle_log.entry_added.connect(tap)
	await main._run_ai_melee({"unit": att, "target": dfn, "charge_from_in": ParityMelee._charge_from_in(sc)})
	main.battle_log.entry_added.disconnect(tap)
	var rec := {"scenario": str(sc["name"]), "seed": seed, "epoch": AiActRecorder.rules_epoch,
		"lines": lines, "final": _final([att, dfn]), "rng": _rng_state(main)}
	_free_units(main, [att, dfn])
	await main.get_tree().process_frame
	return rec


## One morale scenario x seed on one AI-owned unit: optionally lose models and/or place the one-use buff, seed the
## real tray, run the table's real morale test, and record the outcome lines and the unit's final state.
static func _run_morale_case(main: Node, sc: Dictionary, seed: int) -> Dictionary:
	var unit := ParityTable._make_unit(main, sc["unit"], {})
	_kill_models(unit, int(sc.get("dead", 0)))
	var spell := str(sc.get("once_mod", ""))
	if spell != "":
		main._solo_spell_mods[unit.get_instance_id()] = [{"spell": spell, "morale_mod": 1, "duration": "once"}]
	main.seed_tray_rng(seed)
	var lines: Array = []
	var tap := func(e: Dictionary) -> void:
		lines.append("%s|%s" % [BattleLog.Category.keys()[int(e["category"])], str(e["text"])])
	main.battle_log.entry_added.connect(tap)
	await main._solo_morale_test(unit, "AI (%s)" % unit.get_name(), bool(sc.get("melee", false)), "")
	main.battle_log.entry_added.disconnect(tap)
	main._solo_spell_mods.erase(unit.get_instance_id())
	var rec := {"scenario": str(sc["name"]), "seed": seed, "epoch": AiActRecorder.rules_epoch,
		"lines": lines, "final": _final([unit]), "rng": _rng_state(main)}
	_free_units(main, [unit])
	await main.get_tree().process_frame
	return rec


## Marks `n` models of the unit dead (from the back); the model count on the unit stays the starting size, which is
## what the at-or-below-half gate reads.
static func _kill_models(unit: GameUnit, n: int) -> void:
	for i in range(n):
		if i < unit.models.size():
			(unit.models[unit.models.size() - 1 - i] as ModelInstance).is_alive = false


## What "final state" means for the witness: models left, wounds left on them, whether the unit is Shaken, and (v2)
## which model slot is alive with how many wounds left, so "which models died" is part of the record.
static func _final(units: Array) -> Array:
	var out: Array = []
	for u in units:
		var gu := u as GameUnit
		var wounds := 0
		var slots: Array = []
		for i in gu.models.size():
			var m := gu.models[i] as ModelInstance
			wounds += int(m.wounds_current)
			slots.append([i, m.is_alive, int(m.wounds_current)])
		out.append({"unit": gu.get_name(), "alive": gu.get_alive_count(), "wounds": wounds,
			"shaken": gu.is_shaken, "slots": slots})
	return out


## The tray RNG state after the exchange, as a string: it is a 64-bit value and JSON numbers are doubles.
static func _rng_state(main: Node) -> String:
	return str((main._tray_rng as RandomNumberGenerator).state)


## Paints a forest block (or `terrain`, a TerrainType value) around the unit and returns the touched cells as cell -> {had, value} (0 is a valid
## terrain value, so `had` decides whether the restore erases or writes back).
static func _paint_cover(main: Node, unit: GameUnit, terrain: int = -1) -> Dictionary:
	var saved := {}
	var alive: Array = unit.get_alive_models()
	if alive.is_empty() or main.terrain_overlay == null:
		return saved
	var centre := Vector3.ZERO
	for m in alive:
		centre += (m as ModelInstance).node.global_position
	centre /= float(alive.size())
	var o: Node3D = main.terrain_overlay
	var cell: Vector2i = o.world_to_cell(centre)
	for dx in range(-COVER_CELLS, COVER_CELLS + 1):
		for dz in range(-COVER_CELLS, COVER_CELLS + 1):
			var key := cell + Vector2i(dx, dz)
			saved[key] = {"had": o.grid_cells.has(key), "value": int(o.grid_cells.get(key, 0))}
			o.grid_cells[key] = o.TerrainType.FOREST if terrain < 0 else terrain
	return saved


static func _unpaint_cover(main: Node, saved: Dictionary) -> void:
	if saved.is_empty() or main.terrain_overlay == null:
		return
	var o: Node3D = main.terrain_overlay
	for key in saved:
		var row: Dictionary = saved[key]
		if bool(row["had"]):
			o.grid_cells[key] = int(row["value"])
		else:
			o.grid_cells.erase(key)


static func _free_units(main: Node, units: Array) -> void:
	for u in units:
		main.opr_army_manager.game_units.erase((u as GameUnit).unit_id)
		for m in (u as GameUnit).models:
			var nd: Node = (m as ModelInstance).node
			if nd != null and is_instance_valid(nd):
				nd.free()


## The committed fixture of one family (the shooting family stays the default for the older callers).
static func fixture_path(family: String = FAMILY) -> String:
	if family == MELEE_FAMILY:
		return MELEE_FIXTURE_PATH
	if family == MORALE_FAMILY:
		return MORALE_FIXTURE_PATH
	if family == HUMAN_FAMILY:
		return HUMAN_FIXTURE_PATH
	if family == SPLIT_FAMILY:
		return SPLIT_FIXTURE_PATH
	if family == DANGEROUS_FAMILY:
		return DANGEROUS_FIXTURE_PATH
	if family == MIXED_FAMILY:
		return MIXED_FIXTURE_PATH
	if family == MOVE_THROUGH_FAMILY:
		return MOVE_THROUGH_FIXTURE_PATH
	if family == MELEE_SHAPES_FAMILY:
		return MELEE_SHAPES_FIXTURE_PATH
	if family == MELEE_FEAR_HERO_FAMILY:
		return MELEE_FEAR_HERO_FIXTURE_PATH
	if family == CAST_DAMAGE_FAMILY:
		return CAST_DAMAGE_FIXTURE_PATH
	if family == CAST_EFFECTS_FAMILY:
		return CAST_EFFECTS_FIXTURE_PATH
	return FIXTURE_PATH


## The fixture on disk ({} when it is missing — the caller reports that as a difference).
static func load_fixture(path: String = FIXTURE_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


static func save_fixture(fixture: Dictionary, path: String = FIXTURE_PATH) -> Error:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(fixture, " ", true, true) + "\n")
	f.close()
	return OK


## Every difference between the committed fixture and a fresh run, as human-readable lines (empty = green).
## Provenance is compared on what changes behaviour — the rules epoch and the registry data hash — plus the schema;
## the git sha is NOT a difference: a fixture is always committed by the commit AFTER the one that produced it. The
## caller prints the recorded sha as context (see describe_provenance()).
static func compare(expected: Dictionary, got: Dictionary) -> Array:
	var problems: Array = []
	if not SCHEMAS.has(str(expected.get("schema", ""))):
		problems.append("fixture: schema %s, want one of %s" % [str(expected.get("schema", "<none>")), str(SCHEMAS)])
	if str(expected.get("family", "")) != str(got.get("family", "")):
		problems.append("fixture: family %s, want %s" % [
			str(expected.get("family", "<none>")), str(got.get("family", "<none>"))])
	var ep: Dictionary = expected.get("provenance", {})
	var gp: Dictionary = got.get("provenance", {})
	if int(ep.get("epoch", -1)) != int(gp.get("epoch", -1)):
		problems.append("provenance: epoch %d in the fixture, %d now" % [
			int(ep.get("epoch", -1)), int(gp.get("epoch", -1))])
	if str(ep.get("registry_sha256", "")) != str(gp.get("registry_sha256", "")):
		problems.append("provenance: registry %s sha256 %s in the fixture, %s now" % [
			REGISTRY_SYSTEM, str(ep.get("registry_sha256", "")), str(gp.get("registry_sha256", ""))])
	var want := {}
	for c in expected.get("cases", []):
		want[_key(c)] = c
	var seen := {}
	for c in got.get("cases", []):
		var k := _key(c)
		seen[k] = true
		if not want.has(k):
			problems.append("%s: not in the fixture" % k)
			continue
		problems.append_array(_compare_case(k, want[k] as Dictionary, c as Dictionary))
	for k in want:
		if not seen.has(k):
			problems.append("%s: in the fixture but not in the run" % k)
	return problems


static func describe_provenance(fixture: Dictionary, run: Dictionary) -> String:
	var fp: Dictionary = fixture.get("provenance", {})
	var rp: Dictionary = run.get("provenance", {})
	return "epoch %s/%s, git sha %s/%s, registry %s sha256 %s/%s (fixture/run)" % [
		str(fp.get("epoch", "?")), str(rp.get("epoch", "?")),
		str(fp.get("git_sha", "?")), str(rp.get("git_sha", "?")),
		REGISTRY_SYSTEM, str(fp.get("registry_sha256", "?")), str(rp.get("registry_sha256", "?"))]


static func _compare_case(key: String, want: Dictionary, got: Dictionary) -> Array:
	var problems: Array = []
	if got.has("error") or want.has("error"):
		if str(got.get("error", "")) != str(want.get("error", "")):
			problems.append("%s: error %s, fixture %s" % [key, str(got.get("error", "<none>")), str(want.get("error", "<none>"))])
		return problems
	var wf := _final_rows(want.get("final", []))
	var gf := _final_rows(got.get("final", []))
	if wf != gf:
		problems.append("%s: final state %s, fixture %s" % [key, JSON.stringify(gf), JSON.stringify(wf)])
	# v2 keys: compared only when the fixture has them (a v1 fixture has neither).
	var ws := _slot_rows(want.get("final", []))
	if not ws.is_empty() and ws != _slot_rows(got.get("final", [])):
		problems.append("%s: model slots %s, fixture %s" % [
			key, JSON.stringify(_slot_rows(got.get("final", []))), JSON.stringify(ws)])
	if want.has("extra") and JSON.stringify(want["extra"], "", true) != JSON.stringify(got.get("extra", {}), "", true):
		problems.append("%s: extra %s, fixture %s" % [key, JSON.stringify(got.get("extra", {}), "", true),
			JSON.stringify(want["extra"], "", true)])
	if want.has("rng") and str(want["rng"]) != str(got.get("rng", "<none>")):
		problems.append("%s: tray rng state %s, fixture %s" % [key, str(got.get("rng", "<none>")), str(want["rng"])])
	var wl: Array = want.get("lines", [])
	var gl: Array = got.get("lines", [])
	for i in range(maxi(wl.size(), gl.size())):
		var w := str(wl[i]) if i < wl.size() else "<missing>"
		var g := str(gl[i]) if i < gl.size() else "<missing>"
		if w != g:
			problems.append("%s: line %d is %s, fixture %s" % [key, i, JSON.stringify(g), JSON.stringify(w)])
	return problems


## JSON turns every number into a float on the way back in, so both sides are normalised to the same ints/bools
## before they are compared.
static func _final_rows(rows: Array) -> Array:
	var out: Array = []
	for r in rows:
		var row := r as Dictionary
		out.append({"unit": str(row.get("unit", "")), "alive": int(row.get("alive", 0)),
			"wounds": int(row.get("wounds", 0)), "shaken": bool(row.get("shaken", false))})
	return out


## Per unit, the normalised [slot, alive, wounds] triples; [] when a row has no "slots" key (a v1 fixture).
static func _slot_rows(rows: Array) -> Array:
	var out: Array = []
	for r in rows:
		var row := r as Dictionary
		if not row.has("slots"):
			return []
		var triples: Array = []
		for t in row["slots"]:
			triples.append([int(t[0]), bool(t[1]), int(t[2])])
		out.append(triples)
	return out


static func _key(c: Dictionary) -> String:
	return "%s:%d" % [str(c.get("scenario", "?")), int(c.get("seed", -1))]
