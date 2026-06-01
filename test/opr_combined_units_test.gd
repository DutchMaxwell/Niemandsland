extends GdUnitTestSuite
## Tests for OPRApiClient combined-unit merging.
## OPR rule (core): two units of the SAME type may be "Combined" into one larger
## unit at list-building (e.g. 2x[5 models] -> 1x[10 models]). Army Forge exports
## both halves as separate entries with combined==true; the secondary half points
## joinToUnit at the primary (anchor) half's selectionId. A joined Hero
## (combined==false, joinToUnit set) is a distinct model and must remain its own
## unit.


# ===== Helpers =====

func _client() -> OPRApiClient:
	# Not added to the tree, so _ready()/HTTPRequest setup is skipped - the merge
	# helpers under test are pure functions that don't need them.
	return auto_free(OPRApiClient.new())


func _unit(selection_id: String, size: int, cost: int, combined: bool, join_to: String) -> OPRApiClient.OPRUnit:
	var unit := OPRApiClient.OPRUnit.new()
	unit.id = "def"  # same definition id (Combined requires same unit type)
	unit.name = "Prosecution Sisters"
	unit.selection_id = selection_id
	unit.size = size
	unit.cost = cost
	unit.combined = combined
	unit.join_to_unit = join_to
	return unit


func _weapon(weapon_name: String, weapon_range: int, attacks: int, count: int) -> OPRApiClient.OPRWeapon:
	var weapon := OPRApiClient.OPRWeapon.new()
	weapon.name = weapon_name
	weapon.range_value = weapon_range
	weapon.attacks = attacks
	weapon.count = count
	return weapon


# ===== Combined merge =====

func test_combined_halves_merge_into_one_unit() -> void:
	var anchor := _unit("avx_s", 5, 130, true, "")
	anchor.weapons.append(_weapon("Prosecution Rifle", 24, 2, 5))
	anchor.weapons.append(_weapon("CCW", 0, 1, 5))
	var secondary := _unit("NF0bz", 5, 130, true, "avx_s")
	secondary.weapons.append(_weapon("Prosecution Rifle", 24, 2, 5))
	secondary.weapons.append(_weapon("CCW", 0, 1, 5))

	var units: Array[OPRApiClient.OPRUnit] = [anchor, secondary]
	var merged := _client()._merge_combined_units(units)

	# Two halves collapse into a single 10-model squad.
	assert_int(merged.size()).is_equal(1)
	assert_int(merged[0].size).is_equal(10)
	assert_int(merged[0].cost).is_equal(260)
	# Weapon counts fold together: Rifle x10, CCW x10 (still 2 distinct weapons).
	assert_int(merged[0].weapons.size()).is_equal(2)
	assert_int(merged[0].weapons[0].count).is_equal(10)
	assert_int(merged[0].weapons[1].count).is_equal(10)


func test_joined_hero_is_not_merged() -> void:
	var anchor := _unit("avx_s", 5, 130, true, "")
	var secondary := _unit("NF0bz", 5, 130, true, "avx_s")
	# combined==false -> a joined Hero, stays its own unit even with joinToUnit set.
	var hero := _unit("13Xgy", 1, 80, false, "avx_s")
	hero.name = "Great Sister"

	var units: Array[OPRApiClient.OPRUnit] = [hero, anchor, secondary]
	var merged := _client()._merge_combined_units(units)

	# Combined pair -> 1 unit; hero remains its own -> 2 units total.
	assert_int(merged.size()).is_equal(2)
	var sizes: Array = []
	for unit in merged:
		sizes.append(unit.size)
	assert_array(sizes).contains([10])  # merged combined squad
	assert_array(sizes).contains([1])   # hero untouched


func test_non_combined_units_pass_through_unchanged() -> void:
	var first := _unit("7ql_G", 1, 50, false, "")
	var second := _unit("RULOi", 3, 75, false, "")
	var units: Array[OPRApiClient.OPRUnit] = [first, second]
	var merged := _client()._merge_combined_units(units)

	assert_int(merged.size()).is_equal(2)
	assert_int(merged[0].size).is_equal(1)
	assert_int(merged[1].size).is_equal(3)


func test_combined_secondary_without_anchor_is_kept() -> void:
	# Defensive: a combined half whose anchor is missing must not be dropped.
	var orphan := _unit("NF0bz", 5, 130, true, "missing")
	var units: Array[OPRApiClient.OPRUnit] = [orphan]
	var merged := _client()._merge_combined_units(units)

	assert_int(merged.size()).is_equal(1)
	assert_int(merged[0].size).is_equal(5)


# ===== File-import (.json list) path =====

func test_list_import_reads_combined_fields_and_merges() -> void:
	# The Army Forge .json export carries combined/joinToUnit at the units[] level
	# (matching the real Army Forge API format). _parse_unit_from_list reads them
	# straight from the list entry; an empty book just leaves placeholder names/sizes.
	var client := _client()
	var anchor_raw := {"id": "Z6", "selectionId": "avx_s", "combined": true}
	var secondary_raw := {"id": "Z6", "selectionId": "NF0bz", "combined": true, "joinToUnit": "avx_s"}

	var anchor := client._parse_unit_from_list(anchor_raw, {})
	var secondary := client._parse_unit_from_list(secondary_raw, {})
	assert_bool(anchor.combined).is_true()
	assert_str(secondary.join_to_unit).is_equal("avx_s")

	# Book is empty so size defaults to 1; give them the resolved sizes to merge.
	anchor.size = 5
	secondary.size = 5
	var units: Array[OPRApiClient.OPRUnit] = [anchor, secondary]
	var merged := client._merge_combined_units(units)

	assert_int(merged.size()).is_equal(1)
	assert_int(merged[0].size).is_equal(10)
