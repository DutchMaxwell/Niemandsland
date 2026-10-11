extends GdUnitTestSuite
## Tilt-shift (cinematic DOF) rule: on every preset the table is sharp while zoomed out,
## and the blur only fades in as the camera moves in close. Medium+ peaks weaker than Low.

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


func test_the_table_is_sharp_when_zoomed_out_on_every_preset() -> void:
	# At the normal play and overview distance the frame stays clean. The old Medium+ path
	# kept a band and blurred here (0.095 at play, 0.11 at overview); it must be gone.
	for tier in [1, 2, 3]:
		for distance in [0.95, 1.64, 2.09, 2.3, 10.0]:
			assert_float(_view(tier, distance).dof_blur_amount) \
				.override_failure_message("tier %d at %.2f m" % [tier, distance]).is_zero()


func test_blur_fades_in_as_the_camera_moves_close() -> void:
	# Full at/below the near distance, then falling off to nothing by the far distance.
	for tier in [2, 3]:
		assert_float(_view(tier, 0.35).dof_blur_amount).is_equal_approx(0.035, 0.0001)
		assert_float(_view(tier, 0.06).dof_blur_amount).is_equal_approx(0.035, 0.0001)
		var mid := _view(tier, 0.6).dof_blur_amount
		assert_float(mid).is_greater(0.0)
		assert_float(mid).is_less(0.035)


func test_medium_and_high_peak_weaker_than_low_which_is_unchanged() -> void:
	assert_float(_view(2, 0.2).dof_blur_amount).is_equal_approx(0.035, 0.0001)
	assert_float(_view(3, 0.2).dof_blur_amount).is_equal_approx(0.035, 0.0001)
	assert_float(_view(1, 0.2).dof_blur_amount).is_equal_approx(0.045, 0.0001)


func test_low_keeps_the_fixed_band_and_overview_stays_clean() -> void:
	var attributes := _view(1, 2.09)
	assert_float(attributes.dof_blur_amount).is_zero()
	assert_float(attributes.dof_blur_near_distance).is_equal_approx(0.10, 0.0001)
	assert_float(attributes.dof_blur_far_distance).is_equal_approx(0.55, 0.0001)


func test_toggle_off_removes_attributes_and_preset_change_recomputes() -> void:
	_view(3, 0.2)
	_pivot.set_tilt_shift_enabled(false)
	assert_object(_camera.attributes).is_null()
	_pivot.set_tilt_shift_enabled(true)
	assert_float(_camera.attributes.dof_blur_amount).is_equal_approx(0.035, 0.0001)
	GraphicsSettings.current_preset = GraphicsSettings.QualityPreset.LOW
	GraphicsSettings.settings_applied.emit("Low")
	assert_float(_camera.attributes.dof_blur_amount).is_equal_approx(0.045, 0.0001)
