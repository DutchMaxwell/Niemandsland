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


func test_copy_tree_overwrites_install_files() -> void:
	var u: SelfUpdater = auto_free(SelfUpdater.new())
	var src := ProjectSettings.globalize_path(TMP.path_join("src"))
	var install := ProjectSettings.globalize_path(TMP.path_join("install"))
	DirAccess.make_dir_recursive_absolute(src)
	DirAccess.make_dir_recursive_absolute(install)
	# an existing (old) file in the install must be overwritten by the new one
	_write(install.path_join("Niemandsland.pck"), "OLD")
	_write(src.path_join("Niemandsland.pck"), "NEW")
	_write(src.path_join("Niemandsland.x86_64"), "BINARY")
	assert_bool(u._copy_tree(src, install)).is_true()
	assert_str(FileAccess.get_file_as_string(install.path_join("Niemandsland.pck"))).is_equal("NEW")
	assert_bool(FileAccess.file_exists(install.path_join("Niemandsland.x86_64"))).is_true()


# ===== helpers =====

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
