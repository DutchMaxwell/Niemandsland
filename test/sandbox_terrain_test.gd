extends GdUnitTestSuite
## Tests the free-placed casual-sandbox terrain pieces: SandboxTerrainProp (walkable multi-
## storey ruin colliders) and TerrainGroupBase (tree/mine clusters on a shared movable base).
## No physics scene / network involved — structure only.

const INCHES_TO_METERS := 0.0254


func _prop(prop_id: String, kind: int, footprint: Vector2, floors: Array) -> SandboxTerrainProp:
	var prop := SandboxTerrainProp.new()
	prop.configure(prop_id, kind, footprint, floors)
	add_child(prop)
	return auto_free(prop)


func _group(prop_id: String, kind: int, footprint: Vector2) -> TerrainGroupBase:
	var base := TerrainGroupBase.new()
	base.configure(prop_id, kind, footprint)
	add_child(base)
	return auto_free(base)


# === SandboxTerrainProp ===

func test_prop_is_selectable_terrain() -> void:
	var prop := _prop("ruin_small_1f", ObjectManager.SandboxPropKind.RUIN, Vector2(3, 3), [0.0])
	assert_bool(prop.is_in_group("selectable")).is_true()
	assert_bool(prop.is_in_group("terrain")).is_true()
	assert_bool(prop.is_in_group("sandbox_terrain")).is_true()


func test_prop_collision_layer_is_ground_plus_movable() -> void:
	var prop := _prop("ruin_small_1f", ObjectManager.SandboxPropKind.RUIN, Vector2(3, 3), [0.0])
	var expected := SandboxTerrainProp.GROUND_COLLISION_LAYER | SandboxTerrainProp.MOVABLE_TERRAIN_COLLISION_LAYER
	assert_int(prop.collision_layer).is_equal(expected)
	# Mask 0: a terrain prop never settles on anything (it carries the table; minis settle on it).
	assert_int(prop.collision_mask).is_equal(0)


func test_prop_builds_two_arm_colliders_per_storey() -> void:
	# L-shaped ruin: each storey has two walkable arm slabs (an L) anchored at the corner.
	var prop := _prop("ruin_large_3f", ObjectManager.SandboxPropKind.RUIN, Vector2(9, 6), [0.0, 3.0, 6.0])
	var colliders := prop.find_children("*", "CollisionShape3D", true, false)
	assert_int(colliders.size()).is_equal(6)
	assert_int(prop.level_count()).is_equal(3)


func test_top_floor_collider_top_sits_at_storey_height() -> void:
	var prop := _prop("ruin_large_3f", ObjectManager.SandboxPropKind.RUIN, Vector2(9, 6), [0.0, 3.0, 6.0])
	var highest_top := -1.0
	for col in prop.find_children("*", "CollisionShape3D", true, false):
		var shape := (col as CollisionShape3D).shape as BoxShape3D
		var top: float = (col as CollisionShape3D).position.y + shape.size.y * 0.5
		highest_top = maxf(highest_top, top)
	# Walkable top floor of a 3-storey ruin = 6 inches above the table.
	assert_float(highest_top).is_equal_approx(6.0 * INCHES_TO_METERS, 0.0005)


func test_upper_floors_inset_so_lower_floors_stay_reachable() -> void:
	var prop := _prop("ruin_medium_2f", ObjectManager.SandboxPropKind.RUIN, Vector2(6, 4), [0.0, 3.0])
	var widths: Array = []
	for col in prop.find_children("*", "CollisionShape3D", true, false):
		widths.append(((col as CollisionShape3D).shape as BoxShape3D).size.x)
	widths.sort()
	# The upper floor slab is strictly narrower than the ground floor slab.
	assert_bool(widths[0] < widths[widths.size() - 1]).is_true()


# === Ruin catalogue (code-defined, panel-built — no GLB/model-forge) ===

func test_grassland_ruin_catalogue_has_six_storied_ruins() -> void:
	assert_int(ObjectManager.SANDBOX_RUINS.size()).is_equal(6)
	assert_bool(ObjectManager.SANDBOX_RUINS.has("ruin_large_3f")).is_true()
	var floors: Array = ObjectManager.SANDBOX_RUINS["ruin_large_3f"]["floors"]
	assert_int(floors.size()).is_equal(3)


# === TerrainGroupBase ===

func test_forest_group_builds_tree_members() -> void:
	var base := _group("forest_small", ObjectManager.SandboxPropKind.FOREST, Vector2(6, 6))
	base.build(12345, null)  # null lib → procedural trees
	assert_int(_member_count(base)).is_equal(TerrainGroupBase.FOREST_TREE_COUNT)
	assert_bool(base.is_in_group("sandbox_terrain")).is_true()
	assert_int(base.collision_layer).is_equal(TerrainGroupBase.MOVABLE_TERRAIN_COLLISION_LAYER)


func test_hazard_group_builds_mine_members() -> void:
	var base := _group("minefield", ObjectManager.SandboxPropKind.HAZARD_CLUSTER, Vector2(6, 6))
	base.build(999, null)
	assert_int(_member_count(base)).is_equal(TerrainGroupBase.HAZARD_MINE_COUNT)


func test_group_members_carry_back_pointer_to_base() -> void:
	var base := _group("forest_small", ObjectManager.SandboxPropKind.FOREST, Vector2(6, 6))
	base.build(7, null)
	for child in base.get_children():
		if child.has_meta(TerrainGroupBase.MEMBER_META):
			assert_object(child.get_meta(TerrainGroupBase.MEMBER_META)).is_same(base)


func test_cluster_scatter_is_deterministic_for_same_seed() -> void:
	var a := _group("forest_small", ObjectManager.SandboxPropKind.FOREST, Vector2(6, 6))
	var b := _group("forest_small", ObjectManager.SandboxPropKind.FOREST, Vector2(6, 6))
	a.build(4242, null)
	b.build(4242, null)
	assert_bool(_first_member_pos(a).is_equal_approx(_first_member_pos(b))).is_true()


func _member_count(base: TerrainGroupBase) -> int:
	var count := 0
	for child in base.get_children():
		if child.has_meta(TerrainGroupBase.MEMBER_META):
			count += 1
	return count


func _first_member_pos(base: TerrainGroupBase) -> Vector3:
	for child in base.get_children():
		if child.has_meta(TerrainGroupBase.MEMBER_META):
			return (child as Node3D).position
	return Vector3.ZERO
