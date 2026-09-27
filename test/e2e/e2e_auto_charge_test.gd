extends GdUnitTestSuite
## E2E — Automodus A1 (NML-202): the radial's Charge verb runs a whole activation through
## _run_player_intent -> SoloController.player_intent -> execute_intent -> the melee resolver,
## on the real main.tscn loop (patterns: e2e_speed_feat_radial_test.gd, e2e_split_fire_test.gd).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _pump: Timer


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main._solo_fast = true   # shrink pacing holds — real dice, no reason to sit through the beats
	_arm_pump()   # the attacker's own defending saves against the AI's strike-back need a click


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## _run_human_melee awaits the human's OWN save confirmation for the AI's strikes-back
## (_solo_prompt_saves, title "Incoming fire!") — no headless run can click it, so a repeating
## timer answers it (pattern: e2e_volley_morale_test.gd's _arm_pump/_answer_save_prompt).
func _arm_pump() -> void:
	_pump = Timer.new()
	_pump.name = "AutoChargePump"
	_pump.wait_time = 0.02
	_pump.one_shot = false
	get_tree().root.add_child(_pump)   # freed by free_stray_root_nodes in after_test
	_pump.timeout.connect(_answer_save_prompt)
	_pump.start()


func _answer_save_prompt() -> void:
	if _main == null or not is_instance_valid(_main):
		return
	for c in _main.get_children():
		var dlg := c as AcceptDialog
		if dlg != null and dlg.title == "Incoming fire!":
			dlg.confirmed.emit()


## Defense 2 (saves on 2+) and a single attack each: the exchange almost never wipes either 1-model
## side, so the assertions below hold on a stable "both survive, charger consolidates 1 inch back"
## outcome instead of racing the dice for who dies first.
func _armed(pid: int, unit_name: String, pos: Vector3) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, [pos])
	u.unit_properties["defense"] = 2
	var opr := OPRApiClient.OPRUnit.new()
	var ccw := OPRApiClient.OPRWeapon.new()
	ccw.name = "CCW"
	ccw.range_value = 0
	ccw.attacks = 1
	opr.weapons = [ccw]
	u.source_type = "opr"
	u.source_data = opr
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func _log_text() -> String:
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


func test_a_legal_charge_reaches_contact_fights_and_books_the_ai_reply(timeout := 60000) -> void:
	var attacker := _armed(1, "Chargers", Vector3.ZERO)
	var enemy := _armed(2, "Foe", Vector3(8.0 * INCH, 0, 0))
	# A bystander per side, far from the fight: with only one unit per side the AI's answering
	# activation would exhaust BOTH sides at once and the round auto-advances one frame later,
	# resetting is_activated before this test can read it — an artefact of a 1v1 fixture, not
	# something the automod itself does.
	_armed(1, "Reserves", Vector3(50.0 * INCH, 0, 0))
	_armed(2, "Watchers", Vector3(-50.0 * INCH, 0, 0))
	await _main._run_player_intent(attacker, AiDecision.Action.CHARGE, enemy)
	await E2EBoot.settle(get_tree())
	var gap: float = _main.solo_controller.nearest_melee_gap_in(attacker, enemy)
	# Consolidation (GF v3.5.1 p.9) steps the charger back exactly 1" when neither side is destroyed,
	# so the FINAL gap settles at MELEE_ENGAGE_IN itself — a hair of float rounding included.
	assert_float(gap).is_less_equal(SoloController.MELEE_ENGAGE_IN + 0.001)
	var text := _log_text()
	assert_str(text).contains("Auto:")
	assert_str(text).contains("charges")
	assert_str(text) \
		.override_failure_message("no melee line after the charge (log: %s)" % text.strip_edges()) \
		.contains("into melee")
	assert_bool(attacker.is_activated).is_true()
	assert_int(_main._solo_pending_replies) \
		.override_failure_message("the AI's answering activation was never booked/resolved") \
		.is_equal(0)


func test_a_charge_out_of_band_is_refused_and_moves_nothing() -> void:
	var attacker := _armed(1, "Chargers", Vector3.ZERO)
	var enemy := _armed(2, "Foe", Vector3(30.0 * INCH, 0, 0))
	var pos_before := attacker.models[0].node.global_position
	await _main._run_player_intent(attacker, AiDecision.Action.CHARGE, enemy)
	await E2EBoot.settle(get_tree())
	var text := _log_text()
	assert_str(text) \
		.override_failure_message("no refusal reason in the log (log: %s)" % text.strip_edges()) \
		.contains("out of charge band")
	assert_bool(attacker.is_activated).is_false()
	assert_vector(attacker.models[0].node.global_position).is_equal(pos_before)
