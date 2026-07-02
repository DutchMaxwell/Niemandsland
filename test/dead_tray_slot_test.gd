extends GdUnitTestSuite
## Regression (T1): a parked dead loose model's army-tray slot must be RECLAIMED on revive, so a
## kill→revive→kill cycle reuses the freed slot instead of creeping outward forever. Also guards that
## a slot index never leaves the tray (wraps into [0, capacity)). Tests the pure slot bookkeeping
## helpers in OPRArmyManager (_alloc_slot_index / _free_slot_index) — no army/tray nodes needed.


func test_first_allocations_are_sequential() -> void:
	var occ := {}
	assert_int(OPRArmyManager._alloc_slot_index(occ, 8)).is_equal(0)
	assert_int(OPRArmyManager._alloc_slot_index(occ, 8)).is_equal(1)
	assert_int(OPRArmyManager._alloc_slot_index(occ, 8)).is_equal(2)


func test_revive_frees_slot_and_next_kill_reuses_it() -> void:
	var occ := {}
	var a: int = OPRArmyManager._alloc_slot_index(occ, 8)   # 0
	var b: int = OPRArmyManager._alloc_slot_index(occ, 8)   # 1
	OPRArmyManager._free_slot_index(occ, a)                 # revive the first-parked model
	var c: int = OPRArmyManager._alloc_slot_index(occ, 8)   # must REUSE 0, not creep to 2
	assert_int(c).is_equal(0)
	assert_int(b).is_equal(1)


func test_kill_revive_kill_cycle_stays_bounded_and_fully_reclaims() -> void:
	var occ := {}
	for _i in range(20):
		var idx: int = OPRArmyManager._alloc_slot_index(occ, 4)
		assert_int(idx).is_greater_equal(0)
		assert_int(idx).is_less(4)          # never leaves the 4-slot tray
		OPRArmyManager._free_slot_index(occ, idx)
	assert_int(occ.size()).is_equal(0)      # every slot reclaimed — no leak


func test_overflowing_a_full_tray_wraps_into_range() -> void:
	var occ := {}
	for _i in range(4):
		OPRArmyManager._alloc_slot_index(occ, 4)            # 0..3 all occupied
	var idx: int = OPRArmyManager._alloc_slot_index(occ, 4) # overflow → must wrap, not go off-tray
	assert_int(idx).is_greater_equal(0)
	assert_int(idx).is_less(4)


func test_forced_index_is_honoured_for_mp_replay() -> void:
	var occ := {}
	assert_int(OPRArmyManager._alloc_slot_index(occ, 8, 5)).is_equal(5)
	assert_bool(occ.has(5)).is_true()
