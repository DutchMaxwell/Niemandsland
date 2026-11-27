extends GdUnitTestSuite
## Feature test FT-10: picking a target, range, line of sight and cover on a hot-seat table, Firefight (gff) and Skirmish
## (aofs). FF36 p.8 l.560-568 (a valid target: one shooter model sees it and is in range), p.5 l.314-345 (distances base
## to base; other units' perimeters block sight), p.12 l.1058-1061 (+1 Defense for a single model MOSTLY inside cover, for
## a unit only when the majority is FULLY inside). AS36 the same.
## Scene (fresh table per case): shooter A, one model, a 6-attack 24 in rifle; targets in the open 20 in off, 25 in off
## (base to base), behind another unit, a single model straddling a wood's rim, a 3-model unit with 1 of 3 in the wood.
## Real: the main scene, the card's Activate, the radial's targeting and the click on the target, the core's volley, the terrain overlay, the log.

const INCH := 0.0254
const BASE_IN := 32.0 / 25.4
const SEED := Vector3(0.03, 0.0, 0.03)   # a point inside SOME overlay cell

var _t: SkirmishTable


func before_test() -> void:
	_t = await SkirmishTable.boot(self, "H")
	_t.main.seed_tray_rng(0)


func after_test() -> void:
	if _t != null:
		_t.teardown()
	_t = null


## One forest cell painted around SEED, its world extent measured with the overlay (as e2e_cover_fully_inside_test).
func _wood() -> Rect2:
	var o: Node3D = _t.main.terrain_overlay
	o.grid_cells[o.world_to_cell(SEED)] = o.TerrainType.FOREST
	var forest: int = int(o.TerrainType.FOREST)
	var lo := SEED
	var hi := SEED
	while o.get_terrain_at_world_position(lo - Vector3(0.001, 0, 0)) == forest:
		lo.x -= 0.001
	while o.get_terrain_at_world_position(hi + Vector3(0.001, 0, 0)) == forest:
		hi.x += 0.001
	var z_lo := SEED.z
	var z_hi := SEED.z
	while o.get_terrain_at_world_position(Vector3(SEED.x, 0, z_lo - 0.001)) == forest:
		z_lo -= 0.001
	while o.get_terrain_at_world_position(Vector3(SEED.x, 0, z_hi + 0.001)) == forest:
		z_hi += 0.001
	return Rect2(lo.x, z_lo, hi.x - lo.x, z_hi - z_lo)


## Shooter of `sys` at `x_in` (z 0) with a 6-attack rifle, started; P2 keeps a spare unit far off.
func _shooter(sys: String, x_in: float) -> GameUnit:
	var a := _t.unit(sys, 1, "Gunners", 1, 1, x_in, 0.0, {"name": "Rifle", "range_in": 24, "attacks": 6, "count": 1, "rules": []})
	_t.unit(sys, 2, "Spare", 1, 1, x_in, 30.0)
	return a


func _volley(a: GameUnit, target: GameUnit) -> void:
	assert_bool(await _t.start(a)).override_failure_message("Start").is_true()
	await _t.aim(a, target)


func _fired() -> bool:
	return _t.lines.any(func(l: String) -> bool: return l.begins_with("Gunners fires Rifle at"))


## The block roll's line ("P2 defends: ... (N+)"), or "".
func _block() -> String:
	for l in _t.lines:
		if (l as String).begins_with("P2 defends:"):
			return l
	return ""


func _case_open_and_range(sys: String) -> void:
	var a := _shooter(sys, -20.0 - BASE_IN)   # T1's base 20 in off A's base
	var t1 := _t.unit(sys, 2, "Open", 1, 3, 0.0, 0.0)
	await _volley(a, t1)
	assert_bool(_fired()).override_failure_message("%s: T1 at 20 in is shot: %s" % [sys, _t.lines]).is_true()
	assert_str(_block()).override_failure_message("%s: no cover in the open: %s" % [sys, _t.lines]).ends_with("(4+)")


func _case_out_of_range(sys: String) -> void:
	var a := _shooter(sys, -25.0 - BASE_IN)   # 25 in base to base
	var t2 := _t.unit(sys, 2, "Far", 1, 3, 0.0, 0.0)
	await _volley(a, t2)
	assert_bool(_fired()).override_failure_message("%s: T2 at 25 in is not shot: %s" % [sys, _t.lines]).is_false()
	assert_bool(_t.lines.any(func(l: String) -> bool: return l.findn("range") != -1)) \
		.override_failure_message("%s: one line names the range: %s" % [sys, _t.lines]).is_true()


func _case_blocked(sys: String) -> void:
	var a := _shooter(sys, -12.0)
	_t.unit(sys, 2, "Screen", 1, 1, -6.0, 0.0)   # another unit's perimeter on the lane
	var t3 := _t.unit(sys, 2, "Hidden", 1, 3, 0.0, 0.0)
	await _volley(a, t3)
	assert_bool(_fired()).override_failure_message("%s: T3 behind a unit is not shot: %s" % [sys, _t.lines]).is_false()
	assert_bool(_t.lines.any(func(l: String) -> bool: return l.find("line of sight") != -1)) \
		.override_failure_message("%s: the LOS line: %s" % [sys, _t.lines]).is_true()


func _case_single_on_the_rim(sys: String) -> void:
	var w := _wood()
	var t4 := _t.unit(sys, 2, "Rim", 1, 3, 0.0, 0.0)
	(t4.models[0] as ModelInstance).node.global_position = Vector3(w.end.x - 0.004, 0, w.get_center().y)   # centre in, base across
	var a := _shooter(sys, (w.end.x - 0.004) / INCH - 20.0)
	await _volley(a, t4)
	assert_str(_block()).override_failure_message("%s: a single model mostly inside: +1: %s" % [sys, _t.lines]).ends_with("(3+)")


func _case_one_of_three(sys: String) -> void:
	var w := _wood()
	var t5 := _t.unit(sys, 2, "Squad", 3, 1, 0.0, 0.0)
	var mid := w.get_center()
	for i in 3:   # model 1 at the cell centre, models 2 and 3 beside it outside the cell, across the lane
		(t5.models[i] as ModelInstance).node.global_position = Vector3(mid.x, 0, mid.y + i * (w.size.y * 0.5 + BASE_IN * INCH))
	var a := _shooter(sys, mid.x / INCH - 20.0)
	await _volley(a, t5)
	assert_str(_block()).override_failure_message("%s: 1 of 3 inside: no cover: %s" % [sys, _t.lines]).ends_with("(4+)")


func test_gff_target_in_the_open(timeout := 120000) -> void:
	await _case_open_and_range("gff")


func test_aofs_target_in_the_open(timeout := 120000) -> void:
	await _case_open_and_range("aofs")


func test_gff_out_of_range(timeout := 120000) -> void:
	await _case_out_of_range("gff")


func test_aofs_out_of_range(timeout := 120000) -> void:
	await _case_out_of_range("aofs")


func test_gff_blocked_sight(timeout := 120000) -> void:
	await _case_blocked("gff")


func test_aofs_blocked_sight(timeout := 120000) -> void:
	await _case_blocked("aofs")


func test_gff_single_model_mostly_in_cover(timeout := 120000) -> void:
	await _case_single_on_the_rim("gff")


func test_aofs_single_model_mostly_in_cover(timeout := 120000) -> void:
	await _case_single_on_the_rim("aofs")


func test_gff_one_of_three_in_cover(timeout := 120000) -> void:
	await _case_one_of_three("gff")


func test_aofs_one_of_three_in_cover(timeout := 120000) -> void:
	await _case_one_of_three("aofs")

