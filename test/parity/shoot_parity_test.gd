extends GdUnitTestSuite
## Table-vs-core parity gate, shoot lane. The TABLE half is FROZEN (P4.D-38): the old resolver's per-seed output of every
## scenario was recorded once, before that resolver goes, in test/parity/golden/shoot/<scenario>_table.jsonl (how and
## when: PROVENANCE.json next to them). Per scenario this suite runs the same seeds through the Rust core
## (tools/parity/parity_core.py, python wheel) and parity_compare.py compares the core against the frozen record. No scene,
## no table. The handoff is FILES only (OS.execute stdout capture is empty on this Godot build, see objective_layout_test.gd).
##
## The red cases plant a difference on the CORE side (a copy of the scenario file with one rule changed) or in a copy of
## the frozen record, because the table can no longer be changed: each one must turn the gate red.

const SEEDS := 200
const EXCEPTION_CEILING := 1   # the exception list only shrinks: lower this when an entry is retired, never raise it
const FROZEN := "res://test/parity/golden/shoot/"
const _TMP := "user://parity_shoot_tmp"


func before_test() -> void:
	DirAccess.make_dir_recursive_absolute(_TMP)


func after_test() -> void:
	_rm_tree(_TMP)


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


## The scenario file, or a copy with one text replaced for the CORE only: `plant` = {"find": text, "replace": text}. The
## needle must occur exactly once, so a plant that changes nothing cannot make a red case pass by accident. (Text, not a
## JSON round trip: Godot writes whole numbers as 10.0 and the python half indexes with them.)
func _scenario_for_core(name: String, plant: Dictionary) -> String:
	var path := ProjectSettings.globalize_path("res://test/parity/scenarios/shoot/%s.json" % name)
	if plant.is_empty():
		return path
	var text := FileAccess.get_file_as_string(path)
	assert_int(text.count(str(plant["find"]))).override_failure_message(
		"plant needle %s is not in %s exactly once" % [str(plant["find"]), name]).is_equal(1)
	var planted := ProjectSettings.globalize_path(_TMP.path_join(name + "_planted.json"))
	var f := FileAccess.open(planted, FileAccess.WRITE)
	f.store_string(text.replace(str(plant["find"]), str(plant["replace"])))
	f.close()
	return planted


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


## Core half + compare through the python scripts. Returns the compare's result JSON plus "rc".
func _gate(name: String, plant: Dictionary = {}, edit_frozen := false) -> Dictionary:
	var py := _python()
	assert_str(py).override_failure_message(
		"NML_PARITY_PYTHON / NML_DOCTRINE_PYO3_PYTHON unset: point it at a python importing nml_core built from this tree").is_not_empty()
	var core := ProjectSettings.globalize_path(_TMP.path_join(name + "_core.jsonl"))
	var res := ProjectSettings.globalize_path(_TMP.path_join(name + "_result.json"))
	var t0 := Time.get_ticks_msec()
	var tools := ProjectSettings.globalize_path("res://tools/parity/")
	var rc_core := OS.execute(py, [tools + "parity_core.py", _scenario_for_core(name, plant),
		"--repo", ProjectSettings.globalize_path("res://"), "--out", core, "--seeds", str(SEEDS)], [])
	assert_int(rc_core).override_failure_message("parity_core.py exited %d (3 = epoch, 4 = unported)" % rc_core).is_equal(0)
	var rc := OS.execute(py, [tools + "parity_compare.py", "--table", _table_record(name, edit_frozen), "--core", core,
		"--scenario", name, "--exceptions", ProjectSettings.globalize_path("res://test/parity/exceptions.json"),
		"--out", res], [])
	if not FileAccess.file_exists(res):   # rc 2: the record and the core cover different seeds, the compare writes no result
		return {"rc": rc, "seeds": 0, "identical": 0, "mismatching_seeds": [], "first_mismatches": [],
			"problems": ["parity_compare.py exited %d without a result (2 = the record and the core cover different seeds)" % rc]}
	var out := JSON.parse_string(FileAccess.get_file_as_string(res)) as Dictionary
	out["rc"] = rc
	print("[PARITY] %s seeds=%d identical=%d ms=%d" % [name, int(out["seeds"]), int(out["identical"]),
		Time.get_ticks_msec() - t0])
	return out


@warning_ignore('unused_parameter')
func test_plain_volley_matches_the_core(do_skip := not ClassDB.class_exists("NmlCore"),
		skip_reason := "NmlCore extension not loaded") -> void:
	var r := _gate("plain")
	assert_int(int(r["rc"])).override_failure_message(str(r["problems"]) + str(r["first_mismatches"])).is_equal(0)
	assert_int(int(r["identical"])).is_equal(SEEDS)


@warning_ignore('unused_parameter')
func test_ap1_volley_matches_the_core(do_skip := not ClassDB.class_exists("NmlCore"),
		skip_reason := "NmlCore extension not loaded") -> void:
	var r := _gate("ap1")
	assert_int(int(r["rc"])).override_failure_message(str(r["problems"]) + str(r["first_mismatches"])).is_equal(0)
	assert_int(int(r["identical"])).is_equal(SEEDS)


