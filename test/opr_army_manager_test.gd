extends GdUnitTestSuite
## Pure-logic tests for OPRArmyManager's model-building math: tough/scale, walker /
## mount detection, oval long-axis orientation, mount-vs-fuzzy model resolution,
## Aircraft-only hover, and AABB measurement. The spawn / tray / regiment-forming
## paths need the SceneTree + ObjectManager and are out of scope. Already covered
## elsewhere: _compute_model_fit, model_base_long_mm, round bookkeeping, buff_tokens_from_rules.


func _mgr() -> OPRArmyManager:
	# Not added to the tree: _ready() is skipped; the helpers under test are pure.
	return auto_free(OPRArmyManager.new())


# ===== _calculate_model_scale: pow(1.05, tough/3) =====

func test_calculate_model_scale() -> void:
	var m := _mgr()
	assert_float(m._calculate_model_scale(0)).is_equal_approx(1.0, 0.0001)
	assert_float(m._calculate_model_scale(3)).is_equal_approx(1.05, 0.0001)
	assert_float(m._calculate_model_scale(6)).is_equal_approx(1.1025, 0.0001)
	assert_float(m._calculate_model_scale(12)).is_equal_approx(1.2155, 0.001)


# ===== hover: only Aircraft lifts; Flying stands on its base (go-live) =====

func test_only_aircraft_lifts() -> void:
	var m := _mgr()
	assert_float(m._hover_lift_m(["Aircraft"])).is_equal_approx(OPRArmyManager.AIRCRAFT_HOVER_M, 0.001)
	assert_float(m._hover_lift_m(["Flying", "Tough(18)"])).is_equal_approx(0.0, 0.001)  # Flying no longer floats
	assert_float(m._hover_lift_m(["Fast"])).is_equal_approx(0.0, 0.001)


# ===== _is_walker (case-insensitive substring) =====

func test_is_walker() -> void:
	var m := _mgr()
	assert_bool(m._is_walker("Battle Walker")).is_true()
	assert_bool(m._is_walker("WALKER PRIME")).is_true()
	assert_bool(m._is_walker("Battle Brothers")).is_false()


# ===== _model_faces_crosswise: a MOUNT is never crosswise (sits lengthwise like a vehicle) =====

func test_mount_faces_lengthwise_not_crosswise() -> void:
	var m := _mgr()
	# A foot walker faces crosswise (quer); a non-walker foot model runs lengthwise (vehicle-style).
	assert_bool(m._model_faces_crosswise("Battle Walker", false)).is_true()
	assert_bool(m._model_faces_crosswise("Royal Champion", false)).is_false()
	# A MOUNT overrides the walker heuristic → never crosswise, so a snake / chariot sits lengthwise.
	assert_bool(m._model_faces_crosswise("Royal Champion", true)).is_false()
	assert_bool(m._model_faces_crosswise("Battle Walker", true)).is_false()


# ===== _get_tough_value_from_rules (string + dict entries) =====

func test_get_tough_value_from_rules() -> void:
	var m := _mgr()
	assert_int(m._get_tough_value_from_rules(["Fearless", "Tough(6)"])).is_equal(6)
	assert_int(m._get_tough_value_from_rules([{"name": "Tough(12)"}])).is_equal(12)
	assert_int(m._get_tough_value_from_rules(["Fast"])).is_equal(0)
	assert_int(m._get_tough_value_from_rules([])).is_equal(0)
	# First Tough wins.
	assert_int(m._get_tough_value_from_rules(["Tough(3)", "Tough(6)"])).is_equal(3)


# ===== _align_to_oval_long_axis (Y-only rotation) =====

func _glb() -> Node3D:
	return auto_free(Node3D.new())


func test_align_noop_on_non_oval() -> void:
	var m := _mgr()
	var glb := _glb()
	m._align_to_oval_long_axis(glb, AABB(Vector3.ZERO, Vector3(0.1, 0.1, 0.2)), false, 0.035, 0.060)
	assert_float(glb.rotation.y).is_equal_approx(0.0, 0.0001)


