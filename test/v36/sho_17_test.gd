extends GdUnitTestSuite
## Rules 3.6 wave, row SHO-17: the Guarded family's charge leg reads the shared 6" charge gate from
## EPOCH_73_V36 on (Guarded, Versatile Defense, Sturdy); below it the old over-9" reading stays.
## The shot leg keeps its over-9" gate at every epoch and is covered by the Rust twin. Here the
## Impact seam runs for real, with the tray and the save batch as the two probe seams.

class Probe extends "res://scripts/main.gd":
	var faces: Array = []
	var defense_seen := -1

	func _solo_tray_roll(_count: int, _target: int, _owner: String, _kind: String = "attack",
			_purpose: String = "") -> Array:
		return faces

	func _solo_resolve_saves(_striker: GameUnit, _defender: GameUnit, _weapon: String, _faces: Array,
			_hits: int, base_defense: int, _profile: Dictionary, _human: bool, _melee: bool,
			_deadly: bool = true, _charging: bool = false, _dist: float = -1.0,
			_solo: Dictionary = {}) -> int:
		defense_seen = base_defense
		return 0


var _epoch_before := 0


func before_test() -> void:
	_epoch_before = AiActRecorder.rules_epoch


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch_before


## `rules` go on the unit's own special rules; the game system/faction are the shipped gf books the
## registry resolves the Guarded family through.
func _unit(name: String, models: int, rules: Array, faction: String = "blessed_sisters") -> GameUnit:
	var u: GameUnit = auto_free(GameUnit.new())
	u.unit_id = "sho17_%s" % name
	u.unit_properties = {"player_id": 2, "name": name, "quality": 4, "defense": 4,
		"special_rules": rules, "game_system": "gf", "faction_folder": faction}
	for i in models:
		var m := ModelInstance.new()
		m.is_alive = true
		u.models.append(m)
	return u


func _impact(epoch: int, charge_in: float) -> Probe:
	AiActRecorder.rules_epoch = epoch
	var main: Probe = auto_free(Probe.new())
	main.battle_log = auto_free(BattleLog.new())
	main.faces = [2, 2, 2, 2]
	var charger := _unit("Charger", 1, ["Impact(2)"])
	var defender := _unit("Target", 1, ["Guarded"])
	await main._solo_charge_impact(charger, defender, false, charge_in)
	return main


func _log_text(main: Node) -> String:
	var text := ""
	for e in main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


func test_the_guarded_charge_gate_is_six_inches_at_epoch_73_and_nine_below_it() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var main: Node = auto_free(preload("res://scripts/main.gd").new())
	assert_float(float(main._solo_guarded_charge_gate())) \
		.override_failure_message("rules 3.6: the shared 6\" charge gate").is_equal_approx(6.0, 1e-6)
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	assert_float(float(main._solo_guarded_charge_gate())) \
		.override_failure_message("below 73 the old over-9\" reading").is_equal_approx(9.0, 1e-6)


func test_a_guarded_unit_charged_from_seven_inches_saves_one_better_at_epoch_73() -> void:
	var main := await _impact(AiActRecorder.EPOCH_73_V36, 7.0)
	assert_int(main.defense_seen).override_failure_message("charged from over 6\": 4+ becomes 3+") \
		.is_equal(3)
	var text := _log_text(main)
	assert_str(text) \
		.override_failure_message("rules-must-log: the applied gate names Guarded and the 6\" band — got: %s" % text.strip_edges()) \
		.contains("Guarded") \
		.contains("over 6\"")


func test_a_guarded_unit_charged_from_five_inches_keeps_its_save() -> void:
	var main := await _impact(AiActRecorder.EPOCH_73_V36, 5.0)
	assert_int(main.defense_seen).override_failure_message("inside the gate: the bare Defense").is_equal(4)


func test_a_guarded_unit_charged_from_seven_inches_keeps_its_save_at_epoch_72() -> void:
	var main := await _impact(AiActRecorder.EPOCH_72_PLAYTEST_RULES, 7.0)
	assert_int(main.defense_seen).override_failure_message("below 73 only over 9\" pays").is_equal(4)


func test_a_guarded_unit_charged_from_over_nine_inches_still_saves_one_better_at_epoch_72() -> void:
	var main := await _impact(AiActRecorder.EPOCH_72_PLAYTEST_RULES, 10.0)
	assert_int(main.defense_seen).override_failure_message("the old over-9\" reading is unchanged").is_equal(3)
