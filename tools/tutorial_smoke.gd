extends SceneTree
## Launch-smoke + evidence harness for the guided tutorial (T1). Boots the REAL main.tscn
## with the runtime tutorial flags (the same path the TUTORIAL menu button takes, chapter
## "W1" so the whole track plays in order), verifies the bundled board produced real units,
## then walks EVERY lesson step: logs the live instruction, spotlight target key, mask flag
## and resolved spotlight rect, then completes the step through the same event entry the
## real signals use. At each lesson start it attempts a real viewport capture: under a
## windowing display driver this writes tutorial_t1_<lesson>.png; under --headless the
## DUMMY renderer has no texture, so it logs NO-GPU and the text trace is the evidence.
##
## The player's real user://tutorial.cfg is backed up before the walk (lesson completions
## write to it) and restored afterwards. Markers go to stderr (unbuffered). Run:
##   flatpak run org.godotengine.Godot --path <wt> --headless -s res://tools/tutorial_smoke.gd
##   (add `--socket=x11 --rendering-driver vulkan` WITHOUT `--headless` on a display for PNGs)

const SHOT_DIR := "user://tutorial_shots/"
const CFG_PATH := "user://tutorial.cfg"
const MAX_BOOT_FRAMES := 1800
const SETTLE_FRAMES := 8
const MAX_STEPS := 60  # watchdog: the tool track has 18 steps; anything near this is a loop

var _cfg_backup: PackedByteArray = PackedByteArray()
var _cfg_existed: bool = false


func _initialize() -> void:
	_backup_cfg()
	ProjectSettings.set_setting("niemandsland/tutorial_mode", true)
	ProjectSettings.set_setting("niemandsland/tutorial_lesson", "W1")  # full track, no assessment dialog
	_drive.call_deferred()


func _drive() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	change_scene_to_file("res://scenes/main.tscn")

	var director: TutorialDirector = await _await_director()
	if director == null:
		_restore_cfg()
		printerr("SMOKE-FAIL: TutorialDirector never appeared (main.tscn stalled or parse error)")
		quit(1)
		return

	var main := current_scene
	var army_manager: Node = main.get("opr_army_manager") if main != null else null
	var unit_count: int = army_manager.get("game_units").size() if army_manager != null else -1
	printerr("SMOKE: director live on the loaded board — %d game units on the table" % unit_count)
	if unit_count < 4:
		printerr("SMOKE-WARN: expected 4 units from the bundled board, found %d" % unit_count)

	var steps_walked := 0
	var last_lesson := ""
	# The director frees itself (via main) when the track finishes — a freed director
	# IS the success exit of this loop, so guard every access with is_instance_valid.
	while is_instance_valid(director) and director.flow != null and not director.flow.finished:
		if steps_walked >= MAX_STEPS:
			_restore_cfg()
			printerr("SMOKE-FAIL: step watchdog tripped (%d steps) — flow is looping" % steps_walked)
			quit(1)
			return
		for _i in SETTLE_FRAMES:
			await process_frame
		var lesson := director.flow.current_lesson()
		var step := director.flow.current_step()
		if lesson.is_empty() or step.is_empty():
			break
		var lesson_id := String(lesson.get("id", "?"))
		var coach: TutorialCoachMark = director.get_node_or_null("TutorialCoachMark")
		if coach == null:
			_restore_cfg()
			printerr("SMOKE-FAIL: coach overlay missing at %s/%s" % [lesson_id, String(step.get("id", "?"))])
			quit(1)
			return
		printerr("SMOKE: %s/%s | \"%s\" | target=%s mask=%s | spotlight=%s | overlay.visible=%s" % [
			lesson_id, String(step.get("id", "?")),
			String(step.get("text", "")),
			String(step.get("target", "-")), str(step.get("mask", false)),
			str(coach._target_rect) if coach._has_target else "banner",
			str(coach.visible)])
		if lesson_id != last_lesson:
			_try_capture("tutorial_t1_%s" % lesson_id.to_lower())
			last_lesson = lesson_id
		director._force_complete_current_step()
		steps_walked += 1
		await process_frame

	# The walk marks every lesson completed — verify persistence, then restore the player's file.
	var check := TutorialProgress.new()
	check.load_from_disk()
	var all_done := check.first_incomplete(TutorialFlow.ids(TutorialFlow.build_tool_track())).is_empty()
	_restore_cfg()
	if not all_done:
		printerr("SMOKE-FAIL: walk ended but tutorial.cfg does not show all lessons completed")
		quit(1)
		return
	printerr("SMOKE-OK: walked %d steps across W1-W6 on the live main.tscn; overlay + spotlight per step; cfg persisted + restored" % steps_walked)
	quit(0)


func _await_director() -> TutorialDirector:
	for _i in MAX_BOOT_FRAMES:
		await process_frame
		var scene := current_scene
		if scene == null:
			continue
		var node := scene.get_node_or_null("TutorialDirector")
		if node is TutorialDirector and node.flow != null and not node.flow.current_step().is_empty():
			return node
	return null


## Best-effort real capture. Non-null only under a windowing display driver.
func _try_capture(basename: String) -> void:
	var vp := root.get_viewport()
	var tex := vp.get_texture() if vp != null else null
	var image: Image = tex.get_image() if tex != null else null
	if image == null:
		printerr("SMOKE: capture %s skipped — NO-GPU (headless DUMMY renderer)" % basename)
		return
	var path := "%s%s.png" % [SHOT_DIR, basename]
	if image.save_png(path) == OK:
		printerr("SMOKE: captured -> %s" % ProjectSettings.globalize_path(path))
	else:
		printerr("SMOKE: capture %s failed to save" % basename)


func _backup_cfg() -> void:
	_cfg_existed = FileAccess.file_exists(CFG_PATH)
	if _cfg_existed:
		_cfg_backup = FileAccess.get_file_as_bytes(CFG_PATH)


func _restore_cfg() -> void:
	if _cfg_existed:
		var file := FileAccess.open(CFG_PATH, FileAccess.WRITE)
		if file != null:
			file.store_buffer(_cfg_backup)
			file.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG_PATH))
