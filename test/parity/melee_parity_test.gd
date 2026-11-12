extends GdUnitTestSuite
## Table-vs-core parity gate, melee lane: per scenario the table runs its charge seed by seed (parity_table_melee.gd), then
## tools/parity/parity_melee_core.py runs the same seeds through the Rust core (python wheel) and parity_compare.py compares.
## The handoff is FILES only (OS.execute stdout capture is empty on this Godot build, see objective_layout_test.gd).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const ParityMelee := preload("res://test/parity/parity_table_melee.gd")
const SEEDS := 200
const _TMP := "user://parity_melee_tmp"

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _epoch_before: int


func before_test() -> void:
	_epoch_before = AiActRecorder.rules_epoch
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {1: true, 2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	_main._solo_batch = true
	_main.set("_solo_fast", true)
	DirAccess.make_dir_recursive_absolute(_TMP)


func after_test() -> void:
	AiDiceRecorder.close()
	OS.set_environment("NML_DICE_DUMP", "")
	_rm_tree(_TMP)
	AiActRecorder.rules_epoch = _epoch_before
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _rm_tree(dir: String) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)
	for sub in d.get_directories():
		_rm_tree(dir.path_join(sub))
	DirAccess.remove_absolute(dir)


func _python() -> String:
	var py := OS.get_environment("NML_PARITY_PYTHON")
	if py == "":
		py = OS.get_environment("NML_DOCTRINE_PYO3_PYTHON")
	return py


## Table half, then core half + compare through the python scripts. Returns the compare's result JSON plus "rc".
func _gate(name: String, override: Dictionary = {}) -> Dictionary:
	var py := _python()
	assert_str(py).override_failure_message(
		"NML_PARITY_PYTHON / NML_DOCTRINE_PYO3_PYTHON unset: point it at a python importing nml_core built from this tree").is_not_empty()
	var scen := ProjectSettings.globalize_path("res://test/parity/scenarios/melee/%s.json" % name)
	var sc := JSON.parse_string(FileAccess.get_file_as_string(scen)) as Dictionary
	var table := ProjectSettings.globalize_path(_TMP.path_join(name + "_table.jsonl"))
	var core := ProjectSettings.globalize_path(_TMP.path_join(name + "_core.jsonl"))
	var res := ProjectSettings.globalize_path(_TMP.path_join(name + "_result.json"))
	var t0 := Time.get_ticks_msec()
	await ParityMelee.run(_main, sc, SEEDS, table, ProjectSettings.globalize_path(_TMP.path_join("dice")), override)
	var tools := ProjectSettings.globalize_path("res://tools/parity/")
	var rc_core := OS.execute(py, [tools + "parity_melee_core.py", scen, "--repo", ProjectSettings.globalize_path("res://"),
		"--out", core, "--seeds", str(SEEDS)], [])
	assert_int(rc_core).override_failure_message("parity_melee_core.py exited %d (3 = epoch, 4 = unported)" % rc_core).is_equal(0)
	var rc := OS.execute(py, [tools + "parity_compare.py", "--table", table, "--core", core, "--scenario", str(sc["name"]),
		"--exceptions", ProjectSettings.globalize_path("res://test/parity/exceptions.json"), "--out", res], [])
	var out := JSON.parse_string(FileAccess.get_file_as_string(res)) as Dictionary
	out["rc"] = rc
	print("[PARITY] %s seeds=%d identical=%d ms=%d" % [name, int(out["seeds"]), int(out["identical"]),
		Time.get_ticks_msec() - t0])
	return out


@warning_ignore('unused_parameter')
func test_plain_charge_matches_the_core(do_skip := not ClassDB.class_exists("NmlCore"),
		skip_reason := "NmlCore extension not loaded") -> void:
	var r := await _gate("plain")
	assert_int(int(r["rc"])).override_failure_message(str(r["problems"]) + str(r["first_mismatches"])).is_equal(0)
	assert_int(int(r["identical"])).is_equal(SEEDS)


