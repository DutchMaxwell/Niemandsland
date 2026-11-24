extends GdUnitTestSuite
## Three small player-shot cases that used to fall back to the table: a Charge selector and an undeclared movement
## mode are now refused with a reason (nothing rolls, the session stays open), and a declared split whose second group
## has nothing to fire sends the first group alone through the core. A split where both groups are empty stays with
## the table. Real: the main scene, NmlCore, the human session ("Activate"), the door's own toast and battle-log
## lines. Constructed: plain gf units and their positions.
## RED (on main): Charge and mode 0 return false (the table shoots) and the empty second group returns false.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")
const SIDE := {"quality": 4, "defense": 4, "tough": 1, "z_step_in": 1.2, "game_system": "gf",
	"faction_folder": "robot_legions", "rules": []}
const CHARGE_TOAST := "Charge is a melee action - pick Advance or Hold to shoot."
const MODE_TOAST := "Pick a movement mode before shooting."

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
	CoreActivation._env = 1
	CoreSlice.path_override = ""
	CoreSlice.reset_cache()


func after_test() -> void:
	CoreActivation.reset_all(_main)
	CoreActivation._env = -1
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## A plain gf unit of `models` models at `x_in`; its OPR data carries `weapons` (the first is the base one).
func _unit(pid: int, uname: String, models: int, x_in: float, weapons: Array) -> GameUnit:
	var u := ParityTable._make_unit(_main, SIDE.merged({"player": pid, "name": uname, "models": models, "x_in": x_in}, true),
		weapons[0])
	for e in weapons.slice(1):
		var w := OPRApiClient.OPRWeapon.new()
		w.name = str(e["name"])
		w.range_value = int(e["range_in"])
		w.attacks = int(e["attacks"])
		w.count = int(e["count"])
		w.special_rules.assign(e["rules"])
		(u.source_data as OPRApiClient.OPRUnit).weapons.append(w)
	for i in u.models.size():
		(u.models[i] as ModelInstance).node.set_meta("network_id", 700 + pid * 100 + i)
		(u.models[i] as ModelInstance).node.set_meta("model_instance", u.models[i])
	return u


func _free(units: Array) -> void:
	for u in units:
		_main.opr_army_manager.game_units.erase((u as GameUnit).unit_id)
		for m in (u as GameUnit).models:
			if (m as ModelInstance).node != null and is_instance_valid((m as ModelInstance).node):
				(m as ModelInstance).node.free()


## The shooter's Start with `mode` declared on the selector.
func _started(att: GameUnit, mode: int) -> void:
	CoreActivation.last_target = null
	assert_bool(CoreActivation.open_session(_main, att)).override_failure_message("no session").is_true()
	_main.object_manager.set_movement_cap(mode)


func _toasts(text: String) -> Array:
	return _main.find_children("*", "Label", true, false).filter(func(l: Label) -> bool: return l.text == text)


## A Charge selector is a melee action: the door refuses with one toast, no die is thrown and the session stays open.
@warning_ignore('unused_parameter')
func test_a_charge_selector_is_refused_with_a_reason_and_nothing_rolls(timeout := 120000) -> void:
	var att := _unit(1, "Rifles", 5, 0.0, [{"name": "Rifle", "range_in": 24, "attacks": 1, "count": 5, "rules": []}])
	var foe := _unit(2, "Foe", 5, 12.0, [{"name": "Rifle", "range_in": 24, "attacks": 1, "count": 5, "rules": []}])
	_started(att, ObjectManager.MovementCap.CHARGE)
	_main.seed_tray_rng(3)
	var throws := [0]
	var taken: bool = await CoreActivation.human_shoot(_main, att, foe, func(_k: String, _i: int) -> void: throws[0] += 1)
	assert_bool(taken).override_failure_message("the door left the Charge shot to the table").is_true()
	assert_int(throws[0]).override_failure_message("a Charge shot threw dice").is_equal(0)
	assert_int(_toasts(CHARGE_TOAST).size()).override_failure_message("no Charge toast").is_equal(1)
	assert_bool(CoreActivation.session_open(att.unit_id)).override_failure_message("the session closed").is_true()
	assert_bool(CoreActivation.last_target == foe).override_failure_message("last_target set by a refused shot").is_false()
	assert_int(foe.get_alive_count()).is_equal(5)
	CoreActivation.close_session(_main, att.unit_id)
	_free([att, foe])


