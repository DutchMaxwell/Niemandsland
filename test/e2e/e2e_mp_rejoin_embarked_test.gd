extends GdUnitTestSuite
## E2E — NML-928: a late-joiner has to receive the EMBARKED state, not just the numbers.
##
## THE DEFECT. Transport cargo is stored in two halves. The STATE half (embarked_in /
## cargo_unit_ids / embark_return_spots) lives in unit_properties, so it survives a save and rides
## the join sync. The RUNTIME half — the model node's "embarked" meta and its claimed tray slot —
## is rebuilt after the restore, by opr_army_manager.restore_embarked_after_load().
##
## save_manager.load_game() calls it, one line after its dead-parking call. main._rpc_sync_game_state
## runs the very same restore chain (hero attachments, markers, regiments, army trays, dead parking)
## and simply never made that one call. A guest that joined or rejoined a game with loaded cargo
## therefore ended up with passengers whose models had no meta:
##
##   • the radial menu offered them the ORDINARY unit actions instead of the single legal one
##     (radial_menu_controller.open_menu gates the disembark menu on exactly that meta), and
##   • their tray slots were never claimed, so the next casualty parked on top of them.
##
## THE TEST drives the REAL sync path: a host table with an embarked unit is serialized exactly as
## the host serializes it (save_manager.serialize_game_state — the same call
## _sync_loaded_state_to_clients makes), and that payload is fed into the REAL _rpc_sync_game_state.
## Everything the guest ends up with is rebuilt by production code from the wire payload.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254


## Stands in for NetworkManager on the joining peer: enough of a session for _rpc_sync_game_state
## to accept the payload (the version handshake) and to report its loading gate. A LIVE session also
## makes main's _process presence loop fire at ~15 Hz, so the cursor/camera senders have to exist
## here too — without them the first frame after the join takes the whole headless run down.
class FakeNet extends Node:
	var busy_calls: Array = []
	func is_multiplayer_active() -> bool:
		return true
	func slot_has_human_peer(_slot: int) -> bool:
		return false
	func get_game_version() -> String:
		return "e2e-test-version"
	func broadcast_peer_busy(busy: bool) -> void:
		busy_calls.append(busy)
	func broadcast_cursor_position(_pos: Vector3) -> void:
		pass
	func broadcast_camera_direction(_yaw: float, _pitch: float, _zoom: float) -> void:
		pass
	func broadcast_camera_position(_pos: Vector3) -> void:
		pass

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
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_fake = auto_free(FakeNet.new())
	_main.network_manager = _fake


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null
	_fake = null


## Next network_id handed to a fixture model. A spawned model always carries a DISTINCT one, and the
## restore leans on it: _serialize_object defaults a missing meta to 0, and _deserialize_object then
## rebinds every model to the first node it finds under that id (the army-sync idempotency path).
## Unnumbered fixture models would therefore all collapse onto one node.
var _next_network_id: int = 9000


## A unit whose model nodes are REAL ObjectManager children in the "opr_unit"/"selectable" groups —
## which is what save_manager._serialize_objects walks. The nodes come from the production spawner
## (create_model_from_properties); with no faction folder it falls back to its placeholder body, so
## nothing here needs the model library or the network.
func _spawn_unit(pid: int, unit_name: String, positions: Array, rules: Array = []) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = "e2e_p%d_%s" % [pid, unit_name]
	u.unit_properties = {
		"player_id": pid,
		"name": unit_name,
		"quality": 4,
		"defense": 4,
		"size": positions.size(),
		"special_rules": rules,
	}
	for i in positions.size():
		var m := ModelInstance.new()
		m.is_alive = true
		m.unit = u
		m.model_index = i
		var node: Node3D = _main.opr_army_manager.create_model_from_properties(u.unit_properties)
		_main.object_manager.add_child(node)
		node.global_position = positions[i]
		node.set_meta("game_unit", u)
		node.set_meta("model_instance", m)
		node.set_meta("model_index", i)
		node.set_meta("network_id", _next_network_id)
		_next_network_id += 1
		m.node = node
		u.models.append(m)
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func _at(inches_x: float) -> Vector3:
	return Vector3(inches_x * INCH, 0.0, 0.0)


