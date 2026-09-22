extends GdUnitTestSuite
## Option (b), release 0925: a 0.3.12.0 client's Windows updater swaps ONLY Niemandsland.exe, so the first
## 0.3.13 start has no nml_core_godot.dll and NACHTMAHR silently plays the tree. CoreSelfHeal restores the
## DLL from the release that updater left in user://_update/extracted and relaunches ONCE. These tests pin
## the decision and drive the boot entry point through a fake file-op seam — no Windows, no real files.

const EXE := "C:/Games/Niemandsland/Niemandsland.exe"
const BUILD := "0.3.13.0-alpha+abc1234"


func test_decide_heals_only_a_windows_export_without_core_and_only_once() -> void:
	assert_int(CoreSelfHeal.decide(false, false, false, true)).is_equal(CoreSelfHeal.Action.NONE)    # not Windows
	assert_int(CoreSelfHeal.decide(true, true, false, true)).is_equal(CoreSelfHeal.Action.NONE)      # core fine
	assert_int(CoreSelfHeal.decide(true, false, false, true)).is_equal(CoreSelfHeal.Action.HEAL)
	assert_int(CoreSelfHeal.decide(true, false, false, false)).is_equal(CoreSelfHeal.Action.NO_SOURCE)
	assert_int(CoreSelfHeal.decide(true, false, true, true)).is_equal(CoreSelfHeal.Action.GIVE_UP)   # 2nd failure
	assert_int(CoreSelfHeal.decide(true, true, true, false)).is_equal(CoreSelfHeal.Action.HEALED)


func test_heal_copies_the_staged_dll_next_to_the_exe_marks_the_build_and_relaunches_once() -> void:
	var ops := FakeOps.new(true)
	assert_int(CoreSelfHeal.run(ops, true, false)).is_equal(CoreSelfHeal.Action.HEAL)
	assert_array(ops.copies).is_equal([[FakeOps.staged(CoreSelfHeal.DLL_NAME), "C:/Games/Niemandsland/nml_core_godot.dll"]])
	assert_int(ops.relaunches).is_equal(1)
	assert_str(ops.marker).is_equal(BUILD)


func test_second_start_still_without_core_gives_up_and_never_relaunches_again() -> void:
	var ops := FakeOps.new(true)
	ops.marker = BUILD
	assert_int(CoreSelfHeal.run(ops, true, false)).is_equal(CoreSelfHeal.Action.GIVE_UP)
	assert_array(ops.copies).is_empty()
	assert_int(ops.relaunches).is_equal(0)


func test_a_staged_release_of_another_build_is_never_used() -> void:
	var ops := FakeOps.new(false)   # staged exe differs from the running one
	assert_int(CoreSelfHeal.run(ops, true, false)).is_equal(CoreSelfHeal.Action.NO_SOURCE)
	assert_array(ops.copies).is_empty()
	assert_int(ops.relaunches).is_equal(0)
	assert_str(ops.marker).is_empty()


func test_a_failed_copy_gives_up_without_a_relaunch() -> void:
	var ops := FakeOps.new(true)
	ops.copy_result = ERR_FILE_CANT_WRITE
	assert_int(CoreSelfHeal.run(ops, true, false)).is_equal(CoreSelfHeal.Action.GIVE_UP)
	assert_int(ops.relaunches).is_equal(0)
	assert_str(ops.marker).is_equal(BUILD)


func test_the_start_after_a_heal_reports_success_once() -> void:
	var ops := FakeOps.new(true)
	ops.marker = BUILD
	assert_int(CoreSelfHeal.run(ops, true, true)).is_equal(CoreSelfHeal.Action.HEALED)
	assert_int(CoreSelfHeal.run(ops, true, true)).is_equal(CoreSelfHeal.Action.NONE)


func test_linux_and_editor_runs_touch_nothing() -> void:
	var ops := FakeOps.new(true)
	assert_int(CoreSelfHeal.run(ops, false, false)).is_equal(CoreSelfHeal.Action.NONE)
	assert_int(ops.calls).is_equal(0)


## The file-op seam CoreSelfHeal.run() drives: records every effect instead of touching disk.
class FakeOps:
	var marker := ""
	var copies: Array = []
	var relaunches := 0
	var copy_result := OK
	var calls := 0
	var _same_release := true

	func _init(same_release: bool) -> void:
		_same_release = same_release

	static func staged(file: String) -> String:
		return ProjectSettings.globalize_path(CoreSelfHeal.EXTRACT_DIR).path_join(file)

	func exe_path() -> String:
		calls += 1
		return EXE

	func build_id() -> String:
		calls += 1
		return BUILD

	func read_marker() -> String:
		calls += 1
		return marker

	func write_marker(text: String) -> void:
		calls += 1
		marker = text

	func file_exists(path: String) -> bool:
		calls += 1
		return path == staged(CoreSelfHeal.DLL_NAME) or path == staged("Niemandsland.exe")

	func sha256(path: String) -> String:
		calls += 1
		return "OTHER" if (path == staged("Niemandsland.exe") and not _same_release) else "SAME"

	func copy(src: String, dst: String) -> int:
		calls += 1
		copies.append([src, dst])
		return copy_result

	func relaunch() -> void:
		calls += 1
		relaunches += 1
