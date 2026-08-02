extends GdUnitTestSuite
## E2E — a unit MINTED mid-game (reinforcement / split / spawn) has to survive the wire.
##
## THE CHANNEL UNDER TEST. scripts/network_manager.gd's "Runtime Unit Creation" block (see the
## header comment there) gives a mid-game unit its own one-shot message instead of dragging it
## through the whole-army batch: build_unit_created_payload / broadcast_unit_created /
## sync_unit_created, guarded by a per-slot BAND authority (may_create_units_for_slot) so a peer can
## only mint ids in a band it owns, an in-flight guard so a duplicate delivery arriving mid-build
## can't double the models, and the restore lock so a creation queues behind a concurrent army
## build instead of racing it.
##
## This suite drives those REAL bodies against the REAL main.tscn (opr_army_manager, object_manager,
## save_manager all live), with only the actual socket send swapped for a recorder — see
## test/e2e/recording_net.gd for exactly what layer that double sits at and why.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const RecordingNet := preload("res://test/e2e/recording_net.gd")

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _net: RecordingNet


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_net = auto_free(RecordingNet.new())
	_main.add_child(_net)
	_net.army_manager = _main.opr_army_manager
	_main.network_manager = _net


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null
	_net = null


## A 2-model unit whose model nodes look like REAL spawned OPR models (groups + metas), because
## save_manager._serialize_object keys off "opr_unit" group membership and "game_unit" meta
## (save_manager.gd:188) — a fixture without them would silently serialize to an empty dict.
func _make_created_unit(slot: int, unit_name: String) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = GameUnit.generate_unit_id()
	u.unit_properties = {"player_id": slot, "name": unit_name, "quality": 4, "defense": 4}
	for i in 2:
		var n := Node3D.new()
		n.name = "%s_m%d" % [unit_name, i]
		n.add_to_group("selectable")
		n.add_to_group("opr_unit")
		_main.object_manager.add_child(n)
		n.global_position = Vector3(0.3 * i, 0.0, 0.5)
		n.set_meta("network_id", slot * OPRArmyManager.OPR_NET_ID_SLOT_STRIDE + 900 + i)
		n.set_meta("model_index", i)
		n.set_meta("game_unit", u)
		var m := ModelInstance.new()
		m.is_alive = true
		m.unit = u
		m.model_index = i
		m.node = n
		u.models.append(m)
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## Simulates "this unit was never on the receiving table": erase it from the unit registry and free
## its model nodes (free(), not queue_free() — the later table count has to be deterministic, not
## waiting on a frame). The `u` handle itself and any dict already captured from it (a payload) stay
## valid — only the live table state is rolled back.
func _forget_unit(u: GameUnit) -> void:
	_main.opr_army_manager.game_units.erase(u.unit_id)
	for model in u.models:
		var m := model as ModelInstance
		if m == null or m.node == null or not is_instance_valid(m.node):
			continue
		var n := m.node
		var parent := n.get_parent()
		if parent != null:
			parent.remove_child(n)
		n.free()


## How many of object_manager's children carry a network_id meta in `net_ids`.
func _models_on_table(net_ids: Array) -> int:
	var count := 0
	for child in _main.object_manager.get_children():
		if child.has_meta("network_id") and net_ids.has(child.get_meta("network_id")):
			count += 1
	return count