func test_align_walker_turns_crosswise_on_z_long_base() -> void:
	var m := _mgr()
	var glb := _glb()
	# Oval long axis is Z (depth 60 >= width 35); walker (cross_align) -> 90° turn.
	m._align_to_oval_long_axis(glb, AABB(Vector3.ZERO, Vector3(0.6, 0.6, 0.6)), true, 0.035, 0.060, true)
	assert_float(glb.rotation.y).is_equal_approx(PI / 2.0, 0.0001)


func test_align_vehicle_z_long_model_no_turn_on_z_long_base() -> void:
	var m := _mgr()
	var glb := _glb()
	# No marker on the standard Z-long oval (depth 0.060 >= width 0.035): the legacy +Z convention
	# holds -> no turn (the Z-long AABB is passed but never consulted).
	m._align_to_oval_long_axis(glb, AABB(Vector3.ZERO, Vector3(0.1, 0.1, 0.3)), true, 0.035, 0.060, false)
	assert_float(glb.rotation.y).is_equal_approx(0.0, 0.0001)


func test_align_vehicle_x_long_aabb_does_not_turn_without_marker() -> void:
	var m := _mgr()
	var glb := _glb()
	# MARKER-ONLY contract: even a decisively X-LONG AABB must NOT turn on the standard Z-long oval
	# without a `long_axis` marker — an XZ footprint cannot distinguish body length from wingspan
	# (live avatars / greater mutated are X-wide but +Z-facing), so geometry never drives rotation.
	m._align_to_oval_long_axis(glb, AABB(Vector3.ZERO, Vector3(0.3, 0.1, 0.1)), true, 0.035, 0.060, false)
	assert_float(glb.rotation.y).is_equal_approx(0.0, 0.0001)


func test_align_vehicle_near_square_model_keeps_legacy_mapping() -> void:
	var m := _mgr()
	# A near-square hull (0.672 x 0.642) without a marker: the legacy deterministic mapping holds —
	# no turn on a Z-long base, turn on an X-long one (the model's assumed +Z length follows the
	# base's long axis).
	var hull := AABB(Vector3.ZERO, Vector3(0.672, 0.5, 0.642))
	var on_z_long := _glb()
	m._align_to_oval_long_axis(on_z_long, hull, true, 0.035, 0.060, false)
	assert_float(on_z_long.rotation.y).is_equal_approx(0.0, 0.0001)
	var on_x_long := _glb()
	m._align_to_oval_long_axis(on_x_long, hull, true, 0.060, 0.035, false)
	assert_float(absf(on_x_long.rotation.y)).is_equal_approx(PI / 2.0, 0.0001)


func test_align_snake_riders_and_flying_beast_lengthwise_without_marker() -> void:
	var m := _mgr()
	# The REAL pilot geometries (post-snakeflip: the producer re-published serpents Z-forward).
	# Snake riders: combined AABB (2.227, 2.535, 2.722), Z-LONG — on its in-game oval (the AF parse
	# puts the long side into DEPTH: 90x52 -> width 0.052/depth 0.090) it lies lengthwise with NO
	# turn and needs no marker. The flying beast comp (4.732, 4.457, 5.838; Z-LONG) likewise.
	var serpent := AABB(Vector3.ZERO, Vector3(2.227, 2.535, 2.722))
	var riders := _glb()
	m._align_to_oval_long_axis(riders, serpent, true, 0.052, 0.090, false)
	assert_float(riders.rotation.y).is_equal_approx(0.0, 0.0001)
	var beast := _glb()
	m._align_to_oval_long_axis(beast, AABB(Vector3.ZERO, Vector3(4.732, 4.457, 5.838)), true, 0.122, 0.160, false)
	assert_float(beast.rotation.y).is_equal_approx(0.0, 0.0001)


# ===== _get_model_aabb =====

