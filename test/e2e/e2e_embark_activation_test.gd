extends GdUnitTestSuite
## E2E — #209: embarking was a FREE action. GF v3.5.1 p.15: units enter/exit a transport
## "by using any move action" and "can't both embark/disembark as part of the same
## activation" — so in a solo game the transport move IS the unit's activation. It was
## never marked, the unit could act again, and the disembark could follow in the same
## round: a rules exploit the maintainer hit live.
##
## Under test on the real main.tscn radial controller: consumption + hand-over on embark,
## the same-round double-move refusal, and the sandbox/deployment exemptions.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _solo_playing_on() -> void:
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING


## Transport(6) truck at the origin + cargo in reach + an idle spare so the round stays open.
func _truck_and_cargo() -> Array:
	var truck := E2EBoot.make_unit(_main, 1, "Truck", [Vector3.ZERO])
	truck.unit_properties["special_rules"] = ["Transport(6)"]
	var cargo := E2EBoot.make_unit(_main, 1, "Riders", [Vector3(0.04, 0, 0)])
	var spare := E2EBoot.make_unit(_main, 1, "Spare", [Vector3(1.0, 0, 0)])
	for u in [truck, cargo, spare]:
		_main.opr_army_manager.game_units[u.unit_id] = u
	# Fixture must be able to embark at all — otherwise the tests pass vacuously.
	assert_bool(bool(_main.opr_army_manager.can_embark(cargo, truck).get("ok", false))).is_true()
	return [truck, cargo]


func _log_text() -> String:
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


func test_embark_consumes_the_activation(timeout := 120000) -> void:
	_solo_playing_on()
	var tc := _truck_and_cargo()
	_main.radial_menu_controller._embark_unit({"game_unit": tc[1], "embark_target": tc[0]})
	await _runner.simulate_frames(2)
	assert_object(_main.opr_army_manager.transport_of(tc[1])).is_equal(tc[0])
	assert_bool((tc[1] as GameUnit).is_activated) \
		.override_failure_message("#209 — embarking stayed a FREE action: the unit is not activated (GF v3.5.1 p.15: any move action)") \
		.is_true()
	assert_str(_log_text()).contains("spends its activation to embark")


func test_no_disembark_in_the_same_round(timeout := 120000) -> void:
	_solo_playing_on()
	var tc := _truck_and_cargo()
	_main.radial_menu_controller._embark_unit({"game_unit": tc[1], "embark_target": tc[0]})
	await _runner.simulate_frames(2)
	_main.radial_menu_controller._disembark_unit(tc[1])
	assert_object(_main.opr_army_manager.transport_of(tc[1])) \
		.override_failure_message("#209 — the unit hopped out in the same round it embarked (p.15 forbids both in one activation, and its activation is spent)") \
		.is_equal(tc[0])
	assert_str(_log_text()).contains("has already activated this round")


func test_disembark_keeps_the_shot_window(timeout := 120000) -> void:
	# #209 correction (maintainer rules check): exiting is "any move action" (p.15) and an
	# ADVANCE may shoot after moving (p.7) — the exit must NOT consume the activation.
	_solo_playing_on()
	var tc := _truck_and_cargo()
	_main.opr_army_manager.set_unit_embarked(tc[1], tc[0], true)
	_main.radial_menu_controller._disembark_unit(tc[1])
	assert_object(_main.opr_army_manager.transport_of(tc[1])).is_null()
	assert_bool((tc[1] as GameUnit).is_activated) \
		.override_failure_message("#209 — the Advance exit consumed the activation: the unit lost its rulebook shot window (GF v3.5.1 p.7)") \
		.is_false()
	assert_str(_log_text()).contains("may still shoot this activation")


