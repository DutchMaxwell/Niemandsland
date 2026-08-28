extends GdUnitTestSuite
## NML-1115: the PROSE GATE's own instrument check — `verify-the-instrument`.
##
## `tools/prose_gate.gd` answers one question over both AI-list pools: does OPR rule TEXT still
## change what the table plays? A gate that answers "no difference" because it cannot SEE a
## difference is worthless — which is exactly how its LANE channel went "green" after #467 deleted
## the predicate it called, 16k runtime errors deep. These cases pin the one comparison primitive
## that is left, on synthetic units, with no network and no pool: `_reading` must detect a real
## band difference, and must be blind to rule TEXT (the invariant #467 established and
## `tools/no_rule_text_in_gameplay.sh` guards).

const ProseGate := preload("res://tools/prose_gate.gd")

# A band modifier that exists ONLY as text: no name fallback, no registry entry.
const PROSE_ONLY_RULE := "Nimble Step"
const PROSE_ONLY_TEXT := "This model moves +2\" when using Advance, and +4\" when using Rush/Charge."


func _unit(props: Dictionary) -> GameUnit:
	var gu := GameUnit.new()
	gu.unit_properties = {"player_id": 1, "name": "Probe", "quality": 4, "defense": 4,
		"game_system": "gf", "faction_folder": ""}
	gu.unit_properties.merge(props, true)
	return gu


# ===== _reading must still be able to report a difference =====

func test_reading_detects_a_real_band_difference() -> void:
	# The comparison machinery itself: two props that genuinely differ must read differently, or a
	# GREEN run over 4279 units would mean nothing.
	var plain: Array = ProseGate._reading(_unit({"special_rules": ["Fast"]}))
	var slowed: Array = ProseGate._reading(_unit({
		"special_rules": ["Fast"], "spell_move_mod": {"advance": -2, "rush": -4}}))
	assert_array(plain).is_equal([8, 16, 0])
	assert_array(slowed).is_equal([6, 12, 0])


# ===== and it must be blind to rule text =====

func test_reading_is_blind_to_a_prose_only_modifier() -> void:
	# A modifier that exists only in an imported description is inert (NML-1115). This is the
	# invariant the gate protects: its two arms must agree for every unit in both pools.
	var gu := _unit({"special_rules": [PROSE_ONLY_RULE],
		"rule_descriptions": {PROSE_ONLY_RULE: PROSE_ONLY_TEXT}})
	var with_text: Array = ProseGate._reading(gu)
	gu.unit_properties["rule_descriptions"] = {}
	assert_array(with_text) \
		.override_failure_message("an imported rule DESCRIPTION moved a band reading (NML-1115)") \
		.is_equal(ProseGate._reading(gu))


func test_reading_keeps_the_name_and_registry_passes() -> void:
	# The counter-case: what the bands DO read still reads. Ratmen Clans "Scurry" is registry data
	# (primitive "Quick", advance_mod/rush_mod 2) and needs no text at all.
	assert_array(ProseGate._reading(_unit({
		"game_system": "gf", "faction_folder": "ratmen_clans", "special_rules": ["Scurry"]}))) \
		.is_equal([8, 14, 0])