func test_get_model_aabb_measures_box_mesh() -> void:
	var m := _mgr()
	var root: Node3D = auto_free(Node3D.new())
	var mi: MeshInstance3D = auto_free(MeshInstance3D.new())
	var box := BoxMesh.new()
	box.size = Vector3(0.1, 0.2, 0.3)
	mi.mesh = box
	root.add_child(mi)
	var aabb: AABB = m._get_model_aabb(root)
	assert_float(aabb.size.x).is_equal_approx(0.1, 0.0001)
	assert_float(aabb.size.y).is_equal_approx(0.2, 0.0001)
	assert_float(aabb.size.z).is_equal_approx(0.3, 0.0001)


func test_get_model_aabb_empty_node_is_zero() -> void:
	var m := _mgr()
	var root: Node3D = auto_free(Node3D.new())
	var aabb: AABB = m._get_model_aabb(root)
	assert_float(aabb.size.length()).is_equal_approx(0.0, 0.0001)


# ===== _add_ambush_scout_band: the staging band is built from bounds alone (#76) =====
# The band must be reconstructable on any tray without synced state, so it survives every
# rebuild path (live MP receive, late-joiner sync, .nml load), not just the importer.

func test_ambush_scout_band_populates_tray() -> void:
	var m := _mgr()
	var tray: Node3D = auto_free(Node3D.new())
	m._add_ambush_scout_band(tray, Vector2(0.81, 0.81), Color.GRAY)
	# Two tint quads + one divider (all MeshInstance3D) + two Label3Ds (Ambush / Scout).
	assert_int(tray.get_child_count()).is_equal(5)
	var mesh_count := 0
	var label_count := 0
	for child: Node in tray.get_children():
		if child is MeshInstance3D:
			mesh_count += 1
		elif child is Label3D:
			label_count += 1
	assert_int(mesh_count).is_equal(3)   # 2 tint quads + 1 divider
	assert_int(label_count).is_equal(2)  # Ambush + Scout
	# The labels carry stable, unique names used for lookups elsewhere.
	assert_object(tray.get_node_or_null("AmbushScoutLabel_Ambush")).is_not_null()
	assert_object(tray.get_node_or_null("AmbushScoutLabel_Scout")).is_not_null()
	assert_object(tray.get_node_or_null("AmbushScoutDivider")).is_not_null()


func test_ambush_scout_band_guards_null_tray() -> void:
	var m := _mgr()
	# Must not crash when handed an invalid tray (defensive early-return).
	m._add_ambush_scout_band(null, Vector2(0.81, 0.81), Color.GRAY)


# ===== effective_base_props: per-model Tough enlarges the base for tokens/measuring =====
# The mesh stays natural-sized (fixed in _create_unit_model/create_model_from_properties);
# THIS is what tokens/range-rings/measuring read so they anchor to the actual enlarged base.

func test_effective_base_round_enlarged_by_tough() -> void:
	# 25 mm round + Tough(6) -> 60 mm base (max(25, 60)).
	var out := OPRArmyManager.effective_base_props({"base_size_round": 25}, 6)
	assert_int(out["base_size_round"]).is_equal(60)


func test_effective_base_no_tough_is_unchanged() -> void:
	var out := OPRArmyManager.effective_base_props({"base_size_round": 25}, 0)
	assert_int(out["base_size_round"]).is_equal(25)


func test_effective_base_low_tough_below_base_is_unchanged() -> void:
	# Tough(2) -> from_tough 0 -> max(32, 0) = 32, no growth.
	var out := OPRArmyManager.effective_base_props({"base_size_round": 32}, 2)
	assert_int(out["base_size_round"]).is_equal(32)


func test_effective_base_already_big_is_unchanged() -> void:
	# 80 mm round + Tough(6) (->60) -> stays 80 (never shrink).
	var out := OPRArmyManager.effective_base_props({"base_size_round": 80}, 6)
	assert_int(out["base_size_round"]).is_equal(80)


