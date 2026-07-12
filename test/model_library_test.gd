extends GdUnitTestSuite
## Tests ModelLibrary manifest parsing + cache resolution (no network involved).


func _lib() -> ModelLibrary:
	var l := ModelLibrary.new()
	add_child(l)
	return auto_free(l)


func test_make_key_is_case_insensitive() -> void:
	assert_str(ModelLibrary.make_key("Alien_Hives", " Hive Lord ")).is_equal("alien_hives/hive lord")


func test_manifest_parse_and_has_model() -> void:
	var lib := _lib()
	lib.apply_manifest_text(JSON.stringify({
		"version": 1,
		"base_url": "https://cdn/",
		"models": {"alien_hives/hive lord": {"url": "h.glb", "sha256": "abc", "size": 10}},
	}))
	assert_bool(lib.has_model("alien_hives", "Hive Lord")).is_true()
	assert_bool(lib.has_model("alien_hives", "Nope")).is_false()


func test_no_entry_returns_empty_cached_path() -> void:
	var lib := _lib()
	assert_str(lib.get_cached_path("unknown", "unit")).is_equal("")


func test_get_cached_path_when_file_present() -> void:
	var lib := _lib()
	var sha := "modellib_cachetest_123"
	lib.apply_manifest_text(JSON.stringify({
		"version": 1,
		"base_url": "",
		"models": {"f/u": {"url": "x.glb", "sha256": sha, "size": 1}},
	}))
	# Not downloaded yet → empty.
	assert_str(lib.get_cached_path("f", "u")).is_equal("")

	# Simulate a cached download.
	var path := "user://model_cache/%s.glb" % sha
	DirAccess.make_dir_recursive_absolute("user://model_cache")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("x")
	f.close()

	assert_str(lib.get_cached_path("f", "u")).is_equal(path)
	DirAccess.remove_absolute(path)  # cleanup


# ===== variant_slug: the SHIPPED assets/label_slug_map.json (loaded in _ready) =====
# Mummified Undead go-live: every gain name below must resolve to the slug that names the pre-baked
# variant key `mummified_undead/<unit>#<slug>` in the pilot manifest (AF book uid t-sIke2snonFSL6Q).

func test_variant_slug_mummified_weapon_lines() -> void:
	var lib := _lib()
	assert_str(lib.variant_slug(["Lance"])).is_equal("lance")
	assert_str(lib.variant_slug(["Heavy Lance"])).is_equal("heavylance")
	assert_str(lib.variant_slug(["Heavy Halberd"])).is_equal("heavyhalberd")
	assert_str(lib.variant_slug(["Heavy Spear"])).is_equal("heavyspear")
	assert_str(lib.variant_slug(["Great Weapon"])).is_equal("greatweapon")
	assert_str(lib.variant_slug(["Heavy Great Weapon"])).is_equal("sword")
	assert_str(lib.variant_slug(["Heavy Hand Weapon"])).is_equal("heavy")
	assert_str(lib.variant_slug(["Dual Hand Weapons"])).is_equal("dual")
	assert_str(lib.variant_slug(["Dual Heavy Hand Weapons"])).is_equal("dual")


func test_variant_slug_mummified_bow_and_caster_lines() -> void:
	var lib := _lib()
	# Giant/Guardian/Chariot bows all normalise onto the shared bow / royalbow slugs.
	assert_str(lib.variant_slug(["Great Bow"])).is_equal("bow")
	assert_str(lib.variant_slug(["Giant Bow"])).is_equal("bow")
	assert_str(lib.variant_slug(["Bow Crew"])).is_equal("bow")
	assert_str(lib.variant_slug(["Great Royal Bow"])).is_equal("royalbow")
	assert_str(lib.variant_slug(["Giant Royal Bow"])).is_equal("royalbow")
	assert_str(lib.variant_slug(["Royal Bow Crew"])).is_equal("royalbow")
	# Caster items grant the staff variant.
	assert_str(lib.variant_slug(["Priest"])).is_equal("staff")
	assert_str(lib.variant_slug(["Master Priest"])).is_equal("staff")