## An undeclared movement mode (selector Off) is refused with a reason; declared_mode still reports the defect.
@warning_ignore('unused_parameter')
func test_an_undeclared_mode_is_refused_with_a_reason(timeout := 120000) -> void:
	var att := _unit(1, "Rifles", 5, 0.0, [{"name": "Rifle", "range_in": 24, "attacks": 1, "count": 5, "rules": []}])
	var foe := _unit(2, "Foe", 5, 12.0, [{"name": "Rifle", "range_in": 24, "attacks": 1, "count": 5, "rules": []}])
	_started(att, ObjectManager.MovementCap.OFF)
	_main.seed_tray_rng(3)
	var throws := [0]
	var got := [false]
	await assert_error(func() -> void:
		got[0] = await CoreActivation.human_shoot(_main, att, foe, func(_k: String, _i: int) -> void: throws[0] += 1)) \
		.is_push_error("declared_mode: the movement selector is 0 - not Advance, Rush or Charge")
	assert_bool(bool(got[0])).override_failure_message("the door left the undeclared shot to the table").is_true()
	assert_int(throws[0]).override_failure_message("an undeclared shot threw dice").is_equal(0)
	assert_int(_toasts(MODE_TOAST).size()).override_failure_message("no mode toast").is_equal(1)
	assert_bool(CoreActivation.session_open(att.unit_id)).override_failure_message("the session closed").is_true()
	assert_int(foe.get_alive_count()).is_equal(5)
	CoreActivation.close_session(_main, att.unit_id)
	_free([att, foe])


## A declared split whose second group has nothing to fire: the first group fires alone through the core.
@warning_ignore('unused_parameter')
func test_a_split_with_an_empty_second_group_fires_the_first_alone(timeout := 120000) -> void:
	var att := _unit(1, "Squad", 5, 0.0, [{"name": "Rifle", "range_in": 24, "attacks": 1, "count": 5, "rules": []}])
	var a := _unit(2, "DefA", 5, 12.0, [{"name": "Rifle", "range_in": 24, "attacks": 1, "count": 5, "rules": []}])
	var b := _unit(2, "DefB", 5, 30.0, [{"name": "Rifle", "range_in": 24, "attacks": 1, "count": 5, "rules": []}])
	_started(att, ObjectManager.MovementCap.ADVANCE)
	var lines: Array = []
	var tap := func(e: Dictionary) -> void: lines.append(str(e["text"]))
	_main.battle_log.entry_added.connect(tap)
	var taken: bool = await CoreActivation.human_shoot_split(_main, att, a, b, ["Pistol"])
	_main.battle_log.entry_added.disconnect(tap)
	assert_bool(taken).override_failure_message("the empty second group left the split to the table").is_true()
	assert_bool(CoreActivation.last_target == a).override_failure_message("the first group's target was not the one shot").is_true()
	assert_array(lines.filter(func(l: String) -> bool: return l.contains("fires at") and l.contains("DefA"))) \
		.override_failure_message("no core fires line for DefA: %s" % [lines]).is_not_empty()
	assert_int(CoreActivation._sessions.get(att.unit_id, {}).size()).override_failure_message("the door left no session").is_greater(0)
	CoreActivation.close_session(_main, att.unit_id)
	_free([att, a, b])


## Both groups have nothing to fire: the split stays the table's (the door is not taken).
@warning_ignore('unused_parameter')
func test_a_split_where_both_groups_are_empty_stays_with_the_table(timeout := 120000) -> void:
	var att := _unit(1, "Squad", 5, 0.0, [{"name": "Pistol", "range_in": 12, "attacks": 1, "count": 5, "rules": []}])
	var a := _unit(2, "DefA", 5, 20.0, [{"name": "Rifle", "range_in": 24, "attacks": 1, "count": 5, "rules": []}])
	var b := _unit(2, "DefB", 5, 30.0, [{"name": "Rifle", "range_in": 24, "attacks": 1, "count": 5, "rules": []}])
	_started(att, ObjectManager.MovementCap.ADVANCE)
	var lines: Array = []
	var tap := func(e: Dictionary) -> void: lines.append(str(e["text"]))
	_main.battle_log.entry_added.connect(tap)
	var taken: bool = await CoreActivation.human_shoot_split(_main, att, a, b, ["Pistol"])
	_main.battle_log.entry_added.disconnect(tap)
	assert_bool(taken).override_failure_message("an all-empty split was taken by the door").is_false()
	assert_bool(CoreActivation.last_target == null).override_failure_message("last_target set by an empty split").is_true()
	assert_array(lines.filter(func(l: String) -> bool: return l.contains("fires at"))) \
		.override_failure_message("the core fired: %s" % [lines]).is_empty()
	assert_bool(CoreActivation.session_open(att.unit_id)).override_failure_message("the session closed").is_true()
	CoreActivation.close_session(_main, att.unit_id)
	_free([att, a, b])
