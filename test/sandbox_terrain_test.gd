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
	# Tree count is size-scaled (oval area × FOREST_TREE_DENSITY, clamped to
	# [1, FOREST_TREE_MAX]) — _build_forest must create exactly that many member trees.
	var expected := base._forest_tree_count()
	assert_int(expected).is_between(1, TerrainGroupBase.FOREST_TREE_MAX)
	assert_int(_member_count(base)).is_equal(expected)
	assert_bool(base.is_in_group("sandbox_terrain")).is_true()
	assert_int(base.collision_layer).is_equal(TerrainGroupBase.MOVABLE_TERRAIN_COLLISION_LAYER)


func test_hazard_group_builds_mine_members() -> void:
	var base := _group("minefield", ObjectManager.SandboxPropKind.HAZARD_CLUSTER, Vector2(6, 6))
	base.build(999, null)
	assert_int(_member_count(base)).is_equal(TerrainGroupBase.HAZARD_MINE_COUNT)


## A dangerous-terrain cluster now builds the SAME oval ground pad the forests use (a non-member
## floor mesh) and lifts its mines onto the pad top — not bare props on the table.
func test_hazard_cluster_has_ground_pad_and_mines_sit_on_it() -> void:
	var base := _group("minefield", ObjectManager.SandboxPropKind.HAZARD_CLUSTER, Vector2(6, 6))
	base.build(123, null)
	var pad_count := 0
	for child in base.get_children():
		if child is MeshInstance3D and not child.has_meta(TerrainGroupBase.MEMBER_META):
			pad_count += 1
	assert_int(pad_count).is_greater(0)  # the oval ground pad
	var pad_top := TerrainGroupBase.FOREST_BASE_THICKNESS_INCHES * TerrainGroupBase.INCHES_TO_METERS
	for child in base.get_children():
		if child.has_meta(TerrainGroupBase.MEMBER_META):
			assert_float((child as Node3D).position.y).is_equal_approx(pad_top, 0.0001)


## A GLB-prop biome (volcanic lava / jungle plant) places fewer, larger props (HAZARD_PROP_COUNT)
## than a plain minefield (HAZARD_MINE_COUNT). The count is set by the biome, not the asset, so it
## holds even with no hazards library (the procedural fallback fills in).
func test_glb_hazard_biomes_place_fewer_props() -> void:
	var v := _group("volcanic_minefield", ObjectManager.SandboxPropKind.HAZARD_CLUSTER, Vector2(6, 4))
	v.biome_prefix = "volcanic_"
	v.build(7, null)
	assert_int(_member_count(v)).is_equal(TerrainGroupBase.HAZARD_PROP_COUNT)
	assert_int(TerrainGroupBase.HAZARD_PROP_COUNT).is_less(TerrainGroupBase.HAZARD_MINE_COUNT)


## Terrain locking is now MANUAL only: toggling terrain edit mode must NOT lock or unlock placed
## pieces (regression guard for the old auto-lock-all that made a freshly placed piece immovable the
## moment the shelf closed). A piece stays draggable until the player locks it (select + L).
func test_terrain_edit_mode_toggle_does_not_lock_pieces() -> void:
	var om: ObjectManager = auto_free(ObjectManager.new())
	var prop := _prop("ruin_small_1f", ObjectManager.SandboxPropKind.RUIN, Vector2(3, 3), [0.0])
	om.set_terrain_edit_mode(false)
	assert_bool(prop.is_in_group("locked")).is_false()
	assert_bool(prop.get_meta("locked", false)).is_false()
	om.set_terrain_edit_mode(true)
	assert_bool(prop.is_in_group("locked")).is_false()


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


# === per-biome forests (biome encoded in prop_id; no save/wire signature change) ===

func test_sandbox_catalog_prefixes_forests_and_hazards_per_biome() -> void:
	var om: ObjectManager = auto_free(ObjectManager.new())
	var desert: Array = []
	for e in om.sandbox_catalog("desert_"):
		desert.append(e.get("prop_id", ""))
	# Forests AND hazard fields carry their biome prefix (their oval pad crops the biome battlemap).
	assert_bool(desert.has("desert_forest_small")).is_true()
	assert_bool(desert.has("desert_forest_large")).is_true()
	assert_bool(desert.has("desert_minefield")).is_true()
	# Grassland pieces stay bare (no prefix).
	var grass: Array = []
	for e in om.sandbox_catalog(""):
		grass.append(e.get("prop_id", ""))
	assert_bool(grass.has("forest_small")).is_true()
	assert_bool(grass.has("minefield")).is_true()


