extends GdUnitTestSuite
## Phase-1 step 3: parity harness wave 1 — the SAME fixture pushed through the
## real seams (live GameUnits + AiEv/SoloController statics) and through the
## BattleSim snapshot must yield the SAME numbers. Hit and save targets are
## pure functions of the ctx fields, so full-ctx equality covers them; shoot/
## melee EV, band distances and objective-owner verdicts are compared directly.
## This suite is the honesty gate for the planner substrate: any BattleSim
## drift from the live rules shows up here first.

const IN2M := 0.0254


func before_test() -> void:
	AiEv.versatile_enabled = true
	RulesRegistry.reset_cache()
	SpellsRegistry.reset_cache()


func _armed(pid: int, positions: Array, uid: String, weapons: Array,
		rules: Array = [], wounds_now: int = 1) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = uid
	u.unit_properties = {"player_id": pid, "name": uid, "quality": 4, "defense": 4,
		"special_rules": rules}
	for p in positions:
		var m := ModelInstance.new()
		m.is_alive = true
		m.wounds_current = wounds_now
		m.unit = u
		var n := Node3D.new()
		add_child(n)
		n.global_position = p
		m.node = n
		u.models.append(m)
	var opr := OPRApiClient.OPRUnit.new()
	for w in weapons:
		var ow := OPRApiClient.OPRWeapon.new()
		ow.name = str((w as Dictionary).get("name", "W"))
		ow.range_value = int((w as Dictionary).get("range", 0))
		ow.attacks = int((w as Dictionary).get("attacks", 4))
		ow.count = 1
		opr.weapons.append(ow)
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


## The real path's profile pipeline on the LIVE unit (weapons -> range filter ->
## sergeant stamp -> survivor-scaled attacks), independent of BattleSim code.
func _real_profiles(u: GameUnit, melee: bool, d: float) -> Array:
	var weapons: Array = (u.source_data as OPRApiClient.OPRUnit).weapons
	var profiles: Array = AiShooting.melee_profiles(weapons) if melee \
		else AiShooting.profiles_in_range(weapons, d)
	var out: Array = []
	for p in AiEv.stamp_sergeant(profiles, u):
		var q := (p as Dictionary).duplicate()
		q["attacks"] = SoloController.effective_attacks(int(q.get("attacks", 0)),
			u.get_alive_count(), u.models.size())
		out.append(q)
	return out


func _live_dist_in(a: GameUnit, b: GameUnit) -> float:
	var best := INF
	for ma in a.models:
		for mb in b.models:
			if (ma as ModelInstance).is_alive and (mb as ModelInstance).is_alive:
				best = minf(best, ((ma as ModelInstance).node.global_position
					- (mb as ModelInstance).node.global_position).length())
	return best / IN2M


## Full-ctx parity (covers hit target = f(quality) and save target =
## f(defense, cover)), held BOTH before and after the same casualty is applied
## independently in each world: live kill via is_alive, sim kill via the
## snapshot's dynamic arrays. Catches any drift in the models/cover patching.
func test_ctx_parity_survives_a_casualty() -> void:
	var ogres := _armed(1, [Vector3.ZERO, Vector3(IN2M, 0, 0)], "Ogres",
		[{"name": "Claws", "range": 0}], ["Tough(3)"], 3)
	var su: Dictionary = _capture([ogres])["units"]["Ogres"]
	su["in_cover"] = true
	assert_that(BattleSim._ctx_of(su)).is_equal(AiEv.ctx_for(ogres, true))
	(ogres.models[0] as ModelInstance).is_alive = false
	(su["positions"] as Array).remove_at(0)
	(su["wounds"] as Array).remove_at(0)
	su["alive"] = 1
	var sim_ctx := BattleSim._ctx_of(su)
	assert_that(sim_ctx).is_equal(AiEv.ctx_for(ogres, true))
	assert_int(int(sim_ctx["models"])).is_equal(1)


