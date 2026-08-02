extends GdUnitTestSuite
## E2E — NML-945: a unit that LEFT THE TABLE has to leave it on every screen.
##
## THE DEFECT. Ambush Re-Deployment withdraws a unit for a round: _solo_ambush_redeploy_execute sets
## the reserve flag and calls _solo_set_unit_visible(gu, false), which walks the unit's model nodes
## and flips Node3D.visible. Both halves stayed on the client that did the arithmetic — there is no
## visibility message for unit models at all. sync_object_visibility does not cover this: it
## addresses ONE node by network_id among ObjectManager's DIRECT children (a regiment member lives
## under its tray and is unreachable there) and stamps the "deleted" meta, which is the delete/undo
## semantics for terrain and TTS props.
##
## So the opponent kept a unit standing that the acting client had already booked as gone: visible,
## measurable, shootable, chargeable, and counted by every reserve-filtered scan. And the two halves
## of the game contradicted each other — `visible` DOES travel in the state sync (save_manager writes
## model_positions[i].visible), so the ghost vanished the moment that peer rejoined. Same unit, two
## answers, depending on which path spoke last.
##
## THE FIX UNDER TEST. broadcast_unit_visible / sync_unit_visible — one more handler name inside the
## existing {"m","a"} command envelope, sent from INSIDE the _solo_set_unit_visible choke point so
## all three flips (the withdrawal, the AI's ambush arrival, the human's placement from reserve) are
## covered by construction. The message states BOTH facts, visible and in-reserve, because here they
## are separate state (model nodes vs. unit_properties) that nothing keeps in lockstep.
##
## REACHABILITY, honestly: these rules run wherever solo_controller exists, which in a networked room
## means a room with an explicitly designated AI slot (_ensure_solo_controller, main.gd:2021). That
## covers NACHTMAHR's own units AND the human units in such a room — _solo_try_ambush_redeploy hangs
## off the end of the human activation. A plain human-vs-human room has no solo_controller and never
## reaches these paths.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254


## Stands in for NetworkManager at main's seam: a live session that records every outbound
## visibility message in the order main sent them.
class FakeNet extends Node:
	var active: bool = true
	var sent: Array = []
	func is_multiplayer_active() -> bool:
		return active
	func slot_has_human_peer(_slot: int) -> bool:
		return false
	func broadcast_unit_visible(game_unit: GameUnit, is_visible: bool) -> void:
		# Mirrors the real sender: the reserve flag is read HERE, at send time.
		if not active or game_unit == null:
			return
		sent.append({"unit_id": game_unit.unit_id, "visible": is_visible,
			"reserve": bool(game_unit.unit_properties.get("ambush_reserve", false))})

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _fake: FakeNet
var _real_net: Node


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main._solo_batch = true   # no dialogs, no physics tray in a headless sweep
	_real_net = _main.network_manager   # the REAL NetworkManager node, kept for the wire replay
	_fake = auto_free(FakeNet.new())
	_main.network_manager = _fake


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null
	_fake = null
	_real_net = null


func _reg(u: GameUnit) -> GameUnit:
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## A HUMAN unit (slot 1) carrying Ambush Re-Deployment with its once-per-game use unspent. The human
## side is deliberate: the audit's point is that this bites your own units too, because
## _solo_try_ambush_redeploy hangs off the end of the human activation.
func _withdrawable() -> GameUnit:
	var u := _reg(E2EBoot.make_unit(_main, 1, "Raiders", [Vector3.ZERO, Vector3(0.5 * INCH, 0, 0)]))
	u.unit_properties["special_rules"] = ["Ambush Re-Deployment"]
	return u


func _visible_models(u: GameUnit) -> int:
	var n := 0
	for mi in u.models:
		var node: Node3D = (mi as ModelInstance).node
		if node != null and node.visible:
			n += 1
	return n


# === The sending half ==========================================================================

func test_the_withdrawal_leaves_this_client(timeout := 120000) -> void:
	var u := _withdrawable()
	_main.opr_army_manager.current_round = 2
	assert_bool(_main._solo_ambush_redeploy_execute(u)) \
		.override_failure_message("fixture check: the withdrawal must actually happen") \
		.is_true()
	assert_int(_visible_models(u)) \
		.override_failure_message("fixture check: the withdrawal must hide the models locally") \
		.is_equal(0)
	assert_int(_fake.sent.size()) \
		.override_failure_message("the withdrawal never left this client — the opponent keeps a unit standing that is off the table here (sent: %s)" % str(_fake.sent)) \
		.is_equal(1)
	var msg: Dictionary = (_fake.sent[0] as Dictionary) if not _fake.sent.is_empty() else {}
	assert_str(str(msg.get("unit_id", ""))).is_equal(u.unit_id)
	assert_bool(bool(msg.get("visible", true))) \
		.override_failure_message("the message does not say the unit left the table") \
		.is_false()
	assert_bool(bool(msg.get("reserve", false))) \
		.override_failure_message("the reserve flag did not ride along — the peer would keep the unit in its target and activation pools even with the models hidden") \
		.is_true()


