# gdUnit4: a leader/Sergeant model's distinct ranged + melee weapons (each count 1, e.g. Pathfinders'
# Plasma Pistol + Energy Sword) must land on the SAME model — not be split across two by a shared
# distribution cursor — so the special-weapon ring shows the Sergeant's full loadout on one base.
extends GdUnitTestSuite


func _unit_with_models(n: int) -> GameUnit:
	var unit: GameUnit = auto_free(GameUnit.new())
	for i in range(n):
		var m: ModelInstance = ModelInstance.new()
		m.unit = unit
		unit.models.append(m)
	return unit


func test_sergeant_distinct_weapons_land_on_one_model() -> void:
	var unit := _unit_with_models(5)
	# 4 base models (Heavy Pistol + CCW); one Sergeant (Plasma Pistol + Energy Sword).
	EquipmentDistributor.distribute(unit, [
		{"name": "Heavy Pistol", "range": 12, "attacks": 1, "count": 4, "specialRules": []},
		{"name": "CCW", "range": 0, "attacks": 2, "count": 4, "specialRules": []},
		{"name": "Energy Sword", "range": 0, "attacks": 2, "count": 1, "specialRules": []},
		{"name": "Plasma Pistol", "range": 12, "attacks": 1, "count": 1, "specialRules": []},
	], [])

	var sergeants := 0
	for m in unit.models:
		var sp := unit.get_special_equipment_names(m)
		var has_sword := sp.has("Energy Sword")
		var has_pistol := sp.has("Plasma Pistol")
		# Never split: a model has both special weapons or neither.
		assert_bool(has_sword == has_pistol).override_failure_message(
			"special weapons split across models: %s" % str(sp)).is_true()
		if has_sword and has_pistol:
			sergeants += 1
	assert_int(sergeants).is_equal(1)  # exactly one Sergeant carries the full special loadout


func test_weapon_team_enlarged_base_and_ring_on_same_model() -> void:
	# Real HDF "Infantry Squad" shape: the "Weapon Team" is an EQUIPMENT item (attacks 0) carrying
	# Tough(3). distribute() (its special-equipment ring) and per_model_toughs() (the enlarged base
	# derived from that Tough) MUST pick the SAME model — else the bigger base and the ring split
	# onto different models (the reported bug).
	var loadout := [
		{"name": "Rifle", "range": 24, "attacks": 1, "count": 6, "specialRules": []},
		{"name": "CCW", "range": 0, "attacks": 2, "count": 8, "specialRules": []},
		{"name": "Plasma Pistol", "range": 12, "attacks": 1, "count": 1, "specialRules": ["AP(4)"]},
		{"name": "Energy Sword", "range": 0, "attacks": 1, "count": 1, "specialRules": ["Rending"]},
		{"name": "Company Standard", "range": 0, "attacks": 0, "count": 1, "specialRules": []},
		{"name": "Weapon Team", "range": 0, "attacks": 0, "count": 1, "specialRules": ["Tough(3)"]},
	]
	# Base-sizing path: the model whose Tough was elevated to 3 (the weapon team).
	var toughs := EquipmentDistributor.per_model_toughs(10, loadout, [])
	var base_model := -1
	for i in range(toughs.size()):
		if int(toughs[i]) == 3:
			base_model = i
	assert_int(base_model).is_greater_equal(0)
	# Ring path: the model the "Weapon Team" item actually lands on — must be that same model.
	var unit := _unit_with_models(10)
	EquipmentDistributor.distribute(unit, loadout, [])
	var team_model := -1
	for i in range(unit.models.size()):
		if unit.get_special_equipment_names(unit.models[i]).has("Weapon Team"):
			team_model = i
	assert_int(team_model).is_equal(base_model)


func test_parse_tough_takes_the_largest_rating() -> void:
	# A Tough(3) hero on a Tough(12) mount (dinosaur / large vehicle) must size its base + wounds from
	# the LARGER Tough, regardless of which is listed first — not the first one found.
	assert_int(EquipmentDistributor._parse_tough_rating(["Tough(3)", "Tough(12)"])).is_equal(12)
	assert_int(EquipmentDistributor._parse_tough_rating(["Tough(12)", "Tough(3)"])).is_equal(12)
	assert_int(EquipmentDistributor._parse_tough_rating([{"name": "Tough", "rating": 6}, "Tough(3)"])).is_equal(6)
	assert_int(EquipmentDistributor._parse_tough_rating(["Fearless", "Caster(2)"])).is_equal(1)  # default
