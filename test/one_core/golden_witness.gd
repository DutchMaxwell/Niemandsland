extends SceneTree
## P4.0-10 golden witness CLI. Boots the real main.tscn with the one-core kill switch OFF (the OLD table path),
## runs the shooting-volley grid through GoldenWitness, and either writes the committed fixtures or compares a run
## against them.
##
## Capture (writes res://test/fixtures/one_core/golden_shoot_volley.json):
##   godot --headless -s res://test/one_core/golden_witness.gd -- --capture
## Check (exit 0 green, exit 1 on any difference; every difference is printed as GOLDEN-WITNESS-DIFF):
##   godot --headless -s res://test/one_core/golden_witness.gd -- --check
##
## The same compare runs in CI through test/one_core/golden_witness_test.gd.
##
## NOTE the deliberate indirection: the harness is loaded only AFTER main.tscn is up. A `-s` script is compiled
## before the project's autoloads exist, so a compile-time dependency on the game's classes (object_manager.gd reads
## the GraphicsSettings autoload) would fail here even though the game itself is fine.

const HARNESS_PATH := "res://test/one_core/golden_witness_harness.gd"
const MAX_BOOT_FRAMES := 1800


func _initialize() -> void:
	var args: Array = OS.get_cmdline_user_args() + OS.get_cmdline_args()
	_run.call_deferred("--capture" in args)


func _run(capture: bool) -> void:
	ProjectSettings.set_setting("niemandsland/harness_mode", true)
	# Set before any door asks; the harness clears the once-cached decision after it is loaded.
	OS.set_environment("NML_ONE_CORE_ACTIVATION", "0")
	change_scene_to_file("res://scenes/main.tscn")
	var main := await _boot()
	if main == null:
		printerr("GOLDEN-WITNESS-FAIL: main.tscn never finished booting")
		quit(1)
		return
	var harness: Script = load(HARNESS_PATH)
	if harness == null:
		printerr("GOLDEN-WITNESS-FAIL: cannot load %s" % HARNESS_PATH)
		quit(1)
		return
	if not harness.configure(main):
		printerr("GOLDEN-WITNESS-FAIL: the one-core flag is ON — this harness must record the old table path")
		quit(1)
		return
	var got: Dictionary = await harness.capture(main)
	if capture:
		var rc: int = int(harness.save_fixture(got))
		if rc != OK:
			printerr("GOLDEN-WITNESS-FAIL: could not write %s (%d)" % [harness.FIXTURE_PATH, rc])
			quit(1)
			return
		printerr("GOLDEN-WITNESS: wrote %s (%d cases, epoch %d)" % [
			ProjectSettings.globalize_path(harness.FIXTURE_PATH), (got["cases"] as Array).size(),
			int((got["provenance"] as Dictionary)["epoch"])])
		quit(0)
		return
	var want: Dictionary = harness.load_fixture()
	if want.is_empty():
		printerr("GOLDEN-WITNESS-FAIL: %s is missing or unreadable" % harness.FIXTURE_PATH)
		quit(1)
		return
	var problems: Array = harness.compare(want, got)
	printerr("GOLDEN-WITNESS: %s" % harness.describe_provenance(want, got))
	for p in problems:
		printerr("GOLDEN-WITNESS-DIFF: %s" % str(p))
	if problems.is_empty():
		printerr("GOLDEN-WITNESS-OK: %d cases match the fixture" % (got["cases"] as Array).size())
		quit(0)
		return
	printerr("GOLDEN-WITNESS-FAIL: %d difference(s) against %s" % [problems.size(), harness.FIXTURE_PATH])
	quit(1)


func _boot() -> Node:
	for _i in MAX_BOOT_FRAMES:
		await process_frame
		if current_scene != null and current_scene.get("opr_army_manager") != null:
			return current_scene
	return null
