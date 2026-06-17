extends GdUnitTestSuite
## Per-model base sizing (0.3.4.7): a weapon-team / upgrade that raises a model's Tough above the
## squad baseline gets a bigger base; plain models keep the unit base. Covers the per-model Tough
## walk (must mirror EquipmentDistributor.distribute) and the only-enlarge base derivation that
## the spawn, remote-receiver, coherency and boundary paths all share.


func test_per_model_toughs_baseline_only() -> void:
	# No items, no Tough rule: every model is Tough 1 (BASE_WOUNDS).
	assert_array(EquipmentDistributor.per_model_toughs(5, [], [])).is_equal([1, 1, 1, 1, 1])
	# Squad-wide Tough(3) rides every model.
	assert_array(EquipmentDistributor.per_model_toughs(3, [], ["Tough(3)"])).is_equal([3, 3, 3])


func test_per_model_toughs_weapon_team_one_carrier() -> void:
	# A weapon-team item with count 1 < size 5 lands on cursor index 0 only (mirrors distribute()).
	var loadout := [{"name": "Heavy Gun", "attacks": 0, "count": 1, "specialRules": ["Tough(3)"]}]
	assert_array(EquipmentDistributor.per_model_toughs(5, loadout, [])).is_equal([3, 1, 1, 1, 1])


func test_per_model_toughs_universal_item_all_models() -> void:
	# count >= size => universal => every model gets the elevated Tough.
	var loadout := [{"name": "Heavy Armour", "attacks": 0, "count": 3, "specialRules": ["Tough(3)"]}]
	assert_array(EquipmentDistributor.per_model_toughs(3, loadout, [])).is_equal([3, 3, 3])


func test_model_base_long_mm_only_enlarges() -> void:
	# Plain infantry (tough 1) keeps the unit base.
	assert_int(OPRArmyManager.model_base_long_mm(25, 1)).is_equal(25)
	# Weapon team (tough 3) -> 40mm band.
	assert_int(OPRArmyManager.model_base_long_mm(25, 3)).is_equal(40)
	# Never shrinks: a 60mm vehicle base carrying a Tough(3) item stays 60.
	assert_int(OPRArmyManager.model_base_long_mm(60, 3)).is_equal(60)
