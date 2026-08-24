extends GdUnitTestSuite
## NML-1051: an imagined round boundary must run the BOOK round end — seize
## from the final positions, then the round's VP — exactly as the factory
## playout (full_playout) books it. Before the fix, rollout_boundaries froze
## marker ownership and the VP ledger at the last REAL round end, so the
## planner priced imagined futures in a currency the game does not pay.

const IN2M := 0.0254


func _lone(pid: int, pos: Vector3, uid: String) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = uid
	u.unit_properties = {"player_id": pid, "name": uid, "quality": 4, "defense": 4,
		"special_rules": []}
	var m := ModelInstance.new()
	m.is_alive = true
	m.wounds_current = 1
	m.unit = u
	var n := Node3D.new()
	add_child(n)
	n.global_position = pos
	m.node = n
	u.models.append(m)
	var opr := OPRApiClient.OPRUnit.new()
	var ow := OPRApiClient.OPRWeapon.new()
	ow.name = "CCW"
	ow.range_value = 0
	ow.attacks = 1
	ow.count = 1
	opr.weapons.append(ow)
	u.source_type = "opr"
	u.source_data = opr
	return u


## One marker at the origin, one unit per side, live owner as given. The FOE
## is pre-activated so the imagined round ends right after the first action.
func _state(my_pos: Vector3, foe_pos: Vector3, owner0: int) -> Dictionary:
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {"Mine": _lone(1, my_pos, "Mine"), "Foe": _lone(2, foe_pos, "Foe")}
	var state := BattleSim.capture(army, func() -> Array: return [Vector3.ZERO],
		func(_i: int) -> int: return owner0)
	(state["units"]["Foe"] as Dictionary)["activated"] = true
	return state


func _hold_mine() -> Dictionary:
	return {"unit": "Mine", "kind": AiDecision.Action.HOLD}


## The enemy stands alone on OUR marker when the imagined round ends: the
## boundary snapshot must hand the marker over, not keep the stale owner.
func test_boundary_flips_the_marker_to_the_lone_enemy() -> void:
	var ends := AiPlanner.rollout_boundaries(
		_state(Vector3(20.0 * IN2M, 0, 0), Vector3.ZERO, 1), _hold_mine(), 1, 1)
	assert_int(ends.size()).is_equal(1)
	assert_int(int(((ends[0] as Dictionary)["objectives"][0] as Dictionary)["owner"])).is_equal(2)


## Both sides in the 3" ring = NEUTRAL (sides present, not bodies present).
func test_both_sides_near_neutralise_the_marker() -> void:
	var ends := AiPlanner.rollout_boundaries(
		_state(Vector3(1.0 * IN2M, 0, 0), Vector3(-1.0 * IN2M, 0, 0), 1), _hold_mine(), 1, 1)
	assert_int(int(((ends[0] as Dictionary)["objectives"][0] as Dictionary)["owner"])).is_equal(0)


## The VP ledger grows at EVERY imagined boundary (1 VP per held marker per
## round) and the input state's ledger stays untouched — sibling rollouts
## share the captured state, so a leak here would corrupt every other branch.
func test_vp_ledger_grows_across_boundaries() -> void:
	var state := _state(Vector3.ZERO, Vector3(30.0 * IN2M, 0, 0), 1)
	state["vp"] = [0, 0]
	state["vp_flavour"] = {}
	state["vp_memo"] = {}
	var ends := AiPlanner.rollout_boundaries(state, _hold_mine(), 1, 2)
	assert_int(ends.size()).is_equal(2)
	assert_int(int(((ends[0] as Dictionary)["vp"] as Array)[0])).is_equal(1)
	assert_int(int(((ends[1] as Dictionary)["vp"] as Array)[0])).is_equal(2)
	assert_int(int((state["vp"] as Array)[0])).is_equal(0)


## First-seize flavour books exactly like the factory round end: seize (+1
## round VP) plus the one-off first-seizer bonus into a COPIED memo — the
## snapshot carries first_seizer=1 and vp [2,0], the input memo stays empty.
func test_first_seize_books_like_the_factory_and_leaks_nothing() -> void:
	var state := _state(Vector3.ZERO, Vector3(30.0 * IN2M, 0, 0), 0)
	state["vp"] = [0, 0]
	state["vp_flavour"] = {"first_seize": true}
	state["vp_memo"] = {}
	var ends := AiPlanner.rollout_boundaries(state, _hold_mine(), 1, 1)
	var snap: Dictionary = ends[0] as Dictionary
	assert_int(int((snap["vp"] as Array)[0])).is_equal(2)
	assert_int(int((snap["vp_memo"] as Dictionary).get("first_seizer", 0))).is_equal(1)
	assert_bool((state["vp_memo"] as Dictionary).is_empty()).is_true()
	assert_int(int((state["vp"] as Array)[0])).is_equal(0)


## The A/B seam: NML_IMAGINED_ROUND_END=off restores the frozen boundary —
## the two arms of the stage-1 measurement differ in exactly this switch.
func test_seam_off_restores_the_frozen_boundary() -> void:
	OS.set_environment("NML_IMAGINED_ROUND_END", "off")
	AiPlanner._ire_env = -1
	var ends := AiPlanner.rollout_boundaries(
		_state(Vector3(20.0 * IN2M, 0, 0), Vector3.ZERO, 1), _hold_mine(), 1, 1)
	OS.set_environment("NML_IMAGINED_ROUND_END", "")
	AiPlanner._ire_env = -1
	assert_int(int(((ends[0] as Dictionary)["objectives"][0] as Dictionary)["owner"])).is_equal(1)
