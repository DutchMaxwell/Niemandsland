extends GdUnitTestSuite
## Pure-logic tests for OPRArmyManager's model-building math: tough/scale, flying &
## walker detection, oval long-axis orientation, and AABB measurement. The spawn /
## tray / regiment-forming paths need the SceneTree + ObjectManager and are out of
## scope. Already covered elsewhere: _compute_model_fit, model_base_long_mm,
## round bookkeeping, _should_hover, buff_tokens_from_rules.


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


# ===== _is_flying_from_rules =====

func test_is_flying_from_rules() -> void:
	var m := _mgr()
	assert_bool(m._is_flying_from_rules(["Flying", "Tough(3)"])).is_true()
	assert_bool(m._is_flying_from_rules(["Flying(6)"])).is_true()
	assert_bool(m._is_flying_from_rules(["Fast", "Strider"])).is_false()
	assert_bool(m._is_flying_from_rules([])).is_false()


# ===== _is_walker (case-insensitive substring) =====

func test_is_walker() -> void:
	var m := _mgr()
	assert_bool(m._is_walker("Battle Walker")).is_true()
	assert_bool(m._is_walker("WALKER PRIME")).is_true()
	assert_bool(m._is_walker("Battle Brothers")).is_false()


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


func test_align_vehicle_no_turn_on_depth_long_oval() -> void:
	var m := _mgr()
	var glb := _glb()
	# Deterministic: base long = Z (depth 0.060 >= width 0.035) -> vehicle +Z already runs ALONG it,
	# no turn, EVEN with a model-long-X AABB (the AABB is ignored now).
	m._align_to_oval_long_axis(glb, AABB(Vector3.ZERO, Vector3(0.3, 0.1, 0.1)), true, 0.035, 0.060, false)
	assert_float(glb.rotation.y).is_equal_approx(0.0, 0.0001)


func test_align_vehicle_turns_on_width_long_oval() -> void:
	var m := _mgr()
	var glb := _glb()
	# Base long = X (width 0.060 > depth 0.035) -> turn 90° so the vehicle's +Z runs ALONG the long X
	# axis (the exact opposite turn from a walker); AABB ignored.
	m._align_to_oval_long_axis(glb, AABB(Vector3.ZERO, Vector3(0.1, 0.1, 0.3)), true, 0.060, 0.035, false)
	assert_float(absf(glb.rotation.y)).is_equal_approx(PI / 2.0, 0.0001)


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
