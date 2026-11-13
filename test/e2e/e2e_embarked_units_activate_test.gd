extends GdUnitTestSuite
## E2E - units inside a transport are units that can still activate. A passenger leaves with a move action of its
## own (GF Core Rules v3.6.0 p.2, Transport; the same in the AoF books), so a side whose only unactivated units are
## embarked still owes the table an activation: the round must not close over it, the other side must not play out its
## tail unanswered, and the side that finishes first still opens the next round. Driven on the real main.tscn with
## the one-core flag OFF (the released behaviour): the solo alternation pump (a human vs the AI) and the two-human
## hotseat turn (TwoHumanTurn) are different code paths, so both are pinned.
##
## Real: main.tscn, the real alternation pump, the real SoloController, the real hotseat turn state, the real radial
## activation doors. Constructed: the GameUnits (placed at table coordinates; the transport is a Transport(6) unit).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")

const HUMAN_LINE := Vector3(-0.30, 0.0, 0.20)
const AI_LINE := Vector3(0.30, 0.0, -0.20)

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _ai_acted: PackedStringArray = []   ## every AI activation, in order
var _ai_rounds: Array = []              ## the round each of them happened in


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	CoreActivation._env = 0   # the flag OFF, whatever the environment says
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	_main._solo_game_finished = false
	_main._solo_batch = true
	_ai_acted = PackedStringArray()
	_ai_rounds = []


func after_test() -> void:
	CoreActivation._env = -1
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## Solo: player 2 is the AI (NACHTMAHR), player 1 the human.
func _solo_on() -> void:
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.solo_controller.ai_unit_activated.connect(func(gu: GameUnit) -> void:
		_ai_acted.append(gu.get_name())
		_ai_rounds.append(_main.opr_army_manager.current_round))


## Hotseat: two humans, no AI seat, the Automatic table (the engine runs the turn token and the round end).
func _hotseat_on() -> void:
	_main.opr_army_manager.rules_automation = RulesAutomation.Level.AUTOMATIC


func _register(pid: int, unit_name: String, at: Vector3, models: int = 2) -> GameUnit:
	var positions: Array = []
	for i in range(models):
		positions.append(at + Vector3(0.03 * i, 0.0, 0.0))
	var u := E2EBoot.make_unit(_main, pid, unit_name, positions)
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func _row(pid: int, prefix: String, count: int, at: Vector3) -> Array:
	var out: Array = []
	for i in range(count):
		out.append(_register(pid, "%s%d" % [prefix, i + 1], at + Vector3(0.0, 0.0, 0.12 * (i + 1))))
	return out


## A Transport(6) truck and a squad inside it (embarked for real: the table parks the squad and tracks it as cargo).
func _truck_with_cargo(pid: int, at: Vector3, embarked := true) -> Array:
	var truck := _register(pid, "Truck", at, 1)
	truck.unit_properties["special_rules"] = ["Transport(6)"]
	var cargo := _register(pid, "Riders", at + Vector3(0.05, 0.0, 0.0), 2)
	if embarked:
		assert_bool(_main.opr_army_manager.set_unit_embarked(cargo, truck, true)) \
			.override_failure_message("fixture: the squad must really embark, or every case below proves nothing") \
			.is_true()
		assert_object(_main.opr_army_manager.transport_of(cargo)).is_same(truck)
	return [truck, cargo]


func _log_text() -> String:
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


func _count(needle: String) -> int:
	var n := 0
	for e in _main.battle_log.entries():
		if str((e as Dictionary)["text"]).contains(needle):
			n += 1
	return n


func _round() -> int:
	return _main.opr_army_manager.current_round


func _eligible(pid: int) -> int:
	return _main.solo_controller.eligible_units_for(pid).size()


## The human's activation as the table takes it: the unit is spent, then the door answers it.
func _human_activates(u: GameUnit) -> void:
	u.activate(_round())
	await _main._on_solo_human_activated(u)


