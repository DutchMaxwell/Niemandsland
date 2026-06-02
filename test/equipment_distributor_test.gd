extends GdUnitTestSuite
## Tests for EquipmentDistributor - spreads loadout + special rules from API data
## across a unit's ModelInstances (Tough -> wounds, weapons by count, equipment
## to a single model).


# ===== Helpers =====

func _unit_with_models(count: int) -> GameUnit:
	var unit := GameUnit.new()
	for i in range(count):
		var model := ModelInstance.new()
		model.unit = unit
		model.model_index = i
		unit.models.append(model)
	return unit


func _weapon_names(model: ModelInstance) -> Array:
	var names: Array = []
	for w in model.get_weapons():
		names.append(w["name"])
	return names


# ===== Tough -> wounds =====

func test_tough_sets_wounds_on_all_models() -> void:
	var unit := _unit_with_models(3)
	EquipmentDistributor.distribute(unit, [], ["Tough(3)"])
	for model in unit.models:
		assert_int(model.wounds_max).is_equal(3)
		assert_int(model.wounds_current).is_equal(3)
		assert_int(model.properties.get("tough")).is_equal(3)


func test_no_tough_defaults_to_one_wound() -> void:
	var unit := _unit_with_models(2)
	EquipmentDistributor.distribute(unit, [], ["Fearless"])
	for model in unit.models:
		assert_int(model.wounds_max).is_equal(1)


func test_tough_dict_form() -> void:
	var unit := _unit_with_models(1)
	EquipmentDistributor.distribute(unit, [], [{"name": "Tough", "rating": 6}])
	assert_int(unit.models[0].wounds_max).is_equal(6)


# ===== Special rules =====

func test_special_rules_copied_to_all_models() -> void:
	var unit := _unit_with_models(2)
	EquipmentDistributor.distribute(unit, [], ["Fearless", {"name": "Caster", "rating": 2}])
	for model in unit.models:
		var rules: Array = model.properties.get("special_rules", [])
		assert_array(rules).contains(["Fearless"])
		assert_array(rules).contains(["Caster(2)"])


# ===== Weapon distribution by count =====

func test_weapon_with_count_goes_to_first_n_models() -> void:
	var unit := _unit_with_models(5)
	EquipmentDistributor.distribute(unit, [{"name": "Rifle", "attacks": 1, "count": 2}], [])
	# Only the first 2 of 5 models carry the rifle.
	assert_int(unit.models[0].get_weapons().size()).is_equal(1)
	assert_int(unit.models[1].get_weapons().size()).is_equal(1)
	assert_int(unit.models[2].get_weapons().size()).is_equal(0)


func test_weapon_without_count_goes_to_all_models() -> void:
	var unit := _unit_with_models(4)
	EquipmentDistributor.distribute(unit, [{"name": "CCW", "attacks": 1}], [])
	for model in unit.models:
		assert_int(model.get_weapons().size()).is_equal(1)


func test_limited_special_weapon_replaces_base_on_distinct_model() -> void:
	# 9 Rifles + 1 Flamer across 10 models: each model gets exactly one weapon and
	# the Flamer model does NOT also carry a Rifle (special replaced the base).
	var unit := _unit_with_models(10)
	EquipmentDistributor.distribute(unit, [
		{"name": "Rifle", "attacks": 1, "count": 9},
		{"name": "Flamer", "attacks": 1, "count": 1},
	], [])

	var flamer_models := 0
	for model in unit.models:
		assert_int(model.get_weapons().size()).is_equal(1)
		var names: Array = []
		for w in model.get_weapons():
			names.append(w["name"])
		if "Flamer" in names:
			flamer_models += 1
			assert_bool("Rifle" in names).is_false()
	assert_int(flamer_models).is_equal(1)


func test_universal_weapon_stacks_with_a_limited_one() -> void:
	# Everyone has a CCW (count == size); one model also has a special gun (add-on).
	var unit := _unit_with_models(5)
	EquipmentDistributor.distribute(unit, [
		{"name": "CCW", "attacks": 1, "count": 5},
		{"name": "Special Gun", "attacks": 1, "count": 1},
	], [])

	var special_models := 0
	for model in unit.models:
		var names: Array = []
		for w in model.get_weapons():
			names.append(w["name"])
		assert_bool("CCW" in names).is_true()  # universal weapon on every model
		if "Special Gun" in names:
			special_models += 1
	assert_int(special_models).is_equal(1)


# ===== Equipment / tools distribute by count (per-model pinning) =====

func test_equipment_with_count_one_goes_to_single_model() -> void:
	# A tool carried by one model (count 1) lands on exactly one model, so the base
	# ring can label it there.
	var unit := _unit_with_models(3)
	EquipmentDistributor.distribute(unit, [{"name": "Banner", "attacks": 0, "count": 1}], [])
	var carriers := 0
	for model in unit.models:
		if "Banner" in model.get_equipment():
			carriers += 1
	assert_int(carriers).is_equal(1)


func test_equipment_with_full_count_goes_to_all_models() -> void:
	# A unit-wide tool (count == size) lands on every model, so it is NOT special.
	var unit := _unit_with_models(3)
	EquipmentDistributor.distribute(unit, [{"name": "Toxic Cysts", "attacks": 0, "count": 3}], [])
	for model in unit.models:
		assert_bool("Toxic Cysts" in model.get_equipment()).is_true()


func test_special_weapon_and_tool_pin_to_distinct_specials() -> void:
	# 5 models: a universal weapon on all + a single-model tool. The tool lands on one
	# model and is flagged as that model's special equipment (what the base ring shows).
	var unit := _unit_with_models(5)
	EquipmentDistributor.distribute(unit, [
		{"name": "Razor Claws", "attacks": 1, "count": 5},
		{"name": "Synaptic Relay", "attacks": 0, "count": 1},
	], [])
	var carriers: Array = []
	for model in unit.models:
		assert_bool("Razor Claws" in _weapon_names(model)).is_true()
		if "Synaptic Relay" in model.get_equipment():
			carriers.append(model)
	assert_int(carriers.size()).is_equal(1)
	assert_array(unit.get_special_equipment_names(carriers[0])).contains_exactly(["Synaptic Relay"])


# ===== Hero attach / detach =====

func test_attach_and_detach_hero() -> void:
	var hero := GameUnit.new()
	var target := GameUnit.new()

	EquipmentDistributor.attach_hero_to_unit(hero, target)
	assert_bool(hero.unit_properties.get("attached_to") == target).is_true()
	assert_array(target.unit_properties.get("attached_heroes")).contains([hero])

	EquipmentDistributor.detach_hero(hero)
	assert_bool(hero.unit_properties.get("attached_to") == null).is_true()
	assert_int(target.unit_properties.get("attached_heroes").size()).is_equal(0)
