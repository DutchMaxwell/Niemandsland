extends GdUnitTestSuite

const Families := preload("res://tools/idle/idle_families.gd")

func test_warrior_forms_need_the_proven_five_bone_tail() -> void:
	assert_bool(Families.allows("ratmen/warriors", 5)).is_true()
	assert_bool(Families.allows("ratmen/warriors#crest+spear", 5)).is_true()
	assert_bool(Families.allows("ratmen/warriors#crest+spear", 0)).is_false()

func test_tailless_families_are_listed_explicitly() -> void:
	assert_bool(Families.allows("ratmen/storm veterans#sword", 0)).is_true()
	assert_bool(Families.allows("ratmen/monks#banner+censer", 0)).is_true()
	assert_bool(Families.allows("ratmen/monks#dual", 5)).is_false()

func test_prefix_match_stops_at_the_form_separator() -> void:
	assert_bool(Families.allows("ratmen/warriorsx", 5)).is_false()
	assert_bool(Families.allows("ratmen/warriors team", 5)).is_false()
	assert_bool(Families.allows("ratmen/monksters", 0)).is_false()

func test_militia_grenadiers_and_snipers_carry_the_five_bone_tail() -> void:
	for key in ["ratmen/militia", "ratmen/grenadiers#toxinbombs", "ratmen/snipers#pavise+rifle"]:
		assert_bool(Families.allows(key, 5)).is_true()
		assert_bool(Families.allows(key, 0)).is_false()

func test_unlisted_families_are_rejected() -> void:
	assert_bool(Families.allows("ratmen/rat ogres", 0)).is_false()
	assert_bool(Families.allows("mummified_undead/royal champion", 0)).is_false()