func test_sandbox_biome_prefix_split() -> void:
	var om: ObjectManager = auto_free(ObjectManager.new())
	assert_array(om._split_sandbox_biome_prefix("desert_forest_small")).is_equal(["desert_", "forest_small"])
	assert_array(om._split_sandbox_biome_prefix("volcanic_forest_large")).is_equal(["volcanic_", "forest_large"])
	assert_array(om._split_sandbox_biome_prefix("forest_small")).is_equal(["", "forest_small"])
	assert_array(om._split_sandbox_biome_prefix("minefield")).is_equal(["", "minefield"])


func test_forest_group_stores_biome_and_floor_falls_back() -> void:
	var base := _group("desert_forest_small", ObjectManager.SandboxPropKind.FOREST, Vector2(6, 4))
	base.biome_prefix = "desert_"
	assert_str(base.biome_prefix).is_equal("desert_")
	# A missing per-biome floor tile must fall back to the grassland floor, never a null material.
	assert_object(base._forest_floor_material()).is_not_null()


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


# ===== per-biome ruins + forest-floor battlemap crop =====

func test_sandbox_catalog_lists_themed_ruins_in_every_biome() -> void:
	var om: ObjectManager = auto_free(ObjectManager.new())
	# A ruin now appears in every biome with the biome prefix on its prop_id (themed walls).
	var has_desert_ruin := false
	for e in om.sandbox_catalog("desert_"):
		if int(e.get("kind", -1)) == ObjectManager.SandboxPropKind.RUIN and str(e.get("prop_id", "")).begins_with("desert_"):
			has_desert_ruin = true
	assert_bool(has_desert_ruin).is_true()
	# Grassland ruins stay unprefixed.
	var has_grass_ruin := false
	for e in om.sandbox_catalog(""):
		if int(e.get("kind", -1)) == ObjectManager.SandboxPropKind.RUIN and not str(e.get("prop_id", "")).begins_with("desert_"):
			has_grass_ruin = true
	assert_bool(has_grass_ruin).is_true()


func test_split_handles_prefixed_ruin_id() -> void:
	var om: ObjectManager = auto_free(ObjectManager.new())
	assert_array(om._split_sandbox_biome_prefix("desert_ruin_small_1f")).is_equal(["desert_", "ruin_small_1f"])
	assert_array(om._split_sandbox_biome_prefix("ruin_small_1f")).is_equal(["", "ruin_small_1f"])


func test_ruin_prop_stores_theme_prefix() -> void:
	var prop: SandboxTerrainProp = auto_free(SandboxTerrainProp.new())
	prop.configure("volcanic_ruin_small_1f", ObjectManager.SandboxPropKind.RUIN, Vector2(6, 6), [0.0], "volcanic_")
	assert_str(prop._theme_prefix).is_equal("volcanic_")


func test_forest_floor_battlemap_key_map() -> void:
	var m: Dictionary = TerrainGroupBase.FOREST_FLOOR_BATTLEMAP_KEY_BY_PREFIX
	assert_str(str(m.get("desert_", ""))).is_equal("arid_desert")
	assert_str(str(m.get("volcanic_", ""))).is_equal("volcanic_ash")
	# Grassland now crops its own battlemap too (like the other biomes), not the bundled tile.
	assert_str(str(m.get("", ""))).is_equal("temperate_grassland")


## Dangerous terrain uses the biome's GLB prop where one exists (volcanic lava crater, jungle/alien
## carnivore plant); other biomes have no entry and fall back to the procedural anti-tank mine.
func test_biome_hazard_model_map() -> void:
	var m: Dictionary = TerrainGroupBase.BIOME_HAZARD_MODEL_BY_PREFIX
	assert_str(str(m.get("volcanic_", ""))).is_equal("lava_crater")
	assert_str(str(m.get("jungle_", ""))).is_equal("carnivore_plant")
	assert_bool(m.has("")).is_false()         # grassland → procedural mine
	assert_bool(m.has("desert_")).is_false()  # desert → procedural mine
