extends RefCounted
class_name CoreSelfHeal
## Option (b) for release 0925 — NOT merged before a real Windows test.
## A 0.3.12.0 client's in-game updater swaps ONLY Niemandsland.exe on Windows, so the first 0.3.13 start
## has no nml_core_godot.dll: NmlCore is absent and NACHTMAHR silently plays the decision tree. That
## updater leaves the whole release in user://_update/extracted. When the staged exe is byte-identical to
## the running one (same release), its DLL is copied next to the exe and the game relaunches ONCE. The
## build is marked BEFORE the relaunch, so a second start without the core gives up: one line, the tree.

const DLL_NAME := "nml_core_godot.dll"
const EXTRACT_DIR := "user://_update/extracted"
const MARKER_PATH := "user://core_selfheal.txt"

enum Action { NONE, HEAL, HEALED, GIVE_UP, NO_SOURCE }


## Pure: what a start does. `tried` = this build already relaunched to heal.
static func decide(windows_export: bool, core_loaded: bool, tried: bool, source_ok: bool) -> Action:
	if not windows_export:
		return Action.NONE
	if core_loaded:
		return Action.HEALED if tried else Action.NONE
	if tried:
		return Action.GIVE_UP
	return Action.HEAL if source_ok else Action.NO_SOURCE


## Boot entry. `ops` is the file-op seam (Ops below, a fake in the tests); one log line whenever it acts.
static func run(ops, windows_export: bool, core_loaded: bool) -> Action:
	if not windows_export:
		return Action.NONE
	var build: String = ops.build_id()
	var tried: bool = ops.read_marker() == build
	var exe: String = ops.exe_path()
	var src := ProjectSettings.globalize_path(EXTRACT_DIR)
	var source_ok := false
	if not core_loaded and not tried:   # hash the exe only when a heal is on the table
		var staged_exe := src.path_join(exe.get_file())
		source_ok = ops.file_exists(src.path_join(DLL_NAME)) and ops.file_exists(staged_exe) \
				and ops.sha256(staged_exe) == ops.sha256(exe)
	var action := decide(windows_export, core_loaded, tried, source_ok)
	match action:
		Action.HEAL:
			ops.write_marker(build)   # BEFORE copy + relaunch: nothing after this line can loop
			var err: int = ops.copy(src.path_join(DLL_NAME), exe.get_base_dir().path_join(DLL_NAME))
			if err != OK:
				print("core self-heal: NmlCore absent; copying the staged %s failed (error %d) — the tree plays" % [DLL_NAME, err])
				return Action.GIVE_UP
			print("core self-heal: NmlCore absent; restored %s from the staged %s update — relaunching once" % [DLL_NAME, build])
			ops.relaunch()
		Action.HEALED:
			print("core self-heal: NmlCore loaded after the self-heal relaunch")
			ops.write_marker(build + " ok")
		Action.GIVE_UP:
			print("core self-heal: NmlCore still absent after the self-heal relaunch — giving up, the tree plays")
		Action.NO_SOURCE:
			print("core self-heal: NmlCore absent and no staged %s of this release — the tree plays" % DLL_NAME)
	return action


## The real file operations (a Windows export at boot).
class Ops:
	var _node: Node

	func _init(node: Node) -> void:
		_node = node

	func exe_path() -> String:
		return OS.get_executable_path()

	func build_id() -> String:
		return "%s+%s" % [ProjectSettings.get_setting("application/config/version", "?"),
				ProjectSettings.get_setting("application/config/build_hash", "local-dev")]

	func read_marker() -> String:
		var p := CoreSelfHeal.MARKER_PATH
		return FileAccess.get_file_as_string(p).strip_edges() if FileAccess.file_exists(p) else ""

	func write_marker(text: String) -> void:
		var f := FileAccess.open(CoreSelfHeal.MARKER_PATH, FileAccess.WRITE)
		if f != null:
			f.store_string(text)

	func file_exists(path: String) -> bool:
		return FileAccess.file_exists(path)

	func sha256(path: String) -> String:
		return FileAccess.get_sha256(path)

	func copy(src: String, dst: String) -> int:
		return DirAccess.copy_absolute(src, dst)

	func relaunch() -> void:
		OS.create_process(OS.get_executable_path(), [])
		_node.get_tree().quit()
