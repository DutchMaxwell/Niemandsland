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


# ===== Equipment (attacks == 0) goes to a single model =====

func test_equipment_assigned_to_single_model() -> void:
	var unit := _unit_with_models(3)
	EquipmentDistributor.distribute(unit, [{"name": "Banner", "attacks": 0}], [])
	var carriers := 0
	for model in unit.models:
		if "Banner" in model.get_equipment():
			carriers += 1
	assert_int(carriers).is_equal(1)


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
