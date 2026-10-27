extends GdUnitTestSuite
## 29(b): the host kicked a REJOINING guest after 8 s. The relay flushes `peer_disconnected` +
## `peer_connected` for a reconnect that REUSES the transport id (relay_multiplayer_peer.gd
## `_emit_peer_connected`), and the eight-second new-player grace is too short for a guest whose
## own socket is still mid-rejoin. A returning peer therefore gets the long rejoin window - the
## same 25 s its own reconnect loop allows before it gives up (relay_multiplayer_peer.gd
## `RECONNECT_TIMEOUT`).
##
## The new surface is read DYNAMICALLY (`has_method` / `call` / constant map) on purpose: before the
## fix these tests must fail on their own assertions ("no such window/reading"), not on a parse error
## or a crash that would skip the whole suite and prove nothing.

const NetScript := preload("res://scripts/network_manager.gd")
const RelayScript := preload("res://scripts/relay_multiplayer_peer.gd")


## An instance, so the calls are plain Object.call() - a class-level call is a parse error in
## GDScript and would skip the suite instead of failing an assertion.
func _net() -> Node:
	return NetScript.new()


func _const(script: Script, name: String) -> Variant:
	return (script.get_script_constant_map() as Dictionary).get(name)


func _float_setting(value: Variant) -> bool:
	return value is float or value is int


## Never crashes on a missing/!float reading: an absent value becomes -1.0 and fails its assertion.
func _num(value: Variant) -> float:
	return float(value) if _float_setting(value) else -1.0


func _known(peer: RelayMultiplayerPeer) -> Variant:
	return peer.call("is_known_peer", 2) if peer.has_method("is_known_peer") else null


## The long window is the guest's own reconnect bound: kicking earlier than the peer can give up
## is what turns a live rejoin into a kick.
func test_the_rejoin_window_is_the_guests_own_reconnect_bound() -> void:
	var rejoin: Variant = _const(NetScript, "REJOIN_HANDSHAKE_TIMEOUT")
	assert_bool(_float_setting(rejoin)).override_failure_message(
		"no REJOIN_HANDSHAKE_TIMEOUT on NetworkManager").is_true()
	assert_float(_num(rejoin)).is_equal(_num(_const(RelayScript, "RECONNECT_TIMEOUT")))
	assert_float(_num(rejoin)).is_greater(_num(_const(NetScript, "VERSION_HANDSHAKE_TIMEOUT")))


## A returning peer (reused id) gets the long window, a genuinely new peer the 8 s one.
func test_a_returning_peer_gets_the_long_window() -> void:
	var net := _net()
	var has: bool = net.has_method("handshake_grace")
	var returning: Variant = net.call("handshake_grace", true) if has else null
	var fresh: Variant = net.call("handshake_grace", false) if has else null
	net.free()
	assert_bool(has and _float_setting(returning) and _float_setting(fresh)).override_failure_message(
		"NetworkManager.handshake_grace() is missing").is_true()
	assert_float(_num(returning)).is_equal(_num(_const(NetScript, "REJOIN_HANDSHAKE_TIMEOUT")))
	assert_float(_num(fresh)).is_equal(_num(_const(NetScript, "VERSION_HANDSHAKE_TIMEOUT")))


## The relay knows the ids it has already registered; that is the reading the host asks for before
## arming the kick. A pristine transport knows nobody.
func test_a_fresh_transport_knows_no_peer() -> void:
	var peer: RelayMultiplayerPeer = RelayScript.new()
	var known: Variant = _known(peer)
	assert_bool(known is bool).override_failure_message(
		"RelayMultiplayerPeer.is_known_peer() is missing").is_true()
	assert_bool(known is bool and bool(known)).is_false()


## The reused-id path (relay flushes peer_disconnected + peer_connected) leaves the id KNOWN —
## that is precisely the reading the host uses to grant the long window instead of the 8 s one.
func test_a_reused_id_stays_known_after_the_flush() -> void:
	var peer: RelayMultiplayerPeer = RelayScript.new()
	peer._emit_peer_connected(2)
	var known: Variant = _known(peer)
	assert_bool(known is bool).override_failure_message(
		"RelayMultiplayerPeer.is_known_peer() is missing").is_true()
	assert_bool(known is bool and bool(known)).is_true()
	peer._emit_peer_connected(2)
	var again: Variant = _known(peer)
	assert_bool(again is bool and bool(again)).is_true()
