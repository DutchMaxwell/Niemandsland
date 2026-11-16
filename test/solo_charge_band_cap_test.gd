extends GdUnitTestSuite
## #183 (EPOCH_77_CHARGE_CAP): no charging model walks past its band (arc cap), and each model pays its own snap
## (GF 3.6 p.9 "Charging MODELS must move by up to 12\""). Formations: 35x60 mm ovals, nearest edge 1.5" from a
## 40 mm target with two more enemy bases 2.2" to its sides, so the trailing routes wrap far around.

const IN2M := 0.0254
const EPS := 0.05


func before_test() -> void:
	MovementPlanner.fast_planner = false
	MovementPlanner.fast_planner_guard = MovementPlanner.FAST_PLANNER_GUARD


func after_test() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_77_CHARGE_CAP


func _unit(pid: int, unit_name: String, positions: Array, oval: bool, rules: Array = []) -> GameUnit:
	var unit := GameUnit.new()
	unit.unit_id = unit_name.to_lower().replace(" ", "_")
	unit.unit_properties = {"player_id": pid, "name": unit_name, "quality": 4, "defense": 4, "special_rules": rules,
		"base_is_oval": oval, "base_width_mm": 35 if oval else 40, "base_depth_mm": 60 if oval else 40, "base_size_round": 40}
	for position in positions:
		var model := ModelInstance.new()
		model.is_alive = true
		model.unit = unit
		var node := Node3D.new()
		add_child(node)
		node.global_position = position
		model.node = node
		unit.models.append(model)
	if pid == 2:
		var source := OPRApiClient.OPRUnit.new()
		var weapon := OPRApiClient.OPRWeapon.new()
		weapon.name = "Razor Claws"
		weapon.attacks = 2
		weapon.count = 10
		source.weapons.append(weapon)
		unit.source_type = "opr"
		unit.source_data = source
	return unit


## cols x rows ovals (dx/dz inches), shifted along -x until the nearest edge gap to the target is 1.5"
## (`sides`: two more enemy bases 2.2" beside the target).
## Returns [solo, chargers, target].
func _scene(epoch: int, cols: int, rows: int, dx: float, dz: float, along_x: bool, rules: Array = ["Strider"],
		sides := true) -> Array:
	AiActRecorder.rules_epoch = epoch
	var pos: Array = []
	for r in rows:
		for c in cols:
			var a := (float(c) - (cols - 1) / 2.0) * dx
			var b := (float(r) - (rows - 1) / 2.0) * dz
			pos.append(Vector3(a, 0, b) * IN2M if along_x else Vector3(b, 0, a) * IN2M)
	var hounds := _unit(2, "Hounds", pos, true, rules)
	var target := _unit(1, "Destroyer", [Vector3.ZERO], false)
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	var units := [hounds, target]
	if sides:
		units.append_array([_unit(1, "Destroyer B", [Vector3(0, 0, 2.2 * IN2M)], false),
			_unit(1, "Destroyer C", [Vector3(0, 0, -2.2 * IN2M)], false)])
	for u in units:
		army.game_units[(u as GameUnit).unit_id] = u
	army.current_round = 2
	var solo: SoloController = auto_free(SoloController.new())
	add_child(solo)
	solo.setup(army, null, null, 1, 2)
	for _it in 3:
		var gap := solo.nearest_melee_gap_in(hounds, target)
		for m in hounds.models:
			(m as ModelInstance).node.global_position.x -= (gap - 1.5) * IN2M
	return [solo, hounds, target]


## Longest published trail plus whatever the snap added after it (path end -> model now), inches.
func _longest_walk_in(solo: SoloController) -> float:
	var longest := 0.0
	for e in solo.last_move_paths:
		var path: Array = (e as Dictionary)["path"]
		var now := ((e as Dictionary)["model"] as ModelInstance).node.global_position
		var tail := 0.0 if path.is_empty() else Vector2((path.back() as Vector3).x - now.x, (path.back() as Vector3).z - now.z).length()
		longest = maxf(longest, (MovementPlanner.polyline_length(path) + tail) / IN2M)
	return longest


