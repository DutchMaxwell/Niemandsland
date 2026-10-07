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


func test_every_recipe_pick_exists_in_its_fixture() -> void:
	for id in ["S-01", "S-02"]:
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
