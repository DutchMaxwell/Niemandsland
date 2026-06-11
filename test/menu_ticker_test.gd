extends GdUnitTestSuite
## Tests the menu intel-ticker rotation rule and the save-info lookup that feeds the
## CONTINUE menu entry.


func test_next_index_never_repeats_current() -> void:
	for current in range(0, 10):
		for rand in range(0, 50):
			var idx := MenuTicker.next_index(current, 10, rand)
			assert_int(idx).is_not_equal(current)
			assert_int(idx).is_between(0, 9)


func test_next_index_single_entry() -> void:
	assert_int(MenuTicker.next_index(0, 1, 7)).is_equal(0)


func test_quotes_exist() -> void:
	assert_int(MenuTicker.MENU_QUOTES.size()).is_greater(3)


func test_latest_save_info_empty_dir() -> void:
	var dir := "user://test_saves_empty"
	DirAccess.make_dir_recursive_absolute(dir)
	assert_bool(SaveManager.latest_save_info(dir).is_empty()).is_true()
	DirAccess.remove_absolute(dir)


func test_latest_save_info_picks_nml_and_ignores_others() -> void:
	# mtime granularity is one second, so "newest of several .nml" isn't reliably
	# testable headless; pin the filter (.nml only) + the metadata shape instead.
	var dir := "user://test_saves_pick"
	DirAccess.make_dir_recursive_absolute(dir)
	for name in ["battle.nml", "ignored.txt"]:
		var f := FileAccess.open(dir.path_join(name), FileAccess.WRITE)
		f.store_string("x")
		f.close()

	var info := SaveManager.latest_save_info(dir)
	assert_bool(info.is_empty()).is_false()
	assert_str(info["name"]).is_equal("battle")
	assert_str(info["path"]).is_equal(dir.path_join("battle.nml"))
	assert_int(info["modified_unix"]).is_greater(0)

	for name in ["battle.nml", "ignored.txt"]:
		DirAccess.remove_absolute(dir.path_join(name))
	DirAccess.remove_absolute(dir)