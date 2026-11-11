extends GdUnitTestSuite
## Rules 3.6 wave, row DAT-03: the Voidspace Stalkers book (gf) had no section of its own in the gf
## mechanics map, so every army rule the book fields fell back to the common section or printed
## "apply manually". The new section carries the 8 army rules the book needs, each copied from the
## same-named entry other book sections already hold (identical params in every section that carries
## the name; only book_version varies). Godot's JSON reads every number as a float, so the expected
## params below are floats.

const BOUNDING_PARAMS := {"place_d3_plus": 1.0}
const FORTIFIED_PARAMS := {"incoming_ap_reduction": 1.0}
const INCREASED_SHOOTING_RANGE_BUFF_PARAMS := {"max_targets": 1.0, "once": true, "phase": "shoot",
	"range_bonus_in": 6.0, "range_in": 12.0, "target": "friendly"}
const MELEE_SLAYER_PARAMS := {"ap_bonus": 2.0, "charge_only": true, "condition": "vs_tough_ge",
	"threshold": 3.0}
const PRECISION_TARGET_PARAMS := {"bonus": "per_placed_marker", "markers": 1.0, "needs_los": true,
	"range_in": 18.0, "target": "enemy", "uses_per_game": 1.0}
const RAVAGE_PARAMS := {"no_save": true, "rating": "X", "wound_target": 6.0}
const REGENERATION_AURA_PARAMS := {"ignore_target": 5.0}
const SHADOWBORN_PARAMS := {"floor_in": 6.0, "melee_floor_in": 6.0, "melee_move_penalty_in": 2.0,
	"range_penalty_in": 4.0}


func before_test() -> void:
	RulesRegistry.reset_cache()


func after_test() -> void:
	RulesRegistry.reset_cache()


func _assert_entry(rule: String, primitive: String, params: Dictionary, version: String) -> void:
	var entry := RulesRegistry.lookup("gf", "voidspace_stalkers", rule)
	assert_str(str(entry.get("primitive", ""))) \
		.override_failure_message("gf/voidspace_stalkers does not resolve %s to %s: %s" % [rule, primitive, entry]) \
		.is_equal(primitive)
	assert_dict(entry.get("params", {}) as Dictionary) \
		.override_failure_message("gf/voidspace_stalkers resolves %s with other knobs: %s" % [rule, entry]) \
		.is_equal(params)
	assert_str(str(entry.get("book_version", ""))) \
		.override_failure_message("gf/voidspace_stalkers answers %s from the wrong entry: %s" % [rule, entry]) \
		.is_equal(version)


func test_bounding_resolves_in_the_voidspace_stalkers_section() -> void:
	_assert_entry("Bounding", "Bounding", BOUNDING_PARAMS, "3.6.0")


func test_fortified_resolves_in_the_voidspace_stalkers_section() -> void:
	_assert_entry("Fortified", "Fortified", FORTIFIED_PARAMS, "3.6.0")


func test_increased_shooting_range_buff_resolves_in_the_voidspace_stalkers_section() -> void:
	_assert_entry("Increased Shooting Range Buff", "Utility Buff",
		INCREASED_SHOOTING_RANGE_BUFF_PARAMS, "3.6.0")


func test_melee_slayer_resolves_in_the_voidspace_stalkers_section() -> void:
	_assert_entry("Melee Slayer", "Melee Slayer", MELEE_SLAYER_PARAMS, "3.6.0")


func test_precision_target_resolves_in_the_voidspace_stalkers_section() -> void:
	_assert_entry("Precision Target", "Utility Buff", PRECISION_TARGET_PARAMS, "3.6.0")


func test_ravage_resolves_in_the_voidspace_stalkers_section() -> void:
	_assert_entry("Ravage", "Ravage", RAVAGE_PARAMS, "3.6.0")


func test_regeneration_aura_resolves_in_the_voidspace_stalkers_section() -> void:
	_assert_entry("Regeneration Aura", "Regeneration", REGENERATION_AURA_PARAMS, "3.6.0")


func test_shadowborn_resolves_in_the_voidspace_stalkers_section() -> void:
	_assert_entry("Shadowborn", "Ranged Shrouding", SHADOWBORN_PARAMS, "3.6.0")


## CONTROL (passes with and without the change): a book that always had its own Bounding entry keeps
## answering from it, with the same knobs.
func test_control_bounding_in_eternal_dynasty_is_unchanged() -> void:
	var entry := RulesRegistry.lookup("gf", "eternal_dynasty", "Bounding")
	assert_str(str(entry.get("primitive", ""))).is_equal("Bounding")
	assert_dict(entry.get("params", {}) as Dictionary).is_equal(BOUNDING_PARAMS)
	assert_str(str(entry.get("book_version", ""))).is_equal("3.5.3")
