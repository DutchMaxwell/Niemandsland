extends GdUnitTestSuite
## Multiplayer table consistency: three places where ONE peer's table changed without the others hearing of it.
##  1. A guest's Load Game must not wipe the host's table (the clear used to be broadcast to everyone).
##  2. An ESC-cancelled drag must put the object back on every peer, not only on the one that dragged.
##  3. Radial Delete on terrain / generic objects must be the undoable, networked delete the Delete key runs.

const ObjectManagerScript = preload("res://scripts/object_manager.gd")


## Records what a peer would have put on the wire.
class NetStub extends Node:
	var active: bool = true
	var is_host: bool = false
	var clears: int = 0
	var move_batches: Array = []
	var visibility: Array = []

	func is_multiplayer_active() -> bool:
		return active

	func is_any_remote_peer_busy() -> bool:
		return false

	func get_my_peer_id() -> int:
		return 2

	func broadcast_clear() -> void:
		clears += 1

	func broadcast_move_batch(batch: Array) -> void:
		move_batches.append(batch)

	func broadcast_object_visibility(object_id: int, is_visible: bool) -> void:
		visibility.append([object_id, is_visible])


## Stands in for the ObjectManager on the SaveManager side: counts clears and whether they were broadcast.
class OmStub extends Node3D:
	var clears: Array = []
	var _object_counter: int = 0  # the load restores the saved id counter onto the ObjectManager

	func clear_all_objects(broadcast: bool = true) -> void:
		clears.append(broadcast)


# ===== 1. guest Load Game =====

func _write_minimal_save() -> String:
	var path := "user://mp_consistency_probe.nml"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": SaveManager.SAVE_VERSION, "table": {}, "game_units": [], "objects": []}))
	f.close()
	return path


func _save_manager_with(net: NetStub, om: OmStub) -> SaveManager:
	var sm: SaveManager = auto_free(SaveManager.new())
	sm.object_manager = om
	# .set(): the property is the fix's seam; before the fix it does not exist and the load runs unguarded.
	sm.set("network_manager", net)
	return sm


func test_guest_load_game_does_not_clear_the_shared_table() -> void:
	var net: NetStub = auto_free(NetStub.new())
	net.is_host = false
	var om: OmStub = auto_free(OmStub.new())
	var sm := _save_manager_with(net, om)
	var path := _write_minimal_save()
	var err: int = await sm.load_game(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	assert_array(om.clears) \
		.override_failure_message("a guest's load must not clear the table at all (clear calls: %s)" % [om.clears]) \
		.is_empty()
	assert_int(err).override_failure_message("a guest's load into a shared game must be refused").is_not_equal(OK)


func test_host_load_game_still_loads_in_a_session() -> void:
	var net: NetStub = auto_free(NetStub.new())
	net.is_host = true
	var om: OmStub = auto_free(OmStub.new())
	var sm := _save_manager_with(net, om)
	var path := _write_minimal_save()
	var err: int = await sm.load_game(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	assert_int(err).is_equal(OK)
	assert_int(om.clears.size()).is_equal(1)


func test_offline_load_game_still_loads() -> void:
	var net: NetStub = auto_free(NetStub.new())
	net.active = false
	net.is_host = false
	var om: OmStub = auto_free(OmStub.new())
	var sm := _save_manager_with(net, om)
	var path := _write_minimal_save()
	var err: int = await sm.load_game(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	assert_int(err).is_equal(OK)
	assert_int(om.clears.size()).is_equal(1)


# ===== 2. ESC-cancelled drag =====

func test_cancelled_drag_puts_the_object_back_on_the_other_table() -> void:
	var om: Node3D = auto_free(ObjectManagerScript.new())
	add_child(om)
	var net: NetStub = auto_free(NetStub.new())
	om._network_manager = net
	var obj: Node3D = om.spawn_miniature(Vector3(0.10, 0.0, 0.20), false, 7)
	var start: Vector3 = obj.global_position
	# Mid-drag: the object is lifted and has been streamed to the peers at its lifted position.
	om._selected_objects.append(obj)
	om._drag_start_positions = {obj: start}
	om._is_dragging = true
	obj.global_position = start + Vector3(0.3, 0.05, 0.1)
	om._cancel_drag()
	assert_vector(obj.global_position).is_equal(start)
	assert_int(net.move_batches.size()) \
		.override_failure_message("ESC restored the object locally but told nobody: the peers keep the lifted position") \
		.is_equal(1)
	if net.move_batches.is_empty():
		return
	var batch: Array = net.move_batches[0]
	assert_int(batch.size()).is_equal(4)
	assert_int(int(batch[0])).is_equal(7)
	assert_vector(Vector3(batch[1], batch[2], batch[3])).is_equal(start)


func test_cancelled_drag_offline_broadcasts_nothing() -> void:
	var om: Node3D = auto_free(ObjectManagerScript.new())
	add_child(om)
	var net: NetStub = auto_free(NetStub.new())
	net.active = false
	om._network_manager = net
	var obj: Node3D = om.spawn_miniature(Vector3(0.10, 0.0, 0.20), false, 7)
	var start: Vector3 = obj.global_position
	om._selected_objects.append(obj)
	om._drag_start_positions = {obj: start}
	om._is_dragging = true
	obj.global_position = start + Vector3(0.3, 0.05, 0.1)
	om._cancel_drag()
	assert_vector(obj.global_position).is_equal(start)
	assert_array(net.move_batches).is_empty()


# ===== 3. radial Delete on terrain / generic objects =====

func _radial_with(net: NetStub, um: UndoManager) -> RadialMenuController:
	var radial: RadialMenuController = auto_free(RadialMenuController.new())
	radial.network_manager = net
	radial.undo_manager = um
	return radial


func _prop(id: int) -> Node3D:
	var node: Node3D = auto_free(Node3D.new())
	add_child(node)
	node.set_meta("network_id", id)
	return node


func test_radial_delete_terrain_is_undoable_and_synced() -> void:
	var net: NetStub = auto_free(NetStub.new())
	var um: UndoManager = auto_free(UndoManager.new())
	var radial := _radial_with(net, um)
	var terrain := _prop(10042)
	radial._on_action_selected("delete_terrain", {"terrain": terrain})
	assert_bool(terrain.is_queued_for_deletion()) \
		.override_failure_message("radial Delete freed the node: nothing left to undo") \
		.is_false()
	assert_bool(terrain.visible).is_false()
	assert_bool(um.can_undo()).override_failure_message("no undo entry for a radial terrain Delete").is_true()
	assert_array(net.visibility).override_failure_message("the other table never hears of the delete").is_equal([[10042, false]])
	um.undo()
	assert_bool(terrain.visible).is_true()
	assert_array(net.visibility).is_equal([[10042, false], [10042, true]])


func test_radial_delete_generic_object_is_undoable_and_synced() -> void:
	var net: NetStub = auto_free(NetStub.new())
	var um: UndoManager = auto_free(UndoManager.new())
	var radial := _radial_with(net, um)
	var obj := _prop(55)
	radial._on_action_selected("delete", {"object": obj})
	assert_bool(obj.is_queued_for_deletion()).is_false()
	assert_bool(obj.visible).is_false()
	assert_bool(um.can_undo()).is_true()
	assert_array(net.visibility).is_equal([[55, false]])
