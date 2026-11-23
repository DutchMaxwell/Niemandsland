extends GdUnitTestSuite

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main._solo_batch = true


func after_test() -> void:
	CoreActivation.reset_all(_main)
	CoreActivation._env = -1
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## The player's own volley through the core door (the Fire! button's path): the activation is opened first,
## then the door shoots; false from the door would mean the table is left to resolve it.
func _door_fire(attacker: GameUnit, target: GameUnit) -> bool:
	CoreActivation._env = 1
	assert_bool(CoreActivation.open_session(_main, attacker)).override_failure_message("no activation session for the attacker").is_true()
	var took: bool = await CoreActivation.human_shoot(_main, attacker, target)
	assert_bool(took).override_failure_message("the core door did not take the volley (the table would resolve it)").is_true()
	CoreActivation.close_session(_main, attacker.unit_id)
	return took


func _index_of(needle: String) -> int:
	var entries: Array = _main.battle_log.entries()
	for i in range(entries.size()):
		if str((entries[i] as Dictionary)["text"]).contains(needle):
			return i
	return -1


func _unit(unit_name: String, models: int) -> GameUnit:
	var positions: Array = []
	for i in range(models):
		positions.append(Vector3(0.2, 0.0, 0.02 * i))
	var unit := E2EBoot.make_unit(_main, 2, unit_name, positions)
	_main.opr_army_manager.game_units[unit.unit_id] = unit
	return unit


func test_wounds_line_precedes_model_loss(timeout := 240000) -> void:
	var unit := _unit("WoundOrderPair", 2)
	await _main._solo_apply_wounds(unit, 1)
	assert_int(_index_of("WoundOrderPair takes 1 wound")).is_greater_equal(0)
	assert_int(_index_of("WoundOrderPair loses a model")).is_greater_equal(0)
	assert_int(_index_of("WoundOrderPair takes 1 wound")).is_less(_index_of("WoundOrderPair loses a model"))
	assert_int(unit.get_alive_count()).is_equal(1)
	await E2EBoot.settle(get_tree())


func test_wounds_line_precedes_destruction(timeout := 240000) -> void:
	var unit := _unit("WoundOrderSingle", 1)
	await _main._solo_apply_wounds(unit, 1)
	assert_int(_index_of("WoundOrderSingle takes 1 wound")).is_greater_equal(0)
	assert_int(_index_of("WoundOrderSingle destroyed")).is_greater_equal(0)
	assert_int(_index_of("WoundOrderSingle takes 1 wound")).is_less(_index_of("WoundOrderSingle destroyed"))
	assert_int(unit.get_alive_count()).is_equal(0)
	await E2EBoot.settle(get_tree())


func test_deadly_line_names_its_weapon(timeout := 240000) -> void:
	var unit := _unit("WoundOrderDeadly", 1)
	await _main._solo_land_deadly_wounds(unit, "Hammer", 2, 0, 1)
	assert_int(_index_of("Deadly(2): 1 unsaved ×2, no carry-over → 1 wound dealt (Hammer)")) \
		.is_greater_equal(0)
	await E2EBoot.settle(get_tree())


func test_direct_wound_models_still_parks_casualties(timeout := 240000) -> void:
	var unit := _unit("WoundOrderDirect", 1)
	var remaining: int = await _main._solo_wound_models(unit, 1, 2)
	assert_int(remaining).is_equal(0)
	assert_int(_index_of("WoundOrderDirect destroyed")).is_greater_equal(0)
	await E2EBoot.settle(get_tree())


## Your shooter with real OPR weapons, so the volley reads production's own profile dicts.
func _armed_shooter(specs: Array) -> GameUnit:
	var shooter := E2EBoot.make_unit(_main, 1, "WoundOrderShooter", [Vector3.ZERO])
	shooter.unit_properties["quality"] = 2
	var opr := OPRApiClient.OPRUnit.new()
	for spec in specs:
		var w := OPRApiClient.OPRWeapon.new()
		w.name = str(spec["name"])
		w.range_value = 24
		w.attacks = int(spec.get("attacks", 4))
		var rules: Array[String] = []
		for r in spec.get("rules", []):
			rules.append(str(r))
		w.special_rules = rules
		opr.weapons.append(w)
	shooter.source_type = "opr"
	shooter.source_data = opr
	_main.opr_army_manager.game_units[shooter.unit_id] = shooter
	return shooter


## One Tough model with room for the volley's whole state change (no death mid-fixture).
func _tough_target(wounds: int) -> GameUnit:
	var target := E2EBoot.make_unit(_main, 2, "WoundOrderTough", [Vector3(0.2, 0.0, 0.0)])
	target.unit_properties["special_rules"] = ["Tough(%d)" % wounds]
	(target.models[0] as ModelInstance).wounds_max = wounds
	(target.models[0] as ModelInstance).wounds_current = wounds
	_main.opr_army_manager.game_units[target.unit_id] = target
	return target


## Play-test R2: "Scavenger Beast takes 2 wounds (1/6 wounds)" after a Deadly(3) weapon had already dealt 3 of
## the 5 wounds. On the door (the rules core) the wound line must count every wound the volley dealt, Deadly included.
func test_door_volley_wound_line_counts_the_deadly_wounds_it_dealt(timeout := 240000) -> void:
	var shooter := _armed_shooter([{"name": "Poolgun", "rules": ["AP(6)"]},
		{"name": "Deadlygun", "rules": ["AP(6)", "Deadly(3)"]}])
	var foe := _tough_target(24)
	var before: int = int((foe.models[0] as ModelInstance).wounds_current)
	_main.seed_tray_rng(20261116)
	if not await _door_fire(shooter, foe):
		return
	var taken: int = before - int((foe.models[0] as ModelInstance).wounds_current)
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	assert_str(text).override_failure_message("fixture: the Deadly(3) weapon must have landed\n%s" % text) \
		.contains("Deadly(3)")
	assert_bool(text.contains("WoundOrderTough takes")) \
		.override_failure_message("fixture: the core must have printed the wound line\n%s" % text).is_true()
	assert_int(taken).override_failure_message("fixture: the volley must have taken wounds\n%s" % text).is_greater(0)
	assert_str(text).override_failure_message(
		"the \"takes\" line must count every wound the volley dealt (%d), Deadly included\n%s" % [taken, text]) \
		.contains("WoundOrderTough takes %d wound" % taken)
	await E2EBoot.settle(get_tree())
