extends GdUnitTestSuite
## E2E — TableBiomePresenter on the REAL scenes/main.tscn (display only).
##
## The presenter dresses the game table with the accepted reference biome (table tier). These suites pin what
## must hold on the live table: the biome light profile stays on top of the atmosphere controller (maintainer
## decision D1, including the restore_saved() the intro runs), the dressing adds no collider and changes no
## line-of-sight geometry, and teardown gives the table back. Headless CI skips the dressing by default;
## allow_headless opts these suites in.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const Biomes := preload("res://scripts/visual/reference_biomes.gd")
const TreePass := preload("res://scripts/visual/table_tree_pass.gd")

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(10)


func after_test() -> void:
	TreePass.clear_sources()
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## Dress the table with `table_biome` (the table's own id). The biome is set on the property, not through
## table.set_biome, so no battlemap download starts in CI.
func _dress(table_biome: String) -> TableBiomePresenter:
	var presenter: TableBiomePresenter = _main._table_biome_presenter
	presenter.allow_headless = true
	_main.table.biome = table_biome
	await presenter.rebuild()
	await _runner.simulate_frames(2)
	return presenter


func _sun() -> DirectionalLight3D:
	return _main.get_node("DirectionalLight3D") as DirectionalLight3D


## Paint ruins (zone + wall models), a forest and a container onto the live overlay, as the map layout
## editor does (the same calls los_volumes_test uses).
func _paint_terrain() -> void:
	var overlay: Node3D = _main.terrain_overlay
	var table := Vector2(6, 4)
	var cells := {}
	for x in range(10, 14):
		cells[Vector2i(x, 12)] = 1          # TerrainType.RUINS
	for x in range(18, 21):
		for y in range(16, 19):
			cells[Vector2i(x, y)] = 2       # TerrainType.FOREST
	overlay.update_overlay(cells, table, 0.0)
	var walls: Array = []
	for x in range(10, 14):
		walls.append({"edge_cell": Vector2i(x, 12), "edge_side": 0, "wall_key": "w",
			"length_inches": overlay.GRID_SIZE_INCHES, "sub_position": 0})
	overlay.update_wall_models(walls, table, 0.0)
	overlay.update_placed_objects([{"object_type": "container", "cell": Vector2i(15, 15),
		"offset": Vector2(0.5, 0.5), "angle_deg": 0.0}], table, 0.0)
	await _runner.simulate_frames(3)


func _colliders() -> int:
	return _main.find_children("*", "CollisionObject3D", true, false).size()


func test_dressing_adds_no_collider_and_keeps_line_of_sight_geometry(timeout := 180000) -> void:
	await _paint_terrain()
	var volumes: Array = _main.terrain_overlay.los_volumes().duplicate(true)
	var walls: Array = _main.terrain_overlay.get_wall_segments_world().duplicate(true)
	var colliders := _colliders()
	assert_int(walls.size()).override_failure_message("the painted ruins produced no wall segment — the LOS check below would be empty").is_greater(0)
	for biome in ["temperate_grassland", "urban_ruins"]:
		var presenter := await _dress(biome)
		assert_bool(presenter.is_dressed()).is_true()
		assert_int(presenter.current_presentation().find_children("*", "CollisionObject3D", true, false).size()).is_equal(0)
		assert_int(_colliders()).override_failure_message("dressing %s changed the collider count" % biome).is_equal(colliders)
		assert_bool(_main.terrain_overlay.los_volumes() == volumes) \
			.override_failure_message("dressing %s changed the LOS volumes" % biome).is_true()
		assert_bool(_main.terrain_overlay.get_wall_segments_world() == walls) \
			.override_failure_message("dressing %s changed the wall segments" % biome).is_true()


