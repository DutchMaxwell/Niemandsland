extends GdUnitTestSuite
## SHO-20 (0.3.15, rules 3.6): a Slayer's extra AP against a Tough(3)+ target is earned by a HOLD
## on the shooting side from EPOCH_73_V36; a shooter that moved gets none. At
## EPOCH_72_PLAYTEST_RULES the old over-9" leg still pays a moved shooter, and the charge leg is
## unchanged at every epoch. The cases read the real registry through
## main.gd:_solo_conditional_ap_parts, so the table's own gate spelling is part of the proof.

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


## The Slayer AP the table grants against the Tough(3) target; `moved_round` equals the round when
## the shooter moved, so `_solo_unit_held` answers false there.
func _bonus(epoch: int, moved_round: int, charging: bool, melee: bool, dist_in: float) -> int:
	AiActRecorder.rules_epoch = epoch
	var striker := _unit("dao_union", ["Slayer"])
	striker.unit_properties["moved_round"] = moved_round
	var parts: Array = _main._solo_conditional_ap_parts(
		{"rules": []}, striker, _tough_target(), charging, dist_in, melee)
	var total := 0
	for part in parts:
		total += int((part as Dictionary)["bonus"])
	return total


func test_a_holding_slayer_gets_its_extra_ap_at_73() -> void:
	assert_int(_bonus(AiActRecorder.EPOCH_73_V36, -1, false, false, 12.0)) \
		.override_failure_message("a Hold must earn Slayer's AP at 73").is_equal(2)


func test_a_moved_slayer_gets_no_extra_ap_at_73() -> void:
	assert_int(_bonus(AiActRecorder.EPOCH_73_V36, 2, false, false, 12.0)) \
		.override_failure_message("moving gives up Slayer's AP at 73").is_equal(0)


func test_a_moved_slayer_keeps_the_over_nine_leg_at_72() -> void:
	assert_int(_bonus(AiActRecorder.EPOCH_72_PLAYTEST_RULES, 2, false, false, 12.0)) \
		.override_failure_message("72 keeps the over-9\" Slayer leg for a moved shooter").is_equal(2)


## CONTROL: the charge leg pays at both epochs.
func test_a_charging_slayer_keeps_its_extra_ap_at_72_and_73() -> void:
	for epoch: int in [AiActRecorder.EPOCH_72_PLAYTEST_RULES, AiActRecorder.EPOCH_73_V36]:
		assert_int(_bonus(epoch, -1, true, true, -1.0)) \
			.override_failure_message("%d: the charge leg is unchanged" % epoch).is_equal(2)
