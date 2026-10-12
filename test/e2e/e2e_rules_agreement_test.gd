extends GdUnitTestSuite
## Plan 3.0 (Q6): online Automatic needs BOTH players. One proposes (`propose_rules_automation`), the
## other confirms (`confirm_rules_automation`) — only then do both apply Automatic with the line
## "Rules automation: Automatic (agreed by P1 and P2)". A decline, or a 30 s silence, stays Manual with
## one plain line. Manual stays unilateral and immediate (maintainer A1). A bare Automatic value on the
## wire is still ignored (step 1.4): the agreement is the only door.

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
	RulesAutomation.ui_enabled_override = true
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
	RulesAutomation.ui_enabled_override = false
	RulesAutomation.ui_disabled_override = false
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null
	_fake = null


func _cmds(type: String) -> int:
	var n := 0
	for c in _fake.cmds:
		if str((c as Dictionary)["t"]) == type:
			n += 1
	return n


func _lines(needle: String) -> int:
	var n := 0
	for e in _main.battle_log.entries():
		if str((e as Dictionary)["text"]).contains(needle):
			n += 1
	return n


func test_automatic_needs_the_second_peers_confirm() -> void:
	_main.opr_army_manager.rules_automation = MANUAL
	_main._on_network_command("sync_rules_automation", {"level": AUTOMATIC}, 2)
	assert_int(_main.opr_army_manager.rules_automation).is_equal(MANUAL)
	_main._on_network_command("confirm_rules_automation", {}, 2)
	assert_int(_main.opr_army_manager.rules_automation).is_equal(AUTOMATIC)
	assert_int(_lines("Rules automation: Automatic (agreed by P1 and P2)")).is_equal(1)


func test_a_guest_can_propose_and_the_chip_shows_it_is_waiting() -> void:
	_main.opr_army_manager.rules_automation = MANUAL
	assert_bool(_main.propose_rules_automation()).is_true()
	assert_int(_cmds("propose_rules_automation")).is_equal(1)
	assert_bool(_main._rules_proposal_pending).is_true()
	_main._update_rules_chip()
	if _main._rules_chip != null:
		assert_bool(_main._rules_chip.text.to_lower().contains("other player")).is_true()


func test_accepting_a_proposal_applies_logs_and_confirms_back() -> void:
	_main.opr_army_manager.rules_automation = MANUAL
	_main._on_rules_agreement_response(true, 2)
	assert_int(_main.opr_army_manager.rules_automation).is_equal(AUTOMATIC)
	assert_int(_lines("Rules automation: Automatic (agreed by P1 and P2)")).is_equal(1)
	assert_int(_cmds("confirm_rules_automation")).is_equal(1)


func test_declining_a_proposal_stays_manual() -> void:
	_main.opr_army_manager.rules_automation = MANUAL
	_main._on_rules_agreement_response(false, 2)
	assert_int(_main.opr_army_manager.rules_automation).is_equal(MANUAL)
	assert_int(_lines("did not agree")).is_equal(1)
	assert_int(_cmds("decline_rules_automation")).is_equal(1)


func test_manual_is_unilateral_and_immediate() -> void:
	_main.opr_army_manager.rules_automation = AUTOMATIC
	_main._on_network_command("sync_rules_automation", {"level": MANUAL}, 2)
	assert_int(_main.opr_army_manager.rules_automation).is_equal(MANUAL)


func test_waiting_state_reverts_on_timeout() -> void:
	_main.opr_army_manager.rules_automation = MANUAL
	_main.propose_rules_automation()
	assert_bool(_main._rules_proposal_pending).is_true()
	_main._on_rules_agreement_timeout()
	assert_bool(_main._rules_proposal_pending).is_false()
	assert_int(_main.opr_army_manager.rules_automation).is_equal(MANUAL)
	assert_int(_lines("did not confirm, rules stay manual")).is_equal(1)
	_main._update_rules_chip()
	if _main._rules_chip != null:
		assert_bool(_main._rules_chip.text.to_lower().contains("other player")).is_false()
