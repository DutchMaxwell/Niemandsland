extends GdUnitTestSuite
## Plan 1.4: the rules-automation level travels, rooms stay Manual. Manual is unilateral (any peer
## may switch back, at once); Automatic online needs the later two-player agreement, so a room
## clamps to Manual and ignores an Automatic value on the wire.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const MANUAL := RulesAutomation.Level.MANUAL
const AUTOMATIC := RulesAutomation.Level.AUTOMATIC


## Real NetworkManager, transport swapped out: records the commands this client sends.
class FakeNet extends "res://scripts/network_manager.gd":
	var active: bool = true
	var cmds: Array = []
	func is_multiplayer_active() -> bool:
		return active
	func send_command(type: String, payload: Variant = {}, target_peer: int = 0) -> bool:
		cmds.append({"t": type, "p": payload, "to": target_peer})
		return true

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _fake: FakeNet


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_fake = auto_free(FakeNet.new())
	_fake.army_manager = _main.opr_army_manager
	_fake.player_names[2] = "Bea"
	_main.network_manager = _fake


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null
	_fake = null


func _lines(needle: String) -> int:
	var n := 0
	for e in _main.battle_log.entries():
		if str((e as Dictionary)["text"]).contains(needle):
			n += 1
	return n


func _sync_cmds() -> int:
	var n := 0
	for c in _fake.cmds:
		if str((c as Dictionary)["t"]) == "sync_rules_automation":
			n += 1
	return n


func test_accept_predicate_manual_from_any_peer_automatic_never() -> void:
	assert_bool(RulesAutomation.accepts_online(MANUAL)).is_true()
	assert_bool(RulesAutomation.accepts_online(float(MANUAL))).is_true()
	assert_bool(RulesAutomation.accepts_online(AUTOMATIC)).is_false()
	assert_bool(RulesAutomation.accepts_online("0")).is_false()
	assert_bool(RulesAutomation.accepts_online(null)).is_false()


func test_manual_command_from_any_peer_applies_and_logs_once() -> void:
	_main.opr_army_manager.rules_automation = AUTOMATIC
	_fake.active = false   # applying a received value must not need the clamp
	_main._on_network_command("sync_rules_automation", {"level": MANUAL}, 2)
	assert_int(_main.opr_army_manager.rules_automation).is_equal(MANUAL)
	assert_int(_lines("Rules automation: Manual (changed by Bea)")).is_equal(1)
	_main._on_network_command("sync_rules_automation", {"level": MANUAL}, 2)
	assert_int(_lines("Rules automation: Manual")).is_equal(1)   # no change, no second line


func test_automatic_command_is_ignored_in_a_room() -> void:
	_main.opr_army_manager.rules_automation = MANUAL
	_main._on_network_command("sync_rules_automation", {"level": AUTOMATIC}, 2)
	_main._on_network_command("sync_rules_automation", {"level": "x"}, 2)
	assert_int(_main.opr_army_manager.rules_automation).is_equal(MANUAL)
	assert_int(_lines("Rules automation")).is_equal(0)


func test_room_from_an_automatic_local_game_ends_manual_with_one_line_and_one_sync() -> void:
	_main.opr_army_manager.rules_automation = AUTOMATIC
	_main._clamp_rules_online("the room")
	_main._clamp_rules_online("the room")   # idempotent
	assert_int(_main.opr_army_manager.rules_automation).is_equal(MANUAL)
	assert_int(_lines("Rules automation: Manual")).is_equal(1)
	assert_int(_sync_cmds()).is_equal(1)
	var c: Dictionary = _fake.cmds[0]
	assert_int(int((c["p"] as Dictionary)["level"])).is_equal(MANUAL)


func test_no_clamp_without_a_live_session() -> void:
	_fake.active = false
	_main.opr_army_manager.rules_automation = AUTOMATIC
	_main._clamp_rules_online("the room")
	assert_int(_main.opr_army_manager.rules_automation).is_equal(AUTOMATIC)
	assert_int(_sync_cmds()).is_equal(0)


func test_full_state_push_carries_and_clamps_the_level() -> void:
	# Host side: the serializer carries the level (late joiners read it from the push).
	_main.opr_army_manager.rules_automation = AUTOMATIC
	var st: Dictionary = _main.save_manager.serialize_game_state()
	assert_int(RulesAutomation.from_game_state(st["game_state"])).is_equal(AUTOMATIC)
	# Guest side: after adopting a pushed state the room is Manual again.
	_main.opr_army_manager.rules_automation = RulesAutomation.from_game_state(st["game_state"])
	_main._clamp_rules_online("the host")
	assert_int(_main.opr_army_manager.rules_automation).is_equal(MANUAL)