func test_effective_base_oval_scales_both_axes_by_ratio() -> void:
	# Oval 35x60 (long=60) + Tough(12) (->120): ratio 2.0 -> 70x120.
	var out := OPRArmyManager.effective_base_props(
		{"base_is_oval": true, "base_width_mm": 35, "base_depth_mm": 60}, 12)
	assert_int(int(out["base_width_mm"])).is_equal(70)
	assert_int(int(out["base_depth_mm"])).is_equal(120)


func test_effective_base_does_not_mutate_input() -> void:
	var original := {"base_size_round": 25}
	OPRArmyManager.effective_base_props(original, 6)
	assert_int(original["base_size_round"]).is_equal(25)  # copy, not in-place


# ===== _unit_has_rule: Ambush/Scout band detection (base-name match, trailing "(...)" ignored) =====

func _unit_with_rules(rules: Array) -> OPRApiClient.OPRUnit:
	var unit := OPRApiClient.OPRUnit.new()
	unit.special_rules.assign(rules)
	return unit


func test_unit_has_rule_matches_literal() -> void:
	assert_bool(OPRArmyManager._unit_has_rule(_unit_with_rules(["Scout", "Tough(3)"]), "Scout")).is_true()
	assert_bool(OPRArmyManager._unit_has_rule(_unit_with_rules(["Ambush"]), "Ambush")).is_true()


func test_unit_has_rule_ignores_trailing_parens() -> void:
	# Unrated rules may import with a trailing "(...)" — only the base name must match.
	assert_bool(OPRArmyManager._unit_has_rule(_unit_with_rules(["Scout (12\")"]), "Scout")).is_true()


func test_unit_has_rule_no_match() -> void:
	assert_bool(OPRArmyManager._unit_has_rule(_unit_with_rules(["Fast", "Strider"]), "Scout")).is_false()
	assert_bool(OPRArmyManager._unit_has_rule(_unit_with_rules([]), "Ambush")).is_false()


func test_unit_has_rule_null_unit_is_false() -> void:
	assert_bool(OPRArmyManager._unit_has_rule(null, "Scout")).is_false()


func test_unit_rule_describes_catches_free_text_grant() -> void:
	# Path-4 heuristic: a carried rule whose DESCRIPTION grants Scout/Ambush is detected (no structured
	# "grants" field in ArmyForge). A direct rule is left to _unit_has_rule; this scans descriptions.
	var mgr: OPRArmyManager = auto_free(OPRArmyManager.new())
	var unit := _unit_with_rules(["Pathfinder"])
	assert_bool(mgr._unit_rule_describes(unit, "Scout",
		{"Pathfinder": "This unit counts as having the Scout special rule."})).is_true()
	# Unrelated description → not detected.
	assert_bool(mgr._unit_rule_describes(_unit_with_rules(["Furious"]), "Scout",
		{"Furious": "Bonus attacks on the charge."})).is_false()
	# Empty descriptions → not detected.
	assert_bool(mgr._unit_rule_describes(unit, "Scout", {})).is_false()


# ===== _find_mount_glb_name: MOUNT_KEYWORDS + specificity (synthetic model library) =====
# Mummified Undead go-live: a hero's mount upgrade resolves to a faction mount GLB by keyword, and the
# most specific candidate wins (the "beast" collision must not steal the flying mount).

const _MOUNT_LIB_MANIFEST: String = """{
	"version": 1, "base_url": "",
	"models": {
		"mummified_undead/skeleton beast": {"url": "a.glb", "sha256": "a", "size": 1},
		"mummified_undead/beast riders": {"url": "b.glb", "sha256": "b", "size": 1},
		"mummified_undead/hunting beasts": {"url": "c.glb", "sha256": "c", "size": 1},
		"mummified_undead/war sphinx": {"url": "d.glb", "sha256": "d", "size": 1},
		"mummified_undead/war sphinx mount": {"url": "e.glb", "sha256": "e", "size": 1},
		"mummified_undead/snake riders": {"url": "f.glb", "sha256": "f", "size": 1},
		"mummified_undead/great snakes": {"url": "g.glb", "sha256": "g", "size": 1},
		"mummified_undead/skeletal steed": {"url": "h.glb", "sha256": "h", "size": 1}
	}
}"""


