extends GdUnitTestSuite
## A free shelf piece may not be dropped onto painted grid terrain (maintainer D2, 04.10.): there the grid wins every
## rules lookup, so the piece would silently lose its own type. ObjectManager puts such a piece back where the drag
## started and says so; a drop on clear table stays where it landed.

const OverlayScript := preload("res://scripts/terrain_overlay.gd")
const IN2M := 0.0254

var _refused: Array = []


func _setup() -> ObjectManager:
	var om: ObjectManager = auto_free(ObjectManager.new())
	add_child(om)
	var overlay: Node3D = auto_free(OverlayScript.new())
	overlay.grid_cells[overlay.world_to_cell(Vector3.ZERO)] = TerrainRules.TerrainType.FOREST   # one painted cell
	om.terrain_overlay = overlay
	om.terrain_drop_refused.connect(func(nodes: Array) -> void: _refused.append_array(nodes))
	return om


func _drag(om: ObjectManager, start: Vector3, drop: Vector3) -> Node3D:
	var solid := om.spawn_sandbox_terrain("blocker_6x3", ObjectManager.SandboxPropKind.BLOCKER, start, false, 7401)
	om._selected_objects = [solid]
	om._drag_start_positions[solid] = start
	om._drag_start_rotations[solid] = solid.rotation.y
	solid.global_position = drop
	solid.rotation.y = deg_to_rad(30.0)
	om._refuse_drops_on_painted_terrain()
	return solid


func test_a_drop_overlapping_a_painted_cell_goes_back_to_its_start() -> void:
	_refused.clear()
	var start := Vector3(0.6, 0.0, 0.3)
	var solid := _drag(_setup(), start, Vector3(3.5 * IN2M, 0.0, 0.0))   # its footprint now reaches the painted cell
	assert_vector(solid.global_position).is_equal_approx(start, Vector3.ONE * 0.0001)
	assert_float(solid.rotation.y).is_equal_approx(0.0, 0.0001)
	assert_array(_refused).contains_exactly([solid])


func test_a_drop_on_clear_table_stays() -> void:
	_refused.clear()
	var drop := Vector3(-0.5, 0.0, -0.3)
	var solid := _drag(_setup(), Vector3(0.6, 0.0, 0.3), drop)
	assert_vector(solid.global_position).is_equal_approx(drop, Vector3.ONE * 0.0001)
	assert_array(_refused).is_empty()