@warning_ignore('unused_parameter')
func test_red_a_core_with_ap2_against_the_frozen_ap1_table_is_caught(do_skip := not ClassDB.class_exists("NmlCore"),
		skip_reason := "NmlCore extension not loaded") -> void:
	# AP(1) -> AP(2) on the core side only: the gate must see at least one differing seed and exit 1.
	var r := _gate("ap1", {"find": "\"AP(1)\"", "replace": "\"AP(2)\""})
	assert_int(int(r["rc"])).is_equal(1)
	assert_int((r["mismatching_seeds"] as Array).size()).is_greater_equal(1)


@warning_ignore('unused_parameter')
func test_ap_piercing_volleys_match_the_core(do_skip := not ClassDB.class_exists("NmlCore"),
		skip_reason := "NmlCore extension not loaded") -> void:
	# P4.D-30 (a): AP(1) volleys at a defender with 2 Piercing Tag markers (one token per volley, +1 AP), two volleys per seed.
	var r := _gate("ap_piercing")
	assert_int(int(r["rc"])).override_failure_message(str(r["problems"]) + str(r["first_mismatches"])).is_equal(0)
	assert_int(int(r["identical"])).is_equal(SEEDS)


@warning_ignore('unused_parameter')
func test_red_a_core_without_the_markers_against_the_frozen_record_is_caught(do_skip := not ClassDB.class_exists("NmlCore"),
		skip_reason := "NmlCore extension not loaded") -> void:
	# The CORE's defender carries NO marker (the frozen table record spent two): no +1 AP on the core side, so the saves differ.
	var r := _gate("ap_piercing", {"find": "\"piercing_tag_markers\": 2", "replace": "\"piercing_tag_markers\": 0"})
	assert_int(int(r["rc"])).is_equal(1)
	assert_int((r["mismatching_seeds"] as Array).size()).is_greater_equal(1)


@warning_ignore('unused_parameter')
func test_red_one_edited_frozen_record_is_caught(do_skip := not ClassDB.class_exists("NmlCore"),
		skip_reason := "NmlCore extension not loaded") -> void:
	# The frozen record can fail too: one survivor count raised by one in a copy, exactly that seed turns red.
	var r := _gate("plain", {}, true)
	assert_int(int(r["rc"])).is_equal(1)
	assert_array(r["mismatching_seeds"] as Array).has_size(1)


@warning_ignore('unused_parameter')
func test_warbound_control_matches_the_core(do_skip := not ClassDB.class_exists("NmlCore"),
		skip_reason := "NmlCore extension not loaded") -> void:
	# Control for EXC-1: the base Warbound alone at 6" keeps the distance gate on both sides, no exception applies.
	var r := _gate("warbound_6in")
	assert_int(int(r["rc"])).override_failure_message(str(r["problems"]) + str(r["first_mismatches"])).is_equal(0)
	assert_int(int(r["identical"])).is_equal(SEEDS)


@warning_ignore('unused_parameter')
func test_exc1_enhanced_warbound_is_the_listed_difference(do_skip := not ClassDB.class_exists("NmlCore"),
		skip_reason := "NmlCore extension not loaded") -> void:
	# PF-b (#2615), epoch history: the table paid the Shred extra wound at 6" from epoch 73, the core gates its port at
	# 75 (EPOCH_75_TABLE_FIXES, so records stamped 73 and 74 replay byte-exact). Green only with EXC-1 listed.
	var r := _gate("enhanced_warbound_6in")
	assert_int(int(r["rc"])).override_failure_message(str(r["problems"]) + str(r["first_mismatches"])).is_equal(0)


@warning_ignore('unused_parameter')
func test_enhanced_warbound_matches_the_core_at_75(do_skip := not ClassDB.class_exists("NmlCore"),
		skip_reason := "NmlCore extension not loaded") -> void:
	# The same units at epoch 75 (#2654): both sides pay the extra wound at 6", no exception applies.
	var r := _gate("enhanced_warbound_6in_e75")
	assert_int(int(r["rc"])).override_failure_message(str(r["problems"]) + str(r["first_mismatches"])).is_equal(0)
	assert_int(int(r["identical"])).is_equal(SEEDS)


## How many of a record's rolls had this target (the Feat rolls on 5+, the volleys on 4+).
func _rolls_at(rec: Dictionary, target: int) -> int:
	return (rec["rolls"] as Array).filter(func(x) -> bool: return int((x as Dictionary)["target"]) == target).size()


@warning_ignore('unused_parameter')
func test_protection_feat_is_once_per_game_on_both_sides_at_75(do_skip := not ClassDB.class_exists("NmlCore"),
		skip_reason := "NmlCore extension not loaded") -> void:
	# #2613 / #2652: two volleys at one Protection Feat unit, the Feat dice roll in the first only.
	var r := _gate("protection_feat_twice_e75")
	assert_int(int(r["rc"])).override_failure_message(str(r["problems"]) + str(r["first_mismatches"])).is_equal(0)
	assert_int(int(r["identical"])).is_equal(SEEDS)


