extends GdUnitTestSuite

const CameraScript := preload("res://scripts/camera_controller.gd")
var _tier := GraphicsSettings.QualityPreset.MEDIUM
var _tilt := true
var _pivot: Node3D
var _camera: Camera3D


func before_test() -> void:
	_tier = GraphicsSettings.current_preset
	_tilt = GraphicsSettings.tilt_shift
	GraphicsSettings.tilt_shift = true
	_pivot = auto_free(CameraScript.new())
	_camera = Camera3D.new()
	_camera.name = "Camera3D"
	_pivot.add_child(_camera)
	add_child(_pivot)
	_pivot.set_process(false)


func after_test() -> void:
	GraphicsSettings.current_preset = _tier
	GraphicsSettings.tilt_shift = _tilt


func _view(tier: int, distance: float) -> CameraAttributesPractical:
	GraphicsSettings.current_preset = tier as GraphicsSettings.QualityPreset
	_pivot.set_zoom(distance)
	_pivot.call("_apply_camera_transform")
	return _camera.attributes as CameraAttributesPractical


func test_normal_table_view_has_blur_with_a_sharp_band_at_the_table() -> void:
	for distance in [0.75, 1.64, 2.09, 2.3]:
		var attributes := _view(3, distance)
		assert_float(attributes.dof_blur_amount).is_greater(0.05)
		assert_float(attributes.dof_blur_near_distance).is_less(distance)
		assert_float(attributes.dof_blur_far_distance).is_greater(distance)
		assert_float(attributes.dof_blur_far_distance).is_less(distance * 1.3)


func test_low_keeps_the_original_fixed_band_and_zero_overview_blur() -> void:
	var attributes := _view(1, 2.09)
	assert_float(attributes.dof_blur_amount).is_zero()
	assert_float(attributes.dof_blur_far_distance).is_equal_approx(0.55, 0.0001)
	attributes = _view(1, 0.35)
	assert_float(attributes.dof_blur_amount).is_equal_approx(0.045, 0.0001)


func test_toggle_off_removes_attributes_and_preset_change_recomputes_without_camera_motion() -> void:
	_view(3, 2.09)
	_pivot.set_tilt_shift_enabled(false)
	assert_object(_camera.attributes).is_null()
	_pivot.set_tilt_shift_enabled(true)
	assert_float(_camera.attributes.dof_blur_amount).is_greater(0.09)
	GraphicsSettings.current_preset = GraphicsSettings.QualityPreset.LOW
	GraphicsSettings.settings_applied.emit("Low")
	assert_float(_camera.attributes.dof_blur_amount).is_zero()


func test_selection_tracks_view_depth_and_deleted_target_falls_back_to_table() -> void:
	_view(3, 2.09)
	var target := Node3D.new()
	add_child(target)
	target.position = Vector3(0.0, 0.1, 0.5)
	assert_bool(_pivot.has_method("_on_focus_selection")).is_true()
	if not _pivot.has_method("_on_focus_selection"):
		target.free()
		return
	_pivot.call("_on_focus_selection", [target] as Array[Node3D])
	for height in [0.1, 0.3]:
		target.position.y = height
		_pivot.call("_update_tilt_shift")
		var a := _camera.attributes as CameraAttributesPractical
		var focal_depth := (a.dof_blur_near_distance + a.dof_blur_far_distance) * 0.5
		assert_float(focal_depth).is_equal_approx(-_camera.to_local(target.global_position).z, 0.0001)
	target.free()
	_pivot.call("_update_tilt_shift")
	var restored := _camera.attributes as CameraAttributesPractical
	assert_float((restored.dof_blur_near_distance + restored.dof_blur_far_distance) * 0.5).is_equal_approx(-_camera.to_local(Vector3(0,0.025,0)).z, 0.0001)
