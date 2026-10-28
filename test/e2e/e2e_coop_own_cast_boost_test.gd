extends GdUnitTestSuite
## Online co-op (#673): two humans (the host on slot 1, the guest on slot 2) against NACHTMAHR (slot 3).
## A player's cast is boosted by "friendly casters within 18\"" — that player's OWN casters, whose tokens
## are that player's to spend. The boost tableau opens on the caster's machine, so its helpers must be
## the caster's own slot, never the other human's casters (whose tokens this machine does not own).
## Real: scenes/main.tscn, _run_human_cast, the real "Boost your cast?" card. The network side is the
## owner-roll suites' NetworkManager double (records every send instead of sending).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254
const HOST_PEER := 1
const GUEST_PEER := 42
const AI_SLOT := 3

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _real_net: Node
var _net: Node


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main._solo_batch = true
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_real_net = _main.network_manager


func after_test() -> void:
	_end_session()
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## A co-op room: the host (peer 1) on slot 1, the guest on slot 2, NACHTMAHR on slot 3 (nobody seated).
func _fake_session(my_slot: int) -> void:
	var src := GDScript.new()
	src.source_code = "extends \"res://scripts/network_manager.gd\"\nvar sent: Array = []\nvar my_slot := 1\n" \
		+ "func is_multiplayer_active() -> bool:\n\treturn true\n" \
		+ "func get_my_player_slot() -> int:\n\treturn my_slot\n" \
		+ "func _validate_rpc_ready(_context: String = \"\") -> bool:\n\treturn true\n" \
		+ "func send_command(type: String, payload: Variant = {}, target_peer: int = 0) -> bool:\n" \
		+ "\tsent.append([type, payload, target_peer])\n\treturn true\n"
	assert_int(src.reload()).is_equal(OK)
	_net = src.new()
	_net.my_slot = my_slot
	_net.peer_to_slot = {HOST_PEER: 1, GUEST_PEER: 2}
	_net.player_names = {HOST_PEER: "Host", GUEST_PEER: "Guest"}
	_main.network_manager = _net


func _end_session() -> void:
	if _main != null:
		_main.solo_ai_slots = {}
		_main.network_manager = _real_net
	if _net != null:
		_net.free()
		_net = null


func _reg(pid: int, unit_name: String, x_in: float, tokens: int = 0) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, [Vector3(x_in * INCH, 0.0, 0.0)])
	u.unit_properties["special_rules"] = ["Caster(2)"] if tokens > 0 else []
	u.casts_current = tokens
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func _log_from(start: int) -> String:
	var t := ""
	for e in _main.battle_log.entries().slice(start):
		t += str((e as Dictionary)["text"]) + "\n"
	return t


func _boost_card() -> PromptCard:
	for n in _main.get_children():
		if n is InterferenceDialog:
			for c in n.get_children():
				if c is PromptCard and (c as PromptCard).title == "Boost your cast?":
					return c
	return null


func _wait(cond: Callable) -> void:
	for _i in 300:
		if cond.call():
			return
		await get_tree().process_frame


## `seer` (one token, spent on the cast itself) casts at NACHTMAHR's Brutes; one token of boost is taken.
## Returns the battle-log text of the cast.
func _cast_with_one_boost(seer: GameUnit, brutes: GameUnit) -> String:
	var start: int = _main.battle_log.entries().size()
	var done := [false]
	(func() -> void:
		await _main._run_human_cast(seer, seer, {"name": "Bolt", "threshold": 1}, [brutes])
		done[0] = true).call()
	await _wait(func() -> bool: return done[0] or _boost_card() != null)
	var card := _boost_card()
	assert_object(card).override_failure_message("no boost tableau opened:\n%s" % _log_from(start)).is_not_null()
	if card != null:
		card.resolve(1)
	await _wait(func() -> bool: return done[0])
	assert_bool(done[0]).override_failure_message("the cast never resolved:\n%s" % _log_from(start)).is_true()
	return _log_from(start)


## The guest's machine: the guest's Seer casts. Its own Acolyte AND the host's Oracle stand within 18".
## The boost is the guest's to pay — from the guest's Acolyte, never from the host's Oracle.
func test_a_guests_cast_is_boosted_by_the_guests_own_casters(timeout := 120000) -> void:
	_fake_session(2)
	_main.solo_ai_slots = {AI_SLOT: true}
	var seer := _reg(2, "Seer", 0.0, 1)
	var acolyte := _reg(2, "Acolyte", -6.0, 2)
	var oracle := _reg(1, "Oracle", 4.0, 2)
	var brutes := _reg(AI_SLOT, "Brutes", 10.0)
	_main._ensure_solo_controller()
	assert_object(_main.solo_controller).override_failure_message("fixture: no AI controller").is_not_null()
	var sides: Dictionary = _main._solo_cast_sides(seer)
	assert_int(int(sides["own"])).override_failure_message("the guest's cast is booked under slot %d's side" % int(sides["own"])) \
		.is_equal(2)
	assert_array(sides["foes"]).is_equal([AI_SLOT])
	var text := await _cast_with_one_boost(seer, brutes)
	assert_int(oracle.casts_current).override_failure_message(
		"the host's Oracle paid the guest's boost (the guest's machine spent the host's token):\n%s" % text).is_equal(2)
	assert_int(acolyte.casts_current).override_failure_message(
		"the guest's own Acolyte was not the boost's payer:\n%s" % text).is_equal(1)
	assert_str(text).override_failure_message("the boost's payer was not named:\n%s" % text) \
		.contains("Boost: Acolyte ×1 spends 1 token — the cast roll improves to 3+")
	await E2EBoot.settle(get_tree())
	_end_session()   # inside the test: an unparented double alive at its end counts as an orphan


## Regression guard: the host's own cast is boosted by the host's own casters (before and after).
func test_a_hosts_cast_is_boosted_by_the_hosts_own_casters(timeout := 120000) -> void:
	_fake_session(1)
	_main.solo_ai_slots = {AI_SLOT: true}
	var seer := _reg(1, "Seer", 0.0, 1)
	var oracle := _reg(1, "Oracle", -6.0, 2)
	var acolyte := _reg(2, "Acolyte", 4.0, 2)
	var brutes := _reg(AI_SLOT, "Brutes", 10.0)
	_main._ensure_solo_controller()
	var text := await _cast_with_one_boost(seer, brutes)
	assert_int(oracle.casts_current).override_failure_message("the host's own Oracle did not pay:\n%s" % text).is_equal(1)
	assert_int(acolyte.casts_current).override_failure_message("the guest's Acolyte paid the host's boost:\n%s" % text) \
		.is_equal(2)
	await E2EBoot.settle(get_tree())
	_end_session()


## Solo vs NACHTMAHR (no session): the player's casters boost, as always.
func test_solo_cast_is_boosted_by_the_players_casters(timeout := 120000) -> void:
	_main.solo_ai_slots = {2: true}
	var seer := _reg(1, "Seer", 0.0, 1)
	var oracle := _reg(1, "Oracle", -6.0, 2)
	var brutes := _reg(2, "Brutes", 10.0)
	_main._ensure_solo_controller()
	var text := await _cast_with_one_boost(seer, brutes)
	assert_int(oracle.casts_current).override_failure_message("the player's Oracle did not pay:\n%s" % text).is_equal(1)
	assert_str(text).contains("needs 3+ (1 token, +1 boost)")
	await E2EBoot.settle(get_tree())
	_end_session()
