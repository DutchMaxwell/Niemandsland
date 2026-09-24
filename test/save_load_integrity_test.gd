extends GdUnitTestSuite
## Load-path integrity, through the real SaveManager code.
##  Counter: load_game() must restore the saved object counter (clear_all_objects zeroes it), otherwise
##       ids minted after a load collide with the loaded models' ids.
##  Overlay: a save whose objective / wall / placed-object lists are EMPTY must still clear the overlay,
##       otherwise the previous table's objectives, walls and trees survive the load.

const ObjectManagerScript = preload("res://scripts/object_manager.gd")
const OverlayScript = preload("res://scripts/terrain_overlay.gd")
const SAVE_PATH := "user://save_load_integrity_test.nml"


func after_test() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


## Editor stand-in with the fields _deserialize_map_layout writes plus the world-space objective
## conversion the load reads back (1" -> metres, like map_layout.gd get_objectives_for_overlay).
func _mock_editor() -> Control:
	var script := GDScript.new()
	script.source_code = "extends Control\n" + \
		"var grid_cells = {}\n" + \
		"var grid_rotation_degrees := 0.0\n" + \
		"var deployment_type := 0\n" + \
		"var table_size_feet := Vector2(6, 4)\n" + \
		"var custom_zone_vertices_p1: Array[Vector2] = []\n" + \
		"var custom_zone_vertices_p2: Array[Vector2] = []\n" + \
		"var mission_objectives: Array[Vector2] = []\n" + \
		"var wall_segments: Array[Dictionary] = []\n" + \
		"var placed_objects: Array[Dictionary] = []\n" + \
		"func get_objectives_for_overlay() -> Array[Vector3]:\n" + \
		"\tvar out: Array[Vector3] = []\n" + \
		"\tfor p in mission_objectives:\n" + \
		"\t\tout.append(Vector3(p.x * 0.0254, 0.0, p.y * 0.0254))\n" + \
		"\treturn out\n"
	script.reload()
	var editor := Control.new()
	editor.set_script(script)
	return editor


func test_load_game_restores_the_object_counter_so_new_ids_do_not_collide() -> void:
	var om: Node3D = auto_free(ObjectManagerScript.new())
	add_child(om)
	var save_manager: SaveManager = auto_free(SaveManager.new())
	add_child(save_manager)
	save_manager.object_manager = om

	# A session that already minted five ids (OPR models of slot 1 carry 1_000_001..1_000_005).
	om._object_counter = 5
	assert_int(save_manager.save_game(SAVE_PATH)).is_equal(OK)

	var err: int = await save_manager.load_game(SAVE_PATH)
	assert_int(err).is_equal(OK)

	# load_game() empties the table (counter -> 0). The saved counter has to come back ...
	assert_int(om._object_counter).is_equal(5)
	# ... so the next id an army mints continues after the loaded ones instead of reusing slot*1e6 + 1.
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.object_manager = om
	var minted: int = army._next_owned_net_id(1)
	assert_int(minted).is_equal(OPRArmyManager.OPR_NET_ID_SLOT_STRIDE + 6)


func test_load_of_a_save_with_empty_lists_clears_the_previous_overlay() -> void:
	var save_manager: SaveManager = auto_free(SaveManager.new())
	add_child(save_manager)
	var editor := _mock_editor()
	add_child(editor)
	save_manager.map_layout_editor = editor
	# Not added to the tree (like terrain_overlay_test.gd): _ready would start the panel downloads.
	var overlay: Node3D = auto_free(OverlayScript.new())
	save_manager.terrain_overlay = overlay

	# The table the player is looking at BEFORE the load: two objectives, one wall, one tree.
	overlay.update_objectives([Vector3(0.2, 0.0, 0.1), Vector3(-0.2, 0.0, -0.1)], [1, 2])
	overlay.update_wall_models([{
		"edge_cell": Vector2i(20, 20), "edge_side": 0, "wall_key": "", "length_inches": 3.0,
		"sub_position": 0, "role": "full", "taper_dir": -1,
	}], Vector2(6, 4), 0.0)
	overlay.update_placed_objects([{
		"object_key": "", "cell": Vector2i(20, 20), "offset": Vector2(0.5, 0.5), "object_type": "tree",
	}], Vector2(6, 4), 0.0)
	assert_int(overlay.get_objectives().size()).is_equal(2)
	assert_int(overlay._last_wall_segments.size()).is_equal(1)
	assert_int(overlay._last_objects.size()).is_equal(1)

	# Load a save that has NO objectives, NO walls and NO placed objects.
	save_manager._deserialize_map_layout({"size_feet": [6, 4]}, Vector2(6, 4))

	assert_int(overlay.get_objectives().size()).is_equal(0)
	assert_int(overlay.get_objective_owners().size()).is_equal(0)
	assert_int(overlay._last_wall_segments.size()).is_equal(0)
	assert_int(overlay._last_objects.size()).is_equal(0)