func test_shoot_and_melee_ev_parity() -> void:
	var shooter := _armed(2, [Vector3.ZERO], "Shooter", [{"name": "Rifle", "range": 24}])
	var ogres := _armed(1, [Vector3(12.0 * IN2M, 0, 0), Vector3(13.0 * IN2M, 0, 0)],
		"Ogres", [{"name": "Claws", "range": 0}], ["Tough(3)"], 3)
	var state := _capture([shooter, ogres])
	var su: Dictionary = state["units"]["Shooter"]
	var tu: Dictionary = state["units"]["Ogres"]
	var d := BattleSim.dist_in(su["positions"], tu["positions"])
	assert_float(d).is_equal_approx(_live_dist_in(shooter, ogres), 0.001)
	var real_shoot := AiEv.shoot_ev(_real_profiles(shooter, false, d),
		AiEv.ctx_for(shooter), AiEv.ctx_for(ogres), d)
	assert_float(real_shoot).is_greater(0.0)   # parity of zeros proves nothing
	assert_float(AiEv.shoot_ev(BattleSim._profiles_of(su, false, d),
		BattleSim._ctx_of(su), BattleSim._ctx_of(tu), d)).is_equal_approx(real_shoot, 0.0001)
	var real_melee := AiEv.melee_ev(_real_profiles(ogres, true, 0.0),
		AiEv.ctx_for(ogres), AiEv.ctx_for(shooter), true)
	assert_float(real_melee).is_greater(0.0)
	assert_float(AiEv.melee_ev(BattleSim._profiles_of(tu, true),
		BattleSim._ctx_of(tu), BattleSim._ctx_of(su), true)).is_equal_approx(real_melee, 0.0001)


## The sim's clamped translate must land EXACTLY on the official band numbers
## move_bands_for_unit reports for this unit — not on hardcoded 6/12.
func test_band_distance_parity() -> void:
	var grunts := _armed(2, [Vector3.ZERO], "Grunts", [{"name": "CCW", "range": 0}])
	var state := _capture([grunts])
	var bands := SoloController.move_bands_for_unit(grunts, null)
	var goal := Vector3(40.0 * IN2M, 0, 0)
	for pair in [[AiDecision.Action.ADVANCE, "advance"], [AiDecision.Action.RUSH, "rush"]]:
		var next := BattleSim.resolve(state, {"unit": "Grunts", "kind": pair[0], "dest": goal})
		var moved: float = ((next["units"]["Grunts"] as Dictionary)["positions"][0] as Vector3).length() / IN2M
		assert_float(moved).is_equal_approx(float(bands[pair[1]]), 0.01)


## Same seize_objectives verdict from live-node infos and from snapshot infos.
## The shaken holder is the discriminator: if the shaken flag did not survive
## the capture, the sim verdict would flip to P1 while the live one stays 0.
func test_objective_owner_verdict_parity() -> void:
	var obj := Vector3.ZERO
	var holder := _armed(1, [Vector3(2.0 * IN2M, 0, 0)], "Holder", [{"name": "CCW", "range": 0}])
	var shaken := _armed(2, [Vector3(1.0 * IN2M, 0, 0)], "Shaken", [{"name": "CCW", "range": 0}])
	shaken.is_shaken = true
	var far := _armed(2, [Vector3(9.0 * IN2M, 0, 0)], "Far", [{"name": "CCW", "range": 0}])
	var state := _capture([holder, shaken, far])
	var live_infos: Array = []
	for u in [holder, shaken, far]:
		var pos: Array = []
		for m in (u as GameUnit).models:
			pos.append((m as ModelInstance).node.global_position)
		live_infos.append({"player": int((u as GameUnit).unit_properties["player_id"]),
			"positions": pos, "shaken": (u as GameUnit).is_shaken})
	var snap_infos: Array = []
	for key in state["units"]:
		var su: Dictionary = state["units"][key]
		snap_infos.append({"player": su["player"], "positions": su["positions"],
			"shaken": su["shaken"]})
	var live_owners: Array = SoloController.seize_objectives(live_infos, [obj], [0])["owners"]
	var snap_owners: Array = SoloController.seize_objectives(snap_infos, [obj], [0])["owners"]
	assert_that(snap_owners).is_equal(live_owners)
	assert_int(int(live_owners[0])).is_equal(1)   # shaken P2 cannot contest -> P1 seizes
