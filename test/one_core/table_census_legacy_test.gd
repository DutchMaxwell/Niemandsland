extends GdUnitTestSuite
## P4.D-3: the runtime legacy counter. `CoreActivation.note_legacy` counts a volley the TABLE resolves (door -> reason ->
## count) and changes nothing else; `why_not` names why the core door refuses a shooter and its target.
## Real: the main scene (inert + door cases), the table's own AI volley. Constructed: bare units, a stub table for `applies`.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")
const SIDE := {"quality": 4, "defense": 4, "tough": 1, "z_step_in": 1.2, "game_system": "gf",
	"faction_folder": "robot_legions", "rules": []}

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


## `applies` reads only these two members.
class StubMain extends RefCounted:
	var solo_ai_slots := {1: true}
	func _online_turn_room() -> bool:
		return false


func before_test() -> void:
	CoreActivation.legacy.clear()
	CoreActivation.legacy_sets.clear()


func after_test() -> void:
	CoreActivation.legacy.clear()
	CoreActivation.legacy_sets.clear()
	if _main != null:
		E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## A bare OPR unit with the given unit rules and one weapon per entry of `weapon_rules` (each entry = that weapon's rules).
func _unit(unit_rules: Array, weapon_rules: Array) -> GameUnit:
	var gu := GameUnit.new()
	gu.unit_properties["special_rules"] = unit_rules
	var src := OPRApiClient.OPRUnit.new()
	for rules in weapon_rules:
		var w := OPRApiClient.OPRWeapon.new()
		w.special_rules.assign(rules)
		src.weapons.append(w)
	gu.source_type = "opr"
	gu.source_data = src
	return gu


func _boot(slots: Dictionary = {1: true, 2: true}) -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = slots   # default both seats AI: no save prompt waits
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	_main._solo_batch = true


func test_a_plain_shooter_and_target_have_no_unit_reasons() -> void:
	var why := CoreActivation.why_not(StubMain.new(), _unit([], [[]]), _unit([], [[]]))
	assert_array(why.filter(func(r: String) -> bool: return r != "no_core")).is_empty()


func test_every_refusal_is_named() -> void:
	var shooter := _unit(["Tough(3)", {"name": "Fear (spell)"}], [["Blast(3)", "Deadly(3)"], ["Blast(3)"]])
	var target := _unit(["Fearless"], [["Rending"]])
	var why := CoreActivation.why_not(StubMain.new(), shooter, target)
	assert_array(why).contains(["unit_rule:Tough", "unit_rule:Fear", "weapon_rule:Blast", "weapon_rule:Deadly",
		"target_rule:Fearless", "target_weapon_rule:Rending"])
	var bare := GameUnit.new()   # no OPR source: refused as a shooter, not as a target (P4.D-13b: the core takes its profile
	var why_bare := CoreActivation.why_not(StubMain.new(), bare, bare)   # from unit_properties)
	assert_array(why_bare).contains(["non_opr"])
	assert_array(why_bare).override_failure_message("a profile-less target is not a reason: %s" % [why_bare]).not_contains(["target_non_opr"])


func test_a_weapon_rule_is_counted_once_per_volley() -> void:
	var shooter := _unit([], [["Blast(3)"], ["Blast(3)", "Deadly(3)"]])   # two weapons with the same rule
	CoreActivation.note_legacy(StubMain.new(), "ai_volley", shooter, [_unit([], [[]])])
	var d: Dictionary = CoreActivation.legacy.get("ai_volley", {})
	assert_int(d.get("weapon_rule:Blast", 0)).override_failure_message("counts: %s" % [d]).is_equal(1)
	assert_int(d.get("weapon_rule:Deadly", 0)).is_equal(1)
	CoreActivation.note_legacy(StubMain.new(), "ai_volley", shooter, [_unit([], [[]])])
	d = CoreActivation.legacy.get("ai_volley", {})
	assert_int(d.get("weapon_rule:Blast", 0)).is_equal(2)
	assert_int(d.get("_all", 0)).is_equal(2)


