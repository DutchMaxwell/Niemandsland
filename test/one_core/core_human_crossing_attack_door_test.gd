extends GdUnitTestSuite
## A player's Crossing Attack bearer is a core unit: the book makes the attack mandatory once per activation when the bearer moves
## through an enemy unit, and the table never rolled it for a player's unit. The player's drop through the enemy line puts the trails
## in the door session; the activation's End carries them to the core, which rolls the attack once and names the rule.
## Real: the main scene, NmlCore, the Start / drop / End doors, `_solo_human_strafing` (the drop door's strike hook).
## Constructed: a 10-model Crossing Attack(2) unit of seat 1 (human) moving 6" through 20 defenders of seat 2 (AI); the shipped slice.
## RED: put `and not CoreSlice.carries(gu, ["Crossing Attack"])` back into `CoreActivation.is_core_unit` -> no core unit, no session,
## no Crossing Attack line, no die.

const INCH := 0.0254
const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")
const SIDE := {"quality": 4, "defense": 4, "tough": 1, "z_step_in": 1.2, "game_system": "gf",
	"faction_folder": "jackals", "rules": []}
const RIFLE := {"name": "Rifle", "range_in": 24, "attacks": 1, "count": 10, "rules": []}
const SEEDS := 8

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	SoloHarness.start(_main, [2], 1)
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	SoloHarness.instant(_main)
	SoloHarness.auto_saves(_main)
	SoloHarness.fast(_main)
	_main._autosave_controller.set_lesson_paused(true)
	CoreActivation._env = 1


func after_test() -> void:
	CoreActivation.reset_all(_main)
	CoreActivation._env = -1
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _run(s: int) -> Dictionary:
	var att := ParityTable._make_unit(_main, SIDE.merged({"player": 1, "name": "Vultures", "models": 10, "x_in": 0.0,
		"rules": ["Crossing Attack(2)"]}, true), RIFLE)
	var foe := ParityTable._make_unit(_main, SIDE.merged({"player": 2, "name": "Def", "models": 20, "x_in": 3.0}, true), RIFLE.merged({"count": 20}, true))
	for i in foe.models.size():
		(foe.models[i] as ModelInstance).node.global_position.z += float((i * 7) % 5) * 0.0001
	foe.is_activated = true
	var spare := ParityTable._make_unit(_main, SIDE.merged({"player": 1, "name": "Spare", "models": 1, "x_in": 40.0}), {})
	for m in att.models:
		m.node.set_meta("network_id", 901 + att.models.find(m))
		m.node.set_meta("model_instance", m)
	var out := {"core_unit": CoreActivation.is_core_unit(_main, att), "started": false, "ended": false}
	var lines: Array = []
	var tap := func(e: Dictionary) -> void: lines.append(str(e["text"]))
	_main.battle_log.entry_added.connect(tap)
	_main.seed_tray_rng(s)
	var rng0: int = _main._tray_rng.state
	out["started"] = _main.core_activation_start(att)
	var moves: Array = []
	for m in att.get_alive_models():   # every model 6" toward and through the defender line: the player's drop
		var from: Vector3 = (m as ModelInstance).node.global_position
		var to := Vector3(from.x + 6.0 * INCH, from.y, from.z)
		(m as ModelInstance).node.global_position = to
		moves.append({"node": (m as ModelInstance).node, "inches": 6.0, "path": PackedVector2Array([Vector2(from.x, from.z), Vector2(to.x, to.z)])})
	att.unit_properties["moved_round"] = 1
	if out["started"]:
		out["drop_refused"] = _main.attacked_unit_drag_refused(att, 6.0)
	await _main._solo_human_strafing(moves)
	if out["started"]:
		out["ended"] = not await CoreActivation.end(_main, att)
	_main.battle_log.entry_added.disconnect(tap)
	out["lines"] = lines
	out["crossing"] = lines.filter(func(l: String) -> bool: return l.begins_with("Crossing Attack:")).size()
	out["hurt"] = 20 - foe.get_alive_count()
	out["rolled"] = _main._tray_rng.state != rng0
	CoreActivation.close_session(_main, att.unit_id)
	for u in [att, foe, spare]:
		_main.opr_army_manager.game_units.erase((u as GameUnit).unit_id)
		for m in (u as GameUnit).models:
			if (m as ModelInstance).node != null and is_instance_valid((m as ModelInstance).node):
				(m as ModelInstance).node.free()
	return out


## The gate: a human session's trails reach the core's Crossing Attack roll. Once per activation, named, with dice.
func test_a_players_crossing_attack_bearer_attacks_in_the_core_with_its_end() -> void:
	var bad: Array = []
	var hurt := 0
	for s in SEEDS:
		var r := await _run(s)
		hurt += int(r["hurt"])
		if not r["core_unit"] or not r["started"]:
			bad.append("seed %d: no core unit / no Start (core_unit %s, started %s)" % [s, r["core_unit"], r["started"]])
		elif bool(r.get("drop_refused", false)) or not r["ended"]:
			bad.append("seed %d: the drop was refused or the End stayed open: %s" % [s, r["lines"]])
		elif int(r["crossing"]) != 1 or not r["rolled"]:
			bad.append("seed %d: Crossing Attack lines %d, dice rolled %s: %s" % [s, r["crossing"], r["rolled"], r["lines"]])
	print("HUMAN_CROSSING seeds=%d hurt=%d bad=%d" % [SEEDS, hurt, bad.size()])
	assert_array(bad).override_failure_message("\n".join(bad.slice(0, 5))).is_empty()
	assert_int(hurt).override_failure_message("the attack never wounded in %d seeds: the check proves nothing" % SEEDS).is_greater(0)
