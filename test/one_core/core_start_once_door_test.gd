extends GdUnitTestSuite
## PLAN_DOOR_ACTIVATION_START step 2 (containment): Reanimation is an activation-START effect. The table rolls it in `begin_activation`, BEFORE
## the door captures the board (AI) or at Fire, after the capture at "Activate" (human); the core, which takes the whole activation, rolled it
## again (measured 22.11.: 8/8 seeds per door, the core's volley fired more or fewer dice than the table's living shooters, `_land_positions`
## errored). The deny group `activation_start_twice` keeps a Reanimation SHOOTER on the table at both shoot doors until the door tells the core
## that the start effects are done (steps 3-5).
## Real: the main scene, NmlCore, the AI body and the human Fire door, the table's Reanimation, the live deny slice. Constructed: a gf Robot
## Legions unit of 10 with 4 dead at plain foes.
## Each case runs twice: on the LIVE slice (one pool roll, the core does not take the activation, no landing error) and on the same deny file
## WITHOUT the group (the control: two pool rolls, so the count can fail).
## RED: drop the group from assets/solo/core_slice_deny.json -> the live leg reads two pool rolls, `ai_runs` 1 and the landing error.
## D-PAR3 15a: the AI door now TAKES the shooter - its transcript says the table paid the start (`paid{start}`), so the core rolls
## no second pool: live AI leg = one pool roll, `ai_runs` 1, no landing error. Its control leaves `paid` out (the seam
## `CoreActivation.start_paid_input`): two pool rolls on every seed - the double-roll class is gone, not hidden. The human leg is
## unchanged (its capture is before the start; the group still refuses the shooter there), and the refused shot is a free dice roll:
## the pool is rolled once and no volley die.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")
const SIDE := {"quality": 4, "defense": 4, "tough": 1, "z_step_in": 1.2, "game_system": "gf",
	"faction_folder": "robot_legions", "rules": []}
const RIFLE := {"name": "Rifle", "range_in": 24, "attacks": 1, "count": 10, "rules": []}
const GROUP := "activation_start_twice"
const WITHOUT := "user://core_start_once_without_group.json"
const SEEDS := 4
## The table's Reanimation pool roll: an "attack" roll at the rule's 5+ (the unit's own Quality is 4, so no volley roll matches).
const POOL_TARGET := 5


class ErrLogger extends Logger:
	var errs: PackedStringArray = PackedStringArray()

	func _log_error(_function: String, _file: String, _line: int, code: String, rationale: String, _editor_notify: bool,
			_error_type: int, _script_backtrace: Array) -> void:
		errs.append(rationale if not rationale.is_empty() else code)

	func _log_message(_message: String, _error: bool) -> void:
		pass


var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _log: ErrLogger


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	SoloHarness.start(_main, [2])
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	SoloHarness.instant(_main)
	SoloHarness.fast(_main)
	SoloHarness.auto_saves(_main)
	_main._autosave_controller.set_lesson_paused(true)
	CoreActivation._env = 1
	CoreSlice.path_override = ""
	CoreSlice.reset_cache()
	_log = ErrLogger.new()
	OS.add_logger(_log)


