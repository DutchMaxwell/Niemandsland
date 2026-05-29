extends GdUnitTestSuite
## Smoke tests for the cinematic intro (TronIntro). Verifies it instantiates with its
## shaders, runs play_intro on a mock scene without crashing, and cleans up fully on skip.

const TronIntroScript = preload("res://scripts/tron_intro.gd")


## Build a minimal stand-in for the Main scene with the nodes play_intro expects.
func _mock_main() -> Node3D:
	var main: Node3D = auto_free(Node3D.new())
	add_child(main)

	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	world_env.environment = env
	main.add_child(world_env)

	var table := Node3D.new()
	table.name = "Table"
	main.add_child(table)

	var pivot := Node3D.new()
	pivot.name = "CameraPivot"
	main.add_child(pivot)
	var cam := Camera3D.new()
	cam.name = "Camera3D"
	pivot.add_child(cam)

	var ui := CanvasLayer.new()
	ui.name = "UI"
	main.add_child(ui)
	var hud := Control.new()
	hud.name = "HUD"
	ui.add_child(hud)

	return main


func test_instantiates_with_shaders() -> void:
	var intro = auto_free(TronIntroScript.new())
	assert_object(intro).is_not_null()


func test_look_xform_points_at_target() -> void:
	var intro: Node3D = auto_free(TronIntroScript.new())
	add_child(intro)
	var xform: Transform3D = intro._look_xform(Vector3(0, 5, 10))
	# Forward is -Z; from above/behind it should point down toward the table centre.
	var forward := -xform.basis.z
	assert_float(forward.y).is_less(0.0)
	assert_float(forward.z).is_less(0.0)


func test_play_intro_then_skip_cleans_up() -> void:
	var main := _mock_main()
	var intro: Node3D = auto_free(TronIntroScript.new())
	main.add_child(intro)

	intro.play_intro(main)
	assert_bool(intro._is_playing).is_true()
	# Holo grid + camera + IMAX letterbox bars were created.
	assert_object(intro.get_node_or_null("HoloGrid")).is_not_null()
	assert_object(intro.get_node_or_null("IntroCamera")).is_not_null()
	assert_object(intro.top_bar).is_not_null()
	assert_object(intro.bottom_bar).is_not_null()

	await await_idle_frame()
	intro._skip_intro()
	assert_bool(intro._is_playing).is_false()

	# Skip restores the gameplay scene immediately.
	assert_bool(main.get_node("Table").visible).is_true()
