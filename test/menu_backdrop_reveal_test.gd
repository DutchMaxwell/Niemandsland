extends GdUnitTestSuite
## Main-menu backdrop reveal (brief menuload, 23.09.). The live biome scene takes seconds to build (a cold start
## 30-40 s) and used to show every step of it: placeholder walls and trees, miniatures popping in one by one, the
## biome textures landing last and the placeholder models swapped after that. It now stays covered by a still of
## the finished scene until the build is complete, then crossfades; the menu buttons work all along.

const POSTER := "res://assets/ui/menu_backdrop/%s.res"


func test_every_menu_biome_has_a_wide_backdrop_still() -> void:
	for biome in MenuDiorama.Battlefield.BIOMES:
		assert_bool(ResourceLoader.exists(POSTER % biome)) \
			.override_failure_message("no backdrop still for %s" % biome).is_true()
		if not ResourceLoader.exists(POSTER % biome):
			continue
		var still: Texture2D = load(POSTER % biome)
		# Wider than 21:9: the menu fills the window height and crops the sides, as its camera keeps its height.
		assert_float(float(still.get_width()) / still.get_height()).is_greater_equal(2.3)


func test_live_backdrop_stays_covered_until_built_then_fades_in(timeout := 240000) -> void:
	var menu: Control = auto_free(load("res://scenes/startup_menu.tscn").instantiate())
	var diorama: MenuDiorama = menu.get_node("Diorama")
	# A test is neither the current scene nor on a display: force the live build.
	diorama.mode = MenuDiorama.Mode.FORCED
	var built := [false]
	diorama.diorama_ready.connect(func() -> void: built[0] = true)
	add_child(menu)
	await get_tree().process_frame
	assert_float(_cover(diorama)) \
		.override_failure_message("the live backdrop is not covered while it builds").is_equal(1.0)
	assert_that(diorama.get("_poster")).is_same(load(POSTER % diorama.biome))

	# The menu reacts while the backdrop builds: a real click on "Prepare a new table".
	await _click(menu.start_battle_btn)
	assert_bool(built[0]).override_failure_message("the backdrop was already built — the test proves nothing").is_false()
	assert_object(menu._table_setup).override_failure_message("the menu button did not react during loading").is_not_null()
	if menu._table_setup != null:
		menu._table_setup._on_close()

	var uncovered_frames := 0
	var deadline := Time.get_ticks_msec() + 200000
	while not built[0] and Time.get_ticks_msec() < deadline:
		if _cover(diorama) != 1.0:
			uncovered_frames += 1
		await get_tree().process_frame
	assert_bool(built[0]).override_failure_message("the backdrop never finished building").is_true()
	assert_int(uncovered_frames).override_failure_message("the half-built backdrop showed through").is_equal(0)

	# Finished: a crossfade to the live scene, not a cut.
	var fade_start := Time.get_ticks_msec()
	while _cover(diorama) > 0.0 and Time.get_ticks_msec() < fade_start + 5000:
		await get_tree().process_frame
	assert_float(_cover(diorama)).is_equal(0.0)
	assert_int(Time.get_ticks_msec() - fade_start).is_greater_equal(500)


## The cover's opacity; -1 where the diorama has no cover at all (the old menu).
func _cover(diorama: Node) -> float:
	var alpha: Variant = diorama.get("_cover_alpha")
	return -1.0 if alpha == null else float(alpha)


## A real click through the viewport's GUI pipeline. push_input takes SCREEN coordinates; the button rect is in
## canvas coordinates (headless window 1280x720, canvas 1920x1080) — see test/e2e/e2e_boot.gd click_canvas.
func _click(button: Button) -> void:
	var viewport := get_viewport()
	var at := viewport.get_screen_transform() * button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	viewport.push_input(motion)
	await get_tree().process_frame
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = at
		event.global_position = at
		viewport.push_input(event)
		await get_tree().process_frame
