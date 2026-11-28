extends GdUnitTestSuite
## Feature test FT-14: the Hero's Quality for a morale test within 6 in, Firefight (gff) and Skirmish (aofs) on a hot-seat
## table. FF36 p.14 l.1241-1243 (AS36 the same): a friendly Hero within 6 in lends its Quality to a unit's morale test; the
## skirmish books never join a Hero to a unit. Distances base to base (FF36 p.5).
## Scene: U (Quality 5, one Tough(3) model) with a Hero (Quality 3) whose base is 5.5 in off U's base; twin 6.5 in; twin
## 5.5 in with the Hero Shaken. A (Quality 2, 4 attacks) shoots U. Tray seed 18 (R-FT3, the scan of FT-11's scene):
## hits and blocks leave 2 wounds, morale face 4 -> passes on the Hero's 3+, fails on U's own 5+.
## Real: the main scene, the card's Activate, the radial targeting and click, the core's volley, morale and aura.

const INCH := 0.0254
const BASE_IN := 32.0 / 25.4
const SEED := 18

var _t: SkirmishTable


func before_test() -> void:
	_t = await SkirmishTable.boot(self, "H")


func after_test() -> void:
	if _t != null:
		_t.teardown()
	_t = null


## U shot to 2 wounds with its Hero `gap_in` off (base to base); `shaken_hero` shakes the Hero first.
func _case(sys: String, gap_in: float, shaken_hero: bool) -> void:
	var a := _t.unit(sys, 1, "Gunners", 1, 1, -12.0, 0.0, {"name": "Rifle", "range_in": 24, "attacks": 4, "count": 1, "rules": []})
	a.unit_properties["quality"] = 2
	var u := _t.unit(sys, 2, "Target", 1, 3, 0.0, 0.0)
	u.unit_properties["quality"] = 5
	var hero := _t.unit(sys, 2, "Captain", 1, 1, 0.0, gap_in + BASE_IN, {}, ["Hero"])
	hero.unit_properties["quality"] = 3
	hero.is_shaken = shaken_hero
	assert_bool(await _t.start(a)).override_failure_message("A starts").is_true()
	_t.main.seed_tray_rng(SEED)
	await _t.aim(a, u)
	assert_int(_t.count("Target takes 2 wounds (1/3 wounds)")).override_failure_message("%s: 2 wounds: %s" % [sys, _t.lines]).is_equal(1)
	assert_bool(u.is_attached() or hero.is_attached()).override_failure_message("%s: the Hero never joins" % sys).is_false()


func _lent() -> bool:
	return _t.lines.any(func(l: String) -> bool: return l.begins_with("Captain") and l.find("lends its Quality to Target's morale test (Q3+)") != -1)


func _passes(sys: String) -> void:
	await _case(sys, 5.5, false)
	assert_bool(_lent()).override_failure_message("%s: the line names the Hero: %s" % [sys, _t.lines]).is_true()
	assert_int(_t.count("Target passes morale")).override_failure_message("%s: 4 passes on 3+: %s" % [sys, _t.lines]).is_equal(1)


func _fails(sys: String, gap_in: float, shaken_hero: bool) -> void:
	await _case(sys, gap_in, shaken_hero)
	assert_bool(_lent()).override_failure_message("%s: no Hero lends: %s" % [sys, _t.lines]).is_false()
	assert_int(_t.count("Target fails morale — Shaken")).override_failure_message("%s: 4 fails on 5+: %s" % [sys, _t.lines]).is_equal(1)


func test_gff_hero_5_5_in_off_lends(timeout := 120000) -> void:
	await _passes("gff")


func test_aofs_hero_5_5_in_off_lends(timeout := 120000) -> void:
	await _passes("aofs")


func test_gff_hero_6_5_in_off_does_not(timeout := 120000) -> void:
	await _fails("gff", 6.5, false)


func test_aofs_hero_6_5_in_off_does_not(timeout := 120000) -> void:
	await _fails("aofs", 6.5, false)


func test_gff_shaken_hero_does_not(timeout := 120000) -> void:
	await _fails("gff", 5.5, true)


func test_aofs_shaken_hero_does_not(timeout := 120000) -> void:
	await _fails("aofs", 5.5, true)