func test_teardown_gives_the_table_back(timeout := 120000) -> void:
	var table: Node3D = _main.table
	var surface := table.get_node("TableMesh") as MeshInstance3D
	var mesh_before := surface.mesh
	var shadow_before := surface.cast_shadow
	var base_shader_before: Shader = table.get_base_top_material().shader
	var env: Environment = _main.get_node("WorldEnvironment").environment
	var ssr_before := env.ssr_enabled
	var ambient_source_before := env.ambient_light_source
	var mist: Node3D = _main.atmospheric_clouds
	var mist_before := mist.visible
	var presenter := await _dress("volcanic_ash")
	assert_bool(presenter.is_dressed()).is_true()
	# D4: the game's ground mist is off while a biome is dressed (the accepted look had none).
	assert_bool(mist.visible).override_failure_message("the ground mist stayed on over a dressed table").is_false()
	assert_object((surface.material_override as ShaderMaterial).shader).is_same(preload("res://shaders/visual/reference_ground_table.gdshader"))
	assert_bool(table.get_node("GrassField").visible).is_false()
	presenter.enabled = false
	await presenter.rebuild()
	assert_bool(presenter.is_dressed()).is_false()
	assert_object(surface.mesh).is_same(mesh_before)
	assert_int(surface.cast_shadow).is_equal(shadow_before)
	assert_bool(surface.material_override is ShaderMaterial and (surface.material_override as ShaderMaterial).shader == preload("res://shaders/visual/reference_ground_table.gdshader")).is_false()
	assert_object(table.get_base_top_material().shader).is_same(base_shader_before)
	assert_bool(table.get_node("GrassField").visible).is_true()
	assert_bool(env.ssr_enabled == ssr_before).is_true()
	assert_int(env.ambient_light_source).is_equal(ambient_source_before)
	assert_bool(mist.visible).is_equal(mist_before)
	assert_int(presenter.get_child_count()).is_equal(0)


func test_low_presets_keep_the_battlemap_table(timeout := 120000) -> void:
	var presenter := await _dress("arid_desert")
	assert_bool(presenter.is_dressed()).is_true()
	var graphics := get_tree().root.get_node("GraphicsSettings")
	var previous: int = graphics.current_preset
	graphics.current_preset = 1   # LOW, set directly: apply_preset() would persist the player's settings
	presenter._on_graphics_settings_applied("Low")
	await get_tree().create_timer(TableBiomePresenter.REBUILD_DELAY_S + 0.3).timeout
	await _runner.simulate_frames(2)
	var dressed_on_low := presenter.is_dressed()
	graphics.current_preset = previous
	assert_bool(dressed_on_low).override_failure_message("the table stayed dressed on the Low preset").is_false()


func test_layout_events_during_play_do_not_rebuild(timeout := 120000) -> void:
	var presenter := await _dress("frozen_tundra")
	var builds := [0]
	presenter.presentation_built.connect(func(_b: String) -> void: builds[0] += 1)
	var manager = _main.opr_army_manager
	manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	presenter.request_rebuild("layout")
	await get_tree().create_timer(TableBiomePresenter.REBUILD_DELAY_S + 0.3).timeout
	assert_int(builds[0]).override_failure_message("a layout event during play rebuilt the dressing (a mid-game freeze)").is_equal(0)
	# The start of play is the one layout-final rebuild.
	manager.game_phase = OPRArmyManager.GamePhase.DEPLOYMENT
	presenter._on_game_phase_changed(OPRArmyManager.GamePhase.PLAYING)
	await get_tree().create_timer(TableBiomePresenter.REBUILD_DELAY_S + 0.3).timeout
	await _runner.simulate_frames(2)
	assert_int(builds[0]).is_equal(1)


func test_biome_light_profile_stays_on_top_of_the_atmosphere(timeout := 120000) -> void:
	var presenter := await _dress("arid_desert")
	assert_bool(presenter.is_dressed()).is_true()
	var profile: Dictionary = Biomes.get_profile("arid_desert")
	var atmosphere = _main.atmosphere_controller

	# The intro ends with restore_saved() — an INSTANT re-apply of the saved mood (default Sunset). The profile's
	# own sunset values must win (D1), not the game's "Warm Sunset" lighting.
	atmosphere.apply_atmosphere("Sunset", true)
	await _runner.simulate_frames(2)
	assert_float(_sun().light_energy).is_equal_approx(float(profile["sun_energy"]), 0.0001)
	assert_bool(_sun().light_color.is_equal_approx(profile["sun_color_sunset"])) \
		.override_failure_message("after the atmosphere re-applied Sunset the sun is %s, not the profile's sunset %s" % [_sun().light_color, profile["sun_color_sunset"]]) \
		.is_true()

	# Night uses the profile's sunset values too (D1).
	atmosphere.apply_atmosphere("Night", true)
	await _runner.simulate_frames(2)
	assert_bool(_sun().light_color.is_equal_approx(profile["sun_color_sunset"])).is_true()

	# Overcast is not a profile mood: the game's own lighting shows.
	atmosphere.apply_atmosphere("Overcast", true)
	await _runner.simulate_frames(2)
	assert_bool(_sun().light_color.is_equal_approx(profile["sun_color_day"])).is_false()
	assert_bool(_sun().light_color.is_equal_approx(profile["sun_color_sunset"])).is_false()

	# Day: the profile is the Day base.
	atmosphere.apply_atmosphere("Day", true)
	await _runner.simulate_frames(2)
	assert_bool(_sun().light_color.is_equal_approx(profile["sun_color_day"])).is_true()
	assert_float(_sun().light_energy).is_equal_approx(float(profile["sun_energy"]), 0.0001)


