extends GdUnitTestSuite
## #172 with the one-core door on: the human owner of a shot-at unit still allocates their own wounds. The core lands its
## own casualty order, so `CoreActivation.run_ai` leaves a volley at a human unit with a wound-allocation choice (mixed
## loadouts among the alive models, or a Tough model) to the table, which asks "allocate N wounds - CLICK a model".
## Real: the main scene, NmlCore, the AI activation (`_solo_activate_one_ai`), the table's volley and allocation prompt.
## Constructed: plain AI units (10 Rifles) and human units on the right (10 models; mixed = 8 Rifle + 2 Machinegun),
## the human's saves rolling without the save card, the owner answered by right-click (auto-allocate the rest).
## Red-green: on a build without the guard the mixed case shows 0 prompts and the core resolves every volley.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")
const INCH := 0.0254
const SEEDS := 2
const SIDE := {"quality": 4, "defense": 4, "tough": 1, "z_step_in": 1.2, "game_system": "gf",
	"faction_folder": "robot_legions", "rules": []}

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _prompts := 0
var _guard_lines := 0
var _timer: Timer


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.solo_controller.ai_slot = 2
	_main.solo_controller.human_slot = 1
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	_main._solo_batch = false
	_main._solo_fast = true
	_main._solo_auto_saves = true   # the human's saves roll without the "Incoming fire" card (it is not what we test)
	CoreActivation._env = 1         # the flag ON, whatever the environment says
	CoreActivation.ai_runs = 0
	CoreActivation.ai_refusals = 0
	_prompts = 0
	_guard_lines = 0
	_main.battle_log.entry_added.connect(func(e: Dictionary) -> void:
		var t := str(e.get("text", ""))
		if t.contains("CLICK a model"):
			_prompts += 1
		elif t.contains("owner chooses the casualties"):
			_guard_lines += 1)
	# The owner's answer: right-click = auto-allocate the rest, so a shown prompt does not hang the run.
	_timer = Timer.new()
	_timer.wait_time = 0.05
	_main.add_child(_timer)
	_timer.timeout.connect(func() -> void:
		if not _main._solo_model_pick.is_empty():
			var out: Array = _main._solo_model_pick["outcome"]
			if out.is_empty():
				out.append({}))
	_timer.start()


func after_test() -> void:
	CoreActivation.reset_all(_main)
	CoreActivation._env = -1
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## Three AI units (seat 2: 10 plain Rifles, 24") and three human units (seat 1: 10 models). `mixed`: the humans carry
## the imported loadout of a squad with two Machineguns (8 Rifle + 2 Machinegun + CCW, no weapon or unit rule).
func _armies(s: int, mixed: bool) -> Array:
	var out: Array = []
	for u in [[2, "Att A", -18.0], [2, "Att B", -3.0], [2, "Att C", 12.0]]:
		var gu := ParityTable._make_unit(_main, SIDE.merged({"player": u[0], "name": u[1], "models": 10, "x_in": -10.0}),
			{"name": "Rifle", "range_in": 24, "attacks": 1, "count": 10, "rules": []})
		for m in gu.models:
			(m as ModelInstance).node.global_position.z += float(u[2]) * INCH
		out.append(gu)
	for u in [[1, "Def A", 6.0 + s % 5, -18.0], [1, "Def B", 10.0, -3.0], [1, "Def C", 14.0, 12.0]]:
		var gu := ParityTable._make_unit(_main, SIDE.merged({"player": u[0], "name": u[1], "models": 10, "x_in": u[2]}),
			{"name": "Rifle", "range_in": 24, "attacks": 1, "count": 10, "rules": []})
		for m in gu.models:
			(m as ModelInstance).node.global_position.z += float(u[3]) * INCH
		if mixed:
			var src: OPRApiClient.OPRUnit = gu.source_data
			src.size = 10
			var mg := OPRApiClient.OPRWeapon.new()
			mg.name = "Machinegun"
			mg.range_value = 30
			mg.attacks = 3
			mg.count = 2
			var ccw := OPRApiClient.OPRWeapon.new()
			ccw.name = "CCW"
			ccw.range_value = 0
			ccw.attacks = 1
			ccw.count = 10
			src.weapons.append(mg)
			src.weapons.append(ccw)
			src.weapons[0].count = 8
			EquipmentDistributor.distribute(gu, EquipmentDistributor.build_loadout(src), [])
		out.append(gu)
	return out


func _clear(units: Array) -> void:
	for u in units:
		_main.opr_army_manager.game_units.erase((u as GameUnit).unit_id)
		for m in (u as GameUnit).models:
			if (m as ModelInstance).node != null and is_instance_valid((m as ModelInstance).node):
				(m as ModelInstance).node.free()
	_main.solo_controller._peeked_unit = null


## SEEDS boards, three AI activations each; returns the models the humans lost.
func _play(mixed: bool) -> int:
	var lost := 0
	for s in SEEDS:
		var units := _armies(s, mixed)
		var alive0 := 0
		for u in units:
			if int((u as GameUnit).unit_properties["player_id"]) == 1:
				alive0 += _main._solo_combined_alive(u)
				assert_bool(_main._solo_wound_choice_matters(u, 2)).override_failure_message(
					"the human unit's allocation choice (mixed=%s)" % mixed).is_equal(mixed)
		_main.seed_tray_rng(s)
		for i in 3:
			await _main._solo_activate_one_ai()
		for u in units:
			if int((u as GameUnit).unit_properties["player_id"]) == 1:
				alive0 -= _main._solo_combined_alive(u)
		lost += alive0
		_clear(units)
	return lost


@warning_ignore('unused_parameter')
func test_ai_volley_at_a_unit_with_mixed_weapons_asks_the_owner(timeout := 600000,
		do_skip := not ClassDB.class_exists("NmlCore"), skip_reason := "NmlCore extension not loaded") -> void:
	var lost := await _play(true)
	assert_int(lost).override_failure_message("the volleys killed nothing: the test shows no allocation").is_greater(0)
	assert_int(_prompts).override_failure_message("the owner was never asked to allocate (core volleys %d)" \
		% CoreActivation.ai_runs).is_greater(0)
	assert_int(_guard_lines).override_failure_message("the guard wrote no log line").is_greater(0)
	assert_int(CoreActivation.ai_runs).override_failure_message("the core resolved a volley at a unit with a choice").is_equal(0)
	assert_int(CoreActivation.ai_refusals).override_failure_message("the core refused (a defect, not the guard)").is_equal(0)


## The other side of the guard: no choice (one loadout, no Tough model) = no prompt, the core still resolves the volley.
@warning_ignore('unused_parameter')
func test_ai_volley_at_a_uniform_unit_still_goes_through_the_core(timeout := 600000,
		do_skip := not ClassDB.class_exists("NmlCore"), skip_reason := "NmlCore extension not loaded") -> void:
	var lost := await _play(false)
	assert_int(lost).override_failure_message("the volleys killed nothing").is_greater(0)
	assert_int(CoreActivation.ai_runs).override_failure_message("the core did not resolve the volleys").is_equal(SEEDS * 3)
	assert_int(CoreActivation.ai_refusals).override_failure_message("the core refused").is_equal(0)
	assert_int(_prompts).override_failure_message("a prompt where the owner has no choice").is_equal(0)
	assert_int(_guard_lines).override_failure_message("the guard fired without a choice").is_equal(0)
