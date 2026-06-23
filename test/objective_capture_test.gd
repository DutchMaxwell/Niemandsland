extends GdUnitTestSuite
## Tests mission-objective capture: owner colors, pickable bodies (radial capture),
## owner storage, recolor-in-place, and the save/restore owner list.

const TerrainOverlayScript = preload("res://scripts/terrain_overlay.gd")


func _overlay() -> Node3D:
	var overlay: Node3D = auto_free(TerrainOverlayScript.new())
	add_child(overlay)  # objective tokens are added as children
	return overlay


func test_neutral_owner_is_gold() -> void:
	var overlay := _overlay()
	var color: Color = overlay._objective_owner_color(0)
	assert_float(color.r).is_equal_approx(1.0, 0.01)
	assert_float(color.g).is_equal_approx(0.85, 0.01)


func test_player_owner_uses_canonical_army_color() -> void:
	var overlay := _overlay()
	var expected: Color = OPRArmyManager.PLAYER_COLORS[1]
	var color: Color = overlay._objective_owner_color(1)
	assert_float(color.r).is_equal_approx(expected.r, 0.01)
	assert_float(color.g).is_equal_approx(expected.g, 0.01)
	assert_float(color.b).is_equal_approx(expected.b, 0.01)


func test_objectives_are_pickable_bodies_with_index_meta() -> void:
	var overlay := _overlay()
	overlay.update_objectives([Vector3(0, 0, 0), Vector3(0.1, 0, 0.1)])

	assert_int(overlay.objective_meshes.size()).is_equal(2)
	var token: Node3D = overlay.objective_meshes[0]
	assert_bool(token is StaticBody3D).is_true()
	assert_bool(token.is_in_group("selectable")).is_true()
	assert_bool(token.is_in_group("objective")).is_true()
	assert_int(int(token.get_meta("objective_index"))).is_equal(0)
	# Has a collision shape so the raycast picker can hit it
	var has_shape := false
	for child in token.get_children():
		if child is CollisionShape3D:
			has_shape = true
	assert_bool(has_shape).is_true()


func test_update_objectives_applies_initial_owners() -> void:
	var overlay := _overlay()
	overlay.update_objectives([Vector3(0, 0, 0), Vector3(0.1, 0, 0.1)], [0, 2])

	assert_int(overlay.get_objective_owner(0)).is_equal(0)
	assert_int(overlay.get_objective_owner(1)).is_equal(2)
	# Objective 1 fill shows player 2's color
	var fill := overlay.objective_meshes[1].get_node_or_null("Fill") as MeshInstance3D
	var mat := fill.material_override as StandardMaterial3D
	var expected: Color = OPRArmyManager.PLAYER_COLORS[2]
	assert_float(mat.albedo_color.r).is_equal_approx(expected.r, 0.01)


func test_set_objective_owner_recolors_in_place() -> void:
	var overlay := _overlay()
	overlay.update_objectives([Vector3(0, 0, 0)])
	assert_int(overlay.get_objective_owner(0)).is_equal(0)

	overlay.set_objective_owner(0, 3)

	assert_int(overlay.get_objective_owner(0)).is_equal(3)
	var fill := overlay.objective_meshes[0].get_node_or_null("Fill") as MeshInstance3D
	var mat := fill.material_override as StandardMaterial3D
	var expected: Color = OPRArmyManager.PLAYER_COLORS[3]
	assert_float(mat.albedo_color.g).is_equal_approx(expected.g, 0.01)


func test_owner_list_round_trips_for_saving() -> void:
	var overlay := _overlay()
	overlay.update_objectives([Vector3(0, 0, 0), Vector3(0.1, 0, 0.1), Vector3(0.2, 0, 0.2)])
	overlay.set_objective_owner(1, 4)

	var owners: Array = overlay.get_objective_owners()
	assert_array(owners).is_equal([0, 4, 0])


func test_set_objective_owner_ignores_out_of_range() -> void:
	var overlay := _overlay()
	overlay.update_objectives([Vector3(0, 0, 0)])
	overlay.set_objective_owner(5, 2)  # no crash, no change
	assert_int(overlay.get_objective_owner(0)).is_equal(0)


# ===== capture menu (issue #70: must offer players on host, guest, AND after reconnect) =====
# The owner choices are derived from RadialMenuController, which used to read only the
# import-only `armies` dict — empty on a joined/reconnected peer, leaving "Neutral" as the
# only option so objectives could not be seized. They now come from the restored game_units.

func _controller_with_player_units(player_ids: Array, fill_armies: bool = false) -> RadialMenuController:
	var controller := auto_free(RadialMenuController.new()) as RadialMenuController
	var army_manager := auto_free(OPRArmyManager.new()) as OPRArmyManager
	var i := 0
	for pid in player_ids:
		var unit := GameUnit.new()
		unit.unit_id = "u%d" % i
		unit.unit_properties = {"player_id": pid}
		army_manager.game_units[unit.unit_id] = unit
		if fill_armies and pid > 0:
			army_manager.armies[pid] = null  # presence only; the menu reads keys
		i += 1
	controller.army_manager = army_manager
	return controller


func _menu_ids(controller: RadialMenuController) -> Array:
	var ids: Array = []
	for item in controller._create_objective_menu():
		ids.append(item.id)
	return ids


func test_capture_menu_lists_players_from_game_units_when_armies_empty() -> void:
	# Guest / reconnected peer: armies dict is empty, only game_units were restored.
	var controller := _controller_with_player_units([1, 2])
	assert_array(_menu_ids(controller)).is_equal(["set_owner_0", "set_owner_1", "set_owner_2"])


func test_capture_menu_dedupes_sorts_and_skips_unassigned() -> void:
	# Multiple units per player, out of order, plus an unassigned (player_id 0) unit.
	var controller := _controller_with_player_units([2, 1, 2, 0])
	assert_array(_menu_ids(controller)).is_equal(["set_owner_0", "set_owner_1", "set_owner_2"])
	assert_array(controller._active_player_ids()).is_equal([1, 2])


func test_capture_menu_unions_armies_and_game_units() -> void:
	# Host: armies holds the locally-imported player, game_units add the synced opponent.
	var controller := _controller_with_player_units([2], true)  # armies{2}, game_units{2}
	controller.army_manager.armies[1] = null                    # armies-only player 1
	assert_array(controller._active_player_ids()).is_equal([1, 2])