func test_no_reembark_in_the_exit_round(timeout := 120000) -> void:
	# p.15: "can't both embark/disembark as part of the same activation" — the open shot
	# window must not reopen the transport door.
	_solo_playing_on()
	var tc := _truck_and_cargo()
	_main.opr_army_manager.set_unit_embarked(tc[1], tc[0], true)
	_main.radial_menu_controller._disembark_unit(tc[1])
	_main.radial_menu_controller._embark_unit({"game_unit": tc[1], "embark_target": tc[0]})
	assert_object(_main.opr_army_manager.transport_of(tc[1])) \
		.override_failure_message("#209 — the unit hopped back IN during its exit round") \
		.is_null()
	assert_str(_log_text()).contains("can't embark again")


func test_headless_unload_dispatch_bypasses_the_ghost(timeout := 120000) -> void:
	# #210: the radial Unload opens the cursor ghost — but headless (tests, harness, AI)
	# must fall through to the direct placer, or every automated flow would hang waiting
	# for a mouse. Drives the REAL dispatch id.
	_solo_playing_on()
	var tc := _truck_and_cargo()
	_main.opr_army_manager.set_unit_embarked(tc[1], tc[0], true)
	_main.radial_menu_controller._on_action_selected("unload_cargo_0", {"cargo_units": [tc[1]]})
	assert_object(_main.opr_army_manager.transport_of(tc[1])) \
		.override_failure_message("#210 — the headless unload dispatch did not place the unit (ghost hang?)") \
		.is_null()


func test_two_reachable_transports_offer_a_choice(timeout := 120000) -> void:
	# Maintainer find: with two trucks in reach the first was silently taken. Now one entry
	# per vehicle, and the click routes to the PICKED one.
	_solo_playing_on()
	var tc := _truck_and_cargo()
	var truck2 := E2EBoot.make_unit(_main, 1, "Truck B", [Vector3(0.08, 0, 0)])
	truck2.unit_properties["special_rules"] = ["Transport(6)"]
	_main.opr_army_manager.game_units[truck2.unit_id] = truck2
	var rmc = _main.radial_menu_controller
	var ctx := {"game_unit": tc[1]}   # the menu-open path fills this before appending items
	var items: Array = []
	rmc._append_transport_items(tc[1], ctx, items)
	var labels: Array = []
	for it in items:
		labels.append(str(it.label))
	assert_int((ctx.get("embark_targets", []) as Array).size()) \
		.override_failure_message("expected BOTH reachable transports on offer, items: %s" % str(labels)) \
		.is_equal(2)
	# Click the SECOND entry: the cargo must end up in Truck B, not the first hit.
	rmc._on_action_selected("embark_1", ctx)
	assert_object(_main.opr_army_manager.transport_of(tc[1])).is_equal(ctx["embark_targets"][1])


func test_sandbox_embark_stays_free(timeout := 120000) -> void:
	# No solo game engaged: the sandbox consumes nothing (like dice and rulers).
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	var tc := _truck_and_cargo()
	_main.radial_menu_controller._embark_unit({"game_unit": tc[1], "embark_target": tc[0]})
	assert_object(_main.opr_army_manager.transport_of(tc[1])).is_equal(tc[0])
	assert_bool((tc[1] as GameUnit).is_activated).is_false()


func test_deployment_reserve_loading_stays_free(timeout := 120000) -> void:
	# #160 reserve loading happens DURING deployment — no activation economy there.
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.DEPLOYMENT
	var tc := _truck_and_cargo()
	_main.radial_menu_controller._embark_unit({"game_unit": tc[1], "embark_target": tc[0]})
	assert_object(_main.opr_army_manager.transport_of(tc[1])).is_equal(tc[0])
	assert_bool((tc[1] as GameUnit).is_activated).is_false()


# ===== NML-953 — an Unload the player cannot see reads as a broken game =====

## The "unload_cargo_<idx>" entry out of a built item list, or null.
func _unload_item(items: Array, idx: int):
	for it in items:
		if str(it.id) == "unload_cargo_%d" % idx:
			return it
	return null