@warning_ignore('unused_parameter')
func test_ap1_charge_matches_the_core(do_skip := not ClassDB.class_exists("NmlCore"),
		skip_reason := "NmlCore extension not loaded") -> void:
	var r := await _gate("ap1")
	assert_int(int(r["rc"])).override_failure_message(str(r["problems"]) + str(r["first_mismatches"])).is_equal(0)
	assert_int(int(r["identical"])).is_equal(SEEDS)


@warning_ignore('unused_parameter')
func test_red_a_table_only_ap2_is_caught(do_skip := not ClassDB.class_exists("NmlCore"),
		skip_reason := "NmlCore extension not loaded") -> void:
	# AP(1) -> AP(2) on the table side only: the gate must see at least one differing seed and exit 1.
	var r := await _gate("ap1", {"weapon_rules": ["AP(2)"]})
	assert_int(int(r["rc"])).is_equal(1)
	assert_int((r["mismatching_seeds"] as Array).size()).is_greater_equal(1)


## The dice of the record's Parry roll (0 when it has none).
func _parry_dice(rec: Dictionary) -> int:
	for x in rec["rolls"]:
		if str((x as Dictionary)["kind"]) == "parry":
			return int((x as Dictionary)["count"])
	return 0


@warning_ignore('unused_parameter')
func test_parry_dice_count_only_the_carriers_at_75(do_skip := not ClassDB.class_exists("NmlCore"),
		skip_reason := "NmlCore extension not loaded") -> void:
	# #2642 / #2662: 3 of 8 defenders carry Parry(1), so both sides roll 3 Parry dice, not 8 (the defender dies in every seed).
	var r := await _gate("parry_carriers_e75")
	assert_int(int(r["rc"])).override_failure_message(str(r["problems"]) + str(r["first_mismatches"])).is_equal(0)
	assert_int(int(r["identical"])).is_equal(SEEDS)


@warning_ignore('unused_parameter')
func test_red_a_table_where_every_defender_carries_parry_is_caught(do_skip := not ClassDB.class_exists("NmlCore"),
		skip_reason := "NmlCore extension not loaded") -> void:
	# Table side only: the Parry weapon count 3 -> 8 (every model carries it, the pre-#2642 reading); the core keeps 3.
	var r := await _gate("parry_carriers_e75", {"defender_weapon": {"count": 8}})
	assert_int(int(r["rc"])).is_equal(1)
	assert_int((r["mismatching_seeds"] as Array).size()).is_greater_equal(1)
	var m := (r["first_mismatches"] as Array)[0] as Dictionary
	assert_int(_parry_dice(m["table"])).is_greater(_parry_dice(m["core"]))


@warning_ignore('unused_parameter')
func test_strike_back_of_a_partly_armed_unit_matches_the_core(do_skip := not ClassDB.class_exists("NmlCore"),
		skip_reason := "NmlCore extension not loaded") -> void:
	# The weapon count (3) is below the model count (8) and the defenders survive: both engines must strike back with the
	# living bearers (per-model loadout on both sides), not alive/max of the count (table) vs zero bearers (core).
	var r := await _gate("strike_back_bearers_e75")
	assert_int(int(r["rc"])).override_failure_message(str(r["problems"]) + str(r["first_mismatches"])).is_equal(0)
	assert_int(int(r["identical"])).is_equal(SEEDS)


@warning_ignore('unused_parameter')
func test_red_a_table_without_the_per_model_loadout_is_caught(do_skip := not ClassDB.class_exists("NmlCore"),
		skip_reason := "NmlCore extension not loaded") -> void:
	# The pre-fix table: no per-model weapons, so the strike-back scales pro-rata while the core counts living bearers.
	var r := await _gate("strike_back_bearers_e75", {"per_model_loadout": false})
	assert_int(int(r["rc"])).is_equal(1)
	assert_int((r["mismatching_seeds"] as Array).size()).is_greater_equal(1)
