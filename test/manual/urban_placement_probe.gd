extends RefCounted
## Real native placement, clipboard and save/load path in an isolated capture session.

var _tree: SceneTree
var _output: String
var _checks: Array[String] = []


func run(main: Node,presentation: Node3D,output: String,tree: SceneTree) -> bool:
	_tree = tree
	_output = output.path_join("placement")
	DirAccess.make_dir_recursive_absolute(_output)
	var urban: Node3D
	for child in presentation.get_children():
		if child.get_script() == preload("res://scripts/visual/reference_urban.gd"):
			urban = child
	if urban == null:
		return _check(false,"urban controller found")
	var manager: Node = main.object_manager
	var camera: Camera3D = main.get_node("CameraPivot/Camera3D")
	camera.global_position = Vector3(0.35,0.48,0.65)
	camera.look_at(Vector3(0.25,0,0.05))
	var baseline: Dictionary = main.save_manager.serialize_game_state()
	var baseline_walls: Array = urban._walls.duplicate(true)
	var ruin: Node3D = manager.spawn_sandbox_terrain("urban_ruin_small_1f",0,Vector3(0.12,0,-0.03),false)
	var native_bounds: AABB = main.terrain_overlay._model_space_aabb(ruin)
	var native_edges: Array = ruin.wall_segments_world().duplicate(true)
	await _settle()
	var id := ruin.get_instance_id()
	if not _check(urban._owners.has(id),"placed ruin acquires dressing"):
		return false
	if not _check(native_bounds == main.terrain_overlay._model_space_aabb(ruin) and native_edges == ruin.wall_segments_world(),"native bounds and walls remain unchanged"):
		return false
	await _capture("placed")
	ruin.position = Vector3(0.38,0,0.12)
	ruin.rotation.y = deg_to_rad(65)
	await _tree.process_frame
	if not _check(urban._owners[id].rig.global_transform.is_equal_approx(ruin.global_transform),"dressing follows translation and rotation"):
		return false
	await _settle()
	await _capture("moved")
	manager._deselect_all()
	manager._add_to_selection(ruin)
	manager.copy_to_clipboard()
	manager.paste_from_clipboard(Vector3(0.13,0,-0.12))
	var copied: Node3D = manager.get_selected_objects()[0]
	manager._deselect_all()
	await _settle()
	if not _check(urban._owners.has(copied.get_instance_id()) and copied.get_meta("network_id") != ruin.get_meta("network_id"),"native clipboard duplicate owns independent dressing"):
		return false
	if not _check(copied.find_children("UrbanVisualObserver*","Node3D",true,false).size() == 1,"duplicate has one fresh observer"):
		return false
	await _capture("duplicated")
	var saved: Dictionary = main.save_manager.serialize_game_state()
	var ruin_network_id: int = ruin.get_meta("network_id")
	var original_transform := ruin.transform
	ruin.queue_free()
	await _settle()
	if not _check(not urban._owners.has(id),"deletion removes owned dressing"):
		return false
	await _capture("deleted")
	var status: int = await main.save_manager.restore_state(saved)
	await _settle()
	var loaded: Node3D = manager.find_by_network_id(ruin_network_id)
	if not _check(status == OK and loaded != null and loaded.transform.is_equal_approx(original_transform) and urban._owners.has(loaded.get_instance_id()),"save/load restores transformed terrain and dressing"):
		return false
	if not _check(main.get_node("Table/TableMesh").material_override == presentation._ground,"save/load retains reference ground"):
		return false
	await _capture("loaded")
	status = await main.save_manager.restore_state(baseline)
	await _settle()
	if not _check(status == OK and urban._owners.size() == 1 and urban._walls == baseline_walls,"loading original layout removes all added contacts"):
		return false
	var table: Node = main.get_node("Table")
	table.setup_table(Vector2(4,4))
	await _settle()
	if not _check(urban._board_size.is_equal_approx(Vector2(4,4)*0.3048) and table.get_node("TableMesh").material_override == presentation._ground,"table resize rebuilds projection and contacts"):
		return false
	await main.save_manager.restore_state(baseline)
	await _settle()
	FileAccess.open(_output.path_join("checks.json"),FileAccess.WRITE).store_string(JSON.stringify({"passed":_checks},"\t"))
	print("URBAN_PLACEMENT_PROBE_PASSED ",_checks.size())
	return true


func _settle() -> void:
	await _tree.create_timer(1.0).timeout


func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	_tree.root.get_texture().get_image().save_png(_output.path_join(label+".png"))


func _check(condition: bool,label: String) -> bool:
	if condition:
		_checks.append(label)
		print("URBAN_PLACEMENT_OK ",label)
	else:
		push_error("URBAN_PLACEMENT_FAILED "+label)
	return condition
