extends GdUnitTestSuite
## S1-15 — a Solo game keeps its mission through save and load (the serializer half).
##
## The mission's scoring state lives in six SoloController statics (mission_scoring, mission_vp_flavour,
## mission_vp, mission_vp_memo, mission_markers, mission_destroy_seq). Before this change the save carried
## none of them, so a loaded game was scored by the default rule. test/e2e/e2e_mission_save_reload_test.gd
## proves the same through the real scenes/main.tscn; this suite pins the reader's contract on a bare
## SaveManager: a garbled block must never crash the load, and a load replaces the state whole.
##
## Every "reload" here is a genuine JSON pass (a save IS a JSON file: 1 comes back as 1.0), then the same
## _deserialize_game_state the real load calls.


func _save_mgr() -> SaveManager:
	var sm := SaveManager.new()
	add_child(sm)
	return auto_free(sm)


func after_test() -> void:
	SoloController.mission_reset("end", {})   # statics: never leak this game's mission into the next suite


## Demolition, halfway through round 2: P1's marker fell first (seq 1), P2's still stands.
func _arm_demolition_midgame() -> void:
	SoloController.mission_reset("round_vp", {"mode": "demolition", "majority": "none"}, [
		{"owned_by": 1, "destructible": true, "destroyed": true, "destroyed_seq": 1},
		{"owned_by": 2, "destructible": true, "destroyed": false, "destroyed_seq": 0}])
	SoloController.mission_vp = [0, 1]
	SoloController.mission_vp_memo = {"first_seizer": 2}
	SoloController.mission_destroy_seq = [1]


func _wire(sm: SaveManager) -> Dictionary:
	return JSON.parse_string(JSON.stringify(sm._serialize_game_state()))


## Bounds-safe read. On the unrestored state these arrays can be empty, and an out-of-bounds read is a
## script error that aborts the whole run under `-d` instead of failing the one assertion.
func _at(arr: Array, i: int, fallback: Variant) -> Variant:
	return arr[i] if i >= 0 and i < arr.size() else fallback


func _marker(i: int) -> Dictionary:
	return _at(SoloController.mission_markers, i, {})


func _assert_fresh_statics(why: String) -> void:
	assert_str(SoloController.mission_scoring).override_failure_message("%s: scoring is not the default" % why).is_equal("end")
	assert_dict(SoloController.mission_vp_flavour).override_failure_message("%s: VP flavour is left over" % why).is_empty()
	assert_int(SoloController.mission_vp.size()).override_failure_message("%s: ledger is not a pair" % why).is_equal(2)
	assert_int(int(_at(SoloController.mission_vp, 0, -1)) + int(_at(SoloController.mission_vp, 1, -1))) \
		.override_failure_message("%s: ledger is not [0, 0]" % why).is_equal(0)
	assert_dict(SoloController.mission_vp_memo).override_failure_message("%s: first-seize memo is left over" % why).is_empty()
	assert_array(SoloController.mission_markers).override_failure_message("%s: mission markers are left over" % why).is_empty()
	assert_int(int(_at(SoloController.mission_destroy_seq, 0, -1))).override_failure_message("%s: destruction counter is left over" % why).is_equal(0)


# === The scoring state comes back, by value =======================================================

