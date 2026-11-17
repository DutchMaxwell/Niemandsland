extends GdUnitTestSuite
## Phase-1 step 3: parity harness wave 1 — the SAME fixture pushed through the
## live table's statics (SoloController) and through the BattleSim snapshot must
## yield the SAME numbers. Move bands and objective-owner verdicts are compared
## directly. This suite is the honesty gate for the planner substrate: a drift
## between the captured state and the live rules shows up here first.

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


## The sim's move bands are the live table's bands: sim_move_bands feeds every
## ADVANCE/RUSH translate and the captured snapshot stamps it as `bands`. The
## Slow fixture is the discriminator — Advance 4", Rush 8", not the 6"/12"
## defaults — so a lost rule or a hardcoded fallback goes red.
func test_band_distance_parity() -> void:
	var grunts := _armed(2, [Vector3.ZERO], "Grunts", [{"name": "CCW", "range": 0}],
		["Slow"])
	var live := SoloController.move_bands_for_unit(grunts, null)
	var sim := SoloController.sim_move_bands(grunts)
	for band in ["advance", "rush"]:
		assert_float(float(sim[band])).is_equal_approx(float(live[band]), 0.001)
		assert_float(float(sim[band])).is_equal_approx(4.0 if band == "advance" else 8.0, 0.001)
	var stamped: Dictionary = BattleSim.state_to_plain(_capture([grunts]))["units"]["Grunts"]["bands"]
	assert_float(float(stamped["advance"])).is_equal_approx(4.0, 0.001)
	assert_float(float(stamped["rush"])).is_equal_approx(8.0, 0.001)


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