func test_the_arc_cap_keeps_every_charging_trail_inside_the_band() -> void:
	# 76 (the mutant: cap off) walks a trailing model 13.7"; 77 caps every trail, probe and execution alike.
	var old: Array = _scene(76, 10, 1, 1.6, 2.6, true, ["Strider"], false)
	assert_float(float((old[0] as SoloController).charge_path_probe(old[1], old[2], 12.0)["arc_in"])).is_greater(12.0 + EPS)
	var sc: Array = _scene(77, 10, 1, 1.6, 2.6, true, ["Strider"], false)
	var solo: SoloController = sc[0]
	assert_float(float(solo.charge_path_probe(sc[1], sc[2], 12.0)["arc_in"])).is_less_equal(12.0 + EPS)
	solo._charge_move(sc[1], sc[2], 12.0)
	assert_float(_longest_walk_in(solo)).is_less_equal(12.0 + EPS)
	assert_str("\n".join(solo.board_clamp_notes)).contains("charge band")


func test_the_arc_cap_holds_the_6_inch_difficult_band() -> void:
	# Every cell difficult (forest), no Strider: the p.11 cap makes the band 6".
	var forest := func(_p: Vector3) -> int: return TerrainRules.TerrainType.FOREST
	var old: Array = _scene(76, 10, 1, 1.6, 2.6, true, [], false)
	(old[0] as SoloController).terrain_type_at = forest
	assert_float(float((old[0] as SoloController).charge_path_probe(old[1], old[2], 12.0)["arc_in"])).is_greater(6.0 + EPS)
	var sc: Array = _scene(77, 10, 1, 1.6, 2.6, true, [], false)
	var solo: SoloController = sc[0]
	solo.terrain_type_at = forest
	var probe: Dictionary = solo.charge_path_probe(sc[1], sc[2], 12.0)
	assert_float(float(probe["effective_band_in"])).is_equal(6.0)
	assert_float(float(probe["arc_in"])).is_less_equal(6.0 + EPS)
	solo._charge_move(sc[1], sc[2], 12.0)
	assert_float(_longest_walk_in(solo)).is_less_equal(6.0 + EPS)


func test_a_hounds_line_with_a_far_trailing_route_charges_on_its_own_budget() -> void:
	# 3x4 coherent line, nearest edge 1.5": a trailing route spends ~11.7" of the 12" band, the closing model ~1.5".
	var old: Array = _scene(76, 3, 4, 3.0, 2.0, false)
	var old_probe: Dictionary = (old[0] as SoloController).charge_path_probe(old[1], old[2], 12.0)
	assert_bool(bool(old_probe["reachable"])).is_false()
	assert_str(str(old_probe["failed_clauses"])).is_equal("residual_over_remaining")
	var sc: Array = _scene(77, 3, 4, 3.0, 2.0, false)
	var solo: SoloController = sc[0]
	assert_bool(bool(solo.charge_path_probe(sc[1], sc[2], 12.0)["reachable"])).is_true()
	var report := solo._act(sc[1])
	assert_int(int(report.get("action", -1))).is_equal(AiDecision.Action.CHARGE)
	assert_float(solo.snap_charge_per_model(sc[1], sc[2])).is_greater(0.0)
	assert_float(solo.nearest_melee_gap_in(sc[1], sc[2])).is_less_equal(EPS)
	assert_int(solo.last_snap_stayed).is_greater(0)
	assert_float(_longest_walk_in(solo)).is_less_equal(12.0 + EPS)


func test_the_snap_pick_is_the_closing_models_own_budget() -> void:
	# Model 1 is nearer but its own trail spent the band; model 0 can afford its 0.8".
	assert_int(SoloController.charge_snap_pick([0.8, 0.3], [1.5, 11.9], 12.0)).is_equal(0)
	assert_int(SoloController.charge_snap_pick([1.2, 0.3], [1.5, 11.9], 12.0)).is_equal(-1)   # 1.2" > the 1" ring
	assert_int(SoloController.charge_snap_pick([0.0, 0.0], [12.2, 1.0], 12.0)).is_equal(1)   # an over-band trail never closes
	# Twin parity with the core's `snap_pick` (step.rs `snap_pick_grid_checksum_matches_the_table`).
	assert_int(_pick_grid_checksum()).is_equal(PICK_GRID_CHECKSUM)


const PICK_GRID_CHECKSUM := 11715374026


## Deterministic grid over (residual a, residual b, arc a, arc b, band): sum of (pick + 2) * running index.
static func _pick_grid_checksum() -> int:
	var sum := 0
	var k := 0
	for band in [3.0, 6.0, 12.0]:
		for ra in range(0, 13):
			for rb in range(0, 13):
				for aa in range(0, 14):
					for ab in range(0, 14):
						k += 1
						var pick := SoloController.charge_snap_pick([ra * 0.1, rb * 0.1], [aa * band / 12.0, ab * band / 12.0], band)
						sum += (pick + 2) * k
	return sum