func _mgr_with_models() -> OPRArmyManager:
	# _ready() is skipped (not in the tree), so wire a model library by hand. apply_manifest_text
	# populates the index without any network/_ready dependency.
	var m: OPRArmyManager = auto_free(OPRArmyManager.new())
	var lib: ModelLibrary = auto_free(ModelLibrary.new())
	lib.apply_manifest_text(_MOUNT_LIB_MANIFEST)
	m.model_library = lib
	return m


func test_find_mount_glb_beast_collision_resolves_flying_mount() -> void:
	var m := _mgr_with_models()
	# "Skeleton Beast" (champion mount upgrade) must pick `skeleton beast`, NOT the shorter
	# `beast riders`/`hunting beasts` unit models it collides with on the bare "beast" keyword.
	assert_str(m._find_mount_glb_name("Skeleton Beast", "mummified_undead")).is_equal("skeleton beast")


func test_find_mount_glb_snake_keyword_matches() -> void:
	var m := _mgr_with_models()
	# "snake" is a MOUNT_KEYWORD now → the Royal Snake upgrade resolves to the best snake model
	# (was "" before, leaving the hero on foot). {royal, snake} overlaps `snake riders` (1) not
	# `great snakes` (0, "snakes" is not the whole token "snake").
	assert_str(m._find_mount_glb_name("Royal Snake", "mummified_undead")).is_equal("snake riders")


func test_find_mount_glb_sphinx_keyword_exact_name_wins() -> void:
	var m := _mgr_with_models()
	# "sphinx" is a MOUNT_KEYWORD now → "War Sphinx" resolves; exact-name `war sphinx` beats the
	# longer `war sphinx mount` on the tie-break.
	assert_str(m._find_mount_glb_name("War Sphinx", "mummified_undead")).is_equal("war sphinx")


func test_find_mount_glb_no_keyword_stays_on_foot() -> void:
	var m := _mgr_with_models()
	# A non-mount upgrade (no MOUNT_KEYWORD token) yields "" → the model keeps its foot pose.
	assert_str(m._find_mount_glb_name("Master Priest", "mummified_undead")).is_equal("")


func test_find_mount_glb_null_library_is_empty() -> void:
	var m: OPRArmyManager = auto_free(OPRArmyManager.new())  # no model_library wired
	assert_str(m._find_mount_glb_name("Skeleton Beast", "mummified_undead")).is_equal("")


# ===== _labels_with_mount + _resolve_carrier_model: mount is VARIANT-resolved, fuzzy is the fallback =====
# Go-live: a mount upgrade contributes a slug like any weapon (folded into the carrier model 0), so a
# composed mount bake `<hero>#<weapon>+<mountslug>` resolves via the variant path. The fuzzy faction-mount
# GLB is used ONLY when no variant key matches (keeps GF bikes + factions without composed bakes working).

# Composed mount bakes present: the Royal Champion#greatweapon+steed variant exists AND the fuzzy steed.
const _VARIANT_LIB: String = """{
	"version": 1, "base_url": "",
	"models": {
		"mummified_undead/royal champion": {"url": "a.glb", "sha256": "a", "size": 1},
		"mummified_undead/royal champion#greatweapon+steed": {"url": "b.glb", "sha256": "b", "size": 1},
		"mummified_undead/skeletal steed": {"url": "c.glb", "sha256": "c", "size": 1}
	}
}"""

# No composed bakes: only the base hero + the fuzzy steed mount (a faction without composed mount bakes).
const _NO_VARIANT_LIB: String = """{
	"version": 1, "base_url": "",
	"models": {
		"mummified_undead/royal champion": {"url": "a.glb", "sha256": "a", "size": 1},
		"mummified_undead/skeletal steed": {"url": "c.glb", "sha256": "c", "size": 1}
	}
}"""