@warning_ignore('unused_parameter')
func test_red_a_core_without_the_protection_feat_is_caught(do_skip := not ClassDB.class_exists("NmlCore"),
		skip_reason := "NmlCore extension not loaded") -> void:
	# Core side only: the defender loses its Protection Feat; the frozen table still rolls it (once). Must be red, and the
	# difference is the Feat roll the core no longer makes.
	var r := _gate("protection_feat_twice_e75", {"find": "\"Protection Feat\"", "replace": ""})
	assert_int(int(r["rc"])).is_equal(1)
	assert_int((r["mismatching_seeds"] as Array).size()).is_greater_equal(1)
	var m := (r["first_mismatches"] as Array)[0] as Dictionary
	assert_int(_rolls_at(m["table"], 5)).is_greater(_rolls_at(m["core"], 5))


@warning_ignore('unused_parameter')
func test_crossing_strike_volley_shreds_on_both_sides_at_75(do_skip := not ClassDB.class_exists("NmlCore"),
		skip_reason := "NmlCore extension not loaded") -> void:
	# #2612 / #2653: the move-through volley takes the unit-level Shred stamp like any shooting attack.
	var r := _gate("crossing_strike_shred_e75")
	assert_int(int(r["rc"])).override_failure_message(str(r["problems"]) + str(r["first_mismatches"])).is_equal(0)
	assert_int(int(r["identical"])).is_equal(SEEDS)


@warning_ignore('unused_parameter')
func test_red_a_core_without_shred_is_caught(do_skip := not ClassDB.class_exists("NmlCore"),
		skip_reason := "NmlCore extension not loaded") -> void:
	# Core side only: the attacker loses its unit-level Shred (the stamp #2612 added to the move-through volley); the
	# frozen table kept it. Must be red, and the table (extra wounds) never has more survivors than the core.
	var r := _gate("crossing_strike_shred_e75", {"find": "[\"Shred\"]", "replace": "[]"})
	assert_int(int(r["rc"])).is_equal(1)
	assert_int((r["mismatching_seeds"] as Array).size()).is_greater_equal(1)
	var m := (r["first_mismatches"] as Array)[0] as Dictionary
	assert_int(int(m["core"]["def_alive"])).is_greater_equal(int(m["table"]["def_alive"]))


func test_every_scenario_has_its_frozen_table_record() -> void:
	# A scenario without a record cannot be gated; the table that would write one is gone, so a NEW scenario has to be
	# recorded before this step's resolver is deleted (or take its D0 golden from the golden witness instead).
	var names: Array[String] = []
	for f in DirAccess.get_files_at("res://test/parity/scenarios/shoot/"):
		names.append(f.get_basename())
	assert_array(names).is_not_empty()
	var prov := JSON.parse_string(FileAccess.get_file_as_string(FROZEN + "PROVENANCE.json")) as Dictionary
	for n in names:
		assert_bool(FileAccess.file_exists(FROZEN + n + "_table.jsonl")) \
			.override_failure_message("scenario %s has no frozen table record in %s" % [n, FROZEN]).is_true()
		var sc := JSON.parse_string(FileAccess.get_file_as_string("res://test/parity/scenarios/shoot/%s.json" % n)) as Dictionary
		assert_int(int((prov["scenarios"] as Dictionary).get(n, {}).get("epoch", -1))) \
			.override_failure_message("PROVENANCE.json does not name scenario %s at epoch %d" % [n, int(sc["epoch"])]) \
			.is_equal(int(sc["epoch"]))
		var rows := 0
		for line in FileAccess.get_file_as_string(FROZEN + n + "_table.jsonl").split("\n", false):
			rows += 1
		assert_int(rows).override_failure_message("%s: %d records, want %d seeds" % [n, rows, SEEDS]).is_equal(SEEDS)


func test_exceptions_file_is_well_formed() -> void:
	var list = JSON.parse_string(FileAccess.get_file_as_string("res://test/parity/exceptions.json"))
	assert_bool(list is Array).is_true()
	assert_int((list as Array).size()).override_failure_message(
		"the exception list only shrinks: %d entries, ceiling %d" % [(list as Array).size(), EXCEPTION_CEILING]).is_less_equal(EXCEPTION_CEILING)
	var ids := {}
	for e in list:
		for k in ["id", "lane", "since", "pr", "owner_lane", "reason"]:
			assert_bool((e as Dictionary).has(k) and str(e[k]) != "").override_failure_message("%s lacks %s" % [e.get("id"), k]).is_true()
		assert_bool((e as Dictionary).has("scenario")).is_true()
		assert_bool(ids.has(e["id"])).override_failure_message("duplicate id " + str(e["id"])).is_false()
		ids[e["id"]] = true
