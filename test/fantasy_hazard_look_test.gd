extends GdUnitTestSuite
## PLAN_GAME_SYSTEM_SWITCH step 14 (decision M-5): a fantasy table draws no minefield. Each biome gets its own hazard prop (thorn field,
## sinkhole, stone circle; volcanic keeps the lava crater), and until that GLB is cached a low procedural patch - never the mine.

const TerrainOverlayScript = preload("res://scripts/terrain_overlay.gd")
const FANTASY := ["thorn_field", "sinkhole", "stone_circle"]


func test_a_fantasy_table_picks_a_biome_hazard_and_a_grimdark_table_keeps_its_looks() -> void:
	assert_str(TerrainGroupBase.hazard_model_for("", "fantasy")).is_equal("thorn_field")
	assert_str(TerrainGroupBase.hazard_model_for("desert_", "fantasy")).is_equal("sinkhole")
	assert_str(TerrainGroupBase.hazard_model_for("tundra_", "fantasy")).is_equal("stone_circle")
	assert_str(TerrainGroupBase.hazard_model_for("volcanic_", "fantasy")).is_equal("lava_crater")
	assert_str(TerrainGroupBase.hazard_model_for("", "grimdark")).is_equal("")   # the anti-tank mine
	assert_str(TerrainGroupBase.hazard_model_for("jungle_", "grimdark")).is_equal("carnivore_plant")
	assert_str(TerrainGroupBase.hazard_model_for("", "")).is_equal("")   # no system named yet: unchanged


func test_the_fantasy_looks_are_offered_on_fantasy_systems_only() -> void:
	for m: String in FANTASY:
		assert_bool(GameSystem.offers("hazard_look", m, "aof")).is_true()
		assert_bool(GameSystem.offers("hazard_look", m, "gf")).is_false()
		assert_float(float(TerrainGroupBase.HAZARD_MODEL_DIAMETER_INCHES.get(m, 0.0))).is_greater(1.5)


func _members(base: TerrainGroupBase) -> Array:
	return base.get_children().filter(func(c: Node) -> bool: return c.has_meta(TerrainGroupBase.MEMBER_META))


func _cluster(setting: String) -> TerrainGroupBase:
	var base: TerrainGroupBase = auto_free(TerrainGroupBase.new())
	base.configure("minefield", TerrainGroupBase.KIND_HAZARD_CLUSTER, Vector2(6, 6))
	base.table_setting = setting
	add_child(base)
	base.build(7, null, null, null)
	return base


func test_a_fantasy_hazard_cluster_draws_the_low_patch_and_never_a_mine() -> void:
	var fantasy := _members(_cluster("fantasy"))
	assert_int(fantasy.size()).is_greater(0)
	for m: Node in fantasy:
		assert_bool(m.has_meta(TerrainGroupBase.FANTASY_FALLBACK_META)).is_true()
	for m: Node in _members(_cluster("grimdark")):
		assert_bool(m.has_meta(TerrainGroupBase.FANTASY_FALLBACK_META)).is_false()   # grimdark keeps the mine


func test_the_overlay_draws_a_fantasy_prop_without_a_library() -> void:
	var overlay = auto_free(TerrainOverlayScript.new())
	var node: Node3D = auto_free(overlay._create_fantasy_hazard({"cell": Vector2i(2, 3), "offset": Vector2(0.5, 0.5)}, "thorn_field"))
	assert_object(node.get_node_or_null("FantasyHazardFallback")).is_not_null()