# === Tree pass (table_tree_pass.gd): the dressed biome's reference trees replace the table's trees ===

## A stand-in source tree (a 1 m box standing on the ground). Tests inject prepared sources; CI never
## downloads the reconstructed trees.
func _source_tree() -> PackedScene:
	var root := Node3D.new()
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.3, 1.0, 0.3)
	mesh.mesh = box
	mesh.position.y = 0.5
	root.add_child(mesh)
	mesh.owner = root
	var packed := PackedScene.new()
	packed.pack(root)
	root.free()
	return packed


func _inject_tree_sources() -> void:
	var tree := _source_tree()
	TreePass.inject_sources("arid_desert", {"hero": tree,
		"natives": {"desert_tree_a": tree, "desert_tree_b": tree, "desert_tree_c": tree}})
	var oaks: Array[PackedScene] = []
	var bounds: Array[AABB] = []
	for _i in 6:
		oaks.append(tree)
		bounds.append(AABB(Vector3(-0.15, 0.0, -0.15), Vector3(0.3, 1.0, 0.3)))
	TreePass.inject_sources("grassland", {"oak_scenes": oaks, "oak_bounds": bounds})


## A painted forest (zone + three tree models + a container) and a movable forest group of `prefix`.
func _paint_forest(prefix: String) -> TerrainGroupBase:
	var overlay: Node3D = _main.terrain_overlay
	var table := Vector2(6, 4)
	var cells := {}
	for x in range(18, 21):
		for y in range(16, 19):
			cells[Vector2i(x, y)] = 2       # TerrainType.FOREST
	overlay.update_overlay(cells, table, 0.0)
	var objects: Array = []
	for x in range(18, 21):
		objects.append({"object_type": "tree", "cell": Vector2i(x, 17), "offset": Vector2(0.5, 0.5)})
	objects.append({"object_type": "container", "cell": Vector2i(15, 15), "offset": Vector2(0.5, 0.5), "angle_deg": 0.0})
	overlay.update_placed_objects(objects, table, 0.0)
	var group := TerrainGroupBase.new()
	group.configure(prefix + "forest_small", TerrainGroupBase.KIND_FOREST, Vector2(8, 6), prefix)
	_main.object_manager.add_child(group)
	group.position = Vector3(-0.4, 0.0, -0.2)
	group.build(4242, null)
	await _runner.simulate_frames(3)
	return group


## The table's own trees: the overlay's tree models and the forest group's members.
func _tree_roots(group: TerrainGroupBase) -> Array:
	var roots: Array = []
	for original in _main.terrain_overlay._object_instances:
		if is_instance_valid(original) and not original is CollisionObject3D:
			roots.append(original)
	for member in group.get_children():
		if member.has_meta(TerrainGroupBase.MEMBER_META):
			roots.append(member)
	return roots


## Meshes of the table's own trees that show (reference trees under `added` are not counted).
func _visible_old_meshes(group: TerrainGroupBase, added: Array) -> int:
	var count := 0
	for root in _tree_roots(group):
		for mesh: Node in root.find_children("*", "GeometryInstance3D", true, false):
			if (mesh as Node3D).is_visible_in_tree() and not _under_any(mesh, added):
				count += 1
	return count


func _hidden_old_meshes(group: TerrainGroupBase) -> int:
	var count := 0
	for root in _tree_roots(group):
		for mesh: Node in root.find_children("*", "GeometryInstance3D", true, false):
			if not (mesh as Node3D).is_visible_in_tree():
				count += 1
	return count


func _under_any(node: Node, roots: Array) -> bool:
	for root: Node in roots:
		if is_instance_valid(root) and (root == node or root.is_ancestor_of(node)):
			return true
	return false


