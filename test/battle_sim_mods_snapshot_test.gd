extends GdUnitTestSuite
## A1b-1 — BattleSim.capture stamps "mods": SoloController.active_mod_net_of(u), the NET of a
## unit's active spell/token records (durable mirror at unit_properties["spell_records"], shaped
## exactly like main.gd:3652-3665 writes them). Not wired to a consumer yet — this only proves the
## snapshot carries the numbers and that clone_state gives every rollout its own copy.

const IN2M := 0.0254


func _unit(pid: int, positions: Array, uid: String) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = uid
	u.unit_properties = {"player_id": pid, "name": uid, "quality": 4, "defense": 4,
		"special_rules": []}
	for p in positions:
		var m := ModelInstance.new()
		m.is_alive = true
		m.unit = u
		var n := Node3D.new()
		add_child(n)
		n.global_position = p
		m.node = n
		u.models.append(m)
	return u


func _army(units: Array) -> OPRArmyManager:
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	var gu := {}
	for u in units:
		gu[(u as GameUnit).unit_id] = u
	army.game_units = gu
	return army


## main.gd:3652-3665 record shape: only the fields the case cares about differ from zero/empty.
func _record(hit_mod: int, def_mod: int) -> Dictionary:
	return {"spell": "Test Spell", "hit_mod": hit_mod, "def_mod": def_mod, "casting_mod": 0,
		"morale_mod": 0, "range_in": 0, "advance_in": 0, "rush_in": 0, "grants_rule": "",
		"scope": "", "beneficiary": "", "duration": "round"}


func test_capture_stamps_a_hit_buff_into_mods() -> void:
	var buffed := _unit(1, [Vector3.ZERO], "Buffed")
	buffed.unit_properties["spell_records"] = [_record(1, 0)]
	var state := BattleSim.capture(_army([buffed]))
	var mods: Dictionary = (state["units"]["Buffed"] as Dictionary)["mods"]
	assert_int(int(mods["hit"])).is_equal(1)


func test_capture_stamps_zero_mods_with_no_records() -> void:
	var plain := _unit(1, [Vector3.ZERO], "Plain")
	var state := BattleSim.capture(_army([plain]))
	var mods: Dictionary = (state["units"]["Plain"] as Dictionary)["mods"]
	assert_int(int(mods["hit"])).is_equal(0)
	assert_int(int(mods["def"])).is_equal(0)
	assert_int(int(mods["morale"])).is_equal(0)
	assert_float(float(mods["range_in"])).is_equal(0.0)
	assert_float(float(mods["advance"])).is_equal(0.0)
	assert_float(float(mods["rush"])).is_equal(0.0)


func test_clone_state_gives_mods_its_own_copy() -> void:
	var buffed := _unit(1, [Vector3.ZERO], "Buffed")
	buffed.unit_properties["spell_records"] = [_record(1, 0)]
	var state := BattleSim.capture(_army([buffed]))
	var clone := BattleSim.clone_state(state)
	(clone["units"]["Buffed"] as Dictionary)["mods"]["hit"] = 99
	assert_int(int((state["units"]["Buffed"] as Dictionary)["mods"]["hit"])).is_equal(1)
	assert_int(int((clone["units"]["Buffed"] as Dictionary)["mods"]["hit"])).is_equal(99)


func test_capture_stamps_a_def_debuff_into_mods() -> void:
	var hexed := _unit(1, [Vector3.ZERO], "Hexed")
	hexed.unit_properties["spell_records"] = [_record(0, -1)]
	var state := BattleSim.capture(_army([hexed]))
	var mods: Dictionary = (state["units"]["Hexed"] as Dictionary)["mods"]
	assert_int(int(mods["def"])).is_equal(-1)
