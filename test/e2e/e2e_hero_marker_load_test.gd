extends GdUnitTestSuite
## E2E — a joined hero and its host through save -> load on the REAL scenes/main.tscn.
##
## Every load of a save with a shaken or fatigued unit printed "SCRIPT ERROR: Trying to assign a non-object value
## to a variable of type 'game_unit.gd'" in RadialMenuController._hero_marker_suppressed. The save stores
## attached_to as the host's unit_id ("" = not joined); SaveManager resolves it into a live GameUnit only after the
## models have spawned, and those models already draw their unit tokens in between — so the unit_id String counted
## as a join and was assigned to a GameUnit variable.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _tmp_saves: Array = []


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)


func after_test() -> void:
	for p in _tmp_saves:
		if FileAccess.file_exists(str(p)):
			DirAccess.remove_absolute(str(p))
	_tmp_saves.clear()
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _profile(unit_name: String, size: int) -> OPRApiClient.OPRUnit:
	var u := OPRApiClient.OPRUnit.new()
	u.name = unit_name
	u.size = size
	u.quality = 3
	u.defense = 3
	u.cost = 100
	u.base_size_round = 32
	u.base_width_mm = 32
	u.base_depth_mm = 32
	u.game_system = "gf"
	return u


func test_a_loaded_joined_hero_names_a_live_host_and_shows_no_second_token() -> void:
	var mgr = _main.opr_army_manager
	var host: GameUnit = mgr.create_runtime_unit({"opr_unit": _profile("Battle Brothers", 2), "faction_folder": "ratmen_clans"}, 1,
		[Vector3(0.25, 0.0, -0.35), Vector3(0.25 + 1.2 * INCH, 0.0, -0.35)], "spawn")
	var hero: GameUnit = mgr.create_runtime_unit({"opr_unit": _profile("Captain", 1), "faction_folder": "ratmen_clans"}, 1,
		[Vector3(0.25 + 2.4 * INCH, 0.0, -0.35)], "spawn")
	EquipmentDistributor.attach_hero_to_unit(hero, host)
	host.is_shaken = true
	hero.is_shaken = true
	var host_id := host.unit_id
	var hero_id := hero.unit_id
	await _runner.simulate_frames(2)
	var path := "user://e2e_hero_marker_load_%d.nml" % Time.get_ticks_usec()
	_tmp_saves.append(path)
	assert_int(_main.save_manager.save_game(path)).is_equal(OK)
	mgr.clear_all()
	await _runner.simulate_frames(2)

	# Watch every frame of the load: a unit that reads as joined must name a live host, never the save's id (the
	# token code assigns get_attached_to() to a GameUnit variable whenever is_attached() says so).
	var wrong: Array = []
	var radial = _main.radial_menu_controller
	var probe := func() -> void:
		for u in mgr.get_all_game_units():
			if u.is_attached() and not (u.get_attached_to() is GameUnit):
				wrong.append("%s joined to %s" % [u.unit_properties.get("name", u.unit_id), var_to_str(u.get_attached_to())])
	get_tree().process_frame.connect(probe)
	await _main.save_manager.load_game(path)
	await _runner.simulate_frames(4)
	get_tree().process_frame.disconnect(probe)
	assert_array(wrong).override_failure_message("during the load a unit read as joined to a non-unit value: %s" % str(wrong.slice(0, 4))).is_empty()

	# After the load the join is live, and only the host carries the Shaken token (the hero's is suppressed).
	var loaded_host: GameUnit = mgr.get_game_unit_by_id(host_id)
	var loaded_hero: GameUnit = mgr.get_game_unit_by_id(hero_id)
	assert_object(loaded_hero.get_attached_to()).is_same(loaded_host)
	assert_bool(loaded_host.is_attached()).is_false()
	assert_object(radial._get_unit_token_node(loaded_host).get_node_or_null("ShakenMarker")).override_failure_message("the loaded host lost its Shaken token").is_not_null()
	assert_object(radial._get_unit_token_node(loaded_hero).get_node_or_null("ShakenMarker")).override_failure_message("the loaded joined hero shows a second Shaken token").is_null()
	await E2EBoot.settle(get_tree())
