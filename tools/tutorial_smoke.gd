extends SceneTree
## Launch-smoke + evidence harness for the T0 tutorial. Boots the REAL main.tscn with the
## runtime tutorial flag (the same path the "Tutorial" menu button takes), waits for the
## TutorialDirector to appear on the live table, then drives it through SELECT -> MOVE -> ROLL,
## printing each step's live spotlight rect + instruction (proof the overlay targets the right
## thing). At each step it also tries a real viewport capture: under a windowing display driver
## (a physical display / xvfb) this writes tutorial_t0_step{1,2,3}.png; under `--headless` the
## renderer is the DUMMY driver (get_texture() == null) so it logs "NO-GPU" and carries on — the
## text trace is the headless evidence. Markers go to stderr (unbuffered). Run:
##   flatpak run org.godotengine.Godot --path <wt> --headless -s res://tools/tutorial_smoke.gd
##   (add `--socket=x11 --rendering-driver vulkan` WITHOUT `--headless` on a physical display for PNGs)

const SHOT_DIR := "user://tutorial_shots/"
const STEP_NAMES := ["INACTIVE", "SELECT", "MOVE", "ROLL", "DONE"]
const MAX_BOOT_FRAMES := 900
const SETTLE_FRAMES := 12


func _initialize() -> void:
	ProjectSettings.set_setting("niemandsland/tutorial_mode", true)
	_drive.call_deferred()


func _drive() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	change_scene_to_file("res://scenes/main.tscn")

	var director: TutorialDirector = await _await_director()
	if director == null:
		printerr("SMOKE-FAIL: TutorialDirector never appeared (main.tscn stalled or parse error)")
		quit(1)
		return
	printerr("SMOKE: TutorialDirector is live; unit spawned; entered %s" % STEP_NAMES[director.current_step])

	# Step 1 — SELECT (as begun). Then drive MOVE and ROLL via the same advance the real
	# signals trigger, capturing each. We stop before ROLL->DONE (which tears the tutorial down).
	if not await _snap(director, 1):
		quit(1)
		return
	director._advance()  # SELECT -> MOVE
	if not await _snap(director, 2):
		quit(1)
		return
	director._advance()  # MOVE -> ROLL
	if not await _snap(director, 3):
		quit(1)
		return

	printerr("SMOKE-OK: director drove SELECT->MOVE->ROLL on the live main.tscn; overlay + spotlight built each step")
	quit(0)


## Poll for the director node the game creates asynchronously after the (skipped) intro.
func _await_director() -> TutorialDirector:
	for _i in MAX_BOOT_FRAMES:
		await process_frame
		var scene := current_scene
		if scene == null:
			continue
		var node := scene.get_node_or_null("TutorialDirector")
		if node is TutorialDirector and node.current_step != TutorialDirector.Step.INACTIVE:
			return node
	return null


## Let the step settle, log its live spotlight geometry + instruction, and try a capture.
func _snap(director: TutorialDirector, index: int) -> bool:
	for _i in SETTLE_FRAMES:
		await process_frame
	var step_name: String = STEP_NAMES[director.current_step]
	var coach: TutorialCoachMark = director.get_node_or_null("TutorialCoachMark")
	if coach == null:
		printerr("SMOKE-FAIL: coach overlay missing at step %d (%s)" % [index, step_name])
		return false
	var rect: Rect2 = coach._target_rect
	var text: String = coach._label.text if coach._label != null else "<none>"
	printerr("SMOKE: step %d = %s | instruction=\"%s\" | spotlight=%s | overlay.visible=%s" % [
		index, step_name, text, str(rect), str(coach.visible)])
	_try_capture(index)
	return true


## Best-effort real capture. Non-null only under a windowing display driver.
func _try_capture(index: int) -> void:
	var vp := root.get_viewport()
	var tex := vp.get_texture() if vp != null else null
	var image: Image = tex.get_image() if tex != null else null
	if image == null:
		printerr("SMOKE: step %d capture skipped — NO-GPU (headless DUMMY renderer, get_texture()==null)" % index)
		return
	var path := "%stutorial_t0_step%d.png" % [SHOT_DIR, index]
	if image.save_png(path) == OK:
		printerr("SMOKE: step %d captured -> %s" % [index, ProjectSettings.globalize_path(path)])
	else:
		printerr("SMOKE: step %d capture failed to save" % index)