func _mgr_with_variant_lib(manifest: String) -> OPRArmyManager:
	# The ModelLibrary must be in the tree so _ready() loads the SHIPPED label_slug_map.json (which maps
	# "skeletal steed" -> steed); apply_manifest_text then replaces the model index with the synthetic set.
	var m: OPRArmyManager = auto_free(OPRArmyManager.new())
	var lib: ModelLibrary = ModelLibrary.new()
	add_child(lib)
	auto_free(lib)
	lib.apply_manifest_text(manifest)
	m.model_library = lib
	return m


func test_labels_with_mount_folds_into_carrier_only() -> void:
	var per: Array = [["Great Weapon"], ["Hand Weapon"]]
	var out: Array = OPRArmyManager._labels_with_mount(per, "Skeletal Steed")
	assert_array(out[0]).contains(["Skeletal Steed"])   # carrier (model 0) gains the mount slug source
	assert_array(out[1]).is_equal(["Hand Weapon"])       # other models untouched
	assert_array(per[0]).is_equal(["Great Weapon"])      # input array is not mutated
	# Mountless: a no-op, byte-unchanged.
	assert_array(OPRArmyManager._labels_with_mount(per, "")).is_equal(per)


func test_carrier_variant_wins_over_fuzzy_mount() -> void:
	var m := _mgr_with_variant_lib(_VARIANT_LIB)
	# Royal Champion (Great Weapon) on a Skeletal Steed: the mount folds into the carrier labels, so the
	# composed bake resolves and WINS over the (also-present) fuzzy steed mount.
	var labels: Array = OPRArmyManager._labels_with_mount([["Great Weapon"]], "Skeletal Steed")
	var fuzzy: String = m._find_mount_glb_name("Skeletal Steed", "mummified_undead")
	assert_str(fuzzy).is_equal("skeletal steed")  # the fuzzy fallback is available…
	assert_str(m._resolve_carrier_model("Royal Champion", labels[0], "mummified_undead", fuzzy)) \
		.is_equal("Royal Champion#greatweapon+steed")  # …but the composed variant wins


func test_carrier_missing_variant_falls_back_to_fuzzy() -> void:
	var m := _mgr_with_variant_lib(_NO_VARIANT_LIB)
	# Same list, faction WITHOUT the composed bake → no variant key matches → the fuzzy steed mount is used.
	var labels: Array = OPRArmyManager._labels_with_mount([["Great Weapon"]], "Skeletal Steed")
	var fuzzy: String = m._find_mount_glb_name("Skeletal Steed", "mummified_undead")
	assert_str(m._resolve_carrier_model("Royal Champion", labels[0], "mummified_undead", fuzzy)) \
		.is_equal("skeletal steed")


func test_no_mount_carrier_resolution_unaffected() -> void:
	var m := _mgr_with_variant_lib(_VARIANT_LIB)
	# A mountless model (carrier_mount_glb ""): folding is a no-op and, with no `#greatweapon` bake, the
	# weapon-only variant misses → "" (base model). The mount path never touches an unmounted unit.
	var labels: Array = OPRArmyManager._labels_with_mount([["Great Weapon"]], "")
	assert_str(m._resolve_carrier_model("Royal Champion", labels[0], "mummified_undead", "")).is_equal("")


# ===== _apply_manifest_base_overrides: manifest base_mm > API bases > derived (QA r5) =====

const _BASE_OVERRIDE_LIB: String = """{
	"version": 1, "base_url": "",
	"models": {
		"mummified_undead/skeleton giant": {"url": "a.glb", "sha256": "a", "size": 1, "base_mm": {"round": 80}},
		"mummified_undead/royal snake idol": {"url": "b.glb", "sha256": "b", "size": 1, "base_mm": {"round": "90x52"}},
		"mummified_undead/skeleton warriors": {"url": "c.glb", "sha256": "c", "size": 1}
	}
}"""


func _override_army() -> OPRApiClient.OPRArmy:
	var army := OPRApiClient.OPRArmy.new()
	army.faction_folder = "mummified_undead"
	return army


