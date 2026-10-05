extends GdUnitTestSuite
## A stationary hover follows live quality changes without replacing its material.

const ObjectManagerScript := preload("res://scripts/object_manager.gd")
var _preset_before: int


func before_test() -> void:
	_preset_before = GraphicsSettings.current_preset


func after_test() -> void:
	GraphicsSettings.apply_preset(_preset_before)
	RenderingServer.emit_signal("frame_post_draw")
	RenderingServer.emit_signal("frame_post_draw")


func test_new_hover_uses_the_current_quality_without_changing_its_colour() -> void:
	for tier in [0, 1, 2, 3, 4]:
		GraphicsSettings.apply_preset(tier)
		var glow := HoverGlow.new()
		assert_float(glow._material.grow_amount).is_equal_approx(0.003 if tier < 2 else 0.001, 0.00001)
		assert_float(glow._material.albedo_color.a).is_equal_approx(HoverGlow.TINT_ALPHA, 0.0001)
		assert_str(glow._material.emission.to_html()).is_equal(HoverGlow.COLOR.to_html())


func test_live_hover_round_trip_keeps_overlays_and_restores_them_on_clear() -> void:
	var manager: Node = auto_free(ObjectManagerScript.new())
	add_child(manager)  # Real settings_applied connection; no simulated callback.
	var target: Node3D = auto_free(Node3D.new())
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	target.add_child(mesh)
	var original := StandardMaterial3D.new()
	mesh.material_overlay = original
	manager._hover_glow.set_target(target)
	var overlay: StandardMaterial3D = mesh.material_overlay
	for tier in [3, 1, 4, 0, 2]:
		GraphicsSettings.apply_preset(tier)
		assert_object(mesh.material_overlay).is_same(overlay)
		assert_float(overlay.grow_amount).is_equal_approx(0.003 if tier < 2 else 0.001, 0.00001)
		assert_object(manager._hover_glow.get_target()).is_same(target)
	manager._hover_glow.clear()
	assert_object(mesh.material_overlay).is_same(original)
