extends GdUnitTestSuite
## R-1 (A2): a weapon's own Shred and a differently named unit-level extra-wound rule (the Warbound family)
## are two rules and each pays its extra wounds; the table used to fold them into one flag. These cases
## run the real `_solo_attack_groups` profile build and the real `_solo_save_batch` save flow with a fixed
## tray (every die a 1), so the marker is never hand-built and every Defense roll is an unmodified 1.
## The fixture follows sho_18c_test.gd.

class Probe extends "res://scripts/main.gd":
	var faces: Array = []

	func _solo_tray_roll(_count: int, _target: int, _owner: String, _kind: String = "attack",
			_purpose: String = "") -> Array:
		return faces


const SHOTS := 60

var _epoch_before := 0


func before_test() -> void:
	_epoch_before = AiActRecorder.rules_epoch


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch_before


func _unit(unit_name: String, weapons: Array, rules: Array = ["Warbound"]) -> GameUnit:
	var u: GameUnit = auto_free(GameUnit.new())
	u.unit_id = "r1shred_%s" % unit_name
	u.unit_properties = {"player_id": 2, "name": unit_name, "quality": 4, "defense": 4,
		"special_rules": rules, "game_system": "gf", "faction_folder": "war_disciples"}
	var m := ModelInstance.new()
	m.is_alive = true
	u.models.append(m)
	var ws: Array[OPRApiClient.OPRWeapon] = []
	for wd in weapons:
		var d := wd as Dictionary
		var w := OPRApiClient.OPRWeapon.new()
		w.name = str(d.get("name", "Gun"))
		w.range_value = int(d.get("range", 0))
		w.attacks = int(d.get("attacks", 1))
		w.count = 1
		var rs: Array[String] = []
		for r in d.get("rules", []):
			rs.append(str(r))
		w.special_rules = rs
		ws.append(w)
	var src := OPRApiClient.OPRUnit.new()
	src.weapons = ws
	u.source_type = "opr"
	u.source_data = src
	return u


func _probe() -> Probe:
	var main: Probe = auto_free(Probe.new())
	main.battle_log = auto_free(BattleLog.new())
	main.faces = []
	for i in SHOTS:
		main.faces.append(1)
	return main


## The striker the cases share: a unit rule `rules` plus a rifle that prints Shred itself.
func _striker(rules: Array) -> GameUnit:
	return _unit("Shredders", [{"name": "Rifle", "range": 24, "attacks": 2, "rules": ["Shred"]}], rules)


func _profile(main: Probe, striker: GameUnit, dist_in: float) -> Dictionary:
	var groups: Array = main._solo_attack_groups(striker, dist_in, false, null)
	assert_int(groups.size()).override_failure_message("the table built no attack group").is_equal(1)
	if groups.is_empty():
		return {}
	var profiles: Array = (groups[0] as Dictionary).get("profiles", [])
	assert_int(profiles.size()).override_failure_message("the table built no profile").is_equal(1)
	if profiles.is_empty():
		return {}
	var prof := profiles[0] as Dictionary
	assert_bool(bool(prof.get("shred", false))) \
		.override_failure_message("fixture broken: the weapon's Shred did not reach the profile").is_true()
	return prof


## Runs one volley of SHOTS dice through the save step and returns the battle-log texts.
func _save(epoch: int, rules: Array, dist_in: float) -> Array:
	AiActRecorder.rules_epoch = epoch
	var main := _probe()
	var striker := _striker(rules)
	var target := _unit("Target", [])
	var profile := _profile(main, striker, dist_in)
	await main._solo_save_batch(striker, target, "Rifle", SHOTS, 6, 0, profile,
		false, false, true, dist_in > 9.0, {}, dist_in)
	var texts: Array = []
	for e in main.battle_log.entries():
		texts.append(str((e as Dictionary)["text"]))
	return texts


## The N of every "<name>: N Defense roll..." line, in log order.
func _rolls_of(texts: Array, rule_name: String) -> Array:
	var rx := RegEx.new()
	rx.compile("(?:^|\\n)%s: (\\d+) Defense roll" % rule_name)
	var out: Array = []
	for t in texts:
		var m := rx.search(str(t))
		if m != null:
			out.append(int(m.get_string(1)))
	return out


## (a) RED on main: the profile build folds the weapon's own Shred into the unit grant and keeps no trace.
func test_the_profile_marks_a_weapons_own_shred_beside_the_unit_rule_name() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var prof := _profile(_probe(), _striker(["Warbound"]), 12.0)
	assert_bool(bool(prof.get("_shred_own", false))) \
		.override_failure_message("the profile does not say the weapon prints Shred itself").is_true()
	assert_str(str(prof.get("_shred_alias", ""))).is_equal("Warbound")
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var old := _profile(_probe(), _striker(["Warbound"]), 12.0)
	assert_bool(old.has("_shred_own")) \
		.override_failure_message("below rules 3.6 the profile must carry no own-Shred mark").is_false()


## (b) RED on main: over 9" the unit rule pays alone, the weapon's own Shred is folded away.
func test_over_nine_inches_both_rules_pay_the_same_extra_wounds() -> void:
	var texts := await _save(AiActRecorder.EPOCH_73_V36, ["Warbound"], 12.0)
	var unit_rule := _rolls_of(texts, "Warbound")
	var own := _rolls_of(texts, "Shred")
	assert_int(unit_rule.size()).override_failure_message("the unit rule paid %d times" % unit_rule.size()).is_equal(1)
	assert_int(own.size()).override_failure_message("the weapon's own Shred paid %d times" % own.size()).is_equal(1)
	if unit_rule.size() == 1 and own.size() == 1:
		assert_int(unit_rule[0]).is_equal(SHOTS)
		assert_int(own[0]).is_equal(unit_rule[0])


## (c) RED on main: inside 9" the unit rule's own gate closes; the weapon's own Shred must still pay.
func test_inside_nine_inches_only_the_weapons_own_shred_pays() -> void:
	var texts := await _save(AiActRecorder.EPOCH_73_V36, ["Warbound"], 6.0)
	var own := _rolls_of(texts, "Shred")
	assert_int(own.size()).override_failure_message("the weapon's own Shred paid %d times" % own.size()).is_equal(1)
	if own.size() == 1:
		assert_int(own[0]).is_equal(SHOTS)
	assert_int(_rolls_of(texts, "Warbound").size()) \
		.override_failure_message("the unit rule paid inside its own gate").is_equal(0)


## (d) control, GREEN on main: the same rule on the unit and on the weapon is one rule, one roll.
func test_the_same_rule_on_unit_and_weapon_pays_once() -> void:
	var texts := await _save(AiActRecorder.EPOCH_73_V36, ["Shred"], 12.0)
	assert_array(_rolls_of(texts, "Shred")).is_equal([SHOTS])
	assert_int(_rolls_of(texts, "Warbound").size()).is_equal(0)


## (e) control, GREEN on main: below rules 3.6 the fold stays, one line, as old recordings replay.
func test_at_epoch_72_the_fold_stays_one_line() -> void:
	var texts := await _save(AiActRecorder.EPOCH_72_PLAYTEST_RULES, ["Warbound"], 12.0)
	assert_array(_rolls_of(texts, "Warbound")).is_equal([SHOTS])
	assert_int(_rolls_of(texts, "Shred").size()).is_equal(0)
