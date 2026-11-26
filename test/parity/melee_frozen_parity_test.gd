extends GdUnitTestSuite
## Plan step 20b: GF/AoF melee - and the morale test its loser takes - must not move when Firefight work lands. The live
## melee parity (melee_parity_test.gd) runs the table's melee path each time; steps 27-29 change the core paths GF melee
## and morale share and may retire that table path, so each melee scenario's table half was recorded ONCE, 200 seeds, into
## test/parity/golden/melee/<scenario>_table.jsonl (how and when: PROVENANCE.json there). This suite runs only the core half
## (tools/parity/parity_melee_core.py, the python wheel) against that frozen record. `plain_aof` is the same charge in AoF.

const FROZEN := "res://test/parity/golden/melee/"
const SEEDS := 200
const _TMP := "user://parity_melee_frozen_tmp"


func before_test() -> void:
	DirAccess.make_dir_recursive_absolute(_TMP)


func after_test() -> void:
	for f in DirAccess.get_files_at(_TMP):
		DirAccess.remove_absolute(_TMP.path_join(f))
	DirAccess.remove_absolute(_TMP)


func _python() -> String:
	var py := OS.get_environment("NML_PARITY_PYTHON")
	if py == "":
		py = OS.get_environment("NML_DOCTRINE_PYO3_PYTHON")
	return py


## The frozen record, or a copy of it with the first record's survivors raised by one (`edit_frozen`).
func _table_record(name: String, edit_frozen: bool) -> String:
	var frozen := ProjectSettings.globalize_path(FROZEN + name + "_table.jsonl")
	if not edit_frozen:
		return frozen
	var lines := FileAccess.get_file_as_string(frozen).split("\n", false)
	var rec := JSON.parse_string(lines[0]) as Dictionary
	rec["def_alive"] = int(rec["def_alive"]) + 1
	lines[0] = JSON.stringify(rec)
	var edited := ProjectSettings.globalize_path(_TMP.path_join(name + "_table_edited.jsonl"))
	var f := FileAccess.open(edited, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	return edited


## Core half against the frozen record. Returns the compare's result JSON plus "rc".
func _gate(name: String, edit_frozen := false) -> Dictionary:
	var py := _python()
	assert_str(py).override_failure_message(
		"NML_PARITY_PYTHON / NML_DOCTRINE_PYO3_PYTHON unset: point it at a python importing nml_core built from this tree").is_not_empty()
	var scen := ProjectSettings.globalize_path("res://test/parity/scenarios/melee/%s.json" % name)
	var sc := JSON.parse_string(FileAccess.get_file_as_string(scen)) as Dictionary
	var core := ProjectSettings.globalize_path(_TMP.path_join(name + "_core.jsonl"))
	var res := ProjectSettings.globalize_path(_TMP.path_join(name + "_result.json"))
	var tools := ProjectSettings.globalize_path("res://tools/parity/")
	var rc_core := OS.execute(py, [tools + "parity_melee_core.py", scen, "--repo", ProjectSettings.globalize_path("res://"),
		"--out", core, "--seeds", str(SEEDS)], [])
	assert_int(rc_core).override_failure_message("parity_melee_core.py exited %d (3 = epoch, 4 = unported)" % rc_core).is_equal(0)
	var rc := OS.execute(py, [tools + "parity_compare.py", "--table", _table_record(name, edit_frozen), "--core", core,
		"--scenario", str(sc["name"]), "--exceptions", ProjectSettings.globalize_path("res://test/parity/exceptions.json"),
		"--out", res], [])
	if not FileAccess.file_exists(res):
		return {"rc": rc, "seeds": 0, "identical": 0, "mismatching_seeds": [], "first_mismatches": [],
			"problems": ["parity_compare.py exited %d without a result" % rc]}
	var out := JSON.parse_string(FileAccess.get_file_as_string(res)) as Dictionary
	out["rc"] = rc
	return out


func _assert_identical(name: String) -> void:
	var r := _gate(name)
	assert_int(int(r["rc"])).override_failure_message(str(r["problems"]) + str(r["first_mismatches"])).is_equal(0)
	assert_int(int(r["identical"])).is_equal(SEEDS)


@warning_ignore('unused_parameter')
func test_plain_gf_charge_matches_its_frozen_record(do_skip := not ClassDB.class_exists("NmlCore"),
		skip_reason := "NmlCore extension not loaded") -> void:
	_assert_identical("plain")


@warning_ignore('unused_parameter')
func test_plain_aof_charge_matches_its_frozen_record(do_skip := not ClassDB.class_exists("NmlCore"),
		skip_reason := "NmlCore extension not loaded") -> void:
	_assert_identical("plain_aof")


@warning_ignore('unused_parameter')
func test_ap1_charge_matches_its_frozen_record(do_skip := not ClassDB.class_exists("NmlCore"),
		skip_reason := "NmlCore extension not loaded") -> void:
	_assert_identical("ap1")


@warning_ignore('unused_parameter')
func test_parry_carriers_match_their_frozen_record(do_skip := not ClassDB.class_exists("NmlCore"),
		skip_reason := "NmlCore extension not loaded") -> void:
	_assert_identical("parry_carriers_e75")


@warning_ignore('unused_parameter')
func test_strike_back_bearers_match_their_frozen_record(do_skip := not ClassDB.class_exists("NmlCore"),
		skip_reason := "NmlCore extension not loaded") -> void:
	_assert_identical("strike_back_bearers_e75")


@warning_ignore('unused_parameter')
func test_red_one_edited_frozen_record_is_caught(do_skip := not ClassDB.class_exists("NmlCore"),
		skip_reason := "NmlCore extension not loaded") -> void:
	var r := _gate("plain", true)
	assert_int(int(r["rc"])).is_equal(1)
	assert_int((r["mismatching_seeds"] as Array).size()).is_greater_equal(1)