func test_tree_pass_swaps_the_trees_and_keeps_line_of_sight_geometry(timeout := 180000) -> void:
	var group := await _paint_forest("desert_")
	var presenter := await _dress("arid_desert")
	assert_bool(presenter.is_dressed()).is_true()
	# No sources yet (CI never downloads): the table keeps its trees, never an empty spot.
	assert_bool(presenter.are_trees_dressed()).is_false()
	assert_int(_visible_old_meshes(group, [])).override_failure_message("the painted forest shows no tree mesh, nothing to swap").is_greater(0)
	assert_int(_hidden_old_meshes(group)).override_failure_message("old trees were hidden before any source was ready").is_equal(0)
	var volumes: Array = _main.terrain_overlay.los_volumes().duplicate(true)
	var colliders := _colliders()
	var members: Array = group.member_states()
	var group_transform := group.global_transform
	_inject_tree_sources()
	await _runner.simulate_frames(2)   # the presenter's frame poll picks the ready sources up
	assert_bool(presenter.are_trees_dressed()).override_failure_message("ready sources were not swapped in").is_true()
	var added: Array = presenter._tree_pass._added
	assert_int(added.size()).override_failure_message("%d reference trees for %d table trees" % [added.size(), _tree_roots(group).size()]) \
		.is_equal(_tree_roots(group).size())
	assert_int(_visible_old_meshes(group, added)).override_failure_message("old tree meshes still show next to the reference trees").is_equal(0)
	assert_int(_colliders()).override_failure_message("the tree swap changed the collider count").is_equal(colliders)
	assert_bool(_main.terrain_overlay.los_volumes() == volumes).override_failure_message("the tree swap changed the LOS volumes").is_true()
	assert_bool(group.member_states() == members).override_failure_message("the tree swap changed the saved forest members").is_true()
	assert_bool(group.global_transform.is_equal_approx(group_transform)).override_failure_message("the tree swap moved the forest group").is_true()


func test_tree_teardown_puts_the_old_trees_back(timeout := 120000) -> void:
	var group := await _paint_forest("desert_")
	_inject_tree_sources()
	var presenter := await _dress("arid_desert")
	assert_bool(presenter.are_trees_dressed()).is_true()
	var added: Array = presenter._tree_pass._added.duplicate()
	assert_int(added.size()).is_greater(0)
	presenter.enabled = false
	await presenter.rebuild()
	await _runner.simulate_frames(1)
	assert_bool(presenter.are_trees_dressed()).is_false()
	var left := 0
	for tree in added:
		if is_instance_valid(tree) and tree.is_inside_tree():
			left += 1
	assert_int(left).override_failure_message("%d reference trees stayed on the table after teardown" % left).is_equal(0)
	assert_int(_hidden_old_meshes(group)).override_failure_message("old tree meshes stayed hidden after teardown").is_equal(0)


func test_low_preset_keeps_the_old_trees(timeout := 120000) -> void:
	var group := await _paint_forest("desert_")
	_inject_tree_sources()
	var graphics := get_tree().root.get_node("GraphicsSettings")
	var previous: int = graphics.current_preset
	graphics.current_preset = 1   # LOW, set directly: apply_preset() would persist the player's settings
	var presenter := await _dress("arid_desert")
	var dressed := presenter.is_dressed()
	var trees := presenter.are_trees_dressed()
	var hidden := _hidden_old_meshes(group)
	graphics.current_preset = previous
	assert_bool(dressed).override_failure_message("the table was dressed on the Low preset").is_false()
	assert_bool(trees).override_failure_message("the trees were swapped on the Low preset").is_false()
	assert_int(hidden).override_failure_message("old tree meshes were hidden on the Low preset").is_equal(0)


func test_grassland_trees_become_the_reference_oak(timeout := 120000) -> void:
	var group := await _paint_forest("")
	_inject_tree_sources()
	var presenter := await _dress("temperate_grassland")
	assert_bool(presenter.are_trees_dressed()).is_true()
	var added: Array = presenter._tree_pass._added
	var canopies := 0
	for tree: Node in added:
		if str(tree.name).begins_with("ReferenceCanopy") or tree.get_parent() == group:
			canopies += 1
	assert_int(canopies).override_failure_message("%d oaks for %d table trees" % [canopies, _tree_roots(group).size()]) \
		.is_equal(_tree_roots(group).size())
	assert_int(_visible_old_meshes(group, added)).override_failure_message("old tree meshes still show next to the oaks").is_equal(0)