func after_test() -> void:
	OS.remove_logger(_log)
	CoreActivation.start_paid_input = true
	CoreSlice.path_override = ""
	CoreSlice.reset_cache()
	if FileAccess.file_exists(WITHOUT):
		DirAccess.remove_absolute(WITHOUT)
	CoreActivation.reset_all(_main)
	CoreActivation._env = -1
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## The production deny file without the group, through the test seam (the control leg).
func _without_group() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CoreSlice.DENY_PATH))
	(data["groups"] as Dictionary).erase(GROUP)
	var f := FileAccess.open(WITHOUT, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	CoreSlice.path_override = WITHOUT
	CoreSlice.reset_cache()


func _bearer(player: int, name: String, x_in: float) -> GameUnit:
	var gu := ParityTable._make_unit(_main, SIDE.merged({"player": player, "name": name, "models": 10, "x_in": x_in,
		"rules": ["Reanimation"]}, true), RIFLE)
	gu.unit_properties["faction_folder"] = "robot_legions"
	for i in range(6, 10):
		(gu.models[i] as ModelInstance).wounds_current = 0
		(gu.models[i] as ModelInstance).is_alive = false
	return gu


func _free(units: Array) -> void:
	for u in units:
		_main.opr_army_manager.game_units.erase((u as GameUnit).unit_id)
		for m in (u as GameUnit).models:
			if (m as ModelInstance).node != null and is_instance_valid((m as ModelInstance).node):
				(m as ModelInstance).node.free()
	_main.solo_controller._peeked_unit = null


## The tray rolls since decision-log entry `k0`: {"pool": Reanimation pool rolls, "volley": the first volley roll's dice}.
func _rolls(k0: int) -> Dictionary:
	var dice: Array = (_main.solo_controller.decision_log as Array).slice(k0).filter(
		func(r: Dictionary) -> bool: return str(r.get("kind", "")) == "dice" and str(r.get("roll_kind", "")) == "attack")
	var volley: Array = dice.filter(func(r: Dictionary) -> bool: return int(r["target"]) != POOL_TARGET)
	return {"pool": dice.filter(func(r: Dictionary) -> bool: return int(r["target"]) == POOL_TARGET).size(),
		"volley": int(volley[0]["count"]) if not volley.is_empty() else -1}


func _landing_errors(e0: int) -> int:
	return Array(_log.errs.slice(e0)).filter(func(t: String) -> bool: return t.contains("models in the core")).size()


## One AI activation of the bearer per seed. Returns per-seed rows [pool rolls, ai_runs, landing errors, volley dice, table alive,
## the census' `start_twice` count of this activation].
func _ai_runs() -> Array:
	var rows: Array = []
	for s in SEEDS:
		CoreActivation.ai_runs = 0
		var ai := _bearer(2, "Bots%d" % s, -10.0)
		var hu := ParityTable._make_unit(_main, SIDE.merged({"player": 1, "name": "Humans%d" % s, "models": 10, "x_in": 8.0}), RIFLE)
		var k0: int = (_main.solo_controller.decision_log as Array).size()
		var e0 := _log.errs.size()
		var t0 := int((CoreActivation.legacy.get("start", {}) as Dictionary).get("twice", 0))
		_main.opr_army_manager.current_round = 1
		_main.seed_tray_rng(s)
		await _main._solo_activate_one_ai()
		var r := _rolls(k0)
		rows.append([r["pool"], CoreActivation.ai_runs, _landing_errors(e0), r["volley"], ai.get_alive_count(),
			int((CoreActivation.legacy.get("start", {}) as Dictionary).get("twice", 0)) - t0])
		_free([ai, hu])
	return rows


## One human activation per seed: "Activate" (the session), no drag, Fire.
func _human_runs() -> Array:
	var rows: Array = []
	for s in SEEDS:
		var att := _bearer(1, "Att%d" % s, 0.0)
		var foe := ParityTable._make_unit(_main, SIDE.merged({"player": 2, "name": "Def", "models": 10, "x_in": 12.0}), RIFLE)
		foe.is_activated = true   # the AI has no reply
		var spare := ParityTable._make_unit(_main, SIDE.merged({"player": 1, "name": "Spare", "models": 1, "x_in": 40.0}), {})
		_main.opr_army_manager.current_round = 1
		for m in att.models:
			m.node.set_meta("network_id", 901 + att.models.find(m))
			m.node.set_meta("model_instance", m)
		var k0: int = (_main.solo_controller.decision_log as Array).size()
		var e0 := _log.errs.size()
		assert_bool(_main.core_activation_start(att)).override_failure_message("seed %d: no Start" % s).is_true()
		_main.seed_tray_rng(s)
		await _main._run_human_attack(att, foe, false)
		var r := _rolls(k0)
		rows.append([r["pool"], 0, _landing_errors(e0), r["volley"], att.get_alive_count()])
		CoreActivation.close_session(_main, att.unit_id)
		_free([att, foe, spare])
	return rows


func _assert_once(rows: Array, door: String) -> void:
	for s in rows.size():
		var row: Array = rows[s]
		assert_int(int(row[0])).override_failure_message("%s door seed %d: the pool is rolled once (rows %s)" % [door, s, rows]).is_equal(1)
		assert_int(int(row[1])).override_failure_message("%s door seed %d: the core does not take a Reanimation shooter" % [door, s]).is_equal(0)
		assert_int(int(row[2])).override_failure_message("%s door seed %d: no landing error" % [door, s]).is_equal(0)
		# The human door hands the refused shooter to the free roll: no volley roll for the player (-1 = none).
		var want := -1 if door == "human" else int(row[4])
		assert_int(int(row[3])).override_failure_message("%s door seed %d: the volley's dice (%d wanted)" % [door, s, want]).is_equal(want)


## The control legs replay the double pool roll on purpose (the core re-raises models the table never raised), so the
## LANDING-INVARIANT (CI's NML_LANDING_INVARIANT, read by the core in this process) is off for them and restored after.
func _without_landing_invariant(runs: Callable) -> Array:
	var was := OS.get_environment("NML_LANDING_INVARIANT")
	OS.unset_environment("NML_LANDING_INVARIANT")
	var rows: Array = await runs.call()
	if not was.is_empty():
		OS.set_environment("NML_LANDING_INVARIANT", was)
	return rows


func _assert_control_fails(rows: Array, door: String) -> void:
	var twice := rows.filter(func(r: Array) -> bool: return int(r[0]) == 2).size()
	assert_int(twice).override_failure_message("%s door control (no group): the core rolls the pool again (rows %s)" % [door, rows]).is_equal(rows.size())


@warning_ignore('unused_parameter')
func test_the_ai_door_takes_a_reanimation_shooter_and_rolls_the_pool_once(timeout := 600000, do_skip := not ClassDB.class_exists("NmlCore"),
		skip_reason := "no NmlCore") -> void:
	var live := await _ai_runs()
	for s in live.size():
		var row: Array = live[s]
		assert_int(int(row[0])).override_failure_message("AI door seed %d: the pool is rolled once (rows %s)" % [s, live]).is_equal(1)
		assert_int(int(row[1])).override_failure_message("AI door seed %d: the core takes the Reanimation shooter (rows %s)" % [s, live]).is_equal(1)
		assert_int(int(row[2])).override_failure_message("AI door seed %d: no landing error" % s).is_equal(0)
		assert_int(int(row[3])).override_failure_message("AI door seed %d: the volley's dice are the table's living shooters" % s).is_equal(int(row[4]))
		assert_int(int(row[5])).override_failure_message("AI door seed %d: start_twice reads 0 with paid (rows %s)" % [s, live]).is_equal(0)
	CoreActivation.start_paid_input = false   # the control: the same activation without `paid{start}`
	var control := await _without_landing_invariant(_ai_runs)
	CoreActivation.start_paid_input = true
	_assert_control_fails(control, "AI")
	assert_int(control.filter(func(r: Array) -> bool: return int(r[1]) == 1).size()).override_failure_message(
		"AI door control: the core took the activation (rows %s)" % [control]).is_equal(SEEDS)
	assert_int(control.filter(func(r: Array) -> bool: return int(r[5]) == 1).size()).override_failure_message(
		"AI door control: start_twice counts the core's second pool roll (rows %s)" % [control]).is_equal(SEEDS)


@warning_ignore('unused_parameter')
func test_the_human_door_hands_a_reanimation_shooter_to_the_free_roll(timeout := 600000, do_skip := not ClassDB.class_exists("NmlCore"),
		skip_reason := "no NmlCore") -> void:
	_assert_once(await _human_runs(), "human")
	_without_group()
	_assert_control_fails(await _without_landing_invariant(_human_runs), "human")
