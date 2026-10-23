extends GdUnitTestSuite
## "No AI without its tick" (#1719), maintainer test 3: two armies, no tick, "Start Deployment" ran
## as "you vs NACHTMAHR" (the roll-off named it, the engine deployed player 2). The flow refused only
## a missing controller, but one exists without an AI seat on two paths: (a) a local Automatic table
## builds it for geometry (step 2.4), (b) a ticked game earlier in the session leaves it behind.
## Real: scenes/main.tscn, the real handler, the Solo panel tick and the radial builder with main's gates.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const TRAY_P2 := Vector3(5.0, 0.0, 0.0)

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main._solo_batch = true   # zero pacing holds if a (wrong) AI deployment runs


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _reg(pid: int, unit_name: String, at: Vector3) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, [at, at + Vector3(0.03, 0.0, 0.0)])
	var opr := OPRApiClient.OPRUnit.new()
	opr.cost = 100
	u.source_type = "opr"
	u.source_data = opr
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func _two_armies() -> Array:
	return [_reg(1, "Rifles", -TRAY_P2), _reg(2, "Raiders", TRAY_P2), _reg(2, "Bikers", TRAY_P2 + Vector3(0.0, 0.0, 0.2))]


## Press "Start Deployment": no flow, no NACHTMAHR line, P2 stays on its tray, the toast says what to do;
## and no radial entry of either side names the AI or offers an engine move verb.
func _assert_no_ai_behind(units: Array, path: String) -> void:
	var log_before: int = _main.battle_log.entries().size()
	await _main._on_solo_deploy_pressed()
	await E2EBoot.settle(get_tree())
	var lines := ""
	for e in _main.battle_log.entries().slice(log_before):
		lines += str((e as Dictionary)["text"]) + "\n"
	assert_str(lines).override_failure_message("%s: NACHTMAHR in the log without a tick:\n%s" % [path, lines]).not_contains("NACHTMAHR")
	assert_bool(_main._solo_deploy_fsm.is_empty()).override_failure_message("%s: the guided deployment started (fsm %s)" % [
		path, _main._solo_deploy_fsm.get("phase", "?")]).is_true()
	for u in units.slice(1):
		assert_float(((u as GameUnit).models[0] as ModelInstance).node.global_position.x) \
			.override_failure_message("%s: the engine deployed P2's %s" % [path, (u as GameUnit).get_name()]).is_equal_approx(TRAY_P2.x, 0.001)
	assert_bool(_main._solo_toast != null and _main._solo_toast.visible and _main._solo_toast.text.contains("tick an army as AI")) \
		.override_failure_message("%s: no refusal toast that says what to do" % path).is_true()
	var ai_word := RegEx.create_from_string("\\bAI\\b|NACHTMAHR")
	for u in units.slice(0, 2):
		for it in RadialMenu.create_unit_menu(u, _main.solo_combat_available(u), _main.solo_auto_available(u)):
			var line := "%s | %s | %s" % [it.id, it.label, it.tooltip]
			assert_bool(ai_word.search(line) == null and not it.id.begins_with("solo_auto_")) \
				.override_failure_message("%s: P%d's radial names the AI without a tick: %s" % [
					path, int((u as GameUnit).unit_properties["player_id"]), line]).is_true()


func test_automatic_table_without_a_tick_never_deploys_for_nachtmahr(timeout := 120000) -> void:
	var units := _two_armies()
	_main.opr_army_manager.rules_automation = RulesAutomation.Level.AUTOMATIC   # the fresh-table default pick
	assert_bool(_main.solo_ai_slots.is_empty()).override_failure_message("fixture: no tick").is_true()
	await _assert_no_ai_behind(units, "(a) Automatic table")


func test_a_removed_tick_leaves_no_ai_deployment_behind(timeout := 120000) -> void:
	var units := _two_armies()
	_main._on_solo_ai_toggled(true, 2)   # a ticked game earlier in the session builds its controller…
	_main._ensure_solo_controller()
	assert_object(_main.solo_controller).override_failure_message("fixture: the ticked game's controller").is_not_null()
	_main._on_solo_ai_toggled(false, 2)  # …then the tick comes off (a re-import without it does the same)
	assert_bool(_main.solo_ai_slots.is_empty()).override_failure_message("fixture: the tick is off").is_true()
	await _assert_no_ai_behind(units, "(b) tick removed")


func test_a_ticked_army_still_gets_the_guided_deployment(timeout := 120000) -> void:
	_two_armies()
	_main._on_solo_ai_toggled(true, 2)
	await _main._on_solo_deploy_pressed()
	assert_bool(_main._solo_deploy_fsm.is_empty()) \
		.override_failure_message("with the tick, Start Deployment must still run the guided flow").is_false()
	await E2EBoot.settle(get_tree())