func test_variant_slug_is_case_insensitive_and_sorted_combo() -> void:
	var lib := _lib()
	# Gain names are matched case-insensitively (they arrive as parsed loadout item names).
	assert_str(lib.variant_slug(["heavy halberd"])).is_equal("heavyhalberd")
	# Role + weapon on one model → sorted, de-duplicated, "+"-joined (matches the baked key ordering,
	# e.g. beast riders#crest+heavylance, royal guard#banner+sword).
	assert_str(lib.variant_slug(["Sergeant", "Heavy Lance"])).is_equal("crest+heavylance")
	assert_str(lib.variant_slug(["Heavy Great Weapon", "Banner"])).is_equal("banner+sword")


func test_variant_slug_default_weapon_yields_no_slug() -> void:
	var lib := _lib()
	# The default hand weapon (and any unmapped item) produces no slug → caller uses the base model.
	assert_str(lib.variant_slug(["Hand Weapon"])).is_equal("")
	assert_str(lib.variant_slug([])).is_equal("")


func test_variant_slug_mummified_mount_lines() -> void:
	# Mount GAIN names (AF book uid t-sIke2snonFSL6Q v3.5.3) each contribute a mount slug, so a mounted
	# hero resolves to a composed bake `<hero>#<weapon>+<mountslug>` via the same variant path as a weapon.
	var lib := _lib()
	assert_str(lib.variant_slug(["Royal Beast"])).is_equal("beast")
	assert_str(lib.variant_slug(["Skeletal Steed"])).is_equal("steed")
	assert_str(lib.variant_slug(["Royal Snake"])).is_equal("snake")
	assert_str(lib.variant_slug(["Royal Chariot"])).is_equal("chariot")
	assert_str(lib.variant_slug(["War Sphinx"])).is_equal("sphinx")
	assert_str(lib.variant_slug(["Skeleton Beast"])).is_equal("flyingbeast")
	# Weapon + mount fold into one sorted key (matches the composed bake naming).
	assert_str(lib.variant_slug(["Great Weapon", "Skeletal Steed"])).is_equal("greatweapon+steed")


# ===== find_faction_model_matching: mount-model specificity (synthetic manifests) =====

const _MOUNT_MANIFEST: String = """{
	"version": 1, "base_url": "",
	"models": {
		"mummified_undead/skeleton beast": {"url": "a.glb", "sha256": "a", "size": 1},
		"mummified_undead/beast riders": {"url": "b.glb", "sha256": "b", "size": 1},
		"mummified_undead/hunting beasts": {"url": "c.glb", "sha256": "c", "size": 1},
		"mummified_undead/war sphinx": {"url": "d.glb", "sha256": "d", "size": 1},
		"mummified_undead/war sphinx mount": {"url": "e.glb", "sha256": "e", "size": 1},
		"mummified_undead/sphinx champion": {"url": "f.glb", "sha256": "f", "size": 1},
		"mummified_undead/skeleton warriors": {"url": "g.glb", "sha256": "g", "size": 1}
	}
}"""


func test_find_faction_model_matching_beast_collision() -> void:
	var lib := _lib()
	lib.apply_manifest_text(_MOUNT_MANIFEST)
	# "Skeleton Beast" shares 2 whole tokens with `skeleton beast`, only 1 with the collision hits
	# (`beast riders`, `hunting beasts`) → the flying mount wins even though it is not the shortest.
	assert_str(lib.find_faction_model_matching("mummified_undead", ["beast"], "Skeleton Beast")) \
		.is_equal("skeleton beast")


func test_find_faction_model_matching_exact_name_wins() -> void:
	var lib := _lib()
	lib.apply_manifest_text(_MOUNT_MANIFEST)
	# Exact-name match ("War Sphinx" == `war sphinx`) beats the single-keyword `sphinx champion`
	# and, on equal token overlap, the longer `war sphinx mount`.
	assert_str(lib.find_faction_model_matching("mummified_undead", ["sphinx"], "War Sphinx")) \
		.is_equal("war sphinx")


