extends GdUnitTestSuite
## 29(b): the host kicked a REJOINING guest after 8 s. The relay flushes `peer_disconnected` +
## `peer_connected` for a reconnect that REUSES the transport id (relay_multiplayer_peer.gd
## `_emit_peer_connected`), and the eight-second new-player grace is too short for a guest whose
## own socket is still mid-rejoin. A returning peer therefore gets the long rejoin window - the
## same 25 s its own reconnect loop allows before it gives up (relay_multiplayer_peer.gd
## `RECONNECT_TIMEOUT`).

const NetScript := preload("res://scripts/network_manager.gd")
const RelayScript := preload("res://scripts/relay_multiplayer_peer.gd")


## The long window is the guest's own reconnect bound: kicking earlier than the peer can give up
## is what makes a live rejoin a kick.
func test_the_rejoin_window_is_the_guests_own_reconnect_bound() -> void:
	assert_float(NetScript.REJOIN_HANDSHAKE_TIMEOUT).is_equal(RelayScript.RECONNECT_TIMEOUT)
	assert_float(NetScript.REJOIN_HANDSHAKE_TIMEOUT).is_greater(NetScript.VERSION_HANDSHAKE_TIMEOUT)


## A returning peer (reused id) gets the long window, a genuinely new peer the 8 s one.
func test_a_returning_peer_gets_the_long_window() -> void:
	assert_float(NetScript.handshake_grace(true)).is_equal(NetScript.REJOIN_HANDSHAKE_TIMEOUT)
	assert_float(NetScript.handshake_grace(false)).is_equal(NetScript.VERSION_HANDSHAKE_TIMEOUT)


## The relay knows the ids it has already registered; that is what the host asks before arming
## the kick. A pristine transport knows nobody.
func test_a_fresh_transport_knows_no_peer() -> void:
	var peer: RelayMultiplayerPeer = RelayScript.new()
	assert_bool(peer.is_known_peer(2)).is_false()


## The reused-id path (relay flushes peer_disconnected + peer_connected) leaves the id KNOWN —
## that is precisely the reading the host uses to grant the long window instead of the 8 s one.
func test_a_reused_id_stays_known_after_the_flush() -> void:
	var peer: RelayMultiplayerPeer = RelayScript.new()
	peer._emit_peer_connected(2)
	assert_bool(peer.is_known_peer(2)).is_true()
	peer._emit_peer_connected(2)
	assert_bool(peer.is_known_peer(2)).is_true()
