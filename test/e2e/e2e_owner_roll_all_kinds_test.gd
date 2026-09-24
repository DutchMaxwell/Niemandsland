extends GdUnitTestSuite
## RULES_AUTOMATION_PLAN step 0.1b (§2 B4) — in a co-op room every roll that belongs to another
## human's unit goes to its owner through the owner-roll seam (0.1a), not only the first save batch:
## the Bane save re-roll, Regeneration, the morale die, Fearless and No Retreat. Each production entry
## point is driven against the guest's unit and must put exactly one `request_roll` of its kind on the
## wire; the test answers as the owner would (roll_result), so the flow finishes and its rule line is
## written. `_solo_owner_label` names the owner's player for another human's unit instead of "You".
## Same NetworkManager double as e2e_owner_roll_seam_test.gd (active session, this client = slot 1,
## guest peer 42 on slot 2, send_command recorded).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const GUEST_PEER := 42

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _real_net: Node
var _net: Node
var _flow_done := false


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_flow_done = false   # one suite instance serves every test
	_main._solo_batch = true
	_real_net = _main.network_manager
	var src := GDScript.new()
	src.source_code = "extends \"res://scripts/network_manager.gd\"\nvar sent: Array = []\n" \
		+ "func is_multiplayer_active() -> bool:\n\treturn true\n" \
		+ "func get_my_player_slot() -> int:\n\treturn 1\n" \
		+ "func send_command(type: String, payload: Variant = {}, target_peer: int = 0) -> bool:\n" \
		+ "\tsent.append([type, payload, target_peer])\n\treturn true\n"
	src.reload()
	_net = src.new()
	_net.peer_to_slot = {1: 1, GUEST_PEER: 2}
	_net.player_names = {GUEST_PEER: "Guest"}
	_main.network_manager = _net
	_main.solo_ai_slots = {}


func after_test() -> void:
	if _main != null:
		_main.network_manager = _real_net
	if _net != null:
		_net.free()
		_net = null
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _unit(pid: int, unit_name: String, rules: Array, models: int = 2) -> GameUnit:
	var positions: Array = []
	for i in models:
		positions.append(Vector3(0.03 * i, 0.0, 0.3 * (1 if pid == 2 else -1)))
	var u := E2EBoot.make_unit(_main, pid, unit_name, positions)
	u.unit_properties["game_system"] = "gf"
	u.unit_properties["faction_folder"] = "human_defense_force"
	u.unit_properties["special_rules"] = rules
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## Answers the owner's side: every request_roll in order gets the next scripted faces; returns
## [kind, purpose] per request seen, once the driven flow has finished.
func _serve(replies: Array) -> Array:
	var seen: Array = []
	var answered := 0
	for _i in 200:
		var rqs: Array = []
		for s in _net.sent:
			if str((s as Array)[0]) == "request_roll":
				rqs.append((s as Array)[1])
		while answered < rqs.size():
			var rq: Dictionary = rqs[answered]
			seen.append([str(rq["kind"]), str(rq["purpose"])])
			var faces: Array = replies[answered] if answered < replies.size() else [6]
			_main._on_network_command("roll_result", {"req": int(rq["req"]), "faces": faces}, GUEST_PEER)
			answered += 1
		if _flow_done:
			break
		await get_tree().create_timer(0.1).timeout
	return seen


func _log_text() -> String:
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


func _drive_save_batch(striker: GameUnit, defender: GameUnit) -> void:
	await _main._solo_save_batch(striker, defender, "Harness Blade", 3, 4, 0, {"name": "Harness Blade"}, true, true)
	_flow_done = true


func _drive_regeneration(target: GameUnit) -> void:
	await _main._solo_apply_regeneration(target, 2)
	_flow_done = true


func _drive_morale(target: GameUnit) -> void:
	await _main._solo_morale_test(target, _main._solo_owner_label(target), false)
	_flow_done = true


func test_the_bane_re_roll_goes_to_the_owner(timeout := 120000) -> void:
	var striker := _unit(1, "Blades", [])
	var guard := _unit(2, "Guard", [], 3)
	_drive_save_batch(striker, guard)
	# First the save batch itself (0.1a), then the Bane re-roll of its two unmodified 6s.
	var seen: Array = await _serve([[6, 6, 2], [1, 1]])
	assert_bool(_flow_done).is_true()
	var bane: Array = seen.filter(func(s): return str(s[1]).contains("Bane"))
	assert_int(bane.size()) \
		.override_failure_message("0.1b — the Bane save re-roll of the guest's unit must be rolled by its owner (seen: %s)" % str(seen)) \
		.is_equal(1)
	if bane.size() == 1:
		assert_str(str(bane[0][0])).is_equal("defense")
	assert_str(_log_text()).contains("re-rolls 2 unmodified Defense 6s")


func test_regeneration_goes_to_the_owner(timeout := 120000) -> void:
	var guard := _unit(2, "Guard", ["Regeneration"])
	_drive_regeneration(guard)
	var seen: Array = await _serve([[5, 2]])
	assert_bool(_flow_done).is_true()
	assert_array(seen.map(func(s): return s[0])) \
		.override_failure_message("0.1b — Regeneration of the guest's unit must be rolled by its owner (seen: %s)" % str(seen)) \
		.is_equal(["regeneration"])
	assert_str(_log_text()).contains("regeneration")
	assert_str(_log_text()).contains("1 wound ignored")


func test_the_morale_die_goes_to_the_owner(timeout := 120000) -> void:
	var guard := _unit(2, "Guard", [])
	_drive_morale(guard)
	var seen: Array = await _serve([[6]])
	assert_bool(_flow_done).is_true()
	assert_array(seen.map(func(s): return s[0])) \
		.override_failure_message("0.1b — the guest unit's morale die must be rolled by its owner (seen: %s)" % str(seen)) \
		.is_equal(["morale"])
	assert_str(_log_text()).contains("Guard passes morale")


func test_the_fearless_die_goes_to_the_owner(timeout := 120000) -> void:
	var guard := _unit(2, "Guard", ["Fearless"])
	_drive_morale(guard)
	var seen: Array = await _serve([[1], [6]])   # the test fails, the recovery die holds
	assert_bool(_flow_done).is_true()
	assert_array(seen.map(func(s): return s[0])) \
		.override_failure_message("0.1b — morale + Fearless of the guest's unit must both be rolled by its owner (seen: %s)" % str(seen)) \
		.is_equal(["morale", "fearless"])
	assert_str(_log_text()).contains("Guard is Fearless — recovery die (4+) holds")


func test_the_no_retreat_dice_go_to_the_owner(timeout := 120000) -> void:
	var guard := _unit(2, "Guard", ["No Retreat"])
	_drive_morale(guard)
	var seen: Array = await _serve([[1], [5, 6]])   # the test fails, No Retreat pays with no self-wound
	assert_bool(_flow_done).is_true()
	assert_array(seen.map(func(s): return s[0])) \
		.override_failure_message("0.1b — morale + No Retreat of the guest's unit must both be rolled by its owner (seen: %s)" % str(seen)) \
		.is_equal(["morale", "no_retreat"])
	assert_str(_log_text()).contains("Guard has No Retreat — the test counts as passed; 0 self-wounds")


func test_the_owner_label_names_the_guest_not_you(timeout := 120000) -> void:
	var guard := _unit(2, "Guard", [])
	var mine := _unit(1, "Blades", [])
	assert_str(_main._solo_owner_label(guard)) \
		.override_failure_message("0.1b — another human's unit is labelled with its owner's name, not \"You\"") \
		.is_equal("Guest")
	assert_str(_main._solo_owner_label(mine)).is_equal("You")
