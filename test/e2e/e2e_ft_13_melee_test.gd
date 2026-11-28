extends GdUnitTestSuite
## Feature test FT-13: charge, melee, strike back, the loser's morale test, rout and consolidation on a hot-seat table.
## FF36 p.7 l.493-500 (Charge up to 12 in into base contact), p.9 l.709-735 (strike, strike back), p.10 l.754-758 (only
## the loser tests), l.836-842 (a failed test at half or less = Rout = destroyed), l.816-825 (consolidation: the survivor
## of a destroyed enemy may move up to 3 in, else the charger moves back 1 in). AS36 p.13 l.1172-1183 (Brace(X): a charger
## against it makes X fewer Impact rolls).
## Scene: charger C (one Tough(3) model, 3 melee attacks) 10 in (base to base) from D (one Tough(3) model, 1 attack).
## Tray seeds (R-FT3, scanned 0..39 in this scene): 12 = C hits 6 6 3, D blocks 3 3 (2 wounds), D hits 5, C blocks 3
## (1 wound), D's morale 3 fails; 31 = C 3 hits, D blocks 4 2 1 (2 wounds), D 1 hit blocked, D's morale 4 passes.
## Real: the main scene, the card's Activate, the real drag under the Charge selector, the radial's melee targeting and the
## click, the core's melee, morale and the table's consolidation line.
## Not built here: the strike height across ruin levels (plan case c) - ruin floors reach the core only from epoch 107.

const INCH := 0.0254
const BASE_IN := 32.0 / 25.4

var _t: SkirmishTable


func before_test() -> void:
	_t = await SkirmishTable.boot(self, "H")


func after_test() -> void:
	if _t != null:
		_t.teardown()
	_t = null


func _charge(sys: String, gap_in: float, seed_value: int, c_rules: Array = [], d_rules: Array = []) -> Array:
	var c := _t.unit(sys, 1, "Charger", 1, 3, -gap_in - BASE_IN, 0.0, {"name": "Blade", "range_in": 0, "attacks": 3, "count": 1, "rules": []}, c_rules)
	var d := _t.unit(sys, 2, "Defender", 1, 3, 0.0, 0.0, {"name": "Knife", "range_in": 0, "attacks": 1, "count": 1, "rules": []}, d_rules)
	_t.unit(sys, 2, "Spare", 1, 1, 0.0, 30.0)
	_t.main.seed_tray_rng(seed_value)
	assert_bool(await _t.start(c)).override_failure_message("C starts").is_true()
	await _t.walk(c, gap_in, 0.0, CoreActivation.CAP_CHARGE)
	await _t.aim(c, d, true)
	return [c, d]


func _has(line: String) -> bool:
	return _t.count(line) == 1


func test_gff_the_loser_fails_and_routs(timeout := 120000) -> void:
	var cd := await _charge("gff", 10.0, 12)
	for line in ["Charger charges Defender into melee", "Defender takes 2 wounds (1/3 wounds)",
			"Defender strikes with Knife at Charger — 1 hit", "Charger takes 1 wound (2/3 wounds)",
			"Melee result: Charger took 1, Defender took 2 — Defender loses the melee",
			"Defender fails morale at half strength — ROUTS", "Consolidation: Charger may move up to 3\""]:
		assert_bool(_has(line)).override_failure_message("the line '%s': %s" % [line, _t.lines]).is_true()
	assert_int((cd[1] as GameUnit).get_alive_count()).override_failure_message("D routed = removed").is_equal(0)


func test_gff_the_loser_passes_and_the_charger_pulls_back(timeout := 120000) -> void:
	var cd := await _charge("gff", 10.0, 31)
	for line in ["Melee result: Charger took 0, Defender took 2 — Defender loses the melee", "Defender passes morale",
			"Consolidation: move Charger back 1\""]:
		assert_bool(_has(line)).override_failure_message("the line '%s': %s" % [line, _t.lines]).is_true()
	assert_int((cd[1] as GameUnit).get_alive_count()).override_failure_message("D stays").is_equal(1)


func test_gff_a_13_in_charge_is_refused(timeout := 120000) -> void:
	var c := _t.unit("gff", 1, "Charger", 1, 3, -13.0 - BASE_IN, 0.0, {"name": "Blade", "range_in": 0, "attacks": 3, "count": 1, "rules": []})
	_t.unit("gff", 2, "Defender", 1, 3, 0.0, 0.0)
	_t.unit("gff", 2, "Spare", 1, 1, 0.0, 30.0)
	var from: Vector3 = (c.models[0] as ModelInstance).node.global_position
	assert_bool(await _t.start(c)).is_true()
	await _t.walk(c, 13.0, 0.0, CoreActivation.CAP_CHARGE)
	assert_float(((c.models[0] as ModelInstance).node.global_position - from).length() / INCH) \
		.override_failure_message("the 13 in charge snaps back: %s" % [_t.lines]).is_equal_approx(0.0, 0.05)
	assert_bool(_t.lines.any(func(l: String) -> bool: return l.find("allowance is 12.0") != -1)) \
		.override_failure_message("one line names the 12 in: %s" % [_t.lines]).is_true()


func test_aofs_impact_against_brace(timeout := 120000) -> void:
	await _charge("aofs", 10.0, 12, ["Impact(3)"], ["Brace(1)"])
	assert_bool(_has("Brace: Defender takes 1 Impact dice off Charger")).override_failure_message("Brace: %s" % [_t.lines]).is_true()
	assert_int(_t.count("Charger: Impact(3) rolls 2 dice")).override_failure_message("3 - 1 = 2 Impact dice: %s" % [_t.lines]).is_equal(1)