func test_unload_is_offered_while_the_cargo_still_has_its_activation() -> void:
	# CONTROL, declared before the red one: with the cargo's move action still open the entry is
	# there and clickable. Without this the red test below could pass on a fixture that never
	# produces an Unload entry at all.
	_solo_playing_on()
	var tc := _truck_and_cargo()
	_main.opr_army_manager.set_unit_embarked(tc[1], tc[0], true)
	var items: Array = []
	_main.radial_menu_controller._append_transport_items(tc[0], {}, items)
	var it = _unload_item(items, 0)
	assert_object(it).is_not_null()
	assert_bool(bool(it.enabled)).is_true()


func test_a_spent_cargo_keeps_a_greyed_unload_entry(timeout := 120000) -> void:
	# NML-953, the maintainer's own sequence: TC-039 embarks in round 1, TC-040 then opens the
	# transport's radial to unload — and "unload steht nicht im radial menü". Loading IS the cargo's
	# move action (#209), so its activation is spent in that same round and the entry was dropped by
	# a bare `continue`: no entry, no reason, nothing. Refusing is right; refusing invisibly is not.
	_solo_playing_on()
	var tc := _truck_and_cargo()
	_main.radial_menu_controller._embark_unit({"game_unit": tc[1], "embark_target": tc[0]})
	await _runner.simulate_frames(2)
	assert_bool((tc[1] as GameUnit).is_activated).is_true()   # the premise of the find
	var items: Array = []
	_main.radial_menu_controller._append_transport_items(tc[0], {}, items)
	var it = _unload_item(items, 0)
	assert_object(it) \
		.override_failure_message("NML-953 — the Unload entry VANISHED for a cargo unit whose activation is spent: the player sees neither the option nor a reason") \
		.is_not_null()
	if it == null:
		return   # the failure above is recorded; dereferencing null would abort the whole run
	assert_bool(bool(it.enabled)) \
		.override_failure_message("the refused entry must be GREYED, not clickable (GF v3.5.1 p.15 forbids the second move action)") \
		.is_false()
	assert_str(str(it.label)).contains("already activated")
	assert_str(str(it.tooltip)).contains("p.15")


func test_a_spent_unit_keeps_a_greyed_embark_entry(timeout := 120000) -> void:
	# The same defect on the other side of the door: with its activation spent the unit may not
	# board either, and the whole Embark block used to vanish — a transport standing right in front
	# of it offered nothing at all.
	_solo_playing_on()
	var tc := _truck_and_cargo()
	(tc[1] as GameUnit).activate(1)
	var items: Array = []
	_main.radial_menu_controller._append_transport_items(tc[1], {}, items)
	var found = null
	for it in items:
		if str(it.id).begins_with("embark"):
			found = it
	assert_object(found) \
		.override_failure_message("the Embark entry VANISHED for a unit whose activation is spent — no option, no reason") \
		.is_not_null()
	if found == null:
		return
	assert_bool(bool(found.enabled)).is_false()
	assert_str(str(found.tooltip)).contains("p.15")


# ===== NML-954 — a destroyed transport owes its cargo all THREE consequences =====

## Kill the transport's only model through the real dead-parking choke point, the way a lethal
## wound does — which is what fires the spill.
func _wreck(truck: GameUnit, pid: int) -> void:
	var m := truck.models[0] as ModelInstance
	m.node.set_meta("model_instance", m)
	m.is_alive = false
	_main.opr_army_manager.set_loose_model_dead(m.node, pid, true, truck.unit_id)


func test_the_spill_line_quotes_the_rule_and_names_all_three(timeout := 120000) -> void:
	# The maintainer asked why the game makes HIM roll the dangerous terrain test. It is the rule's
	# first consequence — but the old line only ordered the roll, so it read as an app quirk. The
	# line quotes Transport now and names all three consequences.
	_solo_playing_on()
	var tc := _truck_and_cargo()
	_main.opr_army_manager.set_unit_embarked(tc[1], tc[0], true)
	_wreck(tc[0], 1)
	await _runner.simulate_frames(2)
	assert_bool((tc[1] as GameUnit).is_shaken).is_true()
	var text := _log_text()
	assert_str(text) \
		.override_failure_message("NML-954 — the spill line does not QUOTE the rule that demands the dice: %s" % text) \
		.contains("must take a dangerous terrain test")
	assert_str(text).contains("are Shaken")
	# The quote must render as the rulebook prints it — no stray escape backslash in the log.
	assert_str(text).contains("must be placed fully within 6\" of the transport before it's removed\"")
	assert_str(text).contains("placed fully within 6\"")
	assert_str(text).contains("take a Dangerous Terrain test now")   # YOUR cargo: YOUR dice
	await E2EBoot.settle(get_tree())


