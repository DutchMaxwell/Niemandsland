extends GdUnitTestSuite
## Guards the risky file mechanics of the in-game self-updater (extract a release zip, copy it over
## the install) against a synthetic zip — no network, no touching the real install. The download
## (HTTPRequest) and the platform-specific relaunch are covered by the browser-download fallback.

const TMP := "user://_selfupdater_test"


func after_test() -> void:
	var u := SelfUpdater.new()
	u._rmrf(ProjectSettings.globalize_path(TMP))
	u.free()


func test_extract_writes_every_entry() -> void:
	var u: SelfUpdater = auto_free(SelfUpdater.new())
	var zip_path := _make_linux_zip()
	var dest := TMP.path_join("extracted")
	assert_bool(u._extract(zip_path, dest)).is_true()
	assert_bool(FileAccess.file_exists(dest.path_join("Niemandsland.x86_64"))).is_true()
	assert_bool(FileAccess.file_exists(dest.path_join("Niemandsland.pck"))).is_true()
	assert_str(FileAccess.get_file_as_string(dest.path_join("Niemandsland.pck"))).is_equal("PCKDATA")


func test_extract_rejects_a_corrupt_zip() -> void:
	var u: SelfUpdater = auto_free(SelfUpdater.new())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TMP))
	var bad := TMP.path_join("bad.zip")
	var fa := FileAccess.open(bad, FileAccess.WRITE)
	fa.store_string("not a zip")
	fa.close()
	assert_bool(u._extract(bad, TMP.path_join("out"))).is_false()


func test_copy_tree_replaces_install_files_including_the_binary() -> void:
	var u: SelfUpdater = auto_free(SelfUpdater.new())
	var src := ProjectSettings.globalize_path(TMP.path_join("src"))
	var install := ProjectSettings.globalize_path(TMP.path_join("install"))
	DirAccess.make_dir_recursive_absolute(src)
	DirAccess.make_dir_recursive_absolute(install)
	# Existing (old) install files — INCLUDING the binary — must be unlinked + replaced. In-place
	# overwrite of a running binary fails with ETXTBSY on Linux; unlink-first is what makes the swap work.
	_write(install.path_join("Niemandsland.pck"), "OLD")
	_write(install.path_join("Niemandsland.x86_64"), "OLDBIN")
	_write(src.path_join("Niemandsland.pck"), "NEW")
	_write(src.path_join("Niemandsland.x86_64"), "BINARY")
	assert_bool(u._copy_tree(src, install)).is_true()
	assert_str(FileAccess.get_file_as_string(install.path_join("Niemandsland.pck"))).is_equal("NEW")
	assert_str(FileAccess.get_file_as_string(install.path_join("Niemandsland.x86_64"))).is_equal("BINARY")


# Release 0925: the Windows zip ships nml_core_godot.dll next to the .exe (the ONNX evaluator). A
# helper that swaps only the .exe leaves the old DLL (or none) and the updated game silently falls
# back to the decision-tree AI. The helper must install EVERY file of the release zip.
func test_windows_helper_installs_every_file_including_the_extension_dll() -> void:
	var script := SelfUpdater.windows_helper_script(_make_windows_extract(), WIN_EXE)
	var dll_src := ProjectSettings.globalize_path(TMP.path_join("win/nml_core_godot.dll")).replace("/", "\\")
	assert_str(script).contains("copy /Y \"%s\" \"C:\\Games\\Niemandsland\\nml_core_godot.dll\"" % dll_src)
	assert_str(script).contains("\"C:\\Games\\Niemandsland\\Niemandsland.exe\"")


# The .exe AND the .dll stay locked until the game process has really exited — a fixed ~2 s pause
# races a slow shutdown. The helper waits for THIS process id to disappear.
func test_windows_helper_waits_for_this_process_to_exit() -> void:
	var script := SelfUpdater.windows_helper_script(_make_windows_extract(), WIN_EXE)
	assert_str(script).contains("tasklist /FI \"PID eq %d\"" % OS.get_process_id())


# A half-swapped install (new .exe, old .dll) is worse than no update: any failed copy restores
# every file from its .bak, so the player relaunches the version they had.
func test_windows_helper_rolls_back_every_file_on_a_failed_copy() -> void:
	var script := SelfUpdater.windows_helper_script(_make_windows_extract(), WIN_EXE)
	assert_str(script).contains("goto rollback")
	assert_str(script).contains("copy /Y \"C:\\Games\\Niemandsland\\nml_core_godot.dll.bak\" \"C:\\Games\\Niemandsland\\nml_core_godot.dll\"")
	assert_str(script).contains("copy /Y \"C:\\Games\\Niemandsland\\Niemandsland.exe.bak\" \"C:\\Games\\Niemandsland\\Niemandsland.exe\"")


# ===== helpers =====

const WIN_EXE := "C:/Games/Niemandsland/Niemandsland.exe"


## A staged Windows release as the updater extracts it: the .exe (embedded PCK) + the extension DLL.
func _make_windows_extract() -> String:
	var dir := ProjectSettings.globalize_path(TMP.path_join("win"))
	DirAccess.make_dir_recursive_absolute(dir)
	_write(dir.path_join("Niemandsland.exe"), "EXE")
	_write(dir.path_join("nml_core_godot.dll"), "DLL")
	return dir


func _make_linux_zip() -> String:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TMP))
	var zip_path := TMP.path_join("rel.zip")
	var packer := ZIPPacker.new()
	packer.open(ProjectSettings.globalize_path(zip_path))
	packer.start_file("Niemandsland.x86_64"); packer.write_file("BINARY".to_utf8_buffer()); packer.close_file()
	packer.start_file("Niemandsland.pck"); packer.write_file("PCKDATA".to_utf8_buffer()); packer.close_file()
	packer.close()
	return zip_path


func _write(path: String, text: String) -> void:
	var fa := FileAccess.open(path, FileAccess.WRITE)
	fa.store_string(text)
	fa.close()
