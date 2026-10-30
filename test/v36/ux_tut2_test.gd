extends GdUnitTestSuite
## UX-TUT2: the tutorial board and the 11 Game School lesson saves are built from the rules 3.6 practice
## armies and carry the 3.6 stamp. Denied names = UX-TUT1's list; a save also holds names as rule-list
## entries and dictionary keys, so this walker reads those too.

const UX_TUT1 := preload("res://test/v36/ux_tut1_test.gd")
const BOARD := "res://assets/tutorial/tutorial_board.nml"
const SCENARIOS := "res://assets/tutorial/scenarios/"
const P1_FIXTURE := "res://assets/tutorial/tutorial_army_p1.json"
const INCH := 0.0254


static func _files() -> Array[String]:
	var out: Array[String] = [BOARD]
	for file in DirAccess.get_files_at(SCENARIOS):
		if file.get_extension() == "nml":
			out.append(SCENARIOS + file)
	return out


## Every String under a "name" key, every String in an array (rule lists) and every dictionary key
## (item grants, rule descriptions).
static func _names(node: Variant, out: Dictionary) -> void:
	if node is Dictionary:
		if node.get("name") is String:
			out[node["name"]] = true
		for key in node:
			out[str(key)] = true
			_names(node[key], out)
	elif node is Array:
		for value in node:
			if value is String:
				out[value] = true
			_names(value, out)


static func _load(path: String) -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}


static func _unit(save: Dictionary, tag: String) -> Dictionary:
	for unit in save.get("game_units", []):
		if str(unit.get("unit_properties", {}).get("lesson_tag", "")) == tag:
			return unit
	return {}


static func _centre_in(unit: Dictionary) -> Vector2:
	var sum := Vector2.ZERO
	var spots: Array = unit.get("model_positions", [])
	for spot in spots:
		sum += Vector2(spot["position"][0], spot["position"][2])
	return sum / maxf(spots.size(), 1) / INCH


func test_saves_load_carry_units_and_the_3_6_stamp() -> void:
	assert_int(_files().size()).is_equal(12)
	var build_rules := OPRApiClient.rules_core_version("gf").substr(0, 3)
	for path in _files():
		var save := _load(path)
		assert_str(str(save.get("rules_version", "")).substr(0, 3)).override_failure_message("%s: stamp" % path).is_equal(build_rules)
		var found := {}
		_names(save, found)
		if not save.get("game_units", []).is_empty():
			assert_bool(found.has("Battle Brothers") or found.has("Warriors")) \
				.override_failure_message("%s: no core unit name found, the walker sees nothing" % path).is_true()


func test_no_save_carries_a_name_rules_3_6_removed_or_reused() -> void:
	var hits: Array[String] = []
	for path in _files():
		var found := {}
		_names(_load(path), found)
		for denied in UX_TUT1.DENIED:
			if found.has(denied):
				hits.append("%s: %s" % [path.get_file(), denied])
	assert_array(hits).override_failure_message("3.5-only names in the saves:\n" + "\n".join(hits)).is_empty()


func test_s05_nearer_warriors_stand_within_the_3_6_heavy_rifle_range() -> void:
	var fixture_range := 0.0
	for unit in _load(P1_FIXTURE)["units"]:
		for weapon in unit.get("loadout", []):
			if weapon.get("name") == "Heavy Rifle":
				fixture_range = float(weapon["range"])
	assert_float(fixture_range).is_greater(0.0)
	var save := _load(SCENARIOS + "s05_shooting.nml")
	var alpha := _unit(save, "alpha")
	var saved_range := 0.0
	for weapon in alpha.get("source_data", {}).get("weapons", []):
		if weapon.get("name") == "Heavy Rifle":
			saved_range = float(weapon["range_value"])
	assert_float(saved_range).override_failure_message("S-05 Alpha's Heavy Rifle is not the fixture's").is_equal(fixture_range)
	# Centre to centre with a 2in margin, so the whole squad, not just its front models, can reach.
	var gap := _centre_in(alpha).distance_to(_centre_in(_unit(save, "target")))
	assert_float(gap).override_failure_message("S-05 target %.1fin centre to centre, rifle %.0fin" % [gap, fixture_range]) \
		.is_less_equal(fixture_range - 2.0)
