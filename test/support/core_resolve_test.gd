extends GdUnitTestSuite
## The shared CoreResolve helper on the one number its GDScript twin already hand-computed:
## test/battle_sim_resolve_test.gd::test_shoot_kills_by_expectation_and_cover_saves (Rifle: 4 attacks, Q4+ hit
## 0.5, Def4+ AP0 unsaved 0.5 -> 1.0 expected wound -> exactly one model of the 4-model squad falls).
## Epoch proof: the core CARRIES a unit's plain `kits` only from epoch 75 on, and without the header it runs at
## epoch 0 and drops them — so their presence in its answer proves the live epoch reached the core.

const IN2M := 0.0254


func test_a_hold_volley_through_the_core_matches_the_table_hand_number_at_the_live_epoch() -> void:
	var target := []
	for i in range(4):
		target.append(Vector3((12.0 + i) * IN2M, 0, 0))
	var state := _capture([_armed(2, [Vector3.ZERO], "Shooter"), _armed(1, target, "Squad")])
	var next := CoreResolve.resolve(state,
		{"unit": "Shooter", "kind": AiDecision.Action.HOLD, "shoot": "Squad"})
	assert_int(int((next["units"]["Squad"] as Dictionary)["alive"])).is_equal(3)
	assert_bool((next["units"]["Squad"] as Dictionary).has("kits")) \
		.override_failure_message("the core ran at epoch 0: no game header, no kits").is_true()


## The seams dict must reach a core that HAS a header: NmlCore.resolve takes its seams off the header
## knobs, so set_seams alone is headerless-only. Spacing off lands the mover on the blocker's centre
## (a negative base-edge gap); spacing on keeps the UNIT_SPACING_IN disc. Without the header stamp
## both runs clamp and the off assertion reads ~0.99" -> RED.
func test_the_seams_dict_reaches_a_core_that_has_a_header() -> void:
	var mover := _bare(1, [Vector3.ZERO], "Mover")
	var blocker := _bare(2, [Vector3(2.3 * IN2M, 0, 0)], "Blocker")
	var state := _capture([mover, blocker])
	var action := {"unit": "Mover", "kind": AiDecision.Action.RUSH, "dest": Vector3(2.3 * IN2M, 0, 0)}
	var on := CoreResolve.resolve(state, action, {"spacing": true})
	var off := CoreResolve.resolve(state, action, {"spacing": false})
	assert_float(_gap_in(on)).is_greater_equal(SoloController.UNIT_SPACING_IN - 0.01)
	assert_float(_gap_in(off)).is_less(0.0)


func _bare(pid: int, positions: Array, uid: String) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = uid
	u.unit_properties = {"player_id": pid, "name": uid, "quality": 4, "defense": 4, "special_rules": []}
	for p in positions:
		var m := ModelInstance.new()
		m.is_alive = true
		m.wounds_current = 1
		m.unit = u
		var n := Node3D.new()
		add_child(n)
		n.global_position = p
		m.node = n
		u.models.append(m)
	return u


func _gap_in(next: Dictionary) -> float:
	var mp: Vector3 = (next["units"]["Mover"] as Dictionary)["positions"][0]
	var bp: Vector3 = (next["units"]["Blocker"] as Dictionary)["positions"][0]
	return (mp - bp).length() / IN2M - 2.0 * SeparationChecker.DEFAULT_BASE_RADIUS_M / IN2M


func _armed(pid: int, positions: Array, uid: String) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = uid
	u.unit_properties = {"player_id": pid, "name": uid, "quality": 4, "defense": 4, "special_rules": []}
	for p in positions:
		var m := ModelInstance.new()
		m.is_alive = true
		m.wounds_current = 1
		m.unit = u
		var n := Node3D.new()
		add_child(n)
		n.global_position = p
		m.node = n
		u.models.append(m)
	var opr := OPRApiClient.OPRUnit.new()
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Rifle"
	w.range_value = 24
	w.attacks = 4
	w.count = 1
	opr.weapons.append(w)
	u.source_type = "opr"
	u.source_data = opr
	return u


func _capture(units: Array) -> Dictionary:
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	var gu := {}
	for u in units:
		gu[(u as GameUnit).unit_id] = u
	army.game_units = gu
	return BattleSim.capture(army)