## The host's table: a transport with one unit loaded, parked exactly the way the game parks it.
## Returns [truck, cargo].
func _host_table_with_loaded_cargo() -> Array:
	var truck := _spawn_unit(1, "Truck", [_at(0.0)], ["Transport(6)"])
	var cargo := _spawn_unit(1, "Riders", [_at(1.0), _at(2.0)])
	_main.opr_army_manager._create_army_tray(1, "Test Army", OPRArmyManager.army_color(1, Color.GRAY))
	assert_bool(_main.opr_army_manager.set_unit_embarked(cargo, truck, true)) \
		.override_failure_message("fixture check: the cargo must actually embark, or the whole suite proves nothing") \
		.is_true()
	assert_object(_main.opr_army_manager.transport_of(cargo)).is_equal(truck)
	return [truck, cargo]


## The exact payload the host puts on the wire (_sync_loaded_state_to_clients), version stamp and all.
func _host_state() -> Dictionary:
	var state: Dictionary = _main.save_manager.serialize_game_state()
	state["_host_version"] = _fake.get_game_version()
	return state


## Play the joining peer: hand the payload to the real RPC. It clears this table and rebuilds
## everything — units, models, trays, parking — from the payload alone.
func _join_with(state: Dictionary) -> void:
	await _main._rpc_sync_game_state(state)
	await E2EBoot.settle(get_tree())


func _restored(unit_id: String) -> GameUnit:
	return _main.opr_army_manager.get_game_unit_by_id(unit_id)


func _live_nodes(u: GameUnit) -> Array:
	var out: Array = []
	if u == null:
		return out
	for m in u.models:
		var node: Node3D = (m as ModelInstance).node
		if node != null and is_instance_valid(node):
			out.append(node)
	return out


# === 1. The meta ==================================================================================

## The claim: after joining, every cargo model carries the "embarked" meta the whole cargo
## machinery is gated on.
func test_the_late_joiner_rebuilds_the_embarked_meta(timeout := 180000) -> void:
	var tc := _host_table_with_loaded_cargo()
	var cargo_id: String = (tc[1] as GameUnit).unit_id
	var state := _host_state()

	await _join_with(state)

	var joined := _restored(cargo_id)
	assert_object(joined) \
		.override_failure_message("fixture check: the sync must rebuild the cargo unit at all") \
		.is_not_null()
	# CONTROL: the STATE half always arrived — it rides unit_properties. This is what made the
	# defect so easy to miss: the guest knew the unit was cargo and still treated it as free.
	assert_object(_main.opr_army_manager.transport_of(joined)) \
		.override_failure_message("fixture check: the embarked STATE rides unit_properties and must survive the sync") \
		.is_not_null()

	var nodes := _live_nodes(joined)
	assert_int(nodes.size()) \
		.override_failure_message("fixture check: the sync must rebuild the cargo's model nodes") \
		.is_equal(2)
	for node in nodes:
		assert_bool(bool((node as Node3D).get_meta("embarked", false))) \
			.override_failure_message("a late-joiner's cargo model has no \"embarked\" meta — the disembark gate and the tray slots both read exactly this") \
			.is_true()


## …and the tray slot is claimed, which is the other half of the runtime state: without it the next
## casualty parks on top of the passenger.
func test_the_late_joiner_claims_the_tray_slot(timeout := 180000) -> void:
	var tc := _host_table_with_loaded_cargo()
	var cargo_id: String = (tc[1] as GameUnit).unit_id
	var state := _host_state()

	await _join_with(state)

	for node in _live_nodes(_restored(cargo_id)):
		assert_bool((node as Node3D).has_meta("dead_slot")) \
			.override_failure_message("the passenger holds no tray slot — the next casualty parks on top of it") \
			.is_true()


