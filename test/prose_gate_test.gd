extends GdUnitTestSuite
## NML-1115: the PROSE GATE's own instrument check — `verify-the-instrument`.
##
## `tools/prose_gate.gd` answers one question over both AI-list pools: does OPR rule TEXT
## still change what the table plays? A gate that answers "no difference" because it cannot
## SEE a difference is worthless, so these cases pin its two comparison primitives on
## synthetic units, with no network and no pool: `_reading` must report a prose-only band
## modifier, and `_lane` must report a prose-only Ambush/Scout staging hit — and both must
## fall silent when the same rule's effect is registry/name data instead of text.

const ProseGate := preload("res://tools/prose_gate.gd")

# A band modifier that exists ONLY as text: no name fallback, no registry entry.
const PROSE_ONLY_RULE := "Nimble Step"
const PROSE_ONLY_TEXT := "This model moves +2\" when using Advance, and +4\" when using Rush/Charge."


func _unit(rules: Array, descriptions: Dictionary) -> GameUnit:
	var gu := GameUnit.new()
	gu.unit_properties = {"special_rules": rules, "player_id": 1, "name": "Probe",
		"quality": 4, "defense": 4, "game_system": "gf", "faction_folder": "",
		"rule_descriptions": descriptions}
	return gu


func _opr_unit(rules: Array) -> OPRApiClient.OPRUnit:
	var ou := OPRApiClient.OPRUnit.new()
	ou.name = "Probe"
	ou.special_rules.assign(rules)
	return ou


# ===== _reading: the move bands =====

func test_reading_sees_a_prose_only_band_modifier() -> void:
	var gu := _unit([PROSE_ONLY_RULE], {PROSE_ONLY_RULE: PROSE_ONLY_TEXT})
	var with_text: Array = ProseGate._reading(gu)
	gu.unit_properties["rule_descriptions"] = {}
	var without_text: Array = ProseGate._reading(gu)
	assert_array(with_text).is_equal([8, 16, 0])
	assert_array(without_text).is_equal([6, 12, 0])


func test_reading_is_silent_when_the_modifier_is_name_data() -> void:
	# Fast's +2"/+4" is a name fallback, so the same text changes nothing: this is the
	# reading the gate must NOT count, or every unit in both pools would be a difference.
	var gu := _unit(["Fast"], {"Fast": PROSE_ONLY_TEXT})
	var with_text: Array = ProseGate._reading(gu)
	gu.unit_properties["rule_descriptions"] = {}
	assert_array(with_text).is_equal(ProseGate._reading(gu))


# ===== _lane: the tray's Ambush/Scout staging =====

func test_lane_sees_an_ambush_named_only_in_another_rule_s_text() -> void:
	var manager: OPRArmyManager = auto_free(OPRArmyManager.new())
	var ou := _opr_unit(["Repel Ambushers"])
	var descriptions := {"Repel Ambushers": "This model may re-roll misses against Ambush units."}
	assert_bool(ProseGate._lane(manager, ou, descriptions, "Ambush")).is_true()
	assert_bool(ProseGate._lane(manager, ou, {}, "Ambush")).is_false()


func test_lane_is_silent_for_a_directly_carried_rule() -> void:
	var manager: OPRArmyManager = auto_free(OPRArmyManager.new())
	var ou := _opr_unit(["Ambush"])
	assert_bool(ProseGate._lane(manager, ou, {"Ambush": "Deploy from reserve."}, "Ambush")).is_true()
	assert_bool(ProseGate._lane(manager, ou, {}, "Ambush")).is_true()
