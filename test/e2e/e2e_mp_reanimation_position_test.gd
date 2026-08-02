extends GdUnitTestSuite
## E2E — the reanimation RESTORE POSITION has to ride the wire.
##
## THE DEFECT. broadcast_model_wounds sends [unit, model, wounds, alive, dead_slot] and no position,
## so a peer receiving "alive again" rebuilds the spot itself: set_loose_model_dead(dead=false) puts
## the model back on its stashed revive_transform — the point where it FELL. The reanimation placer
## does not always choose that point: when the fall point is blocked it stands the model on a free
## ring position beside a survivor, and that choice never left the acting client. Host and guest then
## showed the same model in two places, and coherency, range and line of sight followed the wrong one.
##
## The fix under test mirrors the ghost-placed disembark correction: after the wounds message, push
## the model's REAL position through the ordinary move channel.
##
## The suite drives the REAL main.tscn resolver (_solo_resolve_reanimation) and records what main
## hands to NetworkManager, in order.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254


## Stands in for NetworkManager at main's seam: a live session that records every outbound
## wounds/position message in the order main sent them.
class FakeNet extends Node:
	var active: bool = true
	var sent: Array = []
	func is_multiplayer_active() -> bool:
		return active
	func slot_has_human_peer(_slot: int) -> bool:
		return false
	func broadcast_model_wounds(model: ModelInstance) -> void:
		sent.append({"kind": "wounds", "index": model.model_index, "alive": model.is_alive})
	func broadcast_move(object_id: int, pos: Vector3) -> void:
		sent.append({"kind": "move", "id": object_id, "pos": pos})

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
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	# Batch mode: no physics dice tray, no floating text — headless would never settle either.
	_main._solo_batch = true
	_fake = auto_free(FakeNet.new())
	_main.network_manager = _fake


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null
	_fake = null


## A two-model reanimating unit whose casualty FELL ON TOP of its surviving comrade: the fall point
## is blocked, so the placer must find a ring spot — the exact case the peer cannot reconstruct.
## Model nodes carry the network_id meta the army spawn assigns them (opr_army_manager).
func _bots_with_blocked_fall_point() -> GameUnit:
	var u := E2EBoot.make_unit(_main, 2, "Bots", [Vector3.ZERO, Vector3(0.5 * INCH, 0, 0)])
	_main.opr_army_manager.game_units[u.unit_id] = u
	u.unit_properties["special_rules"] = ["Reanimation"]
	u.unit_properties["faction_folder"] = "robot_legions"
	for i in u.models.size():
		var m := u.models[i] as ModelInstance
		m.model_index = i
		m.node.set_meta("network_id", 4200 + i)
	var dead := u.models[1] as ModelInstance
	dead.wounds_current = 0
	dead.is_alive = false
	# Fall on the comrade, then die through the REAL parking path — that is what stashes the
	# revive_transform the peer would restore to.
	dead.node.global_position = (u.models[0] as ModelInstance).node.global_position
	_main.opr_army_manager.set_loose_model_dead(dead.node, 2, true, u.unit_id)
	return u


func _fall_point(model: ModelInstance) -> Vector3:
	return (model.node.get_meta("revive_transform") as Transform3D).origin


func _moves() -> Array:
	var out: Array = []
	for e in _fake.sent:
		if str((e as Dictionary)["kind"]) == "move":
			out.append(e)
	return out


func test_the_ring_spot_travels_not_the_fall_point(timeout := 120000) -> void:
	var u := _bots_with_blocked_fall_point()
	var back := u.models[1] as ModelInstance
	var fell: Vector3 = _fall_point(back)
	await _main._solo_resolve_reanimation(u, 1, 5, 1)
	assert_bool(back.is_alive) \
		.override_failure_message("fixture check: the success must actually restore the model") \
		.is_true()
	var here: Vector3 = back.node.global_position
	assert_float(here.distance_to(fell)) \
		.override_failure_message("fixture check: a blocked fall point must send the model to a RING spot") \
		.is_greater(0.01)
	var moves := _moves()
	assert_int(moves.size()) \
		.override_failure_message("the restored model's position never left this client — the peer keeps the fall point (sent: %s)" % str(_fake.sent)) \
		.is_equal(1)
	# Read defensively: with no message at all the assertions below must still FAIL cleanly
	# (an out-of-bounds index would break gdUnit's -d run into the debugger instead).
	var msg: Dictionary = (moves[0] as Dictionary) if not moves.is_empty() else {}
	var told: Vector3 = msg.get("pos", Vector3.INF)
	assert_int(int(msg.get("id", -1))).is_equal(int(back.node.get_meta("network_id")))
	assert_float(told.distance_to(here)) \
		.override_failure_message("the peer is told a position the model does not stand on") \
		.is_less(0.001)
	assert_float(told.distance_to(fell)) \
		.override_failure_message("the fall point was broadcast instead of the ring spot — the divergence stays") \
		.is_greater(0.01)


func test_the_wounds_message_goes_first(timeout := 120000) -> void:
	# Order is load-bearing: the wounds message is what un-parks the model on the peer (and drops
	# it on the fall point). A correction that arrives BEFORE it would be overwritten.
	var u := _bots_with_blocked_fall_point()
	await _main._solo_resolve_reanimation(u, 1, 5, 1)
	var kinds: Array = []
	for e in _fake.sent:
		kinds.append(str((e as Dictionary)["kind"]))
	assert_int(kinds.find("wounds")) \
		.override_failure_message("no wounds message at all (sent: %s)" % str(kinds)) \
		.is_greater_equal(0)
	assert_int(kinds.find("move")) \
		.override_failure_message("the position correction must follow the wounds message, not precede it (sent: %s)" % str(kinds)) \
		.is_greater(kinds.find("wounds"))


func test_solo_without_peers_sends_nothing_and_still_stands_the_model_up(timeout := 120000) -> void:
	# Counter-proof: offline the correction must stay silent — a solo game keeps working exactly
	# as before, no message and no error on a NetworkManager that refuses to send.
	_fake.active = false
	var u := _bots_with_blocked_fall_point()
	var back := u.models[1] as ModelInstance
	var fell: Vector3 = _fall_point(back)
	await _main._solo_resolve_reanimation(u, 1, 5, 1)
	assert_bool(back.is_alive).is_true()
	assert_float(back.node.global_position.distance_to(fell)) \
		.override_failure_message("solo placement changed with the MP fix") \
		.is_greater(0.01)
	assert_array(_moves()) \
		.override_failure_message("an offline game broadcast a position") \
		.is_empty()


func test_a_regiment_member_is_left_to_its_block(timeout := 120000) -> void:
	# The deliberate channel choice: regiment members live under their tray, so the move handler
	# (it walks ObjectManager's direct children) cannot address them — and does not have to, because
	# the peer re-ranks the block from the wounds message. Broadcasting a stray position for them
	# would be a message no receiver can apply.
	var u := _bots_with_blocked_fall_point()
	var back := u.models[1] as ModelInstance
	var tray: Node3D = auto_free(Node3D.new())
	back.node.set_meta(RegimentTray.MEMBER_META, tray)
	_main._broadcast_restored_position(back)
	assert_array(_moves()) \
		.override_failure_message("a per-model position was sent for a model that lives inside a tray") \
		.is_empty()