func test_the_ai_cargo_actually_takes_the_dangerous_test(timeout := 120000) -> void:
	# NML-954, the real rules gap: the S1 note left the dangerous-terrain DICE "in the player's
	# hand". For YOUR cargo that is the same deal every other dangerous terrain test in the game
	# gives you. For NACHTMAHR's cargo there is no hand — nobody rolled, so the rule's first
	# consequence never applied to the AI side at all.
	_solo_playing_on()
	_main._solo_batch = true   # tray faces without the physics settle
	var truck := E2EBoot.make_unit(_main, 2, "AI Truck", [Vector3.ZERO])
	truck.unit_properties["special_rules"] = ["Transport(6)"]
	var grunts := E2EBoot.make_unit(_main, 2, "AI Grunts", [Vector3(0.04, 0, 0)])
	for u in [truck, grunts]:
		_main.opr_army_manager.game_units[u.unit_id] = u
	assert_bool(_main.opr_army_manager.set_unit_embarked(grunts, truck, true)).is_true()
	_wreck(truck, 2)
	await _runner.simulate_frames(12)
	assert_str(_log_text()) \
		.override_failure_message("NML-954 — NACHTMAHR's cargo climbed out of the wreck without the Dangerous Terrain test the rule demands") \
		.contains("takes its Dangerous Terrain test")
	await E2EBoot.settle(get_tree())


# ===== #230 — AI transport doctrine (official Solo rules p.58) =====

func test_ai_deploy_fills_its_transport() -> void:
	_solo_playing_on()
	var truck := E2EBoot.make_unit(_main, 2, "AI Truck", [Vector3.ZERO])
	truck.unit_properties["special_rules"] = ["Transport(6)"]
	var grunts := E2EBoot.make_unit(_main, 2, "AI Grunts", [Vector3(0.3, 0, 0), Vector3(0.35, 0, 0)])
	for u in [truck, grunts]:
		_main.opr_army_manager.game_units[u.unit_id] = u
	var blocked := func(_p: Vector3) -> bool: return false
	_main.solo_controller.deploy_begin(Rect2(-0.5, -0.5, 1.0, 1.0), [], blocked, blocked, 4711)
	assert_object(_main.opr_army_manager.transport_of(grunts)) \
		.override_failure_message("#230 — the AI left its transport empty at deployment (Solo rules p.58: fill up the cargo limit)") \
		.is_equal(truck)


func test_ai_cargo_disembarks_on_first_activation() -> void:
	_solo_playing_on()
	var truck := E2EBoot.make_unit(_main, 2, "AI Truck", [Vector3.ZERO])
	truck.unit_properties["special_rules"] = ["Transport(6)"]
	truck.activate(1)   # the transport already acted — only the cargo is eligible
	var grunts := E2EBoot.make_unit(_main, 2, "AI Grunts", [Vector3(0.05, 0, 0)])
	var foe := E2EBoot.make_unit(_main, 1, "Foe", [Vector3(0.4, 0, 0)])
	for u in [truck, grunts, foe]:
		_main.opr_army_manager.game_units[u.unit_id] = u
	_main.opr_army_manager.set_unit_embarked(grunts, truck, true)
	var acted: GameUnit = _main.solo_controller.activate_next_ai_unit()
	assert_object(acted).is_equal(grunts)
	assert_object(_main.opr_army_manager.transport_of(grunts)) \
		.override_failure_message("#230 — the embarked AI cargo did not disembark on its first activation") \
		.is_null()
	assert_bool(grunts.is_activated).is_true()
