extends GdUnitTestSuite
## PLAN_GAME_SYSTEM_SWITCH step 22, the end-to-end proof over the real scenes/main.tscn: the game system picked in the table setup
## decides the table (size, biomes, shelf, labels, deployment catalogue), the one import door (a list of another system is refused
## with a sentence naming both, a list of the table's own system imports), and it survives a save + reload and reaches a late
## joiner. The second case is a gf table: exactly what main offered before the switch existed. Planted fault: remove the import
## guard and the refused list is stored (red, see the PR).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const SETUP_KEY := "niemandsland/pending_table_setup"
const SAVE_PATH := "user://e2e_game_system_switch.nml"

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _setup_backup: Variant


func before_test() -> void:
	_setup_backup = ProjectSettings.get_setting(SETUP_KEY, null)
	_root_before = E2EBoot.root_children(get_tree())


func after_test() -> void:
	ProjectSettings.set_setting(SETUP_KEY, _setup_backup)
	ProjectSettings.set_setting("niemandsland/pending_load_path", "")
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## Boots the real game with the pending setup the table-setup screen would have left (what the menu hands over).
func _boot(setup: Dictionary) -> void:
	E2EBoot.arm_harness_mode()
	ProjectSettings.set_setting(SETUP_KEY, setup)
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)


## What the dialog hands over after the player picked `system` (and nothing else); the dialog is freed again, because only one
## exclusive window may exist at a time. `checks` runs on the open dialog (the setup screen's own state).
func _setup_of(system: String, checks: Callable = Callable()) -> Dictionary:
	var dialog := TableSizeDialog.new()
	add_child(dialog)
	dialog.set_system(system)
	if checks.is_valid():
		checks.call(dialog)
	var setup := {"size": dialog.chosen_inches() / 12.0, "biome": dialog.selected_biome, "system": dialog.selected_system}
	dialog.queue_free()
	await get_tree().process_frame
	return setup


func _army(abbrev: String, army_name: String) -> OPRApiClient.OPRArmy:
	var a := OPRApiClient.OPRArmy.new()
	a.name = army_name
	a.game_system_abbrev = abbrev
	return a


func _log_has(text: String) -> int:
	var n := 0
	for e in _main.battle_log.entries():
		if str((e as Dictionary)["text"]) == text:
			n += 1
	return n


func _shelf_biomes() -> Array:
	_main._sandbox_shelf.open()
	var option: OptionButton = _main._sandbox_shelf._biome_option
	var labels: Array = []
	for i in option.item_count:
		labels.append(option.get_item_text(i))
	return labels


func _container_label() -> String:
	_main._on_map_layout_pressed()
	return (_main.map_layout_editor.find_child("TerrainContainerButton", true, false) as Button).text


func test_an_aofs_table_follows_its_system_from_setup_to_save_to_a_late_joiner() -> void:
	# --- the setup screen: Age of Fantasy: Skirmish preselects 4 x 4 ft and drops the grimdark-only biomes
	var setup := await _setup_of("aofs", func(dialog: TableSizeDialog) -> void:
		assert_vector(dialog.chosen_inches()).is_equal(Vector2(48, 48))
		assert_bool(dialog._biome_buttons.urban_ruins.visible).is_false())
	assert_str(str(setup["system"])).is_equal("aofs")
	await _boot(setup)
	# --- the table
	assert_vector(_main.table.table_size).is_equal(Vector2(4, 4))
	assert_str(_main._table_system()).is_equal("aofs")
	assert_int(_log_has("Game system: Age of Fantasy: Skirmish")).is_equal(1)
	assert_str(_main._system_chip.text).is_equal("SYSTEM: AoFS")
	# --- what is on offer
	assert_bool(_shelf_biomes().has("Urban Ruins")).override_failure_message("the fantasy shelf lists Urban Ruins").is_false()
	assert_array(_main.object_manager.sandbox_catalog("urban_")).is_empty()
	assert_str(_container_label()).is_equal("Blocker")
	assert_array(DeploymentCatalog.style_ids(_main._deploy_board_in())).is_equal(["front_line"])
	# --- the one import door
	await _main._on_opr_army_imported(_army("gf", "Grim List"), 1, false)
	await E2EBoot.settle(get_tree())
	assert_bool(_main.opr_army_manager.armies.has(1)).override_failure_message("the refused list was stored").is_false()
	assert_int(_log_has("Import refused: Grim List is a list for Grimdark Future, this table plays Age of Fantasy: Skirmish.")).is_equal(1)
	await _main._on_opr_army_imported(_army("aofs", "Skirmish List"), 1, false)
	await E2EBoot.settle(get_tree())
	assert_bool(_main.opr_army_manager.armies.has(1)).override_failure_message("the table's own system was refused").is_true()
	# --- save, quit, start the game again, CONTINUE: the same system
	assert_int(_main.save_manager.save_game(SAVE_PATH)).is_equal(OK)
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	ProjectSettings.set_setting("niemandsland/pending_load_path", SAVE_PATH)
	E2EBoot.arm_harness_mode()
	_main = (load(E2EBoot.MAIN_SCENE) as PackedScene).instantiate()
	get_tree().root.add_child(_main)
	var loaded: Array = []
	_main.save_manager.load_completed.connect(func(_n: int) -> void: loaded.append(true), CONNECT_ONE_SHOT)
	for _i in 600:
		if not loaded.is_empty():
			break
		await get_tree().process_frame
	await get_tree().process_frame
	assert_int(loaded.size()).override_failure_message("CONTINUE never finished its load").is_equal(1)
	assert_str(_main.opr_army_manager.table_system).is_equal("aofs")
	assert_str(_main._table_system()).is_equal("aofs")
	# --- a late joiner: a fresh table on the default system is handed the host's key and adopts it
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	ProjectSettings.set_setting("niemandsland/pending_load_path", "")
	await _boot({})
	assert_str(_main._table_system()).is_equal("gf")
	_main._on_remote_table_settings_changed({"game_system": "aofs"})
	assert_str(_main._table_system()).is_equal("aofs")
	assert_int(_log_has("Game system: Age of Fantasy: Skirmish")).is_equal(1)


func test_a_gf_table_is_offered_exactly_what_main_offered_before() -> void:
	await _boot(await _setup_of("gf"))
	assert_vector(_main.table.table_size).is_equal(Vector2(6, 4))
	assert_str(_main._table_system()).is_equal("gf")
	assert_bool(_shelf_biomes().has("Urban Ruins")).is_true()
	assert_int(_main.object_manager.sandbox_catalog("urban_").size()).is_equal(12)
	assert_str(_container_label()).is_equal("Container")
	assert_int(DeploymentCatalog.style_ids(_main._deploy_board_in()).size()).is_equal(9)
	await _main._on_opr_army_imported(_army("aof", "Elf List"), 1, false)
	await E2EBoot.settle(get_tree())
	assert_bool(_main.opr_army_manager.armies.has(1)).is_false()   # the other system is refused here too
	await _main._on_opr_army_imported(_army("gf", "Grim List"), 1, false)
	await E2EBoot.settle(get_tree())
	assert_bool(_main.opr_army_manager.armies.has(1)).is_true()
