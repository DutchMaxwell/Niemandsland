extends GdUnitTestSuite
## A volley at the OTHER human's unit in an agreed online Automatic room: the saves belong to the defender's
## owner, so they must go out as a `request_roll` through the owner-roll seam (0.1a) and never roll on the
## shooter's tray ("own dice on own tray", Automodus decision 9). Melee already does this; the volley does not.
##
## KNOWN BUG, pinned here (the fix waits for a release decision): _run_human_shooting hands
## human_defends=false to _solo_resolve_saves, so the volley never asks the owner. The volley case is skipped
## unless NML_RUN_KNOWN_RED=1 (env-gated do_skip, pattern: rules_registry_test.gd), so CI stays green; set the
## variable to see it fail. The fix removes the gate. This client is the guest (slot 2); the host (peer 1)
## holds slot 1. Owner answers are served as in e2e_owner_roll_all_kinds_test.gd.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const HOST_PEER := 1
const INCH := 0.0254

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
	_flow_done = false
	_main._solo_batch = true   # tray faces without the physics settle
	_main._solo_auto_saves = true   # the guest's OWN saves (melee strike-back) roll without the prompt
	_real_net = _main.network_manager
	var src := GDScript.new()
	src.source_code = "extends \"res://scripts/network_manager.gd\"\nvar sent: Array = []\n" \
		+ "func is_multiplayer_active() -> bool:\n\treturn true\n" \
		+ "func get_my_player_slot() -> int:\n\treturn 2\n" \
		+ "func send_command(type: String, payload: Variant = {}, target_peer: int = 0) -> bool:\n" \
		+ "\tsent.append([type, payload, target_peer])\n\treturn true\n"
	assert_int(src.reload()).is_equal(OK)
	_net = src.new()
	_net.peer_to_slot = {HOST_PEER: 1}
	_net.player_names = {HOST_PEER: "Host"}
	_main.network_manager = _net
	_main.solo_ai_slots = {}
	_main.opr_army_manager.rules_automation = RulesAutomation.Level.AUTOMATIC
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main._ensure_solo_controller()   # an agreed Automatic room builds the engine controller (3.1)


func after_test() -> void:
	if _main != null:
		_main.network_manager = _real_net
	if _net != null:
		_net.free()
		_net = null
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## A one-model unit with one weapon of 10 attacks at Quality 2+, so some attack always lands and the
## defender always has saves to roll.
func _armed(pid: int, unit_name: String, x_in: float, range_in: int) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, [Vector3(x_in * INCH, 0.0, 0.0)])
	var opr := OPRApiClient.OPRUnit.new()
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Rifle" if range_in > 0 else "Blade"
	w.range_value = range_in
	w.attacks = 10
	opr.weapons = [w]
	u.source_type = "opr"
	u.source_data = opr
	u.unit_properties["quality"] = 2
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## Answers as the owner would: every request_roll gets roll_result faces (all 3s here, so they resolve);
## returns [kind, purpose] per request seen, once the driven flow has finished.
func _serve() -> Array:
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
			var faces: Array = []
			for _f in int(rq.get("count", 1)):
				faces.append(3)
			_main._on_network_command("roll_result", {"req": int(rq["req"]), "faces": faces}, HOST_PEER)
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


func _drive_volley(shooter: GameUnit, target: GameUnit) -> void:
	await _main._run_human_shooting(shooter, target)
	_flow_done = true


func _drive_melee(striker: GameUnit, defender: GameUnit) -> void:
	await _main._solo_melee_strike_phase(striker, defender, true, 0)   # 0 = SoloStrike.ALL
	_flow_done = true


func test_a_volley_at_the_other_humans_unit_asks_its_owner_to_roll(timeout := 120000,
		do_skip := OS.get_environment("NML_RUN_KNOWN_RED") != "1",
		skip_reason := "KNOWN BUG: the volley rolls the other human's saves on the shooter's tray (human_defends=false)") -> void:
	var host_unit := _armed(1, "Guards", -10.0, 12)
	var mine := _armed(2, "Raiders", 0.0, 12)
	_drive_volley(mine, host_unit)
	var seen: Array = await _serve()
	assert_bool(_flow_done).is_true()
	var kinds: Array = seen.map(func(s: Array) -> String: return str(s[0]))
	assert_bool(kinds.has("defense")).override_failure_message(
		"the saves of the host's unit never went to its owner (requests: %s)" % str(seen)).is_true()
	assert_str(_log_text()).override_failure_message("the guest rolled the host's saves on its own tray") \
		.not_contains(" defends: ")
	assert_str(_log_text()).contains("rolled their defense saves")


## Control: the same guest striking the host's unit in MELEE already routes the saves to the owner.
func test_a_melee_strike_at_the_other_humans_unit_asks_its_owner_to_roll(timeout := 120000) -> void:
	var host_unit := _armed(1, "Guards", 1.2, 0)
	var mine := _armed(2, "Raiders", 0.0, 0)
	_drive_melee(mine, host_unit)
	var seen: Array = await _serve()
	assert_bool(_flow_done).is_true()
	var kinds: Array = seen.map(func(s: Array) -> String: return str(s[0]))
	assert_bool(kinds.has("defense")).override_failure_message(
		"melee saves of the host's unit did not go to its owner (requests: %s)" % str(seen)).is_true()
	assert_str(_log_text()).not_contains(" defends: ")
	assert_str(_log_text()).contains("rolled their defense saves")
