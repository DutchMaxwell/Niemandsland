extends GdUnitTestSuite
## Plan E (melee shadow): with the charge door OFF the table fights the AI charge; NML_CORE_SHADOW_MELEE=1 replays every
## charge the door's slice would take through the core's step path (CoreShadow.melee_*) and records whether rolls, end
## state, positions and lines agree. Real: main scene, NmlCore, the planner's charge move, `_run_ai_melee`.
## Constructed: OPR units (ParityTable) at both seats AI. Planted faults: the table board changed after the fight.

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
	CoreActivation._charge_env = 0
	CoreShadow._melee_env = 1
	CoreShadow.melee_records = []
	CoreActivation.ai_charges = 0


func after_test() -> void:
	CoreActivation._charge_landing = false
	CoreActivation.reset_all(_main)
	CoreActivation._env = -1
	CoreActivation._charge_env = -1
	CoreShadow._melee_env = -1
	CoreShadow.melee_records = []
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


## One shadowed AI charge (door off): the shadow board before the planner's charge move, the table's melee between
## `melee_begin` and `melee_compare`. `fault` runs on the table's board after the fight, before the compare (a planted fault).
func _shadow(s: int, models: int, foe_models: int, gap_in: float, foe_rules := [], fault := Callable()) -> Dictionary:
	var att := ParityTable._make_unit(_main, SIDE.merged({"player": 2, "name": "Att", "models": models, "x_in": 0.0}, true), BLADE.merged({"count": models}))
	var foe := ParityTable._make_unit(_main, SIDE.merged({"player": 1, "name": "Def", "models": foe_models, "x_in": gap_in, "z_step_in": 1.4, "rules": foe_rules}, true),
		BLADE.merged({"count": foe_models, "attacks": 1}))
	for i in foe.models.size():
		(foe.models[i] as ModelInstance).node.global_position.z += float((i * 7) % 5) * 0.0001
	_main.seed_tray_rng(s)
	var sc: SoloController = _main.solo_controller
	_main._solo_core_shadow_h = CoreShadow.capture(_main, att)
	var from_in: float = sc.charge_from_in(att, foe, MoveIntent.distance_inches(sc.unit_centre(att), sc.unit_centre(foe)))
	sc._charge_move(att, foe, 12.0)
	att.unit_properties["moved_round"] = 1
	var report := {"unit": att, "target": foe, "action": AiDecision.Action.CHARGE, "charge_from_in": from_in, "moved": true}
	CoreShadow.melee_begin(_main, att, report)
	await _main._run_ai_melee(report)
	if fault.is_valid():
		fault.call(att, foe)
	CoreShadow.melee_compare(_main, att, report)
	CoreShadow.release(_main)
	_free([att, foe])
	await _main.get_tree().process_frame
	return CoreShadow.melee_records.back()


func _sweep_shadow(models: int, foe_models: int, gap_in: float) -> void:
	var bad: Array = []
	for s in 8:
		var rec := await _shadow(s, models, foe_models, gap_in)
		if not rec["taken"] or not rec["equal"]:
			bad.append("seed %d: %s" % [s, rec])
	print("MELEE_SHADOW %dv%d seeds=8 unequal=%d" % [models, foe_models, bad.size()])
	assert_array(bad).override_failure_message("\n".join(bad.slice(0, 4))).is_empty()


## Taken and equal: both sides standing (5 v 8) and the defender wiped out (8 v 2), 8 seeds each.
func test_a_taken_charge_replays_equal() -> void:
	await _sweep_shadow(5, 8, 7.0)
	await _sweep_shadow(8, 2, 6.0)


## Not taken: a Fear defender and a 10-model charger are recorded with their reasons and not replayed.
func test_a_charge_the_slice_refuses_is_recorded_not_replayed() -> void:
	var fear := await _shadow(0, 5, 8, 7.0, ["Fear(1)"])
	assert_bool(fear["taken"]).is_false()
	assert_array(fear["why"]).contains(["target_unit_rule:Fear"])
	var big := await _shadow(0, 10, 2, 6.0)
	assert_array(big["why"]).contains(["size"])
	assert_str(str(big["first_diff"])).is_empty()


## RED (planted on the table's board after the fight): a charger model nudged 1" -> "positions"; a model of the defender
## healed back -> a state field; the compare can fail.
func test_the_compare_sees_a_planted_difference() -> void:
	var nudge := func(att: GameUnit, _foe: GameUnit) -> void: (att.get_alive_models()[0] as ModelInstance).node.global_position.x += 0.0254
	var moved := await _shadow(0, 5, 8, 7.0, [], nudge)
	assert_str(str(moved["first_diff"])).is_equal("positions")
	var shaken := func(_att: GameUnit, foe: GameUnit) -> void: foe.is_shaken = not foe.is_shaken
	var flipped := await _shadow(0, 5, 8, 7.0, [], shaken)
	assert_str(str(flipped["first_diff"])).is_equal("shaken")
