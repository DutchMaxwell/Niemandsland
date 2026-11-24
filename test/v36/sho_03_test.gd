extends GdUnitTestSuite
## Rules 3.6 wave, row SHO-03: Quick Throw is the successor of Quick Readjustment. A bearer's Indirect
## weapons ignore line of sight even when the unit did NOT Hold; the map entry carries the lift as
## `los_needs_hold` false on an Indirect-family entry, which the controller already reads. Seven units
## carry it in the four book sections that carried the old name. The cover waiver is untouched.

const BOOKS := [
	["gf", "human_inquisition"],
	["gf", "ratmen_clans"],
	["aof", "dragon_empire"],
	["aof", "ratmen"],
]


var _epoch0: int


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch
	RulesRegistry.reset_cache()


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0
	RulesRegistry.reset_cache()


## A bare unit of one book section carrying `rules`, with one 24" Indirect weapon.
func _unit(system: String, faction: String, rules: Array) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = "sho03_%s_%s" % [system, faction]
	u.unit_properties = {"player_id": 2, "name": "Bearer", "quality": 4, "defense": 4,
		"special_rules": rules, "game_system": system, "faction_folder": faction}
	var m := ModelInstance.new()
	m.is_alive = true
	u.models.append(m)
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Mortar"
	w.range_value = 24
	w.attacks = 1
	var wr: Array[String] = ["Indirect"]
	w.special_rules = wr
	var src := OPRApiClient.OPRUnit.new()
	var ws: Array[OPRApiClient.OPRWeapon] = [w]
	src.weapons = ws
	u.source_type = "opr"
	u.source_data = src
	return u


func test_the_four_books_resolve_quick_throw_as_an_indirect_entry_without_a_hold() -> void:
	for row in BOOKS:
		var system: String = row[0]
		var faction: String = row[1]
		var where := "%s/%s" % [system, faction]
		var entry := RulesRegistry.lookup(system, faction, "Quick Throw")
		assert_str(str(entry.get("primitive", ""))) \
			.override_failure_message("%s: Quick Throw must be an Indirect entry" % where) \
			.is_equal("Indirect")
		var params: Dictionary = entry.get("params", {})
		assert_bool(params.get("los_needs_hold", true) == false) \
			.override_failure_message("%s: Quick Throw lifts the Hold need" % where).is_true()
		var found: Array = RulesRegistry.unit_rules_of_primitive(_unit(system, faction, ["Quick Throw"]), "Indirect")
		var lifted := false
		for e in found:
			var ep: Dictionary = (e as Dictionary).get("params", {})
			if str((e as Dictionary).get("name", "")) == "Quick Throw" and ep.get("los_needs_hold", true) == false:
				lifted = true
		assert_bool(lifted) \
			.override_failure_message("%s: the bearer's Quick Throw resolves for its section" % where).is_true()


func test_a_moved_quick_throw_bearer_waives_sight_without_holding_at_epoch_73() -> void:
	var u := _unit("gf", "human_inquisition", ["Quick Throw"])
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	assert_bool(SoloController.indirect_ignores_los(u, false)) \
		.override_failure_message("Quick Throw lifts the Hold need: a moved bearer keeps the sight waiver") \
		.is_true()
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	assert_bool(SoloController.indirect_ignores_los(u, false)) \
		.override_failure_message("epoch 72 keeps the 3.5 waiver for every Indirect bearer").is_true()


func test_control_a_moved_plain_indirect_unit_still_needs_sight_at_epoch_73() -> void:
	var u := _unit("gf", "human_inquisition", [])
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	assert_bool(SoloController.indirect_ignores_los(u, false)) \
		.override_failure_message("without Quick Throw a moved Indirect unit still needs a Hold").is_false()
