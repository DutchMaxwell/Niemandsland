extends GdUnitTestSuite
## Command-channel frame validation in network_manager.gd (_on_raw_command).
## Only listed handlers may run, host-only handlers accept frames from the host peer (1) only,
## and legitimate frames still dispatch. Frames are fed straight into _on_raw_command, exactly as
## the relay transport would deliver them, with the stamped sender id.

const NetworkManagerScript := preload("res://scripts/network_manager.gd")
const HOST := 1
const GUEST := 2


func _make_manager() -> Node:
	# In the tree so Node.multiplayer is valid (no transport: get_unique_id() == 1).
	var nm: Node = auto_free(NetworkManagerScript.new())
	add_child(nm)
	return nm


func _rpc_frame(method: String, args: Array) -> PackedByteArray:
	return MPCommand.encode("rpc", 1, {"m": method, "a": args})


# ===== unlisted methods (inherited engine methods included) never run =====

func test_unlisted_engine_method_set_is_refused() -> void:
	var nm := _make_manager()
	nm._on_raw_command(GUEST, _rpc_frame("set", ["is_host", true]))
	assert_bool(nm.is_host).is_false()


func test_unlisted_engine_method_set_meta_is_refused() -> void:
	var nm := _make_manager()
	nm._on_raw_command(GUEST, _rpc_frame("set_meta", ["forged", 1]))
	assert_bool(nm.has_meta("forged")).is_false()


# ===== host-only handlers accept the host peer only =====

func test_reject_version_from_guest_is_refused() -> void:
	var nm := _make_manager()
	var rejected: Array = []
	nm.version_rejected.connect(func(host_version: String, _mine: String) -> void:
		rejected.append(host_version))
	nm._on_raw_command(GUEST, _rpc_frame("_rpc_reject_version", ["0.0.0"]))
	assert_int(rejected.size()).is_equal(0)


func test_assign_slot_from_guest_is_refused() -> void:
	var nm := _make_manager()
	nm._on_raw_command(GUEST, _rpc_frame("_rpc_assign_slot", [7]))
	assert_int(nm._my_assigned_slot).is_not_equal(7)


func test_assign_slot_from_host_runs() -> void:
	var nm := _make_manager()
	nm._on_raw_command(HOST, _rpc_frame("_rpc_assign_slot", [7]))
	assert_int(nm._my_assigned_slot).is_equal(7)


# ===== any-peer handlers stay open =====

func test_any_peer_handler_from_guest_runs() -> void:
	var nm := _make_manager()
	nm._on_raw_command(GUEST, _rpc_frame("sync_peer_busy", [true]))
	assert_bool(nm.is_any_remote_peer_busy()).is_true()


# ===== main-owned host-only command types are forwarded from the host only =====

func test_sync_game_state_from_guest_is_not_forwarded() -> void:
	var nm := _make_manager()
	var seen: Array = []
	nm.command_received.connect(func(type: String, _payload: Variant, _from: int) -> void:
		seen.append(type))
	nm._on_raw_command(GUEST, MPCommand.encode("sync_game_state", 1, {"state": {}}))
	assert_int(seen.size()).is_equal(0)


func test_sync_game_state_from_host_is_forwarded() -> void:
	var nm := _make_manager()
	var seen: Array = []
	nm.command_received.connect(func(type: String, _payload: Variant, _from: int) -> void:
		seen.append(type))
	nm._on_raw_command(HOST, MPCommand.encode("sync_game_state", 1, {"state": {}}))
	assert_array(seen).is_equal(["sync_game_state"])


# ===== the allow-list is complete and every entry is a real handler =====

func test_allow_list_covers_every_remote_call_and_exists() -> void:
	var nm := _make_manager()
	var script: Script = nm.get_script()
	var consts: Dictionary = script.get_script_constant_map()
	var host_only: Variant = consts.get("HOST_ONLY_HANDLERS")
	var any_peer: Variant = consts.get("ANY_PEER_HANDLERS")
	assert_that(host_only).is_not_null()
	assert_that(any_peer).is_not_null()
	if host_only == null or any_peer == null:
		return
	for name: String in host_only:
		assert_bool(nm.has_method(name)).override_failure_message("missing host-only handler " + name).is_true()
		assert_bool(any_peer.has(name)).override_failure_message("listed twice: " + name).is_false()
	for name: String in any_peer:
		assert_bool(nm.has_method(name)).override_failure_message("missing any-peer handler " + name).is_true()
	# Every name the code sends through _remote_call("...") must be listed.
	var source := FileAccess.get_file_as_string("res://scripts/network_manager.gd")
	var re := RegEx.new()
	re.compile("_remote_call\\(\"([A-Za-z_]+)\"")
	var sent: Array = []
	for m: RegExMatch in re.search_all(source):
		var name := m.get_string(1)
		if not sent.has(name):
			sent.append(name)
	assert_int(sent.size()).is_greater(50)
	for name: String in sent:
		assert_bool(host_only.has(name) or any_peer.has(name)) \
			.override_failure_message("sent but not allow-listed: " + name).is_true()