func test_find_faction_model_matching_no_hit_returns_empty() -> void:
	var lib := _lib()
	lib.apply_manifest_text(_MOUNT_MANIFEST)
	assert_str(lib.find_faction_model_matching("mummified_undead", ["griffon"], "War Griffon")) \
		.is_equal("")


func test_find_faction_model_matching_legacy_no_full_name_is_shortest() -> void:
	var lib := _lib()
	lib.apply_manifest_text(_MOUNT_MANIFEST)
	# Without a full name the token set is the keywords, so all "beast" hits tie on overlap and the
	# shortest wins (documents the legacy tie-break the specificity layer builds on).
	assert_str(lib.find_faction_model_matching("mummified_undead", ["beast"])).is_equal("beast riders")


# ===== fit_scale + base_mm: optional per-entry corrections (unknown-field-tolerant) =====

const _CORRECTIONS_MANIFEST: String = """{
	"version": 1, "base_url": "",
	"models": {
		"mummified_undead/scarab swarms": {"url": "a.glb", "sha256": "a", "size": 1, "fit_scale": 0.5},
		"mummified_undead/skeleton giant": {"url": "b.glb", "sha256": "b", "size": 1, "base_mm": {"round": 80}},
		"mummified_undead/skeleton warriors": {"url": "c.glb", "sha256": "c", "size": 1},
		"mummified_undead/broken": {"url": "d.glb", "sha256": "d", "size": 1, "fit_scale": -2.0, "base_mm": 60}
	}
}"""


func test_fit_scale_reads_entry_default_and_invalid() -> void:
	var lib := _lib()
	lib.apply_manifest_text(_CORRECTIONS_MANIFEST)
	assert_float(lib.fit_scale("mummified_undead", "Scarab Swarms")).is_equal_approx(0.5, 0.0001)
	# Missing field -> 1.0 (old manifests / entries unaffected by construction).
	assert_float(lib.fit_scale("mummified_undead", "Skeleton Warriors")).is_equal_approx(1.0, 0.0001)
	# Invalid (<= 0) -> 1.0; unknown entry -> 1.0.
	assert_float(lib.fit_scale("mummified_undead", "Broken")).is_equal_approx(1.0, 0.0001)
	assert_float(lib.fit_scale("mummified_undead", "Nope")).is_equal_approx(1.0, 0.0001)


func test_base_override_reads_entry_and_tolerates_malformed() -> void:
	var lib := _lib()
	lib.apply_manifest_text(_CORRECTIONS_MANIFEST)
	assert_int(int(lib.base_override_mm("mummified_undead", "Skeleton Giant").get("round", 0))).is_equal(80)
	# Missing field -> {}; malformed (non-dict) -> {}; unknown entry -> {}.
	assert_bool(lib.base_override_mm("mummified_undead", "Skeleton Warriors").is_empty()).is_true()
	assert_bool(lib.base_override_mm("mummified_undead", "Broken").is_empty()).is_true()
	assert_bool(lib.base_override_mm("mummified_undead", "Nope").is_empty()).is_true()


func test_long_axis_override_reads_valid_values_only() -> void:
	var lib := _lib()
	lib.apply_manifest_text(JSON.stringify({
		"version": 1, "base_url": "",
		"models": {
			"mummified_undead/great snakes": {"url": "a.glb", "sha256": "a", "size": 1, "long_axis": "z"},
			"mummified_undead/odd": {"url": "b.glb", "sha256": "b", "size": 1, "long_axis": "diagonal"},
			"mummified_undead/plain": {"url": "c.glb", "sha256": "c", "size": 1},
		},
	}))
	assert_str(lib.long_axis_override("mummified_undead", "Great Snakes")).is_equal("z")
	# Invalid value / missing field / unknown entry -> "" (the game infers from the AABB).
	assert_str(lib.long_axis_override("mummified_undead", "Odd")).is_equal("")
	assert_str(lib.long_axis_override("mummified_undead", "Plain")).is_equal("")
	assert_str(lib.long_axis_override("mummified_undead", "Nope")).is_equal("")