## A hotseat activation through the real radial toggle (the turn refusal, the turn token and the round end ride it).
func _toggle(u: GameUnit) -> void:
	await _main.radial_menu_controller._toggle_activation({"game_unit": u})
	await _runner.simulate_frames(2)
	await E2EBoot.settle(get_tree())


# === solo: a human whose transport has activated and whose squad still rides inside =========================

## CONTROL, declared first. Same table, the squad standing OUTSIDE the truck: the AI answers the truck's activation
## ONCE and then waits for the human's squad. If this were red the fixture could not tell an answer from a tail.
func test_control_a_squad_on_the_table_is_answered_one_for_one(timeout := 120000) -> void:
	_solo_on()
	var tc := _truck_with_cargo(1, HUMAN_LINE, false)
	_row(2, "Nachtzehrer", 3, AI_LINE)
	await _human_activates(tc[0])
	assert_int(_ai_acted.size()).override_failure_message("control: the AI answered %s" % [_ai_acted]).is_equal(1)
	assert_int(_eligible(2)).is_equal(2)
	assert_int(_round()).is_equal(1)
	await E2EBoot.settle(get_tree())


## The finding: the squad is INSIDE the truck. It still owes an activation, so the alternation is one for one: the AI
## answers once and waits. The table counts the human's eligible units without passengers, reads "human exhausted" and
## plays the AI's whole remaining army in a row (the TAIL) before the passengers may act.
func test_an_embarked_squad_is_still_a_unit_the_ai_waits_for(timeout := 120000) -> void:
	_solo_on()
	var tc := _truck_with_cargo(1, HUMAN_LINE)
	_row(2, "Nachtzehrer", 3, AI_LINE)
	await _human_activates(tc[0])
	assert_int(_ai_acted.size()) \
		.override_failure_message("the AI took %d activations in a row (%s) while the human's squad was still aboard - one for one means ONE" % [_ai_acted.size(), _ai_acted]) \
		.is_equal(1)
	assert_int(_eligible(2)).is_equal(2)
	assert_int(_round()).is_equal(1)
	await E2EBoot.settle(get_tree())


## The round does not close over passengers: with both eligible pools empty and the squad still aboard the round waits
## (#338) - and "Stay aboard" spends the squad's activation and lets it close. Real door: the radial's _stay_embarked.
func test_the_round_waits_for_the_embarked_squad_and_closes_when_it_acts(timeout := 120000) -> void:
	_solo_on()
	var tc := _truck_with_cargo(1, HUMAN_LINE)
	await _human_activates(tc[0])
	assert_int(_round()).override_failure_message("the round closed over a squad that was still aboard").is_equal(1)
	assert_bool(tc[1].is_activated).is_false()
	_main.radial_menu_controller._stay_embarked(tc[1])
	for _i in 100:
		if _round() == 2:
			break
		await get_tree().create_timer(0.1).timeout
	assert_str(_log_text()).override_failure_message("'Stay aboard' did not spend the squad's activation") \
		.contains("Riders spends its activation to stay aboard")
	assert_int(_round()).override_failure_message("the round did not close once the squad had acted").is_equal(2)
	await E2EBoot.settle(get_tree())


## Who opens the next round: truck, one AI answer, squad, the rest of the AI's army (its tail). The AI took the last
## activation of round 1, so the human finished first and opens round 2 - no AI activation may happen in round 2.
func test_the_side_that_finished_first_opens_when_its_last_unit_was_embarked(timeout := 120000) -> void:
	_solo_on()
	var tc := _truck_with_cargo(1, HUMAN_LINE)
	_row(2, "Nachtzehrer", 3, AI_LINE)
	await _human_activates(tc[0])
	await _human_activates(tc[1])   # the squad spends its activation aboard ("Stay aboard")
	assert_int(_round()).override_failure_message("fixture: round 1 must have closed (AI activations %s)" % [_ai_acted]).is_equal(2)
	assert_array(_ai_rounds).override_failure_message("the AI opened round 2 although the human finished round 1 first: %s" % [_ai_rounds]) \
		.is_equal([1, 1, 1])
	await E2EBoot.settle(get_tree())


