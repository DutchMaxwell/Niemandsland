extends GdUnitTestSuite
## Stable player-identity (token -> slot) logic in network_manager.gd. The live RPC
## round-trip needs a real session; these cover the PURE host-side resolution + the
## remap/reservation bookkeeping that guarantee a reconnecting player returns to the
## SAME slot with no phantom and no army lockout. Only paths that do NOT broadcast an
## RPC are exercised (a rebind of a still-LIVE peer needs a live session and is covered
## by the manual gauntlet); the common reclaim-of-a-reserved-vacant-slot path is pure.

const NetworkManagerScript := preload("res://scripts/network_manager.gd")


func _make_manager() -> Node:
	var nm: Node = auto_free(NetworkManagerScript.new())
	add_child(nm)
	return nm


# ===== fresh slot allocation =====

func test_fresh_slots_are_monotonic_from_two() -> void:
	var nm := _make_manager()
	assert_int(nm._allocate_fresh_slot(10, "tokA")).is_equal(2)
	assert_int(nm._allocate_fresh_slot(11, "tokB")).is_equal(3)
	assert_int(nm._allocate_fresh_slot(12, "tokC")).is_equal(4)
	assert_int(nm.token_to_slot["tokA"]).is_equal(2)
	assert_int(nm.slot_to_peer[2]).is_equal(10)
	assert_int(nm.peer_to_slot[10]).is_equal(2)


func test_empty_token_gets_slot_but_no_reservation() -> void:
	var nm := _make_manager()
	var slot: int = nm._allocate_fresh_slot(7)  # no token
	assert_int(slot).is_equal(2)
	assert_bool(nm.token_to_slot.is_empty()).is_true()  # anonymous: not reserved
	assert_int(nm.peer_to_slot[7]).is_equal(2)


# ===== token resolution =====

func test_unknown_token_allocates_fresh_slot() -> void:
	var nm := _make_manager()
	assert_int(nm._resolve_slot_for_token("newtok", 5)).is_equal(2)
	assert_int(nm.token_to_slot["newtok"]).is_equal(2)


func test_empty_token_resolves_fresh_and_unreserved() -> void:
	var nm := _make_manager()
	assert_int(nm._resolve_slot_for_token("", 5)).is_equal(2)
	assert_bool(nm.token_to_slot.is_empty()).is_true()


func test_known_token_reclaims_its_reserved_slot() -> void:
	# Guest on slot 2 dropped -> slot reserved-vacant. A rejoin with the SAME token must
	# return slot 2 again and rebind it to the new peer (no RPC: old peer is vacant).
	var nm := _make_manager()
	nm.token_to_slot["guestT"] = 2
	nm.slot_to_peer[2] = nm.SLOT_RESERVED_PEER
	nm._next_slot = 3
	var slot: int = nm._resolve_slot_for_token("guestT", 99)
	assert_int(slot).is_equal(2)               # SAME slot reclaimed
	assert_int(nm.slot_to_peer[2]).is_equal(99)  # rebound to the new peer
	assert_int(nm.peer_to_slot[99]).is_equal(2)
	assert_int(nm._next_slot).is_equal(3)       # no new slot consumed


func test_guest_token_never_gets_host_slot_one() -> void:
	# A token mapped to slot 1 (host) presented by a non-host peer is refused and given
	# a fresh slot instead — the host slot is never handed to a guest.
	var nm := _make_manager()
	nm.token_to_slot["hostish"] = 1
	nm.slot_to_peer[1] = 1
	var slot: int = nm._resolve_slot_for_token("hostish", 6)  # sender 6 != 1
	assert_int(slot).is_not_equal(1)
	assert_int(slot).is_equal(2)


# ===== remap re-keys every peer-keyed dict =====

func test_remap_rekeys_all_peer_keyed_state() -> void:
	var nm := _make_manager()
	nm.peer_to_slot[7] = 2
	nm.slot_to_peer[2] = 7
	nm.player_names[7] = "Bob"
	nm.validated_peers[7] = true
	nm.connected_peers.append(7)
	nm._rpc_remap_peer(7, 99, 2)
	assert_bool(nm.peer_to_slot.has(7)).is_false()
	assert_int(nm.peer_to_slot[99]).is_equal(2)
	assert_int(nm.slot_to_peer[2]).is_equal(99)
	assert_str(nm.player_names[99]).is_equal("Bob")
	assert_bool(nm.player_names.has(7)).is_false()
	assert_bool(nm.validated_peers.get(99, false)).is_true()
	assert_bool(nm.connected_peers.has(7)).is_false()
	assert_bool(nm.connected_peers.has(99)).is_true()