func _unit_with_round_base(unit_name: String, mm: int, from_tough: bool) -> OPRApiClient.OPRUnit:
	var u := OPRApiClient.OPRUnit.new()
	u.name = unit_name
	u.base_size_round = mm
	u.base_width_mm = mm
	u.base_depth_mm = mm
	u.base_from_tough = from_tough
	return u


func test_manifest_base_override_wins_over_api_base() -> void:
	var m := _mgr_with_variant_lib(_BASE_OVERRIDE_LIB)
	var army := _override_army()
	# AF API said 60 round (the Great-Scorpion shape); the maintainer override says 80.
	var giant := _unit_with_round_base("Skeleton Giant", 60, false)
	army.units = [giant]
	m._apply_manifest_base_overrides(army)
	assert_int(giant.base_size_round).is_equal(80)
	assert_bool(giant.base_is_oval).is_false()
	assert_bool(giant.base_from_tough).is_false()  # explicit choice, not derived


func test_manifest_base_override_wins_over_derived_and_supports_oval() -> void:
	var m := _mgr_with_variant_lib(_BASE_OVERRIDE_LIB)
	var army := _override_army()
	# A Tough-DERIVED base (no AF recommendation) is also overridden — and the AF "WxD" oval form works.
	var idol := _unit_with_round_base("Royal Snake Idol", 120, true)
	army.units = [idol]
	m._apply_manifest_base_overrides(army)
	assert_bool(idol.base_is_oval).is_true()
	assert_int(idol.base_width_mm).is_equal(52)
	assert_int(idol.base_depth_mm).is_equal(90)
	assert_bool(idol.base_from_tough).is_false()


func test_no_override_keeps_parsed_base() -> void:
	var m := _mgr_with_variant_lib(_BASE_OVERRIDE_LIB)
	var army := _override_army()
	var grunt := _unit_with_round_base("Skeleton Warriors", 25, false)
	army.units = [grunt]
	m._apply_manifest_base_overrides(army)
	assert_int(grunt.base_size_round).is_equal(25)  # entry exists but has no base_mm -> untouched


# ===== Sergeant crest key derivation (QA r5): role-only and role+swap both resolve their bake =====

const _CREST_LIB: String = """{
	"version": 1, "base_url": "",
	"models": {
		"mummified_undead/royal guard": {"url": "a.glb", "sha256": "a", "size": 1},
		"mummified_undead/royal guard#crest": {"url": "b.glb", "sha256": "b", "size": 1},
		"mummified_undead/royal guard#crest+sword": {"url": "c.glb", "sha256": "c", "size": 1}
	}
}"""


func test_sergeant_role_only_resolves_crest_variant() -> void:
	var m := _mgr_with_variant_lib(_CREST_LIB)
	# A default-weapon sergeant model: labels carry the role gain only (the default Hand Weapon maps
	# to no slug) -> the `#crest` bake, NOT the base key.
	assert_str(m._resolve_model_variant_name("Royal Guard", ["Hand Weapon", "Sergeant"], "mummified_undead")) \
		.is_equal("Royal Guard#crest")


func test_sergeant_with_weapon_swap_resolves_combined_variant() -> void:
	var m := _mgr_with_variant_lib(_CREST_LIB)
	# Role + a whole-unit weapon swap ("Heavy Great Weapon" -> slug `sword`) -> sorted combined key.
	assert_str(m._resolve_model_variant_name("Royal Guard", ["Heavy Great Weapon", "Sergeant"], "mummified_undead")) \
		.is_equal("Royal Guard#crest+sword")


# ===== _find_body_node vs the staged blob structures (QA r6) =====

func test_find_body_node_champion_comp_structure_found() -> void:
	# The champion comps nest the rider as `reiter (Node3D) -> body (MeshInstance3D)` — found.
	var m := _mgr()
	var root: Node3D = auto_free(Node3D.new())
	var reiter := Node3D.new()
	reiter.name = "reiter"
	root.add_child(reiter)
	var body := MeshInstance3D.new()
	body.name = "body"
	reiter.add_child(body)
	assert_bool(m._find_body_node(root) == body).is_true()