# === 2. The radial branch ========================================================================

## The user-visible consequence, on the real controller: clicking a joined passenger must open the
## DISEMBARK menu (radial_menu_controller.open_menu gates that branch on the meta), not the ordinary
## unit menu with move/wound/marker actions on a model that is inside a vehicle.
func test_a_joined_passenger_opens_the_disembark_menu(timeout := 180000) -> void:
	var tc := _host_table_with_loaded_cargo()
	var truck_name: String = str((tc[0] as GameUnit).unit_properties.get("name", ""))
	var cargo_id: String = (tc[1] as GameUnit).unit_id
	var state := _host_state()

	await _join_with(state)

	var nodes := _live_nodes(_restored(cargo_id))
	assert_int(nodes.size()) \
		.override_failure_message("fixture check: no model to click") \
		.is_equal(2)
	var rmc = _main.radial_menu_controller
	rmc.open_menu(Vector2(400, 300), [nodes[0]] if not nodes.is_empty() else [])

	var ctx: Dictionary = rmc.radial_menu._context
	assert_bool(ctx.has("disembark_unit")) \
		.override_failure_message("the joined passenger opened the ORDINARY unit menu — a model sitting inside a vehicle offered move/wound/marker actions (context: %s)" % str(ctx.keys())) \
		.is_true()
	assert_object(ctx.get("disembark_unit", null)).is_equal(_restored(cargo_id))

	var ids: Array = []
	for it in rmc.radial_menu._items:
		ids.append(str(it.id))
	assert_array(ids) \
		.override_failure_message("the disembark menu must offer exactly the one legal action (items: %s)" % str(ids)) \
		.is_equal(["disembark"])
	assert_str(str(rmc.radial_menu._items[0].tooltip) if not rmc.radial_menu._items.is_empty() else "") \
		.contains(truck_name)
	rmc.radial_menu.close()


# === 3. Counter-proofs ===========================================================================

## The restore must not stamp EVERYTHING as cargo: a unit that was never loaded stays a free unit
## with a normal menu. (restore_embarked_after_load walks only units with a transport, and this is
## the assertion that says so.)
func test_a_unit_that_was_never_loaded_stays_free(timeout := 180000) -> void:
	var tc := _host_table_with_loaded_cargo()
	var walker := _spawn_unit(1, "Walkers", [_at(20.0)])
	var walker_id: String = walker.unit_id
	var state := _host_state()

	await _join_with(state)

	var joined := _restored(walker_id)
	assert_object(joined).is_not_null()
	assert_object(_main.opr_army_manager.transport_of(joined)).is_null()
	for node in _live_nodes(joined):
		assert_bool(bool((node as Node3D).get_meta("embarked", false))) \
			.override_failure_message("a free unit was marked as cargo by the join restore") \
			.is_false()

	var rmc = _main.radial_menu_controller
	rmc.open_menu(Vector2(400, 300), [_live_nodes(joined)[0]] if not _live_nodes(joined).is_empty() else [])
	assert_bool(rmc.radial_menu._context.has("disembark_unit")) \
		.override_failure_message("a free unit was offered the disembark menu") \
		.is_false()
	rmc.radial_menu.close()
	assert_object(tc[0]).is_not_null()   # the host fixture is what produced the payload


## The .nml load path is what the fix mirrors — it must stay exactly as it was. Same fixture, same
## restore call, driven through save_manager's own hook.
func test_the_load_path_still_restores_the_cargo(timeout := 180000) -> void:
	var tc := _host_table_with_loaded_cargo()
	var cargo := tc[1] as GameUnit
	for node in _live_nodes(cargo):
		(node as Node3D).set_meta("embarked", false)   # strip the runtime half, keep the state half

	_main.opr_army_manager.restore_embarked_after_load()

	for node in _live_nodes(cargo):
		assert_bool(bool((node as Node3D).get_meta("embarked", false))) \
			.override_failure_message("the shared restore itself is broken — the join fix would inherit that") \
			.is_true()
