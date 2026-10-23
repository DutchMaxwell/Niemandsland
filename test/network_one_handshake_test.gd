extends GdUnitTestSuite
## One join = one handshake (REPORT_mp_drops New A + Q3). A repeat announce from an already validated
## peer whose slot binding is unchanged is ignored by the host (each pass was a full state sync plus a
## biome rebuild), and a guest that was ready re-reports it once its (re)join's handshake passed.

const NetworkManagerScript := preload("res://scripts/network_manager.gd")
const GUEST := 2


## Records what would go on the wire instead of needing a relay transport.
class RecordingManager extends "res://scripts/network_manager.gd":
	var sent: Array = []

	func _remote_call(method: String, args: Array, target_peer: int = 0) -> void:
		sent.append([method, args, target_peer])


func _announce_frame() -> PackedByteArray:
	var version := str(ProjectSettings.get_setting("application/config/version", "unknown"))
	return MPCommand.encode("rpc", 1, {"m": "_rpc_announce_version", "a": [version, "guest-token"]})


func test_repeat_announce_from_a_validated_peer_is_one_handshake() -> void:
	# In the tree without a transport: the offline peer is id 1, so this manager is the host.
	var nm: Node = auto_free(NetworkManagerScript.new())
	add_child(nm)
	var passes: Array = []
	nm.peer_version_validated.connect(func(peer: int) -> void: passes.append(peer))
	nm._on_raw_command(GUEST, _announce_frame())   # room_joined -> internet_connected
	nm._on_raw_command(GUEST, _announce_frame())   # connected_to_server, the same join
	assert_array(passes).is_equal([GUEST])


func test_announce_after_a_rejoin_is_a_new_handshake() -> void:
	var nm: Node = auto_free(NetworkManagerScript.new())
	add_child(nm)
	var passes: Array = []
	nm.peer_version_validated.connect(func(peer: int) -> void: passes.append(peer))
	nm._on_raw_command(GUEST, _announce_frame())
	nm._on_peer_disconnected(GUEST)                # the drop clears the validation
	nm._on_raw_command(GUEST, _announce_frame())   # the rejoin announces again: full re-sync
	assert_array(passes).is_equal([GUEST, GUEST])


func test_ready_guest_reports_ready_again_after_the_handshake() -> void:
	var nm: Node = auto_free(RecordingManager.new())
	add_child(nm)
	nm._local_ready = true     # set before the drop; the report may have died with the old socket
	nm._rpc_assign_slot(2)     # the rejoin's handshake passed
	assert_array(nm.sent).is_equal([["_rpc_report_ready", [true], 1]])


func test_unready_guest_sends_nothing_after_the_handshake() -> void:
	var nm: Node = auto_free(RecordingManager.new())
	add_child(nm)
	nm._rpc_assign_slot(2)
	assert_array(nm.sent).is_empty()
