extends GdUnitTestSuite
## FAB-A10 (0.3.15, rules 3.6): a moved Slayer's shooting has no 9" leg at EPOCH_73_V36 — the AP is
## already 0 at every distance, so the "no AP, moved" line must name the rule at every distance.
## Below 73 the old over-9" leg stays. The cases read the real registry through
## main.gd:_solo_conditional_ap_parts (the zero-bonus Slayer part is what _solo_resolve_saves turns
## into "Slayer: no AP, <name> moved"), so the table's own gate is part of the proof.

const MainScript := preload("res://scripts/main.gd")

var _epoch0: int
var _main: Node3D
var _army: OPRArmyManager


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch
	RulesRegistry.reset_cache()
	_main = auto_free(MainScript.new())
	_army = auto_free(OPRArmyManager.new())
	_army.current_round = 2
	_main.opr_army_manager = _army


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0
	RulesRegistry.reset_cache()


func _unit(faction: String, rules: Array) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = "u_%s" % faction
	u.unit_properties = {"player_id": 1, "name": "Slayers", "quality": 4, "defense": 4,
		"special_rules": rules, "faction_folder": faction}
	return u


func _tough_target() -> GameUnit:
	var t := GameUnit.new()
	t.unit_id = "target"
	t.unit_properties = {"player_id": 2, "name": "Target", "quality": 4, "defense": 4,
		"special_rules": ["Tough(3)"], "faction_folder": "dao_union"}
	return t


## The conditional-AP parts the table grants against the Tough(3) target; `moved_round` equals the
## round when the shooter moved, so `_solo_unit_held` answers false there. The zero-bonus Slayer part
## is the moved line at 73.
func _parts(epoch: int, moved_round: int, dist_in: float) -> Array:
	AiActRecorder.rules_epoch = epoch
	var striker := _unit("dao_union", ["Slayer"])
	striker.unit_properties["moved_round"] = moved_round
	return _main._solo_conditional_ap_parts(
		{"rules": []}, striker, _tough_target(), false, dist_in, false)


func _bonus(parts: Array) -> int:
	var total := 0
	for part in parts:
		total += int((part as Dictionary)["bonus"])
	return total


func _names(parts: Array) -> Array:
	var names: Array = []
	for part in parts:
		names.append(str((part as Dictionary)["name"]))
	return names


## RED on main: at 7" the table returns no part at 73, so the moved line never prints.
func test_a_moved_slayer_names_the_rule_at_seven_inches_at_73() -> void:
	var parts := _parts(AiActRecorder.EPOCH_73_V36, 2, 7.0)
	assert_int(_bonus(parts)) \
		.override_failure_message("the AP stays 0 under 9\" (parts: %s)" % str(parts)).is_equal(0)
	assert_array(_names(parts)) \
		.override_failure_message("RED on main: the moved line only prints over 9\" (parts: %s)" % str(parts)) \
		.contains(["Slayer"])


## CONTROL: the over-9" wording is unchanged at 73.
func test_a_moved_slayer_names_the_rule_at_twelve_inches_at_73() -> void:
	var parts := _parts(AiActRecorder.EPOCH_73_V36, 2, 12.0)
	assert_int(_bonus(parts)).override_failure_message("no AP over 9\" either").is_equal(0)
	assert_array(_names(parts)) \
		.override_failure_message("the over-9\" line is unchanged (parts: %s)" % str(parts)) \
		.contains(["Slayer"])


## CONTROL: below 73 the old over-9" leg stays — no moved line under 9", AP(+2) over 9".
func test_a_moved_slayer_keeps_the_old_over_nine_leg_at_72() -> void:
	assert_array(_parts(AiActRecorder.EPOCH_72_PLAYTEST_RULES, 2, 7.0)) \
		.override_failure_message("72 has no moved line below the gate").is_empty()
	var far := _parts(AiActRecorder.EPOCH_72_PLAYTEST_RULES, 2, 12.0)
	assert_int(_bonus(far)) \
		.override_failure_message("72: past 9\" earns AP(+2) even after moving (parts: %s)" % str(far)).is_equal(2)
	assert_array(_names(far)) \
		.override_failure_message("72 keeps the old over-9\" reading only (parts: %s)" % str(far)) \
		.contains(["Slayer"])
