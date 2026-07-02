extends GdUnitTestSuite
## Slot bookkeeping for parked dead loose models (G1/G2). Exercises the pure static helpers in
## OPRArmyManager (_alloc_unit_slot / _first_free_row_start / _free_slot_index / _release_unit_anchor)
## — no army/tray nodes needed. Guarantees:
##  • a unit's dead models group into a CONTIGUOUS block, two units never interleave (G2);
##  • kill→revive→kill within a unit reuses its block; a fully-revived unit's block is released (G2);
##  • a revived slot is reclaimed — no kill→revive→kill creep (the original T1 regression);
##  • a full tray wraps in-range (never off-tray); MP forced slots are honoured;
##  • fill order is row-major from row 0, so the first rows sit in the FAR two-thirds, out of the
##    near-third Ambush/Scout band (G1) — the band starts at center + bounds.y/6 ≈ row 6 of 8.

const COLS := 8
const CAP := 64   # 8×8 tray (matches the ~0.81 m square army tray)


func test_single_unit_fills_sequentially_from_its_anchor() -> void:
	var occ := {}
	var anc := {}
	assert_int(OPRArmyManager._alloc_unit_slot(occ, anc, "u1", COLS, CAP)).is_equal(0)
	assert_int(OPRArmyManager._alloc_unit_slot(occ, anc, "u1", COLS, CAP)).is_equal(1)
	assert_int(OPRArmyManager._alloc_unit_slot(occ, anc, "u1", COLS, CAP)).is_equal(2)


func test_two_interleaved_units_stay_in_separate_contiguous_blocks() -> void:
	var occ := {}
	var anc := {}
	var a0 := OPRArmyManager._alloc_unit_slot(occ, anc, "A", COLS, CAP)   # A anchors row 0 → 0
	var b0 := OPRArmyManager._alloc_unit_slot(occ, anc, "B", COLS, CAP)   # B first fully-free row → 8
	var a1 := OPRArmyManager._alloc_unit_slot(occ, anc, "A", COLS, CAP)   # A extends → 1
	var b1 := OPRArmyManager._alloc_unit_slot(occ, anc, "B", COLS, CAP)   # B extends → 9
	assert_int(a0).is_equal(0)
	assert_int(a1).is_equal(1)             # A block contiguous: 0,1 (row 0)
	assert_int(b0).is_equal(COLS)          # B on its own row
	assert_int(b1).is_equal(COLS + 1)      # B block contiguous: 8,9 (row 1)
	assert_int(a1 / COLS).is_equal(0)      # blocks on different rows → never interleaved
	assert_int(b1 / COLS).is_equal(1)


func test_kill_revive_kill_within_a_unit_reuses_its_block() -> void:
	var occ := {}
	var anc := {}
	var a0 := OPRArmyManager._alloc_unit_slot(occ, anc, "A", COLS, CAP)   # 0
	var a1 := OPRArmyManager._alloc_unit_slot(occ, anc, "A", COLS, CAP)   # 1
	OPRArmyManager._free_slot_index(occ, a1)                             # revive the 2nd model
	OPRArmyManager._release_unit_anchor(occ, anc, "A")                   # still has slot 0 → anchor kept
	var a1b := OPRArmyManager._alloc_unit_slot(occ, anc, "A", COLS, CAP)  # re-kill → reuse slot 1
	assert_int(a0).is_equal(0)
	assert_int(a1b).is_equal(1)
	assert_bool(anc.has("A")).is_true()


func test_fully_revived_unit_releases_its_block_for_repacking() -> void:
	var occ := {}
	var anc := {}
	OPRArmyManager._alloc_unit_slot(occ, anc, "A", COLS, CAP)             # 0
	OPRArmyManager._alloc_unit_slot(occ, anc, "A", COLS, CAP)             # 1
	OPRArmyManager._free_slot_index(occ, 0)
	OPRArmyManager._free_slot_index(occ, 1)
	OPRArmyManager._release_unit_anchor(occ, anc, "A")                   # no slots left → anchor dropped
	assert_bool(anc.has("A")).is_false()
	# a new unit re-packs the freed row 0 instead of creeping outward
	assert_int(OPRArmyManager._alloc_unit_slot(occ, anc, "B", COLS, CAP)).is_equal(0)