func test_door_facts_and_the_target_are_counted() -> void:
	CoreActivation.note_legacy(StubMain.new(), "ai_volley", _unit([], [[]]), [_unit(["Fear"], [[]]), _unit([], [[]])],
		"split,no_handle")
	var d: Dictionary = CoreActivation.legacy.get("ai_volley", {})
	for k in ["split", "no_handle", "target_rule:Fear"]:
		assert_int(d.get(k, 0)).override_failure_message("reason %s missing in %s" % [k, d]).is_equal(1)
	CoreActivation.note_legacy(StubMain.new(), "human_split", _unit([], [[]]), [])
	assert_int(CoreActivation.legacy.get("human_split", {}).get("_all", 0)).is_equal(1)


func test_the_whole_reason_set_of_each_volley_is_counted() -> void:
	for rules in [["Blast(3)", "AP(1)"], ["AP(1)", "Blast(3)"]]:   # the same set found in two orders counts as one set
		CoreActivation.note_legacy(StubMain.new(), "ai_volley", _unit([], [rules]), [_unit(["Tough(3)"], [[]])], "no_handle")
	CoreActivation.note_legacy(StubMain.new(), "ai_volley", _unit([], [["AP(1)"]]), [_unit([], [[]])], "no_handle")
	var sets: Dictionary = CoreActivation.legacy_sets.get("ai_volley", {})
	var extra := [] if ClassDB.class_exists("NmlCore") else ["no_core"]   # `applies` adds no_core on a build without the core
	var a := extra + ["no_handle", "target_rule:Tough", "weapon_rule:AP", "weapon_rule:Blast"]
	var b := extra + ["no_handle", "weapon_rule:AP"]
	a.sort()
	b.sort()
	assert_int(sets.get("|".join(PackedStringArray(a)), 0)).override_failure_message("sets: %s" % [sets]).is_equal(2)
	assert_int(sets.get("|".join(PackedStringArray(b)), 0)).override_failure_message("sets: %s" % [sets]).is_equal(1)
	assert_int(sets.size()).is_equal(2)


func test_the_dump_is_written_only_when_the_env_names_a_path() -> void:
	var path := "user://table_census_dump_test.json"
	DirAccess.remove_absolute(path)
	CoreActivation.note_legacy(StubMain.new(), "ai_strafe", _unit([], [["Blast(3)"]]), [])
	CoreActivation.dump_legacy()
	assert_bool(FileAccess.file_exists(path)).is_false()
	OS.set_environment("NML_TABLE_CENSUS", path)
	CoreActivation.dump_legacy()
	OS.unset_environment("NML_TABLE_CENSUS")
	var text := FileAccess.get_file_as_string(path)
	var got: Dictionary = JSON.parse_string(text) if text != "" else {}
	DirAccess.remove_absolute(path)
	assert_int(int(got.get("legacy", {}).get("ai_strafe", {}).get("weapon_rule:Blast", 0))).is_equal(1)
	assert_bool(got.has("core_ai_runs")).is_true()
	assert_int(got.get("legacy_sets", {}).get("ai_strafe", {}).size()).is_equal(1)


func test_counting_draws_no_dice_and_writes_no_line() -> void:
	await _boot()
	var lines := []
	_main.battle_log.entry_added.connect(func(_e) -> void: lines.append(1))
	var rng_before: int = _main._tray_rng.state
	seed(77)
	var global_next := randi()
	seed(77)
	CoreActivation.note_legacy(_main, "ai_volley", _unit(["Tough(3)"], [["Blast(3)"]]), [_unit([], [[]])], "split")
	assert_int(_main._tray_rng.state).override_failure_message("the counter drew from the tray RNG").is_equal(rng_before)
	assert_int(randi()).override_failure_message("the counter drew from the global RNG").is_equal(global_next)
	assert_array(lines).override_failure_message("the counter wrote a battle-log line").is_empty()


