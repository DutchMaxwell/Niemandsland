extends GdUnitTestSuite
## E2E — an OPEN targeting window must not outlive its unit's activation by another route.
##
## solo_begin_targeting refuses a unit that already activated, but a window that is ALREADY open was
## only closed by a pick, a right-click or Esc. Activate the same unit through the unit card's
## "Activate" function (radial_menu_controller.card_start_activation -> _on_solo_human_activated)
## and the window stayed open: the opponent answered, and a later pick could still resolve an attack
## for a unit that is marked activated.
##
## Two hypothesis tests (shooting, melee): open the window, activate the unit through the card's own
## function, then assert (a) the window is gone and (b) a real pick on the enemy resolves NO attack.
## Two controls: the same pick WITHOUT the activation in between does resolve an attack - without
## them a green hypothesis test could just mean the pick never reaches the resolver.
##
## Real: scenes/main.tscn, solo_begin_targeting, the card's activation function, the real pick ray
## (_solo_pick_unit_at over a spawned miniature) and the SAME handler main._unhandled_input feeds
## (_solo_targeting_input). Boot pattern: e2e_auto_preview_test.gd, e2e_auto_charge_test.gd.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _pump: Timer
var _resolved: Array = []   # one entry per human_attack_resolved emission


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	_main._solo_fast = true
	_main._solo_batch = true   # no player at the board: every board-side question takes its first option
	_resolved = []
	_main.human_attack_resolved.connect(func(attacker: GameUnit, melee: bool) -> void:
		_resolved.append({"attacker": attacker, "melee": melee}))
	_arm_pump()


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null
	_pump = null


## The melee resolver awaits the human's OWN save confirmation for the AI's strikes-back
## ("Incoming fire!"); no headless run can click it, so a repeating timer answers it
## (pattern: e2e_auto_charge_test.gd).
func _arm_pump() -> void:
	_pump = Timer.new()
	_pump.name = "StaleTargetingPump"
	_pump.wait_time = 0.02
	_pump.one_shot = false
	get_tree().root.add_child(_pump)   # freed by free_stray_root_nodes in after_test
	_pump.timeout.connect(_answer_save_prompt)
	_pump.start()


func _answer_save_prompt() -> void:
	if _main == null or not is_instance_valid(_main):
		return
	for c in _main.get_children():
		var card := c as PromptCard
		if card != null and card.title == "Incoming fire!":
			card.ok_button.pressed.emit()


## A one-model unit: a 24" rifle (2 attacks) or a close-combat weapon (3 attacks).
func _armed(pid: int, unit_name: String, pos: Vector3, melee: bool) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, [pos])
	u.unit_properties["defense"] = 2   # saves on 2+: a one-model foe survives the exchange almost surely
	var opr := OPRApiClient.OPRUnit.new()
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "CCW" if melee else "Rifle"
	w.range_value = 0 if melee else 24
	w.attacks = 3 if melee else 2
	opr.weapons = [w]
	u.source_type = "opr"
	u.source_data = opr
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## Same unit, but its model is a REAL spawned miniature (StaticBody3D + collider) so the real pick
## ray can hit it (pattern: e2e_auto_preview_test.gd).
func _pickable(pid: int, unit_name: String, pos: Vector3, melee: bool) -> GameUnit:
	var u := _armed(pid, unit_name, pos, melee)
	var m := u.models[0] as ModelInstance
	var body: Node3D = (_main.object_manager as Object).call("spawn_miniature", m.node.global_position, false)
	body.set_meta("game_unit", u)
	m.node.queue_free()
	m.node = body
	return u


## A screen point the real pick ray resolves to `u` (INF when none: a fixture failure, asserted).
func _pick_point(u: GameUnit) -> Vector2:
	var cam: Camera3D = _main.get_viewport().get_camera_3d()
	if cam == null:
		return Vector2.INF
	var node: Node3D = (u.models[0] as ModelInstance).node
	for dy in [0.016, 0.03, 0.0]:
		var pt: Vector2 = cam.unproject_position(node.global_position + Vector3(0.0, dy, 0.0))
		if _main._solo_pick_unit_at(pt) == u:
			return pt
	return Vector2.INF


