extends GdUnitTestSuite
## Feature test FT-11: wounds, morale after shooting and Shaken on a hot-seat Firefight (gff) table. FF36 p.10 l.750-752 and
## the example l.765-767 (2 wounds on a single Tough(3) model = half or less = a Morale Test), l.787-790 (a failed test =
## Shaken), l.848-854 (Shaken: idle only, cannot seize, not Shaken after that idle activation), p.9 l.713-724 (wounds go
## on the most wounded model until it dies).
## Scene: A (one model, Quality 2, 4 attacks) 12 in from T (Quality 5, Tough(3)) standing on a marker. Dice by tray seed
## (R-FT3, scanned 0..63): seed 4 = hits 4 4 3 1, blocks 5 2 2 -> 2 wounds, morale face 1 (fail); seed 6 = hits 6 5 3 3,
## blocks 5 4 3 3 -> 2 wounds, morale face 6 (pass).
## Real: the main scene, the card's Activate / End, the radial targeting and click, the core's volley and morale, the
## hot-seat round end and its seize.

const INCH := 0.0254
const FAIL_SEED := 4
const PASS_SEED := 6

var _t: SkirmishTable
var _x: GameUnit
var _a: GameUnit
var _target: GameUnit
var _spare: GameUnit


func before_test() -> void:
	_t = await SkirmishTable.boot(self, "H")


func after_test() -> void:
	if _t != null:
		_t.teardown()
	_t = null


func _scene(models: int) -> void:
	_x = _t.unit("gff", 1, "Opener", 1, 1, -12.0, 20.0)
	_a = _t.unit("gff", 1, "Gunners", 1, 1, -12.0, 0.0, {"name": "Rifle", "range_in": 24, "attacks": 4, "count": 1, "rules": []})
	_a.unit_properties["quality"] = 2
	_target = _t.unit("gff", 2, "Target", models, 3, 0.0, 0.0)
	_target.unit_properties["quality"] = 5
	_spare = _t.unit("gff", 2, "Spare", 1, 1, 0.0, 30.0)
	_t.main.terrain_overlay.update_objectives([Vector3.ZERO], [0])


func _idle(u: GameUnit) -> void:
	if await _t.start(u):
		await _t.end(u)
	await _t.runner.simulate_frames(4)


func _shot(seed_value: int) -> void:
	assert_bool(await _t.start(_a)).override_failure_message("A starts").is_true()
	_t.main.seed_tray_rng(seed_value)
	await _t.aim(_a, _target)


## P1 opens with X, P2's T stands idle on the marker, A shoots T (seed), P2's Spare closes round 1.
func _round_one(seed_value: int) -> void:
	await _idle(_x)
	await _idle(_target)
	await _shot(seed_value)
	await _idle(_spare)


func test_two_wounds_on_tough_3_fail_morale_and_shake(timeout := 180000) -> void:
	_scene(1)
	await _round_one(FAIL_SEED)
	assert_int(_t.count("Target takes 2 wounds (1/3 wounds)")).override_failure_message("2 wounds: %s" % [_t.lines]).is_equal(1)
	assert_int(_t.count("Target is at half its tough value (1/3) — morale test")) \
		.override_failure_message("the morale test: %s" % [_t.lines]).is_equal(1)
	assert_int(_t.count("Target fails morale — Shaken")).override_failure_message("Shaken: %s" % [_t.lines]).is_equal(1)
	assert_int(_t.main.opr_army_manager.current_round).override_failure_message("round 2: %s" % [_t.lines]).is_equal(2)
	assert_int(_t.main.terrain_overlay.get_objective_owner(0)) \
		.override_failure_message("a Shaken unit cannot seize: %s" % [_t.lines]).is_equal(0)
	# Round 2: P1 opens (it finished first), then T's idle activation (Activate, End) ends its Shaken.
	assert_bool(_target.is_shaken).is_true()
	await _idle(_x)
	await _idle(_target)
	assert_bool(_target.is_activated).override_failure_message("T spent its idle activation: %s" % [_t.lines]).is_true()
	assert_bool(_target.is_shaken).override_failure_message("not Shaken after the idle activation: %s" % [_t.lines]).is_false()


## FINDING #3849 (R-FT2): the table lets a Shaken unit move in its activation (the drag stands, it stays Shaken).
@warning_ignore("unused_parameter")
func test_a_shaken_unit_may_not_move(timeout := 180000, do_skip := true,
		skip_reason := "FINDING #3849: a Shaken unit's drag stands and it stays Shaken") -> void:
	_scene(1)
	await _round_one(FAIL_SEED)
	assert_bool(_target.is_shaken).override_failure_message("Shaken: %s" % [_t.lines]).is_true()
	await _idle(_x)
	assert_bool(await _t.start(_target)).override_failure_message("T starts: %s" % [_t.lines]).is_true()
	var at: Vector3 = (_target.models[0] as ModelInstance).node.global_position
	await _t.walk(_target, -3.0, 0.0, CoreActivation.CAP_ADVANCE)
	assert_float(((_target.models[0] as ModelInstance).node.global_position - at).length() / INCH) \
		.override_failure_message("a Shaken unit stays idle - the move snaps back: %s" % [_t.lines]).is_equal_approx(0.0, 0.05)
	await _t.end(_target)
	assert_bool(_target.is_shaken).override_failure_message("not Shaken after the idle activation: %s" % [_t.lines]).is_false()


func test_a_passed_morale_test_keeps_the_marker(timeout := 180000) -> void:
	_scene(1)
	await _round_one(PASS_SEED)
	assert_int(_t.count("Target passes morale")).override_failure_message("passed: %s" % [_t.lines]).is_equal(1)
	assert_int(_t.main.terrain_overlay.get_objective_owner(0)) \
		.override_failure_message("a steady T seizes its marker: %s" % [_t.lines]).is_equal(2)


func test_two_wounds_go_on_one_model(timeout := 180000) -> void:
	_scene(2)
	await _idle(_x)
	await _idle(_target)
	await _shot(FAIL_SEED)
	var w: Array = _target.models.map(func(m: ModelInstance) -> int: return m.wounds_max - m.wounds_current)
	w.sort()
	assert_array(w).override_failure_message("both wounds on one model: %s" % [_t.lines]).is_equal([0, 2])
	assert_int(_t.lines.filter(func(l: String) -> bool: return l.find("morale test") != -1).size()) \
		.override_failure_message("no model lost: no test: %s" % [_t.lines]).is_equal(0)