func test_the_return_travels_too(timeout := 120000) -> void:
	# Same seam, other direction. Both arrival sites (the AI's paced ambush beat and the human's
	# placement from reserve) clear the reserve flag and then call THIS function; a reveal that
	# stayed local would strand the unit hidden on the peer for the rest of the game.
	var u := _withdrawable()
	_main.opr_army_manager.current_round = 2
	_main._solo_ambush_redeploy_execute(u)
	_fake.sent.clear()
	u.unit_properties["ambush_reserve"] = false
	_main._solo_set_unit_visible(u, true)
	assert_int(_fake.sent.size()) \
		.override_failure_message("the return never left this client (sent: %s)" % str(_fake.sent)) \
		.is_equal(1)
	var msg: Dictionary = (_fake.sent[0] as Dictionary) if not _fake.sent.is_empty() else {}
	assert_bool(bool(msg.get("visible", false))).is_true()
	assert_bool(bool(msg.get("reserve", true))) \
		.override_failure_message("the peer is told the unit is back but still in reserve") \
		.is_false()


func test_an_offline_game_hides_the_unit_and_sends_nothing(timeout := 120000) -> void:
	# Counter-proof: solo must behave exactly as before — no message, no error on a manager that
	# refuses to send.
	_fake.active = false
	var u := _withdrawable()
	_main.opr_army_manager.current_round = 2
	assert_bool(_main._solo_ambush_redeploy_execute(u)).is_true()
	assert_int(_visible_models(u)) \
		.override_failure_message("the offline withdrawal stopped hiding the unit") \
		.is_equal(0)
	assert_array(_fake.sent) \
		.override_failure_message("an offline game broadcast a visibility message") \
		.is_empty()


# === The receiving half — what the guest actually does with it ==================================

## THE RED PROOF the audit asked for: before the fix the guest can still pick the withdrawn unit as a
## shooting target, because nothing about the withdrawal ever reached it. nearest_human_unit is the
## official not-activated-first/nearest target key — the very function that is supposed to skip
## anything still off the table in reserve.
func test_a_guest_stops_choosing_the_withdrawn_unit_as_a_target(timeout := 120000) -> void:
	var solo = _main.solo_controller
	var shooter := _reg(E2EBoot.make_unit(_main, 2, "Gunners", [Vector3(6.0 * INCH, 0, 0)]))
	var u := _withdrawable()
	# The guest's world BEFORE any message arrives: the unit stands there and is a legal pick.
	assert_object(solo.nearest_human_unit(shooter)) \
		.override_failure_message("fixture check: the unit must be a legal target while it is on the table") \
		.is_same(u)
	# The wire message arrives and is applied by the REAL receiver.
	_main._on_remote_unit_visibility_updated(u, false, true)
	assert_int(_visible_models(u)) \
		.override_failure_message("the guest still has the unit's models on the table") \
		.is_equal(0)
	assert_bool(SoloController.unit_in_reserve(u)) \
		.override_failure_message("the guest never learned the unit is in reserve — every reserve-filtered scan still counts it") \
		.is_true()
	assert_object(solo.nearest_human_unit(shooter)) \
		.override_failure_message("the guest still offers the withdrawn unit as a shooting target — it is off the table on the other screen") \
		.is_null()


func test_the_return_message_puts_the_unit_back(timeout := 120000) -> void:
	var solo = _main.solo_controller
	var shooter := _reg(E2EBoot.make_unit(_main, 2, "Gunners", [Vector3(6.0 * INCH, 0, 0)]))
	var u := _withdrawable()
	_main._on_remote_unit_visibility_updated(u, false, true)
	_main._on_remote_unit_visibility_updated(u, true, false)
	assert_int(_visible_models(u)).is_equal(u.models.size())
	assert_bool(SoloController.unit_in_reserve(u)).is_false()
	assert_object(solo.nearest_human_unit(shooter)) \
		.override_failure_message("the returned unit is still invisible to the guest's targeting") \
		.is_same(u)


func test_the_receiver_does_not_echo_the_message_back(timeout := 120000) -> void:
	# The split between _solo_set_unit_visible (apply + send) and _apply_unit_visible (apply only) is
	# what stops two peers bouncing the same flip at each other forever.
	var u := _withdrawable()
	_main._on_remote_unit_visibility_updated(u, false, true)
	assert_array(_fake.sent) \
		.override_failure_message("applying a peer's message sent it straight back out (sent: %s)" % str(_fake.sent)) \
		.is_empty()


## The REAL RPC handler, not a stand-in: sync_unit_visible resolves the unit by unit_id through the
## army manager and emits the signal main is connected to. This is what _on_raw_command calls by name
## when the frame arrives.
func test_the_real_rpc_handler_reaches_the_unit(timeout := 120000) -> void:
	var u := _withdrawable()
	assert_object(_real_net) \
		.override_failure_message("fixture check: the real NetworkManager node must exist in main.tscn") \
		.is_not_null()
	_real_net.sync_unit_visible(u.unit_id, false, true)
	assert_int(_visible_models(u)) \
		.override_failure_message("the wire frame did not reach the unit through the real handler") \
		.is_equal(0)
	assert_bool(SoloController.unit_in_reserve(u)).is_true()


func test_an_unknown_unit_id_is_ignored(timeout := 120000) -> void:
	# A frame for a unit this peer does not have (army sync still running, or a unit already deleted)
	# must be dropped quietly, not crash the handler.
	_real_net.sync_unit_visible("no_such_unit", false, true)
	assert_bool(true).is_true()
