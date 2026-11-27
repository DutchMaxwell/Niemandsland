extends GdUnitTestSuite
## PLAN_GAME_SYSTEM_SWITCH step 20b: the pick travels from the table-setup dialog through the startup menu into the pending
## setup (the "system" key step 3 applies) and is remembered in the menu config for the next table. Red proof: on a build without
## this step the dialog opened on gf again after the player had picked Age of Fantasy: Skirmish.

const MENU_CFG := "user://menu.cfg"
const SETUP_KEY := "niemandsland/pending_table_setup"

class MenuTransitionProbe extends "res://scripts/startup_menu.gd":
	var entered_game := false
	func _transition_to_game() -> void:
		entered_game = true

var _cfg_backup := ""
var _setup_backup: Variant


func before_test() -> void:
	_cfg_backup = FileAccess.get_file_as_string(MENU_CFG) if FileAccess.file_exists(MENU_CFG) else ""
	DirAccess.remove_absolute(ProjectSettings.globalize_path(MENU_CFG))
	_setup_backup = ProjectSettings.get_setting(SETUP_KEY, null)


func after_test() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(MENU_CFG))
	if not _cfg_backup.is_empty():
		var f := FileAccess.open(MENU_CFG, FileAccess.WRITE)
		f.store_string(_cfg_backup)
	ProjectSettings.set_setting(SETUP_KEY, _setup_backup)


func _menu() -> Control:
	var probe = auto_free(load("res://scenes/startup_menu.tscn").instantiate())
	probe.set_script(MenuTransitionProbe)
	add_child(probe)
	probe.setup_lists = false   # no CDN request for NACHTMAHR's lists
	return probe


func test_default_pick_is_gf_until_a_system_is_remembered() -> void:
	assert_str(GameSystem.default_pick()).is_equal("gf")
	GameSystem.remember_pick("aofs")
	assert_str(GameSystem.default_pick()).is_equal("aofs")
	GameSystem.remember_pick("nonsense")   # no system: nothing stored
	assert_str(GameSystem.default_pick()).is_equal("aofs")


func test_remembering_keeps_the_other_menu_keys_and_a_junk_value_reads_as_gf() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("menu", "biome", "arid_desert")
	cfg.set_value("menu", GameSystem.PICK_KEY, "fantasy")
	cfg.save(MENU_CFG)
	assert_str(GameSystem.default_pick()).is_equal("gf")
	GameSystem.remember_pick("gff")
	var read := ConfigFile.new()
	read.load(MENU_CFG)
	assert_str(str(read.get_value("menu", "biome", ""))).is_equal("arid_desert")
	assert_str(GameSystem.default_pick()).is_equal("gff")


func test_the_pick_reaches_the_pending_setup_and_the_next_dialog_opens_on_it() -> void:
	var menu = _menu()
	menu._show_table_setup()
	assert_str(menu._table_setup.selected_system).is_equal("gf")
	menu._table_setup.set_system("aofs")
	menu._table_setup._confirm()
	await get_tree().create_timer(HudTokens.DUR_COMMIT + 0.1).timeout   # the commit beat, then the screen change
	assert_bool(menu.entered_game).is_true()
	var setup: Dictionary = ProjectSettings.get_setting(SETUP_KEY, {})
	assert_str(str(setup.get("system", "<missing>"))).is_equal("aofs")
	assert_vector(setup.get("size", Vector2.ZERO)).is_equal(Vector2(4, 4))   # the system's preselected board
	# "restart": a fresh menu opens its dialog on the remembered pick, with its board and biome filter
	var again = _menu()
	again._show_table_setup()
	assert_str(again._table_setup.selected_system).override_failure_message("the dialog forgot the pick").is_equal("aofs")
	assert_str(again._table_setup.selected_size).is_equal("square")
	assert_bool(again._table_setup._biome_buttons.urban_ruins.visible).is_false()
