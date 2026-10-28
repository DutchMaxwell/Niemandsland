extends GdUnitTestSuite
## E2E - Automodus rework step 2.3a: the drag lines ask the volley's own sight truth only "does ANY model
## see?", many enemy units per drag tick. Two cheap modes, the same verdict: `first_hit` stops at the first
## model with range + line of sight, and the sight blockers are built ONCE (_solo_los_blockers(shooter, null))
## and shared by every enemy check. The volley and the 1.5 preview keep the full count.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## A registered unit whose models carry one ranged OPR weapon (the volley reads source_data).
func _unit(pid: int, unit_name: String, positions: Array, range_in := 12, rules: Array = []) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, positions)
	var opr := OPRApiClient.OPRUnit.new()
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Test Rifle"
	w.range_value = range_in
	var sr: Array[String] = []
	for r in rules:
		sr.append(str(r))
	w.special_rules = sr
	var weapons: Array[OPRApiClient.OPRWeapon] = [w]
	opr.weapons = weapons
	u.source_type = "opr"
	u.source_data = opr
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func _at(x_in: float, z_in: float) -> Vector3:
	return Vector3(x_in * INCH, 0.0, z_in * INCH)


## [full volley count, first-hit count over blockers built once without a target].
func _counts(shooter: GameUnit, target: GameUnit) -> Array:
	var shared: Array = _main._solo_los_blockers(shooter, null)
	return [_main._solo_volley_sighted(shooter, target), _main._solo_volley_sighted(shooter, target, null, true, shared)]


## One lane per case (20" apart): in range and clear, out of range, blocked by another unit's model, and an
## Indirect gun behind that kind of wall. The first-hit verdict equals "full count > 0" in every case, and it
## stops at ONE model where the full count finds three.
func test_first_hit_matches_the_full_count() -> void:
	var clear := _unit(1, "Clear", [_at(0, -1.5), _at(0, 0), _at(0, 1.5)])
	var near := _unit(2, "Near", [_at(8, 0), _at(10, 0)])   # two models in a row: its own models never block
	var far_s := _unit(1, "FarShooter", [_at(0, 20)])
	var far_t := _unit(2, "FarTarget", [_at(-20, 20)])
	var hid_s := _unit(1, "HidShooter", [_at(0, 40)], 24)
	_unit(1, "OwnWall", [_at(6, 40)])
	var hid_t := _unit(2, "HidTarget", [_at(12, 40)])
	var ind_s := _unit(1, "Mortar", [_at(0, 60)], 24, ["Indirect"])
	_unit(1, "OwnWall2", [_at(6, 60)])
	var ind_t := _unit(2, "IndTarget", [_at(12, 60)])
	var cases := {"in range": [clear, near, 3], "out of range": [far_s, far_t, 0],
		"blocked": [hid_s, hid_t, 0], "indirect": [ind_s, ind_t, 1]}
	for name in cases:
		var c: Array = cases[name]
		var got := _counts(c[0], c[1])
		assert_int(int(got[0])).override_failure_message("%s: full count %d, the case expects %d" % [
			name, got[0], c[2]]).is_equal(int(c[2]))
		assert_int(int(got[1])).override_failure_message("%s: first-hit %d, full count %d" % [
			name, got[1], got[0]]).is_equal(1 if int(got[0]) > 0 else 0)


## Bench (no threshold; the numbers go in the PR body): every enemy unit checked from a 10-model unit with a
## 24" gun, full count with per-enemy blockers vs first hit over shared blockers, at 80 and then 150 bases.
## The verdicts must agree on the crowded table too.
func test_bench_drag_sight_at_80_and_150_bases() -> void:
	var mover := _block(Vector3(-0.09, 0.0, -0.40), "BenchMover", 1)
	var own := 0
	var foes: Array = []
	for step in [[3, 4], [7, 7]]:
		for k in range(own, int(step[0])):
			_block(Vector3(-0.85 + k * 0.25, 0.0, -0.12 + (k % 2) * 0.1), "BenchOwn%d" % k, 1)
		own = int(step[0])
		for e in range(foes.size(), int(step[1])):
			foes.append(_block(Vector3(-0.85 + (e % 7) * 0.25, 0.0, 0.10 + (e / 7) * 0.25 + (e % 2) * 0.08), "BenchFoe%d" % e, 2))
		var full_ms := 0.0
		var fast_ms := 0.0
		var reps := 10
		var seen := 0
		for r in reps:
			var t0 := Time.get_ticks_usec()
			var full: Array = foes.map(func(f: GameUnit) -> bool: return _main._solo_volley_sighted(mover, f) > 0)
			full_ms += (Time.get_ticks_usec() - t0) / 1000.0
			t0 = Time.get_ticks_usec()
			var shared: Array = _main._solo_los_blockers(mover, null)
			var fast: Array = foes.map(func(f: GameUnit) -> bool: return _main._solo_volley_sighted(mover, f, null, true, shared) > 0)
			fast_ms += (Time.get_ticks_usec() - t0) / 1000.0
			assert_array(fast).is_equal(full)
			seen = full.count(true)
		print("DRAG_SIGHT_BENCH bases=%d enemies=%d seen=%d full_ms=%.3f fast_ms=%.3f" % [
			_main.opr_army_manager.get_all_game_units().size() * 10, foes.size(), seen, full_ms / reps, fast_ms / reps])


## A 10-model block (2 rows of 5) with 24" guns.
func _block(origin: Vector3, unit_name: String, pid: int) -> GameUnit:
	var spots: Array = []
	for i in 10:
		spots.append(origin + Vector3((i % 5) * 0.036, 0.0, (i / 5) * 0.036))
	return _unit(pid, unit_name, spots, 24)