func test_a_created_unit_goes_out_exactly_once(timeout := 120000) -> void:
	var u := _make_created_unit(1, "Reinforcements")
	_net.broadcast_unit_created(u, "reinforcement")
	assert_int(_net.sent.size()) \
		.override_failure_message("a mid-game creation must go out exactly once (sent: %s)" % str(_net.sent)) \
		.is_equal(1)
	var msg: Dictionary = _net.sent[0]
	assert_str(str(msg.get("m", ""))).is_equal("sync_unit_created")
	assert_int(int(msg.get("t", -1))).is_equal(0)
	var payload: Dictionary = (msg.get("a", []) as Array)[0]
	assert_int(int(payload.get("v", -1))).is_equal(1)
	assert_str(str(payload.get("origin", ""))).is_equal("reinforcement")
	assert_int(int(payload.get("player_id", -1))).is_equal(1)
	var unit_dict: Dictionary = payload.get("unit", {})
	assert_str(str(unit_dict.get("unit_id", ""))).is_equal(u.unit_id)
	var objects: Array = payload.get("objects", [])
	assert_int(objects.size()) \
		.override_failure_message("2 live models must produce 2 wire objects (objects: %s)" % str(objects)) \
		.is_equal(2)
	for i in objects.size():
		var obj: Dictionary = objects[i]
		assert_str(str(obj.get("type", ""))) \
			.override_failure_message("a created-unit model must serialize as an opr_unit object (got: %s)" % str(obj)) \
			.is_equal("opr_unit")
		var want_nid: int = 1 * OPRArmyManager.OPR_NET_ID_SLOT_STRIDE + 900 + i
		assert_int(int(obj.get("network_id", -1))) \
			.override_failure_message("object %d lost its network_id on the way to the wire (obj: %s)" % [i, str(obj)]) \
			.is_equal(want_nid)


func test_solo_without_peers_sends_nothing(timeout := 120000) -> void:
	_net.active = false
	var u := _make_created_unit(1, "Solo Split")
	_net.broadcast_unit_created(u, "split")
	assert_array(_net.sent) \
		.override_failure_message("an offline session must never touch the wire (sent: %s)" % str(_net.sent)) \
		.is_empty()


func test_a_peer_may_not_mint_in_another_peers_band(timeout := 120000) -> void:
	_net.my_slot = 2
	_net.session_host = true
	_net.peer_to_slot = {77: 1}  # a live peer holds slot 1
	var foreign := _make_created_unit(1, "Not Mine")
	_net.broadcast_unit_created(foreign, "spawn")
	assert_array(_net.sent) \
		.override_failure_message("slot 1 is occupied by a live peer — this client must refuse to mint ids in that band (sent: %s)" % str(_net.sent)) \
		.is_empty()

	var own := _make_created_unit(2, "Mine")
	_net.broadcast_unit_created(own, "spawn")
	assert_int(_net.sent.size()) \
		.override_failure_message("a slot-2 client creating a slot-2 unit is its own band and must go out (sent: %s)" % str(_net.sent)) \
		.is_equal(1)

	assert_bool(_net.may_create_units_for_slot(3)) \
		.override_failure_message("the host owns every band nobody has joined") \
		.is_true()
	_net.session_host = false
	assert_bool(_net.may_create_units_for_slot(3)) \
		.override_failure_message("a guest owns only its own band, not an unclaimed one") \
		.is_false()
	assert_bool(_net.may_create_units_for_slot(2)) \
		.override_failure_message("a guest must always be able to mint in its own band") \
		.is_true()