## The AI's own passengers are counted (#230: its cargo is eligible, its activation is the disembark): the truck has
## acted, the squad is aboard, the human has one unit. The human's activation is answered by the squad's.
func test_the_ais_embarked_squad_still_activates_and_closes_the_round(timeout := 120000) -> void:
	_solo_on()
	var tc := _truck_with_cargo(2, AI_LINE)
	var human := _register(1, "Grenzer", HUMAN_LINE)
	tc[0].activate(_round())
	assert_int(_eligible(2)).override_failure_message("the AI's embarked squad is not counted as a unit that can activate").is_equal(1)
	await _human_activates(human)
	assert_array(Array(_ai_acted)).override_failure_message("the AI's squad did not activate: %s" % [_ai_acted]).is_equal(["Riders"])
	assert_int(_round()).override_failure_message("the round did not close after the last activation").is_equal(2)
	await E2EBoot.settle(get_tree())


# === Delayed Action counts the squad aboard as a unit left to activate ===================================

## A Delayed Action carrier (the rule is a once-per-round pass "if your opponent has more units left to activate than
## you"); the cost makes the AI's carrier the prize a pass is meant to protect.
func _carrier(pid: int, unit_name: String, at: Vector3) -> GameUnit:
	var u := _register(pid, unit_name, at)
	u.unit_properties["special_rules"] = ["Delayed Action"]
	u.unit_properties["cost"] = 240
	return u


## CONTROL, declared first: the human's squad stands on the table. The carrier, the squad and the AI's two units:
## 2 against 2, so the pass is refused (the rule needs the opponent to have MORE).
func test_control_a_squad_on_the_table_counts_for_the_humans_pass(timeout := 120000) -> void:
	_solo_on()
	var carrier := _carrier(1, "Wachtturm", HUMAN_LINE + Vector3(0.0, 0.0, 0.30))
	var tc := _truck_with_cargo(1, HUMAN_LINE, false)
	tc[0].activate(_round())
	_row(2, "Nachtzehrer", 2, AI_LINE)
	assert_int(_eligible(1)).is_equal(2)
	await _main.solo_begin_pass(carrier)
	assert_str(_log_text()).contains("Wachtturm may not pass — your opponent has 2 units left to activate, you have 2")
	assert_int(_ai_acted.size()).is_equal(0)
	await E2EBoot.settle(get_tree())


## The squad is INSIDE the truck: it is still a unit the human has left to activate, so the count is the same 2 against
## 2 and the pass is refused. The table counted the pool (the carrier alone, 1 against 2) and let the pass through.
func test_delayed_action_counts_the_squad_aboard_on_the_humans_side(timeout := 120000) -> void:
	_solo_on()
	var carrier := _carrier(1, "Wachtturm", HUMAN_LINE + Vector3(0.0, 0.0, 0.30))
	var tc := _truck_with_cargo(1, HUMAN_LINE)
	tc[0].activate(_round())
	_row(2, "Nachtzehrer", 2, AI_LINE)
	await _main.solo_begin_pass(carrier)
	assert_int(_count("passes the turn")) \
		.override_failure_message("the pass went through with the squad still aboard, counting 1 unit against the AI's 2:\n%s" % _log_text()) \
		.is_equal(0)
	assert_str(_log_text()).contains("Wachtturm may not pass — your opponent has 2 units left to activate, you have 2")
	assert_int(_ai_acted.size()).is_equal(0)
	await E2EBoot.settle(get_tree())


## The AI's side of the same count. The human has two units on the table and a squad aboard (3 left), the AI has two
## (its carrier and one more), the human's Jaeger stands inside the carrier's reach: the AI may pass. The table read the
## human's count from the pool (2 against 2) and the AI activated instead. `embarked` false = the control table.
func _delayed_ai_table(embarked: bool) -> GameUnit:
	var guard := _carrier(2, "Waechter", AI_LINE)
	_row(2, "Nachtzehrer", 1, AI_LINE + Vector3(0.0, 0.0, 0.3))
	_register(1, "Jaeger", AI_LINE + Vector3(0.15, 0.0, 0.0))
	_row(1, "Grenzer", 1, HUMAN_LINE)
	var tc := _truck_with_cargo(1, HUMAN_LINE + Vector3(0.0, 0.0, -0.3), embarked)
	tc[0].activate(_round())
	return guard


