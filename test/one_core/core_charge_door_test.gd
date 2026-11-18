extends GdUnitTestSuite
## One core P4.D-48: the AI charge door. A plain AI charge (no rule on either side, an AI defender) hands the activation to the
## core's step path instead of `_run_ai_melee`: the core lands the charge (`charge_move` from the board before the move, the snap, the pile-in), the
## strikes, the melee result, the loser's morale and the consolidation; the table lands Shaken, Fatigue and the end positions
## from the delta. Seed for seed against the table's own `_run_ai_melee` (the door off): survivors, wounds, positions (within
## 0.01"), Shaken, Fatigue, the tray RNG after and the battle-log lines in order.
## Real: the main scene, NmlCore, the planner's own charge move (`SoloController._charge_move`), `_run_ai_melee`.
## Constructed: OPR units (ParityTable) at both seats AI. NML_ONE_CORE_SEEDS overrides 16.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")
const INCH := 0.0254
const SIDE := {"quality": 4, "defense": 4, "tough": 1, "z_step_in": 1.3, "game_system": "gf",
	"faction_folder": "robot_legions", "rules": []}
const BLADE := {"name": "Blade", "range_in": 0, "attacks": 2, "count": 10, "rules": []}

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {1: true, 2: true}
	_main._ensure_solo_controller()
	_main.solo_controller.ai_slot = 2
	_main.solo_controller.human_slot = 1
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	_main._solo_batch = true
	_main._solo_auto_saves = true
	_main._solo_fast = true
	_main._autosave_controller.set_lesson_paused(true)
	CoreActivation._env = 1
	CoreActivation._charge_env = 1
	CoreActivation.ai_charges = 0


func after_test() -> void:
	CoreActivation._charge_landing = false
	CoreActivation.reset_all(_main)
	CoreActivation._env = -1
	CoreActivation._charge_env = -1
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _free(units: Array) -> void:
	for u in units:
		_main.opr_army_manager.game_units.erase((u as GameUnit).unit_id)
		for m in (u as GameUnit).models:
			if (m as ModelInstance).node != null and is_instance_valid((m as ModelInstance).node):
				(m as ModelInstance).node.free()
	_main.solo_controller._peeked_unit = null


func _pos(u: GameUnit) -> Array:
	var a: Array = u.get_alive_models().map(func(m: ModelInstance) -> Vector2: return Vector2(m.node.global_position.x, m.node.global_position.z) / INCH)
	a.sort()
	return a


