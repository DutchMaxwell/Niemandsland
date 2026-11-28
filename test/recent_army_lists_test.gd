extends GdUnitTestSuite
## Step 51.1: the store of the recent army lists (sheet 04). Red before: there is no RecentArmyLists.

const PATH := "user://recent_lists_test.cfg"


func after_test() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


func _entry(i: int) -> Dictionary:
	return {"link": "https://army-forge.onepagerules.com/share?id=L%d" % i, "name": "List %d" % i, "system": "gf", "points": 1000 + i}


func test_six_links_leave_five_newest_first() -> void:
	for i in 6:
		RecentArmyLists.remember(_entry(i), PATH)
	var lists := RecentArmyLists.load_all(PATH)
	assert_int(lists.size()).is_equal(5)
	assert_str(str(lists[0].name)).is_equal("List 5")
	assert_str(str(lists[4].name)).is_equal("List 1")
	assert_int(int(lists[0].points)).is_equal(1005)


func test_a_repeated_link_is_stored_once_on_top() -> void:
	for i: int in [1, 2, 1]:
		RecentArmyLists.remember(_entry(i), PATH)
	var lists := RecentArmyLists.load_all(PATH)
	assert_array(lists.map(func(e: Dictionary) -> String: return str(e.name))).is_equal(["List 1", "List 2"])


func test_a_broken_file_reads_as_empty() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string("[recent\nlists = {{{ not a list")
	f.close()
	assert_array(RecentArmyLists.load_all(PATH)).is_empty()


func test_an_import_remembers_its_list() -> void:
	var dlg := OPRImportDialog.new()
	dlg.recent_path = PATH
	add_child(dlg)
	await get_tree().process_frame
	var army := OPRApiClient.OPRArmy.new()
	army.name = "Iron Vanguard"
	army.game_system_abbrev = "gf"
	army.points = 2000
	dlg._preview_army = army
	dlg.share_link_input.text = "https://army-forge.onepagerules.com/share?id=IRON"
	dlg.import_btn.disabled = false
	dlg.import_btn.pressed.emit()
	var lists := RecentArmyLists.load_all(PATH)
	assert_int(lists.size()).is_equal(1)
	if lists.size() == 1:
		assert_str(str(lists[0].link)).is_equal("https://army-forge.onepagerules.com/share?id=IRON")
		assert_str(str(lists[0].system)).is_equal("gf")
	dlg.queue_free()


class StubClient extends OPRApiClient:
	var asked: Array = []

	func import_from_share_link(link: String) -> OPRArmy:
		asked.append(link)
		return null


## Step 51.2 (sheet 04): three stored lists show three rows with their tag and points; Load puts the stored link into
## the field and loads it (fresh, through the client); no stored list, no section (red before: no section at all).
func test_the_import_shows_the_recent_lists_and_load_fetches_one() -> void:
	for i in 3:
		RecentArmyLists.remember(_entry(i), PATH)
	var dlg := OPRImportDialog.new()
	dlg.recent_path = PATH
	add_child(dlg)
	dlg.hide()
	await get_tree().process_frame
	var stub := StubClient.new()
	dlg.api_client = stub
	dlg.add_child(stub)
	dlg.show()
	await get_tree().process_frame
	var section := dlg.find_child("RecentLists", true, false) as Control
	assert_object(section).override_failure_message("no recent lists").is_not_null()
	if section == null:
		dlg.queue_free()
		return
	var texts: Array = section.find_children("*", "Label", true, false).map(func(l: Node) -> String: return (l as Label).text)
	assert_array(texts).contains(["RECENT LISTS", "List 2", "List 1", "List 0", "GF", "1002 PTS"])
	var load_buttons := section.find_children("*", "Button", true, false).filter(func(b: Node) -> bool: return (b as Button).text == "Load")
	assert_int(load_buttons.size()).is_equal(3)
	(load_buttons[0] as Button).pressed.emit()
	await get_tree().process_frame
	assert_str(dlg.share_link_input.text).is_equal(str(_entry(2).link))
	assert_array(stub.asked).is_equal([str(_entry(2).link)])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	dlg.hide()
	dlg.show()
	assert_bool(section.visible).override_failure_message("a section without lists").is_false()
	dlg.queue_free()
