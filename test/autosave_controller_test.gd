extends GdUnitTestSuite
## Autosave (ROADMAP follow-up): the PURE decision + slot-rotation helpers. The runtime wiring
## (timer, round hook, SaveManager write) reuses save_game unchanged and is covered by the
## existing save/load suites; these tests pin the gate rules and the oldest-slot rotation.


# === slot rotation: empty slot first, else the OLDEST ===

func test_pick_slot_prefers_an_empty_slot() -> void:
	assert_int(AutosaveController.pick_slot({})).is_equal(1)
	assert_int(AutosaveController.pick_slot({1: 100})).is_equal(2)
	assert_int(AutosaveController.pick_slot({1: 100, 2: 200})).is_equal(3)


func test_pick_slot_overwrites_the_oldest_when_full() -> void:
	assert_int(AutosaveController.pick_slot({1: 300, 2: 100, 3: 200})).is_equal(2)
	assert_int(AutosaveController.pick_slot({1: 50, 2: 100, 3: 200})).is_equal(1)
	# A corrupted-latest scenario: the newest slot is never the next write target.
	assert_int(AutosaveController.pick_slot({1: 100, 2: 200, 3: 300})).is_equal(1)


func test_pick_slot_respects_a_custom_slot_count() -> void:
	assert_int(AutosaveController.pick_slot({1: 10}, 2)).is_equal(2)
	assert_int(AutosaveController.pick_slot({1: 10, 2: 20}, 2)).is_equal(1)


# === the gate: every no-autosave rule in one place ===

func test_gate_happy_path_offline_with_content() -> void:
	assert_bool(AutosaveController.should_autosave(false, false, false, true, -1)).is_true()


func test_gate_blocks_without_content() -> void:
	assert_bool(AutosaveController.should_autosave(false, false, false, false, -1)).is_false()


func test_gate_blocks_during_restore() -> void:
	assert_bool(AutosaveController.should_autosave(false, false, true, true, -1)).is_false()


func test_gate_mp_host_only() -> void:
	# In a live MP session the guest never autosaves (replica state); the host does.
	assert_bool(AutosaveController.should_autosave(true, false, false, true, -1)).is_false()
	assert_bool(AutosaveController.should_autosave(true, true, false, true, -1)).is_true()


func test_gate_debounces_bursts() -> void:
	# A round-advance right after a periodic save must not burst-write; past the gap it may.
	var gap_ms := int(AutosaveController.MIN_GAP_SEC * 1000.0)
	assert_bool(AutosaveController.should_autosave(false, false, false, true, gap_ms - 1)).is_false()
	assert_bool(AutosaveController.should_autosave(false, false, false, true, gap_ms)).is_true()
	# -1 = never autosaved yet — always allowed.
	assert_bool(AutosaveController.should_autosave(false, false, false, true, -1)).is_true()