## Whether two sorted position lists agree within 0.01" per model.
func _near(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if (a[i] as Vector2).distance_to(b[i]) > 0.01:
			return false
	return true


## One AI charge: `Att` (seat 2, `models`) from x = 0 at `Def` (seat 1, `foe_models`) at `gap_in`. The planner's charge move,
## then the body's hand-over. `core_run` = the board is captured before the move (the body's capture), else none: the table fights.
func _run(s: int, core_run: bool, models: int, foe_models: int, gap_in: float, foe_attacks := 1) -> Dictionary:
	var att := ParityTable._make_unit(_main, SIDE.merged({"player": 2, "name": "Att", "models": models, "x_in": 0.0}, true), BLADE.merged({"count": models}))
	var foe := ParityTable._make_unit(_main, SIDE.merged({"player": 1, "name": "Def", "models": foe_models, "x_in": gap_in, "z_step_in": 1.4}, true),
		BLADE.merged({"count": foe_models, "attacks": foe_attacks}))
	# Ties in the casualty pick break on the last float bit (table node vs core): nudge every defender by its own few thousandths.
	for i in foe.models.size():
		(foe.models[i] as ModelInstance).node.global_position.z += float((i * 7) % 5) * 0.0001
	var lines: Array = []
	var tap := func(e: Dictionary) -> void:
		lines.append("%s|%s" % [BattleLog.Category.keys()[int(e["category"])], str(e["text"])])
	_main.battle_log.entry_added.connect(tap)
	_main.seed_tray_rng(s)
	var charges := CoreActivation.ai_charges
	var sc: SoloController = _main.solo_controller
	var h := CoreActivation.capture(_main) if core_run else 0
	_main._solo_core_ai_h = h
	var from_in: float = sc.charge_from_in(att, foe, MoveIntent.distance_inches(sc.unit_centre(att), sc.unit_centre(foe)))
	sc._charge_move(att, foe, 12.0)
	att.unit_properties["moved_round"] = 1
	var report := {"unit": att, "target": foe, "action": AiDecision.Action.CHARGE, "charge_from_in": from_in, "moved": true}
	# The body's hand-over (`_solo_activate_one_ai_body`): the door when it takes the charge, else the table's own melee.
	if not (CoreActivation.takes_ai_charge(_main, att, report) and await CoreActivation.run_ai_charge(_main, att, report)):
		await _main._run_ai_melee(report)
	_main._solo_core_ai_h = 0
	if h != 0:
		sc._core_node_ready().release(h)
	_main.battle_log.entry_added.disconnect(tap)
	var out := {"att": _pos(att), "foe": _pos(foe), "wounds": [_main._solo_unit_wounds_now(att), _main._solo_unit_wounds_now(foe)],
		"alive": [att.get_alive_count(), foe.get_alive_count()], "shaken": [att.is_shaken, foe.is_shaken],
		"fatigued": [att.is_fatigued, foe.is_fatigued], "rng": _main._tray_rng.state, "lines": lines,
		"core": CoreActivation.ai_charges - charges}
	_free([att, foe])
	await _main.get_tree().process_frame
	return out


func _sweep(name: String, models: int, foe_models: int, gap_in: float, foe_attacks := 1) -> void:
	var seeds := int(OS.get_environment("NML_ONE_CORE_SEEDS")) if OS.has_environment("NML_ONE_CORE_SEEDS") else 16
	var bad: Array = []
	var hurt := 0
	for s in seeds:
		var table := await _run(s, false, models, foe_models, gap_in, foe_attacks)
		var core := await _run(s, true, models, foe_models, gap_in, foe_attacks)
		hurt += foe_models - int(core["alive"][1])
		if int(core["core"]) != 1 or int(table["core"]) != 0:
			bad.append("seed %d: the door took it %d times (table run %d)" % [s, core["core"], table["core"]])
		for k in ["att", "foe"]:
			if not _near(table[k], core[k]):
				bad.append("seed %d: %s positions: table %s, core %s" % [s, k, table[k], core[k]])
		for k in ["wounds", "alive", "shaken", "fatigued", "rng", "lines"]:
			if table[k] != core[k]:
				bad.append("seed %d: %s: table %s, core %s" % [s, k, table[k], core[k]])
	print("CHARGE_DOOR %s seeds=%d hurt=%d mismatches=%d" % [name, seeds, hurt, bad.size()])
	assert_int(hurt).override_failure_message("no seed hurt the defender: the sweep compares nothing").is_greater(0)
	assert_array(bad).override_failure_message("core vs table:\n" + "\n".join(bad.slice(0, 8))).is_empty()


## Both sides survive: the strikes, the strike back, the result, the loser's morale and the charger's 1" step back.
func test_a_plain_charge_both_sides_standing() -> void:
	await _sweep("standing", 5, 8, 7.0)


## A small defender the charge wipes out: the winner's consolidation move.
func test_a_plain_charge_that_wipes_the_defender_out() -> void:
	await _sweep("wipe", 8, 2, 6.0)


## A 10-model unit on either side stays on the table (`MELEE_MAX_MODELS`, the known consolidation difference of #3025): the
## door does not take it. RED: drop the size clause from `takes_ai_charge` -> the door takes it.
func test_a_ten_model_unit_stays_on_the_table() -> void:
	for sides in [[10, 2], [5, 10]]:
		var out := await _run(0, true, sides[0], sides[1], 6.0)
		assert_int(int(out["core"])).override_failure_message("the door took a %d v %d charge" % sides).is_equal(0)