func test_control_the_ai_passes_when_the_squad_stands_on_the_table(timeout := 120000) -> void:
	_solo_on()
	var guard := _delayed_ai_table(false)
	assert_int(_eligible(1)).is_equal(3)
	_main._solo_pending_replies = 1
	await _main._solo_pump()
	assert_str(_log_text()).contains("Delayed Action: Waechter passes the turn — the opponent has 3 units left to activate, you have 2")
	assert_int(_ai_acted.size()).is_equal(0)
	assert_bool(guard.is_activated).is_false()
	await E2EBoot.settle(get_tree())


func test_delayed_action_counts_the_squad_aboard_on_the_ais_side(timeout := 120000) -> void:
	_solo_on()
	var guard := _delayed_ai_table(true)
	assert_int(_eligible(1)).is_equal(2)
	_main._solo_pending_replies = 1
	await _main._solo_pump()
	assert_str(_log_text()) \
		.override_failure_message("the AI did not pass although the human has 3 units left to its 2 (the squad aboard counts):\n%s" % _log_text()) \
		.contains("Delayed Action: Waechter passes the turn — the opponent has 3 units left to activate, you have 2")
	assert_int(_ai_acted.size()).is_equal(0)
	assert_bool(guard.is_activated).is_false()
	await E2EBoot.settle(get_tree())


# === hotseat: two humans, the turn token alternates =======================================================

## P1's transport has acted and its squad is aboard; P2 has one unit left. P2's activation hands the turn BACK to P1
## (the squad is a unit that can activate) and the round stays open until the squad has acted; the side that took the
## round's last activation (P1) does not open round 2.
func test_hotseat_the_squad_aboard_keeps_its_side_in_the_turn_order(timeout := 120000) -> void:
	_hotseat_on()
	var tc := _truck_with_cargo(1, HUMAN_LINE)
	var b1 := _register(2, "Raiders", AI_LINE)
	await _toggle(tc[0])
	assert_int(_main._hotseat_side_on_turn()).is_equal(2)
	await _toggle(b1)
	assert_int(_round()).override_failure_message("the round closed while P1's squad was still aboard").is_equal(1)
	assert_int(_main._hotseat_side_on_turn()).override_failure_message("the turn did not return to P1 for its squad").is_equal(1)
	await _toggle(tc[1])
	assert_int(_round()).override_failure_message("the round did not close once the squad had acted").is_equal(2)
	assert_int(_main._hotseat_side_on_turn()).override_failure_message("P1 took the last activation, P2 must open").is_equal(2)
	await E2EBoot.settle(get_tree())


## Alternation, not only the tail: P1 truck, P2 first unit, P1 squad (aboard), P2 second unit - P2 took the last
## activation, so P1 opens round 2.
func test_hotseat_the_squad_aboard_takes_its_turn_in_between(timeout := 120000) -> void:
	_hotseat_on()
	var tc := _truck_with_cargo(1, HUMAN_LINE)
	var raiders := _row(2, "Raiders", 2, AI_LINE)
	await _toggle(tc[0])
	await _toggle(raiders[0])
	assert_int(_main._hotseat_side_on_turn()).override_failure_message("P1 still owes its squad: the turn is P1's").is_equal(1)
	await _toggle(tc[1])
	assert_int(_main._hotseat_side_on_turn()).is_equal(2)
	await _toggle(raiders[1])
	assert_int(_round()).is_equal(2)
	assert_int(_main._hotseat_side_on_turn()).override_failure_message("P2 took the last activation, P1 must open").is_equal(1)
	await E2EBoot.settle(get_tree())