## The player's targeting click: a real left-button InputEventMouseButton through the SAME handler
## main._unhandled_input feeds.
func _click_target(pt: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = pt
	ev.global_position = pt
	await _main._solo_targeting_input(ev)


func _log_text() -> String:
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


## Board and window: the human attacker, a pickable enemy the AI already activated (so the AI's
## answer goes to its bystander and the enemy stays where the player sees it), a bystander per side
## (with one unit a side the round would end by itself), then the targeting window for `melee`.
func _open_window(melee: bool) -> Dictionary:
	var attacker := _armed(1, "Strikers" if melee else "Riflemen", Vector3.ZERO, melee)
	var foe := _pickable(2, "Foe", Vector3((1.5 if melee else 8.0) * INCH, 0, 0), melee)
	foe.is_activated = true
	_armed(1, "Reserves", Vector3(50.0 * INCH, 0, 0), melee)
	_armed(2, "Watchers", Vector3(-50.0 * INCH, 0, 0), melee)
	await _runner.simulate_frames(1)   # the pick is a raycast: let physics register the fresh body
	await E2EBoot.start_activation(_main, attacker)   # the explicit activation a player opens first
	await _main.solo_begin_targeting(attacker, melee)
	return {"attacker": attacker, "foe": foe}


## What the unit card's "Activate" button does (unit_dock.gd "start_activation"), then let the
## activation's coroutines (the AI's answer included) settle.
func _activate_like_the_card(unit: GameUnit) -> void:
	await _main.radial_menu_controller.card_end_activation(unit)   # one-core release: the card's End activation ends the open one
	await _runner.simulate_frames(4)
	await E2EBoot.settle(get_tree())


## The pick starts the attack as a detached coroutine (_solo_targeting_input does not await it), so
## wait on the resolved signal - up to `max_ms` - before reading the outcome.
func _wait_resolved(count: int, max_ms: int) -> void:
	var deadline := Time.get_ticks_msec() + max_ms
	while _resolved.size() < count and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame


## The battle-log line a resolved attack leaves: the volley's sight count, or the melee declaration.
func _attack_line_logged(attacker: GameUnit, melee: bool) -> bool:
	var text := _log_text()
	if melee:
		return text.find("%s charges Foe into melee" % attacker.get_name()) != -1
	# The table prints the sight count; a plain human unit's volley goes through the core (one-core release), whose
	# declaration beat reads "<unit> fires at <target>" instead (by design, plan note 14.11).
	return (text.find("%s: " % attacker.get_name()) != -1 and text.find("with line of sight + range") != -1) \
		or text.find("%s fires at " % attacker.get_name()) != -1


## Drive one scenario. `activate_first` is the hypothesis (activate by the card between the window
## and the pick); false is the control. Returns what the game did.
func _run(melee: bool, activate_first: bool, wait_ms: int) -> Dictionary:
	var s := await _open_window(melee)
	var attacker: GameUnit = s["attacker"]
	var foe: GameUnit = s["foe"]
	var window_opened: bool = (_main._solo_target_mode.get("unit") == attacker)
	var legal: String = _main._solo_validate_target(attacker, foe, melee)
	if activate_first:
		await _activate_like_the_card(attacker)
	var window_after: bool = not _main._solo_target_mode.is_empty()
	var pt := _pick_point(foe)
	var foe_alive_before := foe.get_alive_count()
	if pt != Vector2.INF:
		await _click_target(pt)
		await _runner.simulate_frames(2)
		if _attack_line_logged(attacker, melee):   # an attack began: let it finish before reading the outcome
			await _wait_resolved(1, wait_ms)
		await _runner.simulate_frames(4)
		await E2EBoot.settle(get_tree())
	return {
		"attacker": attacker, "foe": foe, "melee": melee,
		"window_opened": window_opened, "legal": legal,
		"activated": attacker.is_activated, "window_open_after_activation": window_after,
		"pick_point_found": pt != Vector2.INF,
		"resolved": _resolved.size(), "line": _attack_line_logged(attacker, melee),
		"drop_logged": _log_text().find("the open target pick is dropped") != -1,
		"foe_alive_before": foe_alive_before, "foe_alive_after": foe.get_alive_count(),
	}


func _assert_fixture(r: Dictionary) -> void:
	assert_bool(bool(r["window_opened"])) \
		.override_failure_message("fixture: solo_begin_targeting did not open the window") \
		.is_true()
	assert_str(str(r["legal"])) \
		.override_failure_message("fixture: the enemy is not a legal target (%s)" % r["legal"]) \
		.is_empty()
	assert_bool(bool(r["pick_point_found"])) \
		.override_failure_message("fixture: no screen point resolves to the enemy through the real pick ray") \
		.is_true()


func _hypothesis(melee: bool) -> void:
	var r := await _run(melee, true, 20000)
	_assert_fixture(r)
	assert_bool(bool(r["activated"])) \
		.override_failure_message("fixture: the card's activation did not mark the unit activated") \
		.is_true()
	# (a) activating the unit another way closes its open window
	assert_bool(bool(r["window_open_after_activation"])) \
		.override_failure_message("the targeting window stayed open after its unit was activated by the card") \
		.is_false()
	assert_bool(bool(r["drop_logged"])) \
		.override_failure_message("the battle log does not say the open pick was dropped") \
		.is_true()
	# (b) a later pick on the enemy resolves nothing
	assert_int(int(r["resolved"])) \
		.override_failure_message("a pick resolved an attack for a unit that was already activated") \
		.is_equal(0)
	assert_bool(bool(r["line"])) \
		.override_failure_message("the battle log shows an attack by the already activated unit") \
		.is_false()
	assert_int(int(r["foe_alive_after"])) \
		.override_failure_message("the enemy lost models to an attack by an already activated unit") \
		.is_equal(int(r["foe_alive_before"]))
	await E2EBoot.settle(get_tree())


func _control(melee: bool) -> void:
	var r := await _run(melee, false, 20000)
	_assert_fixture(r)
	assert_bool(bool(r["window_open_after_activation"])) \
		.override_failure_message("control: the window was open before the pick (nothing closed it)") \
		.is_true()
	assert_int(int(r["resolved"])) \
		.override_failure_message("control: the pick did not resolve an attack") \
		.is_equal(1)
	assert_bool(bool(r["line"])) \
		.override_failure_message("control: no attack line in the battle log (log: %s)" % _log_text().strip_edges()) \
		.is_true()
	assert_bool(bool(r["activated"])) \
		.override_failure_message("control: the resolved attack did not complete the activation") \
		.is_true()
	await E2EBoot.settle(get_tree())


func test_shooting_window_closes_when_the_unit_activates_by_the_card(timeout := 120000) -> void:
	await _hypothesis(false)


func test_melee_window_closes_when_the_unit_activates_by_the_card(timeout := 120000) -> void:
	await _hypothesis(true)


func test_control_shooting_pick_without_activation_resolves_an_attack(timeout := 120000) -> void:
	await _control(false)


func test_control_melee_pick_without_activation_resolves_an_attack(timeout := 120000) -> void:
	await _control(true)


# === The Coordinate offer belongs to an ALREADY activated unit by design ==========================
##
## The hand-off offer (`_solo_try_coordinate_human`) is a window whose unit is the activated bearer. It
## owns the activation flow: only its pick or its decline books the AI's reply. Un-marking and
## re-marking the bearer while the offer is open ("a mis-click fix") emits unit_activated again; that
## must NOT close the offer, or nothing is left to book the owed reply.

## A human bearer with Coordinate (the book that fields it, as e2e_wave4_ebr_coordinate_test.gd stamps
## it), a friend in reach to hand off to, and an AI unit far away. The AI is frozen: this measures the
## reply LEDGER, not the AI's turn. Opens the REAL offer by activating the bearer through the card's
## toggle; `_solo_try_coordinate_human` offers nothing while `_solo_batch` is on, so it is switched off.
func _open_coordinate_offer() -> GameUnit:
	var bearer := _armed(1, "Comms Team", Vector3.ZERO, false)
	var receiver := _armed(1, "Riflemen", Vector3(8.0 * INCH, 0, 0), false)
	_armed(2, "Watchers", Vector3(-50.0 * INCH, 0, 0), false)
	bearer.unit_properties["game_system"] = "gf"
	bearer.unit_properties["faction_folder"] = "human_defense_force"
	bearer.unit_properties["special_rules"] = ["Coordinate"]
	assert_bool(receiver.is_activated).is_false()
	_main._solo_batch = false
	_main._solo_ai_busy = true
	_main._solo_pending_replies = 0
	await E2EBoot.start_activation(_main, bearer)   # the explicit activation a player opens first ...
	await _main.radial_menu_controller.card_end_activation(bearer)   # ... and the End that offers the hand-off
	var deadline := Time.get_ticks_msec() + 5000
	while not _main._solo_target_mode.has("coordinate") and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return bearer


## "Un-mark and re-mark": the unit card's activation toggle twice.
func _toggle_off_and_on(bearer: GameUnit) -> void:
	await _main.radial_menu_controller.card_toggle_activation(bearer)
	assert_bool(bearer.is_activated).override_failure_message("fixture: the toggle did not un-mark the bearer").is_false()
	await E2EBoot.start_activation(_main, bearer)   # re-marking = Activate again + End activation
	await _main.radial_menu_controller.card_end_activation(bearer)
	assert_bool(bearer.is_activated).override_failure_message("fixture: the toggle did not re-mark the bearer").is_true()
	await _runner.simulate_frames(4)


func _assert_offer_open_and_undropped(bearer: GameUnit) -> void:
	assert_bool(_main._solo_target_mode.has("coordinate")) \
		.override_failure_message("the Coordinate offer was closed by re-marking its bearer") \
		.is_true()
	assert_bool(_main._solo_target_mode.get("unit") == bearer).is_true()
	assert_bool(_log_text().find("the open target pick is dropped") != -1) \
		.override_failure_message("the log says the Coordinate offer was dropped") \
		.is_false()


func test_coordinate_offer_survives_a_re_toggle_and_decline_books_one_reply(timeout := 120000) -> void:
	var bearer := await _open_coordinate_offer()
	assert_bool(_main._solo_target_mode.has("coordinate")) \
		.override_failure_message("fixture: no Coordinate offer opened for the bearer") \
		.is_true()
	assert_bool(bearer.is_activated).override_failure_message("fixture: the bearer is not activated").is_true()
	await _toggle_off_and_on(bearer)
	_assert_offer_open_and_undropped(bearer)
	var before: int = _main._solo_pending_replies
	await _main._solo_coordinate_decline(bearer)
	assert_int(_main._solo_pending_replies) \
		.override_failure_message("declining the offer must book exactly one AI reply") \
		.is_equal(before + 1)
	_main._solo_ai_busy = false
	await E2EBoot.settle(get_tree())


## The same through the player's real decline (Esc): with the offer gone, Esc finds no window and the
## owed reply is never booked - the ledger is where a dropped offer shows.
func test_coordinate_offer_esc_after_a_re_toggle_books_one_reply(timeout := 120000) -> void:
	var bearer := await _open_coordinate_offer()
	assert_bool(_main._solo_target_mode.has("coordinate")) \
		.override_failure_message("fixture: no Coordinate offer opened for the bearer") \
		.is_true()
	await _toggle_off_and_on(bearer)
	var before: int = _main._solo_pending_replies
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	await _main._solo_targeting_input(esc)
	assert_int(_main._solo_pending_replies) \
		.override_failure_message("Esc on the Coordinate offer must book exactly one AI reply") \
		.is_equal(before + 1)
	_main._solo_ai_busy = false
	await E2EBoot.settle(get_tree())
