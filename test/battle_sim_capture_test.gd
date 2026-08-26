extends GdUnitTestSuite
## BattleSim.capture — phase-1 planner substrate, step 1. The snapshot must
## (a) map the dynamic game state faithfully (alive models only, wounds, flags,
## objective owners) and (b) be a COPY: editing it never touches the scene, and
## later scene changes never leak into an already-taken snapshot.

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


func test_capture_maps_units_flags_and_objectives() -> void:
	var grunts := _unit(2, [Vector3.ZERO, Vector3(1.0 * IN2M, 0, 0), Vector3(2.0 * IN2M, 0, 0)], "Grunts")
	grunts.models[1].is_alive = false          # dead models never enter the snapshot
	grunts.models[2].wounds_current = 3
	grunts.is_shaken = true
	grunts.is_activated = true
	var tank := _unit(1, [Vector3(10.0 * IN2M, 0, 0)], "Tank")
	tank.casts_current = 2
	var objs := [Vector3(5.0 * IN2M, 0, 0), Vector3(15.0 * IN2M, 0, 0)]
	var owners := [0, 1]
	var state := BattleSim.capture(_army([grunts, tank]),
		func() -> Array: return objs, func(i: int) -> int: return owners[i], 2, 4)
	assert_int(state["round"]).is_equal(2)
	var g: Dictionary = state["units"]["Grunts"]
	assert_int(g["alive"]).is_equal(2)
	assert_that(g["positions"][1]).is_equal(Vector3(2.0 * IN2M, 0, 0))
	assert_int(g["wounds"][1]).is_equal(3)
	assert_bool(g["shaken"]).is_true()
	assert_bool(g["activated"]).is_true()
	assert_object(g["unit"]).is_same(grunts)
	var t: Dictionary = state["units"]["Tank"]
	assert_int(t["player"]).is_equal(1)
	assert_int(t["casts"]).is_equal(2)
	assert_that((state["objectives"][1] as Dictionary)["owner"]).is_equal(1)


## Gap 18a: capture stamps the Banner morale bonus once, so the rollout's morale never
## has to ask the rules registry again. Plain units stamp 0.
func test_capture_stamps_the_morale_bonus() -> void:
	var plain := _unit(1, [Vector3.ZERO], "Plain")
	var bearer := _unit(2, [Vector3(10.0 * IN2M, 0, 0)], "Bearer")
	bearer.unit_properties["special_rules"] = ["Banner"]
	var state := BattleSim.capture(_army([plain, bearer]))
	var b: Dictionary = state["units"]["Bearer"]
	assert_bool(b.has("morale_bonus")).is_true()
	assert_int(int(b.get("morale_bonus", 0))).is_equal(1)
	assert_int(int((state["units"]["Plain"] as Dictionary).get("morale_bonus", -1))).is_equal(0)


## T1: cover_of stamps per-unit in_cover at capture time; no callable keeps
## the pre-T1 default (false) byte-identically.
func test_capture_stamps_in_cover_via_cover_of() -> void:
	var grunts := _unit(1, [Vector3.ZERO], "Grunts")
	var tank := _unit(2, [Vector3(10.0 * IN2M, 0, 0)], "Tank")
	var army := _army([grunts, tank])
	var state := BattleSim.capture(army, Callable(), Callable(), 1, 4,
		func(u: GameUnit) -> bool: return u.unit_id == "Grunts")
	assert_bool((state["units"]["Grunts"] as Dictionary)["in_cover"]).is_true()
	assert_bool((state["units"]["Tank"] as Dictionary)["in_cover"]).is_false()
	assert_bool((BattleSim.capture(army)["units"]["Grunts"] as Dictionary)["in_cover"]).is_false()


## T2: los_of stamps a capture-time enemy-pair matrix; allies never appear in
## it; no callable leaves the key out entirely (= all-true, pre-T2 behaviour).
func test_capture_stamps_enemy_los_matrix() -> void:
	var a := _unit(1, [Vector3.ZERO], "A")
	var b := _unit(2, [Vector3(10.0 * IN2M, 0, 0)], "B")
	var c := _unit(2, [Vector3(20.0 * IN2M, 0, 0)], "C")
	var army := _army([a, b, c])
	var state := BattleSim.capture(army, Callable(), Callable(), 1, 4, Callable(),
		func(_u: GameUnit, t: GameUnit) -> bool: return t.unit_id != "C")
	assert_that((state["units"]["A"] as Dictionary)["los"]).is_equal({"B": true, "C": false})
	assert_that((state["units"]["B"] as Dictionary)["los"]).is_equal({"A": true})
	assert_bool(BattleSim.sees(state["units"]["A"], "B")).is_true()
	assert_bool(BattleSim.sees(state["units"]["A"], "C")).is_false()
	assert_bool((BattleSim.capture(army)["units"]["A"] as Dictionary).has("los")).is_false()


func test_snapshot_is_a_copy_in_both_directions() -> void:
	var grunts := _unit(2, [Vector3.ZERO, Vector3(1.0 * IN2M, 0, 0)], "Grunts")
	var army := _army([grunts])
	var state := BattleSim.capture(army)
	var g: Dictionary = state["units"]["Grunts"]
	g["positions"][0] = Vector3(99, 0, 0)      # rollout edits...
	g["wounds"][0] = 7
	assert_that(grunts.models[0].node.global_position).is_equal(Vector3.ZERO)
	assert_int(grunts.models[0].wounds_current).is_equal(1)
	grunts.models[1].is_alive = false          # ...and later scene changes
	assert_int(int((BattleSim.capture(army)["units"]["Grunts"] as Dictionary)["alive"])).is_equal(1)
	assert_int(g["alive"]).is_equal(2)


