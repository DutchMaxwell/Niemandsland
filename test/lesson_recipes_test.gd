extends GdUnitTestSuite


func test_s01_recipe_has_one_tagged_unit_on_a_small_table() -> void:
	var recipe := LessonRecipes.recipe("S-01")
	for key in ["size_feet", "biome", "deployment", "phase", "round", "sides"]:
		assert_bool(recipe.has(key)).is_true()
	assert_vector(recipe.get("size_feet", Vector2.ZERO)).is_equal(Vector2(4, 4))
	assert_str(recipe.get("biome", "")).is_equal("temperate_grassland")
	assert_int(recipe.get("deployment", 0)).is_equal(-1)
	assert_int(recipe.get("phase", -1)).is_equal(0)
	assert_int(recipe.get("round", 0)).is_equal(1)
	var sides: Array = recipe.get("sides", [])
	assert_int(sides.size()).is_equal(1)
	if sides.is_empty():
		return
	assert_int(sides[0].player).is_equal(1)
	assert_int(sides[0].units.size()).is_equal(1)
	assert_str(sides[0].units[0].tag).is_equal("alpha")
	assert_str(sides[0].units[0].name).is_equal("Battle Brothers")
	assert_int(sides[0].units[0].nth).is_equal(1)
	assert_vector(sides[0].units[0].at_in).is_equal(Vector2(0, 12))


func test_s02_recipe_is_an_empty_small_table() -> void:
	var recipe := LessonRecipes.recipe("S-02")
	for key in ["size_feet", "biome", "deployment", "phase", "round", "sides"]:
		assert_bool(recipe.has(key)).is_true()
	assert_vector(recipe.get("size_feet", Vector2.ZERO)).is_equal(Vector2(4, 4))
	assert_str(recipe.get("biome", "")).is_equal("temperate_grassland")
	assert_int(recipe.get("deployment", 0)).is_equal(-1)
	assert_array(recipe.get("sides", [])).is_empty()


func test_s03_recipe_is_a_standard_empty_table_with_front_line_zones() -> void:
	var recipe := LessonRecipes.recipe("S-03")
	for key in ["size_feet", "biome", "deployment", "phase", "round", "sides"]:
		assert_bool(recipe.has(key)).is_true()
	assert_vector(recipe.get("size_feet", Vector2.ZERO)).is_equal(Vector2(6, 4))
	assert_str(recipe.get("biome", "")).is_equal("temperate_grassland")
	assert_int(recipe.get("deployment", 0)).is_equal(1)
	assert_array(recipe.get("sides", [])).is_empty()


func test_s04_recipe_is_a_playing_table_with_two_sides_and_ai_slots() -> void:
	var recipe := LessonRecipes.recipe("S-04")
	assert_vector(recipe.get("size_feet", Vector2.ZERO)).is_equal(Vector2(4, 4))
	assert_int(recipe.get("phase", 0)).is_equal(1)
	assert_int(recipe.get("round", 0)).is_equal(1)
	assert_array(recipe.get("ai_slots", [])).contains([2])
	var tags: Array[String] = []
	for side in recipe.get("sides", []):
		for pick in side.get("units", []):
			tags.append(String(pick.get("tag", "")))
	assert_array(tags).contains(["alpha", "bravo", "target"])


func test_s05_recipe_is_a_playing_shooting_table() -> void:
	var recipe := LessonRecipes.recipe("S-05")
	assert_vector(recipe.get("size_feet", Vector2.ZERO)).is_equal(Vector2(4, 4))
	assert_int(recipe.get("phase", 0)).is_equal(1)
	assert_array(recipe.get("ai_slots", [])).contains([2])
	var tags: Array[String] = []
	for side in recipe.get("sides", []):
		for pick in side.get("units", []):
			tags.append(String(pick.get("tag", "")))
	assert_array(tags).contains(["alpha", "target", "far"])


func test_s06_recipe_is_a_playing_melee_table() -> void:
	var recipe := LessonRecipes.recipe("S-06")
	assert_vector(recipe.get("size_feet", Vector2.ZERO)).is_equal(Vector2(4, 4))
	assert_int(recipe.get("phase", 0)).is_equal(1)
	assert_int(recipe.get("round", 0)).is_equal(1)
	assert_array(recipe.get("ai_slots", [])).contains([2])
	var tags: Array[String] = []
	for side in recipe.get("sides", []):
		for pick in side.get("units", []):
			tags.append(String(pick.get("tag", "")))
	assert_array(tags).contains(["alpha", "target"])


