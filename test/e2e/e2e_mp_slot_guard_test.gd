extends GdUnitTestSuite
## E2E — #196 CRITICAL: in a human-vs-human multiplayer room the host's solo automation
## hijacked the guest's slot ("activated (AI)", "AI (X) defends", NACHTMAHR playing the
## guest's army). Root cause: the implicit "no designation → P2 is the AI" solo default
## held in multiplayer too, and one targeting/cast click summoned the controller for good.
##
## This suite drives the REAL main.tscn with a REAL ENet server peer (an empty room is
## enough — is_multiplayer_active() and the mirrored slot table are what the guards read):
##  - the choke-point predicate _solo_is_ai_unit (all ~35 automation consumers),
##  - the controller summon gate, the radial combat gate,
##  - designation refusal + the join-time release (with its rules-must-log line).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const TEST_PORT := 47831
const GUEST_PEER := 777

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _server: ENetMultiplayerPeer


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)


func after_test() -> void:
	if _server != null:
		_server.close()
		_server = null
	if _main != null:
		_main.get_tree().get_multiplayer().multiplayer_peer = OfflineMultiplayerPeer.new()
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## Turn this scene into a live multiplayer host: a real ENet server (no guests needed) plus
## the slot table exactly as the join handshake leaves it.
func _go_multiplayer(peer_to_slot: Dictionary) -> void:
	_server = ENetMultiplayerPeer.new()
	assert_int(_server.create_server(TEST_PORT)).is_equal(OK)
	_main.get_tree().get_multiplayer().multiplayer_peer = _server
	_main.network_manager.peer_to_slot = peer_to_slot
	assert_bool(_main.network_manager.is_multiplayer_active()).is_true()


func _unit_for(pid: int, unit_name: String) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, [Vector3.ZERO])
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func test_human_peer_slot_is_never_the_ai(timeout := 120000) -> void:
	var u2 := _unit_for(2, "GuestArmy")
	# SOLO baseline: offline, the implicit "P2 is NACHTMAHR" default stands.
	_main.solo_ai_slots = {}
	assert_bool(_main._solo_is_ai_unit(u2)).is_true()
	# Multiplayer, no designation: NOBODY is an AI unit — this implicit branch WAS the hijack.
	_go_multiplayer({1: 1})
	assert_bool(_main._solo_is_ai_unit(u2)) \
		.override_failure_message("#196 — with no AI designation at all, multiplayer still treats P2 as NACHTMAHR's") \
		.is_false()
	# Explicit designation but a human peer SITS on the slot: the hard guard wins.
	_main.solo_ai_slots = {2: true}
	_main.network_manager.peer_to_slot = {1: 1, GUEST_PEER: 2}
	assert_bool(_main._solo_is_ai_unit(u2)) \
		.override_failure_message("#196 — a stale AI designation outranked the connected human on the slot") \
		.is_false()
	# Explicit designation, slot vacant: NACHTMAHR may drive it (the deliberate co-op path).
	_main.network_manager.peer_to_slot = {1: 1}
	assert_bool(_main._solo_is_ai_unit(u2)).is_true()


func test_no_controller_summoned_in_a_human_room(timeout := 120000) -> void:
	_go_multiplayer({1: 1, GUEST_PEER: 2})
	_main.solo_ai_slots = {}
	_main._ensure_solo_controller()
	assert_object(_main.solo_controller) \
		.override_failure_message("#196 — a cast/targeting click in a human-vs-human room summoned NACHTMAHR (the controller's existence arms the alternation pump)") \
		.is_null()


func test_radial_combat_hidden_in_a_human_room(timeout := 120000) -> void:
	var u1 := _unit_for(1, "HostArmy")
	var _u2 := _unit_for(2, "GuestArmy")
	# Solo baseline: Shoot/Fight available against the AI's living units.
	_main.solo_ai_slots = {}
	assert_bool(_main.solo_combat_available(u1)).is_true()
	# Human room: no automation-driven enemy → the solo entries stay out of the radial.
	_go_multiplayer({1: 1, GUEST_PEER: 2})
	assert_bool(_main.solo_combat_available(u1)) \
		.override_failure_message("#196 — the radial still offers solo Shoot/Fight against a human's army") \
		.is_false()


func test_designating_an_occupied_slot_is_refused(timeout := 120000) -> void:
	_go_multiplayer({1: 1, GUEST_PEER: 2})
	_main._on_solo_ai_toggled(true, 2)
	assert_bool(_main.solo_ai_slots.has(2)) \
		.override_failure_message("#196 — the Solo panel handed a connected human's slot to NACHTMAHR") \
		.is_false()
	# The vacant slot 3 stays designatable (co-op path unharmed).
	_main._on_solo_ai_toggled(true, 3)
	assert_bool(_main.solo_ai_slots.has(3)).is_true()


func test_join_release_strips_the_designation_and_logs(timeout := 120000) -> void:
	_go_multiplayer({1: 1, GUEST_PEER: 2})
	_main.solo_ai_slots = {2: true}
	_main._solo_release_slot_to_human(2)
	assert_bool(_main.solo_ai_slots.has(2)).is_false()
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	assert_str(text).contains("NACHTMAHR releases the slot")


func test_join_release_tears_down_a_surviving_controller(timeout := 120000) -> void:
	# The solo-session-rolls-into-hosting sequence: the controller is built OFFLINE (solo
	# match), then a human joins its slot. The designation strip alone is not enough — the
	# alternation pump drives by controller.ai_slot, not by the designation.
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	assert_object(_main.solo_controller).is_not_null()
	_go_multiplayer({1: 1, GUEST_PEER: 2})
	_main._solo_release_slot_to_human(2)
	assert_object(_main.solo_controller) \
		.override_failure_message("#196 — the controller from the earlier solo session survived the join release: the pump would still drive the guest's slot") \
		.is_null()