func test_the_receiver_builds_an_equivalent_unit(timeout := 120000) -> void:
	var u := _make_created_unit(1, "Fresh Squad")
	var payload := _net.build_unit_created_payload(u, "split")
	var want_ids: Array = []
	var want_pos: Array = []
	for model in u.models:
		var m := model as ModelInstance
		want_ids.append(int(m.node.get_meta("network_id")))
		want_pos.append(m.node.global_position)
	_forget_unit(u)

	await _net.sync_unit_created(payload)
	await _runner.simulate_frames(4)

	assert_bool(_main.opr_army_manager.game_units.has(payload.get("unit", {}).get("unit_id", ""))) \
		.override_failure_message("the receiver never registered the unit it was sent (payload: %s)" % str(payload)) \
		.is_true()
	var built: GameUnit = _main.opr_army_manager.game_units[payload["unit"]["unit_id"]]
	assert_int(built.models.size()) \
		.override_failure_message("the rebuilt unit does not have both models (models: %d)" % built.models.size()) \
		.is_equal(2)
	assert_str(str(built.unit_properties.get("name", ""))).is_equal("Fresh Squad")
	assert_int(int(built.unit_properties.get("player_id", -1))).is_equal(1)

	for i in built.models.size():
		var bm := built.models[i] as ModelInstance
		assert_bool(bm.node != null and is_instance_valid(bm.node)) \
			.override_failure_message("rebuilt model %d has no live node" % i) \
			.is_true()
		assert_int(int(bm.node.get_meta("network_id", -1))) \
			.override_failure_message("rebuilt model %d's network_id does not match the wire (want %s)" % [i, str(want_ids)]) \
			.is_equal(int(want_ids[i]))
		assert_bool(bm.node.has_meta("game_unit")) \
			.override_failure_message("rebuilt model %d has no game_unit meta — later systems (selection, save) key off it" % i) \
			.is_true()
		assert_bool(bm.node.has_meta("model_index")) \
			.override_failure_message("rebuilt model %d has no model_index meta" % i) \
			.is_true()
		assert_float(bm.node.global_position.distance_to(want_pos[i])) \
			.override_failure_message("rebuilt model %d landed off its sent position (at %s, wanted %s)" % [i, str(bm.node.global_position), str(want_pos[i])]) \
			.is_less(0.001)

	# The session stays LIVE for this assertion on purpose. Silencing the double (active = false)
	# would make it pass for the wrong reason — every broadcast_* refuses offline, so an echo could
	# not have gone out either way. What has to be true is narrower and stronger: with the wire
	# open, building a received creation must not put a creation back ON it, or two peers would
	# bounce the same unit at each other forever. Presence traffic (cursor/camera, main._broadcast_presence)
	# legitimately flows on that same live wire, so the check names the message instead of the count.
	var echoed: Array = []
	for e in _net.sent:
		if str((e as Dictionary).get("m", "")) == "sync_unit_created":
			echoed.append(e)
	assert_array(echoed) \
		.override_failure_message("a receiver echoed the creation it just built back onto the wire — two peers would bounce the same unit at each other (sent: %s)" % str(_net.sent)) \
		.is_empty()


func test_the_same_creation_twice_builds_one_unit(timeout := 120000) -> void:
	var u := _make_created_unit(1, "Echoed Unit")
	var payload := _net.build_unit_created_payload(u, "split")
	var want_ids: Array = []
	for model in u.models:
		want_ids.append(int((model as ModelInstance).node.get_meta("network_id")))
	_forget_unit(u)
	var unit_id: String = str(payload["unit"]["unit_id"])

	await _net.sync_unit_created(payload)
	# The model layer has its own second net (find_by_network_id rebinds instead of duplicating —
	# see the doc comment on sync_unit_created), so a duplicate build would still land on 2 models,
	# not 4, and would still leave game_units.has(unit_id) true. What that second net does NOT
	# catch is the unit-level rebuild it would be papering over: a second GameUnit.from_dict would
	# replace the registered GameUnit with a fresh, unrelated instance mid-game (dropping whatever
	# the first instance had accumulated — activation state, wounds already resolved this round —
	# for a "duplicate" a live in-flight guard should have refused outright). So the real proof
	# the guard did its job is IDENTITY: the SAME GameUnit object before and after the repeat.
	var first_built: GameUnit = _main.opr_army_manager.game_units.get(unit_id, null)
	await _net.sync_unit_created(payload)
	await _runner.simulate_frames(4)

	assert_bool(_main.opr_army_manager.game_units.has(unit_id)) \
		.override_failure_message("the unit never got registered at all") \
		.is_true()
	assert_int(_models_on_table(want_ids)) \
		.override_failure_message("the same wire delivery arriving twice built the models twice instead of being dropped as already-here") \
		.is_equal(2)
	assert_object(_main.opr_army_manager.game_units.get(unit_id, null)) \
		.override_failure_message("the same wire delivery arriving twice replaced the registered GameUnit with a freshly rebuilt one instead of being dropped — a duplicate delivery silently reset the unit's live state") \
		.is_same(first_built)