func test_s06_alpha_cannot_wipe_the_target_before_it_strikes_back() -> void:
	# G4: the defender must survive Alpha's melee to strike back. Alpha's melee is one CCW A1
	# attack per model and a landed wound removes one Tough(1) Warrior, so Alpha's LIVE model
	# count (times its per-model melee attacks) must stay below the target's model count — the
	# parked casualties in the recipe guarantee it.
	var p1: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/tutorial/tutorial_army_p1.json"))
	var melee_per_model := 0
	for w in _first_unit(p1, "Battle Brothers").get("loadout", []):
		if int(w.get("range", 0)) == 0:
			melee_per_model += int(w.get("attacks", 1))
	assert_int(melee_per_model).is_equal(1)
	var recipe := LessonRecipes.recipe("S-06")
	var alpha_dead := 0
	for side in recipe.get("sides", []):
		for pick in side.get("units", []):
			if String(pick.get("tag", "")) == "alpha":
				alpha_dead = int(pick.get("dead", 0))
	var table: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Spielschule.chapter("S-06").scenario))
	var alpha_alive := 0
	var target_models := 0
	for u in table.get("game_units", []):
		var tag := String((u.get("unit_properties", {}) as Dictionary).get("lesson_tag", ""))
		if tag == "alpha":
			for m in u.get("models", []):
				if bool(m.get("is_alive", false)):
					alpha_alive += 1
		elif tag == "target":
			target_models = (u.get("models", []) as Array).size()
	assert_bool(alpha_dead > 0).is_true()
	assert_bool(alpha_alive * melee_per_model < target_models) \
		.override_failure_message("Alpha (%d live x %d attacks) can wipe the %d-model target" % [
			alpha_alive, melee_per_model, target_models]) \
		.is_true()


func _first_unit(army: Dictionary, unit_name: String) -> Dictionary:
	for unit in army.get("units", []):
		if String(unit.get("name", "")) == unit_name:
			return unit
	return {}


func test_s07_recipe_is_a_playing_morale_table() -> void:
	var recipe := LessonRecipes.recipe("S-07")
	assert_vector(recipe.get("size_feet", Vector2.ZERO)).is_equal(Vector2(4, 4))
	assert_int(recipe.get("phase", 0)).is_equal(1)
	assert_array(recipe.get("ai_slots", [])).contains([2])
	var tags: Array[String] = []
	var by_tag: Dictionary = {}
	for side in recipe.get("sides", []):
		for pick in side.get("units", []):
			tags.append(String(pick.get("tag", "")))
			by_tag[String(pick.get("tag", ""))] = pick
	assert_array(tags).contains(["shaken", "alpha", "target", "tough"])
	assert_bool(by_tag["shaken"].get("shaken", false)).is_true()
	assert_int(by_tag["target"].get("dead", 0)).is_equal(5)
	assert_int(by_tag["tough"].get("wounds", 0)).is_equal(2)
	assert_str(by_tag["tough"].get("name", "")).is_equal("Master Brother")


func test_recipe_schema_names_the_combat_seam_keys() -> void:
	assert_bool(LessonRecipes.RECIPE_KEYS.has("ai_slots")).is_true()
	for key in ["shaken", "fatigued", "dead", "wounds"]:
		assert_bool(LessonRecipes.UNIT_KEYS.has(key)) \
			.override_failure_message("unit key '%s' must be part of the recipe schema" % key) \
			.is_true()

func test_every_recipe_pick_exists_in_its_fixture() -> void:
	for id in ["S-01", "S-02", "S-03", "S-04", "S-05", "S-06", "S-07"]:
		var recipe := LessonRecipes.recipe(id)
		for side in recipe.get("sides", []):
			var path := String(side.get("fixture", ""))
			assert_bool(FileAccess.file_exists(path)).is_true()
			var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
			var names: Array[String] = []
			for unit in data.get("units", []):
				names.append(String(unit.get("name", "")))
			for pick in side.get("units", []):
				assert_bool(names.has(String(pick.get("name", "")))).is_true()
	assert_dict(LessonRecipes.recipe("S-99")).is_empty()
