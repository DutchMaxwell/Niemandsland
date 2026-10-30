extends GdUnitTestSuite
## W1.1d (0.3.15, rules 3.6): an online room refuses a peer on other rules. The game-version check
## stays first and unchanged; only when the game versions match does the host compare the rules
## versions (major.minor, from the rule maps). A peer that sent no rules version is refused too, and
## the refusal names both rules versions. Older builds keep today's game-version refusal: the joining
## peer sends its rules in a separate message BEFORE the unchanged two-argument version announce, and
## a host that does not know that message drops it.

const NetworkManagerScript := preload("res://scripts/network_manager.gd")
const HOST := 1
const GUEST := 2
const OLDER_RELEASE := "0.3.13.0-alpha"


func before_test() -> void:
	get_tree().get_multiplayer().multiplayer_peer = OfflineMultiplayerPeer.new()


func after_test() -> void:
	get_tree().get_multiplayer().multiplayer_peer = OfflineMultiplayerPeer.new()


## Records what would go on the wire instead of needing a relay transport.
class RecordingManager extends "res://scripts/network_manager.gd":
	var sent: Array = []

	func _remote_call(method: String, args: Array, target_peer: int = 0) -> void:
		sent.append([method, args, target_peer])


func _game_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "unknown"))


func _build_rules() -> String:
	return OPRApiClient.rules_core_version("gf")


func _frame(method: String, args: Array) -> PackedByteArray:
	return MPCommand.encode("rpc", 1, {"m": method, "a": args})


## A host-side manager (the offline peer is id 1) that counts passed handshakes.
func _host(passes: Array) -> Node:
	var nm: Node = auto_free(RecordingManager.new())
	add_child(nm)
	nm.peer_version_validated.connect(func(peer: int) -> void: passes.append(peer))
	return nm


func _rejects(nm: Node) -> Array:
	return nm.sent.filter(func(call: Array) -> bool: return str(call[0]).begins_with("_rpc_reject"))


# ===== host: same game version, other rules =====

func test_same_game_version_other_rules_is_refused_naming_both() -> void:
	var passes: Array = []
	var nm := _host(passes)
	nm._on_raw_command(GUEST, _frame("_rpc_announce_rules_version", ["3.5.1"]))
	nm._on_raw_command(GUEST, _frame("_rpc_announce_version", [_game_version(), "guest-token"]))
	assert_array(passes).is_empty()
	assert_array(_rejects(nm)).is_equal([
		["_rpc_reject_rules_version", [_game_version(), _build_rules(), "3.5.1"], GUEST]])


func test_same_game_version_without_a_rules_version_is_refused() -> void:
	var passes: Array = []
	var nm := _host(passes)
	nm._on_raw_command(GUEST, _frame("_rpc_announce_version", [_game_version(), "guest-token"]))
	assert_array(passes).is_empty()
	assert_array(_rejects(nm)).is_equal([
		["_rpc_reject_rules_version", [_game_version(), _build_rules(), ""], GUEST]])


## Control: only major.minor counts, so a later patch of the same rules joins as before.
func test_same_rules_other_patch_passes_the_handshake() -> void:
	var passes: Array = []
	var nm := _host(passes)
	var same_rules := OPRApiClient._major_minor(_build_rules()) + ".9"
	nm._on_raw_command(GUEST, _frame("_rpc_announce_rules_version", [same_rules]))
	nm._on_raw_command(GUEST, _frame("_rpc_announce_version", [_game_version(), "guest-token"]))
	assert_array(passes).is_equal([GUEST])
	assert_array(_rejects(nm)).is_empty()


## Control: an older build announces like today (two arguments, no rules message) and still gets
## today's one-argument game-version refusal, which an older build understands.
func test_old_peer_gets_todays_game_version_reject() -> void:
	var passes: Array = []
	var nm := _host(passes)
	nm._on_raw_command(GUEST, _frame("_rpc_announce_version", [OLDER_RELEASE, "old-token"]))
	assert_array(passes).is_empty()
	assert_array(_rejects(nm)).is_equal([["_rpc_reject_version", [_game_version()], GUEST]])


# ===== client =====

func test_client_sends_rules_before_a_two_argument_announce() -> void:
	var relay := RelayMultiplayerPeer.new()
	relay._my_peer_id = GUEST
	relay._connection_status = MultiplayerPeer.CONNECTION_CONNECTED
	get_tree().get_multiplayer().multiplayer_peer = relay
	var nm: Node = auto_free(RecordingManager.new())
	add_child(nm)
	nm.announce_version_to_host()
	assert_array(nm.sent).is_equal([
		["_rpc_announce_rules_version", [_build_rules()], HOST],
		["_rpc_announce_version", [_game_version(), nm._my_client_token], HOST]])


func test_client_rules_reject_shows_both_rules_versions() -> void:
	var nm: Node = auto_free(NetworkManagerScript.new())
	add_child(nm)
	var shown: Array = []
	nm.version_rejected.connect(func(host_text: String, my_text: String) -> void:
		shown.append([host_text, my_text]))
	nm._on_raw_command(HOST, _frame("_rpc_reject_rules_version", [_game_version(), "3.6.0", "3.5.1"]))
	assert_int(shown.size()).is_equal(1)
	assert_str(shown[0][0] if shown.size() == 1 else "").contains("3.6.0")
	assert_str(shown[0][1] if shown.size() == 1 else "").contains("3.5.1")


## Control: an older host refuses with today's one-argument message; a new client still shows it.
func test_client_still_shows_an_old_hosts_game_reject() -> void:
	var nm: Node = auto_free(NetworkManagerScript.new())
	add_child(nm)
	var shown: Array = []
	nm.version_rejected.connect(func(host_text: String, my_text: String) -> void:
		shown.append([host_text, my_text]))
	nm._on_raw_command(HOST, _frame("_rpc_reject_version", [OLDER_RELEASE]))
	assert_array(shown).is_equal([[OLDER_RELEASE, _game_version()]])