func test_a_second_delivery_inside_the_build_window_is_dropped(timeout := 120000) -> void:
	var u := _make_created_unit(1, "Racing Unit")
	var payload := _net.build_unit_created_payload(u, "split")
	var want_ids: Array = []
	for model in u.models:
		want_ids.append(int((model as ModelInstance).node.get_meta("network_id")))
	_forget_unit(u)

	_net.sync_unit_created(payload)  # bare call: starts building, does not finish this frame
	await get_tree().process_frame
	await _net.sync_unit_created(payload)  # arrives while the first build is still in flight
	await _runner.simulate_frames(6)

	assert_int(_models_on_table(want_ids)) \
		.override_failure_message("a duplicate delivery landing INSIDE the build window (before the unit is registered) must be dropped by the in-flight guard, not raced into a double build") \
		.is_equal(2)


func test_an_unknown_wire_version_is_refused(timeout := 120000) -> void:
	var u := _make_created_unit(1, "Future Unit")
	var payload := _net.build_unit_created_payload(u, "split")
	_forget_unit(u)
	payload["v"] = 99

	await _net.sync_unit_created(payload)

	assert_bool(_main.opr_army_manager.game_units.has(payload["unit"]["unit_id"])) \
		.override_failure_message("a wire version this build does not understand must be refused, not half-built") \
		.is_false()


func test_a_creation_waits_for_an_army_build_instead_of_racing_it(timeout := 120000) -> void:
	var u := _make_created_unit(1, "Queued Unit")
	var payload := _net.build_unit_created_payload(u, "split")
	_forget_unit(u)
	var unit_id: String = str(payload["unit"]["unit_id"])

	await _main.save_manager.begin_restore()  # someone else holds the restore lock
	_net.sync_unit_created(payload)  # bare call: must queue behind the lock, not race it
	await get_tree().process_frame
	await get_tree().process_frame
	assert_bool(_main.opr_army_manager.game_units.has(unit_id)) \
		.override_failure_message("a creation delivered while the restore lock is held must WAIT for it, not build concurrently") \
		.is_false()

	_main.save_manager.end_restore()
	await _runner.simulate_frames(6)
	assert_bool(_main.opr_army_manager.game_units.has(unit_id)) \
		.override_failure_message("once the restore lock is released the queued creation must complete") \
		.is_true()


func test_a_wire_created_unit_comes_back_in_the_full_state_sync(timeout := 120000) -> void:
	# THE REJOIN COUNTER-PROOF: a unit created mid-game must be indistinguishable, to a LATER
	# joiner's full state sync, from a unit that was always here.
	var u := _make_created_unit(1, "Midgame Unit")
	var payload := _net.build_unit_created_payload(u, "split")
	var want_ids: Array = []
	for model in u.models:
		want_ids.append(int((model as ModelInstance).node.get_meta("network_id")))
	_forget_unit(u)
	await _net.sync_unit_created(payload)
	await _runner.simulate_frames(4)
	var unit_id: String = str(payload["unit"]["unit_id"])

	var state: Dictionary = _main.save_manager.serialize_game_state()

	var found_unit := false
	for unit_data in state.get("game_units", []):
		if str((unit_data as Dictionary).get("unit_id", "")) == unit_id:
			found_unit = true
			break
	assert_bool(found_unit) \
		.override_failure_message("a unit created mid-game is MISSING from serialize_game_state() — a player who joins after the creation would never see it (state game_units: %s)" % str(state.get("game_units", []))) \
		.is_true()

	var found_nids: Array = []
	for obj_data in state.get("objects", []):
		var nid := int((obj_data as Dictionary).get("network_id", -1))
		if want_ids.has(nid):
			found_nids.append(nid)
	assert_int(found_nids.size()) \
		.override_failure_message("a unit created mid-game left models MISSING from serialize_game_state()'s objects — a rejoining player would see the unit's card but an empty spot on the table (found: %s, want: %s)" % [str(found_nids), str(want_ids)]) \
		.is_equal(2)
