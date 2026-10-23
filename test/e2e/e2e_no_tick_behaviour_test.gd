extends GdUnitTestSuite
## "No AI without its tick" (#1719), the behaviour. A SoloController exists without an AI seat on two
## paths — (a) a local Automatic table builds it for geometry, (b) a ticked game leaves it behind when
## the tick comes off — and five steps asked "does a controller exist" instead of "is there an AI
## seat": the round-1 Rapid Ambush beat, the defender's Hit & Run step, Re-Position Artillery's mover,
## the off-table Ambush set-aside (P1 only) and the game-start fill-up of a leftover AI deploy queue.
## Real: scenes/main.tscn, the real radial activation, Start Game, _run_human_attack and the buff door.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254
const TRAY := Vector3(1.5, 0.0, 0.0)   # off the 6x4' table

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main._solo_batch = true


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _reg(pid: int, unit_name: String, at: Vector3, rules: Array = [], models: int = 1) -> GameUnit:
	var pos: Array = []
	for i in models:
		pos.append(at + Vector3(0.03 * i, 0.0, 0.0))
	var u := E2EBoot.make_unit(_main, pid, unit_name, pos)
	u.unit_properties["special_rules"] = rules
	u.unit_properties["game_system"] = "gf"
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func _automatic() -> void:
	_main.opr_army_manager.rules_automation = RulesAutomation.Level.AUTOMATIC
	_main._solo_batch = false   # the deployment gate (and its set-aside) skips unattended runs
	_main._ensure_solo_controller()   # (a) the geometry controller
	assert_bool(_main.solo_ai_slots.is_empty()).override_failure_message("fixture: no tick").is_true()


func _log_from(start: int) -> String:
	var t := ""
	for e in _main.battle_log.entries().slice(start):
		t += str((e as Dictionary)["text"]) + "\n"
	return t


func _activate(unit: GameUnit) -> void:
	await _main.radial_menu_controller._toggle_activation({"game_unit": unit})
	await _runner.simulate_frames(4)
	await E2EBoot.settle(get_tree())


func _refute(text: String, needle: String, why: String) -> void:
	assert_str(text).override_failure_message("%s ('%s'):\n%s" % [why, needle, text]).not_contains(needle)


## (b) items 3 + 8: a ticked game queued its deployment and Ambush arrival, the tick came off, the
## players placed P2 by hand — the first activation (which starts play) must not deploy or arrive anything.
func test_a_removed_tick_leaves_no_ai_queue_behind(timeout := 120000) -> void:
	var rifles := _reg(1, "Rifles", Vector3(0.0, 0.0, -0.3))
	var raiders := _reg(2, "Raiders", Vector3(0.0, 0.0, 0.3))
	var stalkers := _reg(2, "Stalkers", TRAY, ["Rapid Ambush"])
	var scouts := _reg(1, "Scouts", TRAY + Vector3(0.0, 0.0, 0.2), ["Ambush"])
	_main._on_solo_ai_toggled(true, 2)
	_main._ensure_solo_controller()
	var zone := Rect2(Vector2(-0.9, 0.3), Vector2(1.8, 0.3))
	assert_int(_main.solo_controller.deploy_begin(zone, [], Callable(), Callable(), 7)) \
		.override_failure_message("fixture: the ticked game's queue").is_greater(0)
	_main._on_solo_ai_toggled(false, 2)
	_main._solo_batch = false
	var before: Vector3 = (raiders.models[0] as ModelInstance).node.global_position
	var start: int = _main.battle_log.entries().size()
	await _activate(rifles)
	var text := _log_from(start)
	assert_int(_main.opr_army_manager.game_phase).override_failure_message("fixture: play did not start:\n%s" % text) \
		.is_equal(OPRArmyManager.GamePhase.PLAYING)
	_refute(text, "NACHTMAHR deploys", "a leftover AI queue deployed P2's army")
	_refute(text, "AI Ambush", "NACHTMAHR's arrival beat ran on a table without a tick")
	assert_str(text).override_failure_message("a Manual table does not name the round-1 rule:\n%s" % text) \
		.contains("Rapid Ambush: Stalkers may arrive at the start of round 1 — the players place it by hand")
	assert_vector((raiders.models[0] as ModelInstance).node.global_position) \
		.override_failure_message("P2's hand-placed unit was moved:\n%s" % text).is_equal(before)
	assert_bool(bool(scouts.unit_properties.get("ambush_reserve", false))) \
		.override_failure_message("a Manual table flagged P1's Ambush unit nobody will ask to arrive").is_false()
	assert_int(_main.solo_controller.deploy_pending() + _main.solo_controller.ambush_reserve.size()) \
		.override_failure_message("the tick came off but the AI queues stayed").is_equal(0)
	assert_bool(bool(stalkers.unit_properties.get("ambush_reserve", false))).is_true()   # P2 still holds it