func test_find_body_node_chariot_unit_structure_missing() -> void:
	# The staged Skeleton Chariot UNIT blobs (rolefix wave) name the crew group `lenker` but its mesh
	# `mesh` — NO node named `body` exists, so the rider fit CANNOT engage (contract v1.2 violation;
	# producer defect, verified on all three unit keys). The game must detect nothing here rather than
	# guess from localized group names.
	var m := _mgr()
	var root: Node3D = auto_free(Node3D.new())
	for group_name in ["cart", "steed_l", "steed_r", "lenker"]:
		var group := Node3D.new()
		group.name = group_name
		root.add_child(group)
		var mesh := MeshInstance3D.new()
		mesh.name = "mesh"
		group.add_child(mesh)
	assert_bool(m._find_body_node(root) == null).is_true()


# ===== long_axis manifest marker: the ONLY rotation driver (QA r7 + marker-only follow-up) =====
# Geometry cannot express INTENT: the bare great-snakes blob is a COILED +Z-facing serpent whose coil
# spreads wider in X (aspect 1.35) than a genuinely X-composed comp, and live wide/winged models
# (avatars, greater mutated) are X-wide but +Z-facing. Only the producer knows the facing -> the
# per-entry `long_axis` marker decides; without one the legacy +Z convention holds (no turn on the
# standard depth-long oval). No AABB inference exists.

func test_great_snakes_coil_needs_no_turn_marker_pins_it() -> void:
	var m := _mgr()
	# REAL great-snakes geometry (1.505, 1.553, 1.115 - X-wide by coil, +Z-facing) on its 90x52 oval.
	# WITHOUT a marker the marker-only default already keeps the +Z facing on the long axis: no turn
	# (under the removed aspect inference this coil turned sideways - the r7 QA finding).
	var coiled := AABB(Vector3.ZERO, Vector3(1.505, 1.553, 1.115))
	var unmarked := _glb()
	m._align_to_oval_long_axis(unmarked, coiled, true, 0.052, 0.090, false)
	assert_float(unmarked.rotation.y).is_equal_approx(0.0, 0.0001)
	# The staged producer marker `long_axis: "z"` pins that facing explicitly - same result.
	var marked := _glb()
	m._align_to_oval_long_axis(marked, coiled, true, 0.052, 0.090, false, "z")
	assert_float(marked.rotation.y).is_equal_approx(0.0, 0.0001)


func test_hunting_beasts_z_long_needs_no_marker() -> void:
	var m := _mgr()
	# REAL hunting-beasts geometry (0.527, 1.300, 1.790 - strongly Z-long) on its 60x35 oval: the
	# marker-only default keeps it lengthwise (no turn) - no marker needed.
	var beast := _glb()
	m._align_to_oval_long_axis(beast, AABB(Vector3.ZERO, Vector3(0.527, 1.300, 1.790)), true, 0.035, 0.060, false)
	assert_float(beast.rotation.y).is_equal_approx(0.0, 0.0001)


func test_long_axis_marker_x_forces_turn_and_walker_unaffected() -> void:
	var m := _mgr()
	# An "x" marker is the ONLY way a model turns on the standard Z-long oval - here it forces the
	# turn for a near-square model the default would leave alone.
	var square := AABB(Vector3.ZERO, Vector3(0.672, 0.5, 0.642))
	var marked_x := _glb()
	m._align_to_oval_long_axis(marked_x, square, true, 0.052, 0.090, false, "x")
	assert_float(absf(marked_x.rotation.y)).is_equal_approx(PI / 2.0, 0.0001)
	# Walker regression guard: cross_align stays deterministic crosswise - the marker path is the
	# lengthwise (vehicle/mount) path only.
	var walker := _glb()
	m._align_to_oval_long_axis(walker, square, true, 0.052, 0.090, true, "z")
	assert_float(absf(walker.rotation.y)).is_equal_approx(PI / 2.0, 0.0001)