func test_remap_is_noop_on_same_peer() -> void:
	var nm := _make_manager()
	nm.player_names[5] = "Eve"
	nm._rpc_remap_peer(5, 5, 3)
	assert_str(nm.player_names[5]).is_equal("Eve")


func test_remap_tolerates_absent_old_peer() -> void:
	# A late third-guest may not know the old id; record the new binding, never crash.
	var nm := _make_manager()
	nm._rpc_remap_peer(404, 99, 2)
	assert_int(nm.peer_to_slot[99]).is_equal(2)
	assert_int(nm.slot_to_peer[2]).is_equal(99)


func test_remap_excludes_self_from_connected_peers() -> void:
	# The remap broadcast reaches the returning guest too (new_peer == our own id). It must
	# record the slot binding but NOT list us in connected_peers (presence excludes self).
	var nm := _make_manager()
	var me: int = nm.get_my_peer_id()  # 0 in a test (no live peer)
	nm._rpc_remap_peer(7, me, 2)
	assert_bool(nm.connected_peers.has(me)).is_false()
	assert_int(nm.peer_to_slot[me]).is_equal(2)  # binding still recorded


func test_slot_one_refusal_rehomes_token() -> void:
	# A guest token mapped to slot 1 (e.g. a copied identity.cfg) is refused slot 1 AND
	# re-homed to a fresh slot, so it stays stable on this guest's future rejoins.
	var nm := _make_manager()
	nm.token_to_slot["dup"] = 1
	nm.slot_to_peer[1] = 1
	var slot: int = nm._resolve_slot_for_token("dup", 8)
	assert_int(slot).is_not_equal(1)
	assert_int(nm.token_to_slot["dup"]).is_equal(slot)  # re-homed, not left at 1


# ===== disconnect reserves the slot (does not recycle it) =====

func test_disconnect_reserves_slot_keeps_token() -> void:
	var nm := _make_manager()
	nm.token_to_slot["T"] = 2
	nm.slot_to_peer[2] = 7
	nm.peer_to_slot[7] = 2
	nm.player_names[7] = "Bob"
	nm.connected_peers.append(7)
	nm._on_peer_disconnected(7)
	assert_int(nm.token_to_slot["T"]).is_equal(2)                 # reservation kept
	assert_int(nm.slot_to_peer[2]).is_equal(nm.SLOT_RESERVED_PEER)  # vacant
	assert_bool(nm.peer_to_slot.has(7)).is_false()
	assert_bool(nm.player_names.has(7)).is_false()


func test_stale_late_disconnect_after_rebind_is_noop() -> void:
	# Slot 2 was rebound to peer 9; a late close of the OLD peer 7 must NOT vacate it.
	var nm := _make_manager()
	nm.slot_to_peer[2] = 9          # already rebound to the newer peer
	nm.peer_to_slot[7] = 2          # stale reverse entry for the old peer
	nm.peer_to_slot[9] = 2
	nm._on_peer_disconnected(7)
	assert_int(nm.slot_to_peer[2]).is_equal(9)   # untouched
	assert_int(nm.peer_to_slot[9]).is_equal(2)   # newer peer still mapped


# ===== slot lookups =====

func test_slot_for_peer_falls_back_to_peer_id() -> void:
	var nm := _make_manager()
	assert_int(nm.slot_for_peer(42)).is_equal(42)  # unmapped -> identity
	nm.peer_to_slot[42] = 3
	assert_int(nm.slot_for_peer(42)).is_equal(3)


# (get_my_player_slot()'s host=1 / guest-assigned / pending-0 branches depend on the live
# multiplayer singleton state and are covered by the manual reconnect gauntlet, not here.)


# ===== genuine session end clears the maps =====

func test_disconnect_game_clears_identity_maps() -> void:
	var nm := _make_manager()
	nm.token_to_slot["T"] = 2
	nm.slot_to_peer[2] = 7
	nm.peer_to_slot[7] = 2
	nm._my_assigned_slot = 2
	nm._next_slot = 5
	nm.disconnect_game()
	assert_bool(nm.token_to_slot.is_empty()).is_true()
	assert_bool(nm.slot_to_peer.is_empty()).is_true()
	assert_bool(nm.peer_to_slot.is_empty()).is_true()
	assert_int(nm._next_slot).is_equal(2)
	assert_int(nm._my_assigned_slot).is_equal(0)