## (a) item 3: two humans on an Automatic table — BOTH are asked for their round-1 Rapid Ambush, opener
## first (the round-2+ Ambush step); NACHTMAHR's beat never runs.
func test_two_humans_are_both_asked_for_round_one_rapid_ambush(timeout := 120000) -> void:
	_reg(1, "Rifles", Vector3(0.0, 0.0, -0.3))
	_reg(2, "Raiders", Vector3(0.0, 0.0, 0.3))
	_reg(1, "Scouts", TRAY, ["Rapid Ambush"])
	_reg(2, "Stalkers", TRAY + Vector3(0.0, 0.0, 0.2), ["Rapid Ambush"])
	_automatic()
	var start: int = _main.battle_log.entries().size()
	_main._on_start_game_pressed()
	var asked: Array = []
	for slot in [1, 2]:
		var line := "P%d Ambush (round 1)" % slot
		for _i in 120:
			if _log_from(start).contains(line):
				break
			await get_tree().process_frame
		if _log_from(start).contains(line):
			asked.append(slot)
			_main._solo_deploy_ui_btn2.pressed.emit()   # "Keep waiting"
			await _runner.simulate_frames(4)
	var text := _log_from(start)
	assert_array(asked).override_failure_message("not both players were asked for round 1:\n%s" % text).is_equal([1, 2])
	_refute(text, "AI Ambush", "NACHTMAHR's arrival beat ran without a tick")
	assert_bool(_main._solo_ai_busy).override_failure_message("the AI beat holds the table:\n%s" % text).is_false()


## (a) item 7: Start Game on an Automatic table sets aside BOTH players' off-table Ambush units.
func test_start_game_sets_aside_both_players_ambushers(timeout := 120000) -> void:
	_reg(1, "Rifles", Vector3(0.0, 0.0, -0.3))
	_reg(2, "Raiders", Vector3(0.0, 0.0, 0.3))
	var scouts := _reg(1, "Scouts", TRAY, ["Ambush"])
	var stalkers := _reg(2, "Stalkers", TRAY + Vector3(0.0, 0.0, 0.2), ["Ambush"])
	_automatic()
	var start: int = _main.battle_log.entries().size()
	_main._on_start_game_pressed()
	var text := _log_from(start)
	for u in [scouts, stalkers]:
		assert_bool(bool((u as GameUnit).unit_properties.get("ambush_reserve", false))) \
			.override_failure_message("%s was not set aside:\n%s" % [(u as GameUnit).get_name(), text]).is_true()
	assert_str(text).contains("P2 holds 1 Ambush unit(s)")
	_refute(text, "You hold", "the set-aside line speaks to one 'you'")


## (a) item 4: the engine never takes a human defender's optional Hit & Run step.
func test_a_human_defender_keeps_its_hit_and_run(timeout := 120000) -> void:
	var rifles := _reg(1, "Rifles", Vector3.ZERO)
	var raiders := _reg(2, "Raiders", Vector3(1.0 * INCH, 0.0, 0.0), ["Hit & Run"], 3)
	raiders.unit_properties["faction_folder"] = "custodian_brothers"   # a book that fields Hit & Run
	_automatic()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	var start: int = _main.battle_log.entries().size()
	await _main._run_human_attack(rifles, raiders, true, true)
	_refute(_log_from(start), "Hit & Run: Raiders", "the engine moved P2's unit out of the melee")
	await E2EBoot.settle(get_tree())


## (a) item 6: Re-Position Artillery on a human gun names itself; the AI mover never moves it.
func test_a_human_gun_is_repositioned_by_hand(timeout := 120000) -> void:
	var captain := _reg(1, "Gun Captain", Vector3.ZERO, ["Hero", "Re-Position Artillery"])
	captain.unit_properties["faction_folder"] = "battle_brothers"   # a book that fields the rule
	var gun := _reg(1, "Field Gun", Vector3(4.0 * INCH, 0.0, 0.0), ["Artillery"])
	_reg(2, "Raiders", Vector3(30.0 * INCH, 0.0, 0.0))
	_automatic()
	var before: Vector3 = _main._los_unit_centre(gun)
	var start: int = _main.battle_log.entries().size()
	await _main._solo_apply_utility_buffs(captain)
	var text := _log_from(start)
	assert_str(text).override_failure_message("the rule did not name itself:\n%s" % text).contains("move it by hand")
	assert_vector(_main._los_unit_centre(gun)).override_failure_message("the AI mover moved P1's gun:\n%s" % text).is_equal(before)
