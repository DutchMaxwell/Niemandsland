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

func test_champions_and_battle_masters_carry_a_tail_built_from_the_body_mesh() -> void:
	for key in ["ratmen/champion#censer+rifle", "ratmen/champion", "ratmen/battle master#heavyspear"]:
		assert_bool(Families.allows(key, 5)).is_true()
		assert_bool(Families.allows(key, 0)).is_false()
	assert_bool(Families.allows("ratmen/championship", 5)).is_false()
	assert_bool(Families.allows("ratmen/battle masterx", 5)).is_false()

func test_saurian_families_carry_their_five_bone_tail() -> void:
	for key in ["saurians/saurian warriors#spear", "saurians/geckos#banner+javelin", "saurians/chameleons", "saurians/saurian guardians#crest", "saurians/gators#greatweapon",
			"saurians/gator veteran#greatweapon", "saurians/gecko champion#blowpipe+lance", "saurians/kikatle", "saurians/teqi", "saurians/hakatlo"]:
		assert_bool(Families.allows(key, 5)).is_true()
		assert_bool(Families.allows(key, 0)).is_false()
	assert_bool(Families.allows("saurians/gatorsx", 5)).is_false()

func test_vampiric_undead_foot_families_are_listed_without_tail_bones() -> void:
	for key in ["vampiric_undead/skeleton guard#halberd", "vampiric_undead/skeleton watch", "vampiric_undead/drained soldiers#musician", "vampiric_undead/drained archers#bow+sergeant", "vampiric_undead/ghouls#halberd", "vampiric_undead/skeleton champion", "vampiric_undead/vampire master", "vampiric_undead/stitched zombies#banner", "vampiric_undead/werewolves#heavy_hand_weapon", "vampiric_undead/stitched butchers#carving_tool"]:
		assert_bool(Families.allows(key, 0)).is_true()
		assert_bool(Families.allows(key, 5)).is_false()
	assert_bool(Families.allows("vampiric_undead/ghoulsx", 0)).is_false()
	assert_bool(Families.allows("vampiric_undead/wolves", 0)).is_false()

func test_vampiric_undead_scope_v2_foot_families_are_listed_without_tail_bones() -> void:
	for key in ["vampiric_undead/drained leader#bow+halberd", "vampiric_undead/ghoul champion#greatweapon", "vampiric_undead/captain blackfang", "vampiric_undead/werewolf champion#greatsword"]:
		assert_bool(Families.allows(key, 0)).is_true()
		assert_bool(Families.allows(key, 5)).is_false()
	assert_bool(Families.allows("vampiric_undead/drained leaderx", 0)).is_false()

func test_night_scouts_keep_their_cloak_skinned_and_carry_no_tail_bones() -> void:
	for key in ["ratmen/night scouts", "ratmen/night scouts#bow+knives+smokebombs", "ratmen/night scouts#dual"]:
		assert_bool(Families.allows(key, 0)).is_true()
		assert_bool(Families.allows(key, 5)).is_false()
	assert_bool(Families.allows("ratmen/night scoutsx", 0)).is_false()

func test_mummified_skeleton_foot_families_are_listed_without_tail_bones() -> void:
	for key in ["mummified_undead/skeleton warriors#halberd", "mummified_undead/skeleton archers#horn", "mummified_undead/skeleton leader#dual",
			"mummified_undead/royal guard#banner+sword", "mummified_undead/royal champion#heavyspear"]:
		assert_bool(Families.allows(key, 0)).is_true()
		assert_bool(Families.allows(key, 5)).is_false()
	assert_bool(Families.allows("mummified_undead/skeleton warriorsx", 0)).is_false()
	assert_bool(Families.allows("mummified_undead/skeleton champion", 0)).is_false()

func test_mummified_large_rigs_are_listed_without_tail_bones() -> void:
	for key in ["mummified_undead/guardian statues#royalbow", "mummified_undead/skeleton giant#greatweapon", "mummified_undead/rammit den geddul"]:
		assert_bool(Families.allows(key, 0)).is_true()
		assert_bool(Families.allows(key, 5)).is_false()
	assert_bool(Families.allows("mummified_undead/skeleton giantx", 0)).is_false()

func test_mummies_are_listed_without_tail_bones() -> void:
	assert_bool(Families.allows("mummified_undead/mummies", 0)).is_true()
	assert_bool(Families.allows("mummified_undead/mummies", 5)).is_false()
	assert_bool(Families.allows("mummified_undead/mummiesx", 0)).is_false()

func test_named_ratmen_foot_heroes_are_listed_with_rigid_tails() -> void:
	for key in ["ratmen/brother hepalit", "ratmen/captain kedseit", "ratmen/getrie veikasip"]:
		assert_bool(Families.allows(key, 0)).is_true()
		assert_bool(Families.allows(key, 5)).is_false()
	assert_bool(Families.allows("ratmen/captain kedseitx", 0)).is_false()

func test_unlisted_families_are_rejected() -> void:
	assert_bool(Families.allows("ratmen/rat ogres", 0)).is_false()
	assert_bool(Families.allows("mummified_undead/chariot", 0)).is_false()