func test_kill_revive_kill_cycle_stays_bounded_and_fully_reclaims() -> void:
	var occ := {}
	var anc := {}
	for _i in range(40):
		var idx: int = OPRArmyManager._alloc_unit_slot(occ, anc, "A", COLS, 4)
		assert_int(idx).is_greater_equal(0)
		assert_int(idx).is_less(4)          # never leaves the 4-slot tray
		OPRArmyManager._free_slot_index(occ, idx)
		OPRArmyManager._release_unit_anchor(occ, anc, "A")
	assert_int(occ.size()).is_equal(0)      # every slot reclaimed — no leak


func test_overflowing_a_full_tray_wraps_into_range() -> void:
	var occ := {}
	var anc := {}
	for i in range(4):
		OPRArmyManager._alloc_unit_slot(occ, anc, "u%d" % i, 2, 4)   # fill all 4 slots
	var idx: int = OPRArmyManager._alloc_unit_slot(occ, anc, "x", 2, 4)  # overflow → wraps in-range
	assert_int(idx).is_greater_equal(0)
	assert_int(idx).is_less(4)


func test_forced_index_is_honoured_and_anchors_the_block() -> void:
	var occ := {}
	var anc := {}
	assert_int(OPRArmyManager._alloc_unit_slot(occ, anc, "A", COLS, CAP, 5)).is_equal(5)
	assert_bool(occ.has(5)).is_true()
	assert_int(int(anc["A"])).is_equal(5)   # pinned slot becomes the block anchor (MP replay/restore)


func test_fill_order_keeps_early_rows_out_of_the_band() -> void:
	# The near-third band starts at row ~6 of 8 (center + bounds.y/6). Row-major fill means the first
	# 48 slots (rows 0–5) are claimed before any band row — dead minis park behind the band (G1).
	var occ := {}
	var anc := {}
	for _i in range(48):
		var idx: int = OPRArmyManager._alloc_unit_slot(occ, anc, "big", COLS, CAP)
		assert_int(idx / COLS).is_less(6)   # stays in the far-two-thirds safe rows


func test_dead_group_key_derives_unit_from_meta_when_id_empty() -> void:
	# J2: with an empty caller id, the block key is derived from the model's own game_unit, so a whole
	# unit parks as one block no matter which call site removed it.
	var gu := GameUnit.new()
	gu.unit_id = "U1"
	var n1: Node3D = auto_free(Node3D.new())
	var n2: Node3D = auto_free(Node3D.new())
	n1.set_meta("game_unit", gu)
	n2.set_meta("game_unit", gu)
	assert_str(OPRArmyManager._dead_group_key("", n1)).is_equal("U1")
	assert_str(OPRArmyManager._dead_group_key("", n2)).is_equal("U1")
	assert_str(OPRArmyManager._dead_group_key("X", n1)).is_equal("X")   # explicit id always wins
	var n3: Node3D = auto_free(Node3D.new())
	assert_str(OPRArmyManager._dead_group_key("", n3)).is_not_equal("U1")   # no unit → lone key


func test_multikill_one_unit_empty_id_forms_one_contiguous_block() -> void:
	# 4 simultaneous removals from ONE unit via the public entry with an EMPTY unit_id: the derived key
	# is identical, so the slots pack into ONE contiguous block instead of scattering (J2 regression).
	var gu := GameUnit.new()
	gu.unit_id = "squad"
	var occ := {}
	var anc := {}
	var slots: Array[int] = []
	for _i in range(4):
		var n: Node3D = auto_free(Node3D.new())
		n.set_meta("game_unit", gu)
		slots.append(OPRArmyManager._alloc_unit_slot(occ, anc, OPRArmyManager._dead_group_key("", n), COLS, CAP))
	assert_array(slots).is_equal([0, 1, 2, 3])   # contiguous, not scattered across rows
