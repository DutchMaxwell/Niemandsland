extends GdUnitTestSuite
## MOVE_GAPS D2 (P3 step 71, flag-free): with "Enforce Movement Limit" on, the strict drag cap
## shrinks to 6" as soon as a dragged model's path touches Difficult terrain, and the readout names
## it; Strider and Flying units ignore it. Drives the REAL ObjectManager drag (_start_dragging /
## _update_drag) through a top-down camera over a stub overlay with a FOREST strip at x = 4"..7".

const INCH := 0.0254


## Rush band 12": a 10" Rush drag is legal in the open.
class _BandStub extends Node:
	func bands_for_model(_node) -> Dictionary:
		return {"advance": 6, "rush": 12}


## The drag tint's sampler: FOREST (Difficult) in a strip across the whole lane, open elsewhere.
class _StripOverlay extends Node3D:
	func get_terrain_at_world_position(p: Vector3) -> int:
		return TerrainRules.TerrainType.FOREST if p.x >= 4.0 * INCH and p.x <= 7.0 * INCH \
			else TerrainRules.TerrainType.NONE


var _om: ObjectManager
var _was_enforced: bool
var _reasons: Array = []


func before_test() -> void:
	_was_enforced = GraphicsSettings.enforce_movement_limit
	GraphicsSettings.enforce_movement_limit = true
	var camera: Camera3D = auto_free(Camera3D.new())
	add_child(camera)
	camera.look_at_from_position(Vector3(0.0, 0.6, 0.001), Vector3.ZERO)
	camera.current = true
	_om = auto_free(ObjectManager.new())
	add_child(_om)
	var bands: Node = auto_free(_BandStub.new())
	add_child(bands)
	_om.movement_range_controller = bands
	_om.terrain_overlay = auto_free(_StripOverlay.new())
	_om.set_movement_cap(ObjectManager.MovementCap.RUSH)
	_reasons.clear()
	_om.movement_capped.connect(func(_c: float, _cap: float, _dry: bool, reason: String) -> void:
		_reasons.append(reason))
	# The camera's transform only reaches unproject_position after one frame.
	await get_tree().process_frame


func after_test() -> void:
	GraphicsSettings.enforce_movement_limit = _was_enforced


## One real model at the origin whose unit carries `rules`.
func _model(rules: Array) -> Node3D:
	var unit := GameUnit.new()
	unit.unit_properties = {"special_rules": rules}
	var body: Node3D = auto_free(Node3D.new())
	add_child(body)
	body.add_to_group("miniature")
	var model := ModelInstance.new()
	model.unit = unit
	model.node = body
	body.set_meta("model_instance", model)
	body.set_meta("game_unit", unit)
	return body


func _screen(wx: float, wz: float) -> Vector2:
	return get_viewport().get_camera_3d().unproject_position(Vector3(wx, 0.0, wz))


## Drags `body` from the origin 10" along `dir` in half-inch cursor steps; returns how far
## (inches, straight line) the model got.
func _drag_ten_inches(body: Node3D, dir: Vector2) -> float:
	_om._selected_objects.append(body)
	_om._start_dragging(_screen(0.0, 0.0))
	assert_bool(_om._is_dragging).is_true()
	for i in range(1, 21):
		var p := dir * (0.5 * float(i) * INCH)
		_om._update_drag(_screen(p.x, p.y))
	return Vector2(body.global_position.x, body.global_position.z).length() / INCH


func test_a_rush_through_difficult_terrain_stops_at_six_inches() -> void:
	var got := _drag_ten_inches(_model([]), Vector2(1, 0))
	assert_float(got).override_failure_message(
			"a 10\" Rush through the forest strip got %.2f\", expected the 6\" Difficult cap" % got) \
		.is_equal_approx(6.0, 0.05)
	assert_float(float(_om._strict_cap_meters) / INCH).is_equal_approx(6.0, 0.01)
	assert_str(str(_reasons.back())).contains("Difficult terrain")


func test_a_strider_unit_rushes_ten_inches_through_difficult_terrain() -> void:
	var got := _drag_ten_inches(_model(["Strider"]), Vector2(1, 0))
	assert_float(got).override_failure_message(
			"a Strider unit ignores Difficult terrain but got %.2f\" of a 10\" Rush" % got) \
		.is_equal_approx(10.0, 0.05)
	assert_str(str(_reasons.back())).not_contains("Difficult terrain")


func test_a_rush_that_never_touches_difficult_terrain_goes_ten_inches() -> void:
	var got := _drag_ten_inches(_model([]), Vector2(0, 1))
	assert_float(got).override_failure_message(
			"a 10\" Rush in the open got %.2f\"" % got) \
		.is_equal_approx(10.0, 0.05)
	assert_float(float(_om._strict_cap_meters) / INCH).is_equal_approx(12.0, 0.01)