func test_the_six_statics_survive_a_save() -> void:
	var sm := _save_mgr()
	_arm_demolition_midgame()
	var wire := _wire(sm)
	SoloController.mission_reset("end", {})   # a fresh process: the statics start at their defaults
	sm._deserialize_game_state(wire)
	assert_str(SoloController.mission_scoring).is_equal("round_vp")
	assert_str(str(SoloController.mission_vp_flavour.get("mode", ""))).is_equal("demolition")
	assert_str(str(SoloController.mission_vp_flavour.get("majority", ""))).is_equal("none")
	assert_int(SoloController.mission_vp.size()).is_equal(2)
	assert_int(int(_at(SoloController.mission_vp, 0, -1))).is_equal(0)
	assert_int(int(_at(SoloController.mission_vp, 1, -1))).is_equal(1)
	assert_int(int(SoloController.mission_vp_memo.get("first_seizer", 0))).is_equal(2)
	assert_int(int(_at(SoloController.mission_destroy_seq, 0, -1))).is_equal(1)
	assert_int(SoloController.mission_markers.size()).is_equal(2)
	var m0 := _marker(0)
	assert_int(int(m0.get("owned_by", 0))).is_equal(1)
	assert_bool(bool(m0.get("destructible", false))).is_true()
	assert_bool(bool(m0.get("destroyed", false))).is_true()
	assert_int(int(m0.get("destroyed_seq", 0))).is_equal(1)
	var m1 := _marker(1)
	assert_int(int(m1.get("owned_by", 0))).is_equal(2)
	assert_bool(bool(m1.get("destroyed", true))).is_false()
	assert_int(int(m1.get("destroyed_seq", -1))).is_equal(0)


## The restored numbers are ints again, not the 1.0 a JSON pass hands out: the ledger, the destruction
## counter and the marker fields are added to and compared by the bookkeeping.
func test_restored_counters_are_integers_again() -> void:
	var sm := _save_mgr()
	_arm_demolition_midgame()
	var wire := _wire(sm)
	SoloController.mission_reset("end", {})
	sm._deserialize_game_state(wire)
	assert_int(typeof(_at(SoloController.mission_vp, 1, null))).is_equal(TYPE_INT)
	assert_int(typeof(_at(SoloController.mission_destroy_seq, 0, null))).is_equal(TYPE_INT)
	assert_int(typeof(_marker(0).get("destroyed_seq"))).is_equal(TYPE_INT)
	assert_int(typeof(SoloController.mission_vp_memo.get("first_seizer"))).is_equal(TYPE_INT)


# === A load REPLACES the state; a save without mission data is today's behaviour ==================

func test_a_save_without_mission_data_resets_the_statics() -> void:
	var sm := _save_mgr()
	_arm_demolition_midgame()   # the session was playing a mission before the load
	sm._deserialize_game_state({"current_round": 2, "game_phase": OPRArmyManager.GamePhase.PLAYING})
	_assert_fresh_statics("old save")


func test_a_duel_save_clears_the_mission_the_session_was_playing() -> void:
	var sm := _save_mgr()
	SoloController.mission_reset("end", {})
	var wire := _wire(sm)   # saved in a Duel: no mission, default scoring
	_arm_demolition_midgame()
	sm._deserialize_game_state(wire)
	_assert_fresh_statics("duel save")


func test_a_mission_block_does_not_leak_into_the_next_load() -> void:
	var sm := _save_mgr()
	_arm_demolition_midgame()
	sm._deserialize_game_state(_wire(sm))
	sm._deserialize_game_state({"current_round": 1})   # then an old save is loaded
	_assert_fresh_statics("second load")


# === Robustness — a hand-edited or damaged save must not abort the load ===========================

func test_a_garbled_mission_block_falls_back_to_the_defaults() -> void:
	var sm := _save_mgr()
	_arm_demolition_midgame()
	sm._deserialize_game_state({"solo_mission": "garbage"})
	_assert_fresh_statics("garbled block")
	_arm_demolition_midgame()
	sm._deserialize_game_state({"solo_mission": {"scoring": 5, "vp": "x", "vp_memo": 3, "markers": [1, "x", null],
		"destroy_seq": {}, "vp_flavour": []}})
	_assert_fresh_statics("garbled fields")


## JSON null in a field (a hand edit, or a writer that lost a value) is not a number to int().
func test_null_fields_fall_back_to_the_defaults() -> void:
	var sm := _save_mgr()
	_arm_demolition_midgame()
	sm._deserialize_game_state({"solo_mission": {"scoring": null, "vp": [null, null], "vp_memo": null, "markers": null,
		"destroy_seq": [null], "vp_flavour": null, "id": null}})
	_assert_fresh_statics("null fields")
