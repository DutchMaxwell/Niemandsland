extends GdUnitTestSuite
## #673 co-op: the defender's owner rolls its own saves — the per-unit owner lookup and the
## owner-is-local gate (the prompt must open ONLY on the peer that owns the defender).

const MainScript := preload("res://scripts/main.gd")


func test_unit_owner_slot_reads_player_id() -> void:
	assert_int(MainScript.unit_owner_slot({"player_id": 2})).is_equal(2)
	assert_int(MainScript.unit_owner_slot({"player_id": 3})).is_equal(3)


func test_unit_owner_slot_defaults_to_zero() -> void:
	# A unit without a player_id is unowned (never a local owner in MP).
	assert_int(MainScript.unit_owner_slot({})).is_equal(0)


func test_owner_is_local_when_no_mp_session() -> void:
	# SOLO INVARIANT: without a session the local player owns everything, whatever the
	# player_id says — the save prompt UX stays byte-identical in single-player.
	assert_bool(MainScript.defender_owner_is_local({"player_id": 2}, false, 1)).is_true()
	assert_bool(MainScript.defender_owner_is_local({"player_id": 0}, false, 0)).is_true()


func test_owner_is_local_only_for_the_owners_slot_in_mp() -> void:
	# The prompt opens ONLY on the defender's owner; every other peer routes the batch away.
	assert_bool(MainScript.defender_owner_is_local({"player_id": 2}, true, 2)).is_true()
	assert_bool(MainScript.defender_owner_is_local({"player_id": 2}, true, 1)).is_false()
	assert_bool(MainScript.defender_owner_is_local({"player_id": 0}, true, 1)).is_false()