func test_the_ai_volley_door_counts_a_volley_the_table_resolved() -> void:
	await _boot()
	var rifle := {"name": "Rifle", "range_in": 24, "attacks": 1, "count": 5, "rules": ["Blast(3)"]}
	var att := ParityTable._make_unit(_main, SIDE.merged({"player": 2, "name": "Att", "models": 5, "x_in": -10.0}), rifle)
	var foe := ParityTable._make_unit(_main, SIDE.merged({"player": 1, "name": "Foe", "models": 5, "x_in": 2.0}), {})
	_main.seed_tray_rng(5)
	var rng_before: int = _main._tray_rng.state
	await _main._run_ai_shooting({"unit": att, "moved": false})
	var d: Dictionary = CoreActivation.legacy.get("ai_volley", {})
	assert_int(d.get("_all", 0)).override_failure_message("the table volley was not counted: %s" % [d]).is_equal(1)
	assert_int(d.get("weapon_rule:Blast", 0)).is_equal(1)
	assert_int(d.get("no_handle", 0)).is_equal(1)   # a direct call has no AI-body capture
	assert_int(_main._tray_rng.state).override_failure_message("fixture broken: no die was thrown").is_not_equal(rng_before)
	assert_int(foe.models.size()).is_equal(5)
	await E2EBoot.settle(get_tree())


func test_the_human_shoot_door_counts_a_table_volley() -> void:
	await _boot({2: true})
	var shooter := E2EBoot.make_unit(_main, 1, "Shooter", [Vector3.ZERO])
	var foe := E2EBoot.make_unit(_main, 2, "Foe", [Vector3(8.0 * 0.0254, 0, 0)])
	var src := OPRApiClient.OPRUnit.new()
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Rifle"
	w.range_value = 24
	w.attacks = 2
	w.special_rules.assign(["Rending"])
	src.weapons.append(w)
	shooter.source_type = "opr"
	shooter.source_data = src
	_main.opr_army_manager.game_units[shooter.unit_id] = shooter
	assert_bool(await E2EBoot.start_activation(_main, shooter)).override_failure_message("no open activation").is_true()
	await _main._run_human_attack(shooter, foe, false)
	var d: Dictionary = CoreActivation.legacy.get("human_shoot", {})
	assert_int(d.get("_all", 0)).override_failure_message("the table volley was not counted: %s" % [CoreActivation.legacy]).is_equal(1)
	assert_int(d.get("weapon_rule:Rending", 0)).is_equal(1)
	await E2EBoot.settle(get_tree())


func test_the_strafe_door_counts_a_table_volley() -> void:
	await _boot()
	var epoch_before := AiActRecorder.rules_epoch
	AiActRecorder.rules_epoch = 75   # the strafing volley exists from the v3.6 rules epochs on
	var gun := {"name": "Strafe Gun", "range_in": 24, "attacks": 2, "count": 10, "rules": ["Crossing Strike"]}
	var att := ParityTable._make_unit(_main, SIDE.merged({"player": 2, "name": "Att", "models": 10, "x_in": 11.0}), gun)
	var dfn := ParityTable._make_unit(_main, SIDE.merged({"player": 1, "name": "Def", "models": 10, "x_in": 8.0}), {})
	var legs: Array = []
	for i in 10:   # the rush from x=0 to x=11 through the defender, as the parity scenario walks it
		legs.append({"path": [Vector3(0.0, 0.0, 1.2 * 0.0254 * i), Vector3(11.0 * 0.0254, 0.0, 1.2 * 0.0254 * i)]})
	_main.solo_controller.last_move_paths = legs
	_main.solo_controller.ai_slot = 2
	_main.solo_controller.human_slot = 1
	await _main._solo_apply_strafing(att)
	AiActRecorder.rules_epoch = epoch_before
	var d: Dictionary = CoreActivation.legacy.get("ai_strafe", {})
	assert_int(d.get("_all", 0)).override_failure_message("the strafe volley was not counted: %s" % [CoreActivation.legacy]).is_equal(1)
	# P4.D-37: Strafing is in the slice (activation_level), so the weapon is no reason; the strike the table makes anyway is named.
	assert_int(d.get("move_through", 0)).is_equal(1)
	assert_int(d.get("weapon_rule:Crossing Strike", 0)).is_equal(0)
	assert_int(dfn.models.size()).is_equal(10)
	await E2EBoot.settle(get_tree())
