extends GdUnitTestSuite
## Rules 3.6, fix PF-b: the Enhanced forms of the Shred alias family (Enhanced Warbound, Enhanced Destroyer, Enhanced
## Infected; War Disciples, Ogres and Infected Colonies 3.6.0 books) deal the extra wound on unmodified Defense 1s
## "always" - at any distance and on any attack - instead of only on a shot at a target over 9" away or a charge from
## over 6". They no longer widen the window to 1-2 (that was the 3.5 Boost). The base forms keep the distance
## condition (controls). From EPOCH_73_V36; epoch 72 replays the 3.5 Boost (1-2, only over 9").
## Real _solo_attack_groups profile build + real _solo_save_batch on a fixed tray face (the SHO-18c probe).

class Probe extends "res://scripts/main.gd":
	var faces: Array = []

	func _solo_tray_roll(_count: int, _target: int, _owner: String, _kind: String = "attack",
			_purpose: String = "") -> Array:
		return faces


var _epoch_before := 0
var _log := ""


func before_test() -> void:
	_epoch_before = AiActRecorder.rules_epoch
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	_log = ""


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch_before


func _unit(unit_name: String, weapons: Array, rules: Array, system: String, faction: String) -> GameUnit:
	var u: GameUnit = auto_free(GameUnit.new())
	u.unit_id = "pfb_%s" % unit_name
	u.unit_properties = {"player_id": 2, "name": unit_name, "quality": 4, "defense": 4,
		"special_rules": rules, "game_system": system, "faction_folder": faction}
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
		ws.append(w)
	var src := OPRApiClient.OPRUnit.new()
	src.weapons = ws
	u.source_type = "opr"
	u.source_data = src
	return u


func _probe(face: int) -> Probe:
	var main: Probe = auto_free(Probe.new())
	main.battle_log = auto_free(BattleLog.new())
	main.faces = [face]
	return main


func _read_log(main: Probe) -> void:
	_log = ""
	for e in main.battle_log.entries():
		_log += str((e as Dictionary)["text"]) + "\n"


## One hit saved at Defense 4+ with the given unmodified face; returns the wounds the batch deals.
func _shoot(rules: Array, dist_in: float, face: int, system := "gf", faction := "war_disciples") -> int:
	var main := _probe(face)
	var striker := _unit("Rifles", [{"name": "Rifle", "range": 24, "attacks": 2}], rules, system, faction)
	var target := _unit("Target", [], [], system, faction)
	var groups: Array = main._solo_attack_groups(striker, dist_in, false, null)
	var profile: Dictionary = ((groups[0] as Dictionary).get("profiles", [])[0]) as Dictionary
	var wounds: int = await main._solo_save_batch(striker, target, "Rifle", 1, 4, 0, profile,
		false, false, true, dist_in > 9.0, {}, dist_in)
	_read_log(main)
	return wounds


func _charge(rules: Array, charge_in: float, face: int, system := "gf", faction := "war_disciples") -> int:
	var main := _probe(face)
	var striker := _unit("Blades", [{"name": "Blade", "range": 0, "attacks": 3}], rules, system, faction)
	var target := _unit("Target", [], [], system, faction)
	var groups: Array = main._solo_attack_groups(striker, 0.0, true, null)
	var profile: Dictionary = ((groups[0] as Dictionary).get("profiles", [])[0]) as Dictionary
	var wounds: int = await main._solo_save_batch(striker, target, "Blade", 1, 4, 0, profile,
		false, false, true, false, {}, -1.0, charge_in)
	_read_log(main)
	return wounds


## A non-charging melee strike-back: no charge distance, no shot distance.
func _strike_back(rules: Array, face: int) -> int:
	var main := _probe(face)
	var striker := _unit("Blades", [{"name": "Blade", "range": 0, "attacks": 3}], rules, "gf", "war_disciples")
	var target := _unit("Target", [], [], "gf", "war_disciples")
	var groups: Array = main._solo_attack_groups(striker, 0.0, true, null)
	var profile: Dictionary = ((groups[0] as Dictionary).get("profiles", [])[0]) as Dictionary
	var wounds: int = await main._solo_save_batch(striker, target, "Blade", 1, 4, 0, profile,
		false, false, true, false, {}, -1.0, 0.0)
	_read_log(main)
	return wounds


## Controls (base rule, distance condition): over 9" a 1 deals 2 wounds, inside 9" it deals 1; a 2 never shreds.
func test_control_warbound_shreds_over_nine_inches_only() -> void:
	assert_int(await _shoot(["Warbound"], 12.0, 1)).override_failure_message("Warbound 12\" face 1").is_equal(2)
	assert_int(await _shoot(["Warbound"], 6.0, 1)).override_failure_message("Warbound 6\" face 1").is_equal(1)
	assert_int(await _shoot(["Warbound"], 12.0, 2)).override_failure_message("Warbound 12\" face 2").is_equal(1)
	assert_int(await _charge(["Warbound"], 8.0, 1)).override_failure_message("Warbound charge 8\" face 1").is_equal(2)
	assert_int(await _charge(["Warbound"], 4.0, 1)).override_failure_message("Warbound charge 4\" face 1").is_equal(1)
	assert_int(await _strike_back(["Warbound"], 1)).override_failure_message("Warbound strike-back face 1").is_equal(1)