## NML-1006 sidecar: board_row_indices mirrors board_rows' living-filter and
## order — a dead unit keeps its roster SLOT (index gap) but vanishes from
## the list, so per-board ids always map into the game-long roster.
func test_board_row_indices_skip_dead_but_keep_slots() -> void:
	var a := _unit(1, [Vector3.ZERO], "A")
	var b := _unit(1, [Vector3(1.0 * IN2M, 0, 0)], "B")
	var c := _unit(2, [Vector3(2.0 * IN2M, 0, 0)], "C")
	var state := BattleSim.capture(_army([a, b, c]),
		func() -> Array: return [], func(_i: int) -> int: return 0, 1, 4)
	assert_array(BattleSim.board_row_indices(state)).is_equal([0, 1, 2])
	(state["units"]["B"] as Dictionary)["alive"] = 0
	assert_array(BattleSim.board_row_indices(state)).is_equal([0, 2])
	# board_rows = unit rows (mirrored by the index sidecar) + non-unit rows
	# (objective rows and, since input v1, the ONE game-state row).
	assert_int(BattleSim.board_rows(state).size()) \
		.is_equal(BattleSim.board_row_indices(state).size() + 1)


## NML-1012 input v1 — the GAME-STATE row: the net played blind to round,
## score and scoring mode (unit stats were already in the rows; this was the
## real remaining blindfold). One type-4 row carries [4, round, rounds_total,
## vp1, vp2, scoring_code, majority_code, first_seize] and rides the existing
## row trunk — no trainer change, every consumer sees it via board_rows.
func test_board_rows_carry_the_game_state_row() -> void:
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	SoloController.mission_reset("round_vp", {"majority": "round"})
	SoloController.mission_vp = [3, 1]
	var state := BattleSim.capture(army, func() -> Array: return [Vector3.ZERO],
		func(_i: int) -> int: return 0, 2, 4)
	var rows := BattleSim.board_rows(state)
	var gs: Array = []
	for r in rows:
		if int((r as Array)[0]) == 4:
			gs = r
	assert_bool(gs.is_empty()).is_false()
	assert_int(int(gs[1])).is_equal(2)    # round
	assert_int(int(gs[2])).is_equal(4)    # rounds_total
	assert_int(int(gs[3])).is_equal(3)    # vp1
	assert_int(int(gs[4])).is_equal(1)    # vp2
	assert_int(int(gs[5])).is_equal(1)    # scoring_code: round_vp
	assert_int(int(gs[6])).is_equal(2)    # majority_code: round
	SoloController.mission_reset("end", {})
	var plain := BattleSim.board_rows(BattleSim.capture(army,
		func() -> Array: return [Vector3.ZERO], func(_i: int) -> int: return 0, 1, 4))
	var gs2: Array = []
	for r in plain:
		if int((r as Array)[0]) == 4:
			gs2 = r
	assert_bool(gs2.is_empty()).is_false()
	assert_int(int(gs2[5])).is_equal(0)   # scoring_code: end


func test_capture_marks_reserve_units_dormant() -> void:
	# Arrivals wave S1: a unit still on the tray (ambush_reserve) must enter the
	# snapshot DORMANT — zero table presence (alive=0, no positions, so every
	# existing dead-unit guard excludes it from eligibility/targeting/scoring)
	# while its strength survives in dormant_* for the later arrival step.
	var amb := _unit(2, [Vector3(30.0 * IN2M, 0, 0)], "Ambushers")
	amb.unit_properties["ambush_reserve"] = true   # tray node position must NOT leak
	var tank := _unit(1, [Vector3.ZERO], "Tank")
	var state := BattleSim.capture(_army([amb, tank]),
		func() -> Array: return [], func(_i: int) -> int: return 0, 1, 4)
	var a: Dictionary = state["units"]["Ambushers"]
	assert_bool(a.get("dormant", false)).is_true()
	assert_int(a["alive"]).is_equal(0)
	assert_array(a["positions"]).is_empty()
	assert_int(a["dormant_models"]).is_equal(1)
	assert_int(a["earliest_arrival_round"]).is_equal(2)
	var t: Dictionary = state["units"]["Tank"]
	assert_bool(t.get("dormant", false)).is_false()
	assert_int(t["alive"]).is_equal(1)


func _opr_source(selection_id: String, join_to_unit: String) -> OPRApiClient.OPRUnit:
	var opr := OPRApiClient.OPRUnit.new()
	opr.selection_id = selection_id
	opr.join_to_unit = join_to_unit
	return opr


## NML-1081: an imported/AI army never calls EquipmentDistributor.attach_hero_to_unit
## (MP-only), so runtime attached/attached_to are always empty — capture must fall back
## to the list's join_to_unit/selectionId. Hero captured BEFORE its host on purpose.
func test_capture_links_a_joined_hero_by_join_to_unit_when_runtime_attachment_is_empty() -> void:
	var hero := _unit(1, [Vector3(1.0 * IN2M, 0, 0)], "Hero")
	hero.source_type = "opr"
	hero.source_data = _opr_source("HeroSel", "H1")
	var host := _unit(1, [Vector3.ZERO], "Host")
	host.source_type = "opr"
	host.source_data = _opr_source("H1", "")
	var control := _unit(1, [Vector3(2.0 * IN2M, 0, 0)], "Control")
	control.source_type = "opr"
	control.source_data = _opr_source("C1", "")
	var state := BattleSim.capture(_army([hero, host, control]))
	var h: Dictionary = state["units"]["Hero"]
	assert_str(str(h["attached_to"])).is_equal("Host")
	var o: Dictionary = state["units"]["Host"]
	assert_array(o["attached"]).is_equal(["Hero"])
	var c: Dictionary = state["units"]["Control"]
	assert_str(str(c["attached_to"])).is_equal("")
	assert_array(c["attached"]).is_equal([])