## PF-b (1): Enhanced Warbound lifts the distance condition - a 6" shot's unmodified 1 deals the extra wound,
## and the log line names the Enhanced form.
func test_pfb_enhanced_warbound_shreds_a_six_inch_shot() -> void:
	assert_int(await _shoot(["Warbound", "Enhanced Warbound"], 6.0, 1)) \
		.override_failure_message("PF-b: Enhanced Warbound at 6\" dealt no extra wound on a 1").is_equal(2)
	assert_str(_log).override_failure_message("the Enhanced form is not named (log: %s)" % _log) \
		.contains("Enhanced Warbound: 1 Defense roll of 1 → +1 wound")


## PF-b (2): Enhanced Warbound lifts the condition on a charge too - a 4" charge's unmodified 1 shreds.
func test_pfb_enhanced_warbound_shreds_a_four_inch_charge() -> void:
	assert_int(await _charge(["Warbound", "Enhanced Warbound"], 4.0, 1)) \
		.override_failure_message("PF-b: Enhanced Warbound on a 4\" charge dealt no extra wound on a 1").is_equal(2)


## PF-b (3): "always" includes a strike-back (no charge, no distance).
func test_pfb_enhanced_warbound_shreds_a_strike_back() -> void:
	assert_int(await _strike_back(["Warbound", "Enhanced Warbound"], 1)) \
		.override_failure_message("PF-b: Enhanced Warbound dealt no extra wound on a strike-back 1").is_equal(2)


## PF-b (4): the window is unmodified 1s - a failed save of 2 deals exactly 1 wound at any distance.
func test_pfb_enhanced_warbound_does_not_shred_a_two() -> void:
	assert_int(await _shoot(["Warbound", "Enhanced Warbound"], 12.0, 2)) \
		.override_failure_message("PF-b: Enhanced Warbound at 12\" shredded a failed save of 2 (3.5 Boost window)").is_equal(1)
	assert_int(await _shoot(["Warbound", "Enhanced Warbound"], 6.0, 2)) \
		.override_failure_message("PF-b: Enhanced Warbound at 6\" shredded a failed save of 2").is_equal(1)
	assert_int(await _charge(["Warbound", "Enhanced Warbound"], 8.0, 2)) \
		.override_failure_message("PF-b: Enhanced Warbound shredded a 2 on an 8\" charge").is_equal(1)


## PF-b (5): the other registry rows of the family behave the same - Enhanced Destroyer (Ogres, AoF) and
## Enhanced Infected (Infected Colonies, GF): a 1 shreds at 6", a 2 never does.
func test_pfb_enhanced_destroyer_and_infected_follow_the_same_rule() -> void:
	var destroyer := ["Destroyer", "Enhanced Destroyer"]
	assert_int(await _shoot(destroyer, 6.0, 1, "aof", "ogres")).override_failure_message("Enhanced Destroyer 6\" face 1").is_equal(2)
	assert_int(await _shoot(destroyer, 12.0, 2, "aof", "ogres")).override_failure_message("Enhanced Destroyer 12\" face 2").is_equal(1)
	assert_int(await _shoot(["Destroyer"], 6.0, 1, "aof", "ogres")).override_failure_message("Destroyer 6\" face 1").is_equal(1)
	var infected := ["Infected", "Enhanced Infected"]
	assert_int(await _shoot(infected, 6.0, 1, "gf", "infected_colonies")).override_failure_message("Enhanced Infected 6\" face 1").is_equal(2)
	assert_int(await _shoot(infected, 12.0, 2, "gf", "infected_colonies")).override_failure_message("Enhanced Infected 12\" face 2").is_equal(1)
	assert_int(await _shoot(["Infected"], 6.0, 1, "gf", "infected_colonies")).override_failure_message("Infected 6\" face 1").is_equal(1)


## Epoch 72 replays the 3.5 Boost: the alias pays at every distance there, and over 9" the window widens to 1-2.
func test_pfb_epoch_72_keeps_the_boost_window() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	assert_int(await _shoot(["Warbound", "Enhanced Warbound"], 12.0, 2)) \
		.override_failure_message("epoch 72: Enhanced Warbound over 9\" must still widen to 1-2").is_equal(2)
	assert_int(await _shoot(["Warbound", "Enhanced Warbound"], 6.0, 2)) \
		.override_failure_message("epoch 72: the 1-2 window stays a shot-over-9\" read").is_equal(1)
