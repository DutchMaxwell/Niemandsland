extends GdUnitTestSuite
## G4-T6 (0.3.15, rules 3.6): the Surge alias line names a distance condition only when
## the alias really carries one. A plain alias pays at any range from EPOCH_73_V36, so a
## 3" shot must not claim "from over 9\""; a gated alias keeps its band, and epoch 72 keeps
## the recorded wording. The profile comes from the live AiEv stamp and the table's alias
## marker, never from a hand-built dictionary.

var _epoch_before := 0


func before_test() -> void:
	_epoch_before = AiActRecorder.rules_epoch
	RulesRegistry.reset_cache()


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch_before
	RulesRegistry.reset_cache()


func _unit(name: String, rules: Array, system: String, faction: String) -> GameUnit:
	var u: GameUnit = auto_free(GameUnit.new())
	u.unit_id = "g4t6_%s" % name
	u.unit_properties = {"player_id": 2, "name": name, "quality": 4, "defense": 4,
		"special_rules": rules, "game_system": system, "faction_folder": faction}
	var m := ModelInstance.new()
	m.is_alive = true
	u.models.append(m)
	return u


## The live shooting build: AiEv stamps the entry's params, then the table marks the alias name.
func _log_text(epoch: int, unit: GameUnit, dist_in: float) -> String:
	AiActRecorder.rules_epoch = epoch
	var main: Node = auto_free(preload("res://scripts/main.gd").new())
	main.battle_log = auto_free(BattleLog.new())
	var profile := {"name": "Rifle", "attacks": 8, "ap": 0, "range": 24, "rules": []}
	var profiles: Array = [profile]
	AiEv.stamp_sergeant(profiles, unit)
	main._solo_stamp_alias_markers(unit, profiles)
	await main._solo_hits([6, 3, 2, 1], 4, profile, dist_in)
	var text := ""
	for e in main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


## RED on main: the plain Lucky shot at 3" pays and logs a 9" gate it does not have.
func test_a_plain_alias_at_three_inches_does_not_claim_over_nine() -> void:
	var text := await _log_text(AiActRecorder.EPOCH_73_V36,
		_unit("Lucky", ["Lucky"], "aof", "halflings"), 3.0)
	assert_str(text) \
		.override_failure_message("the plain alias paid but never named itself — got: %s" % text.strip_edges()) \
		.contains("Lucky")
	assert_str(text) \
		.override_failure_message("the 3\" plain-alias shot still claims a 9\" gate — got: %s" % text.strip_edges()) \
		.not_contains("over 9\"")


## Epoch-72 control: the recorded line stands byte-exact.
func test_epoch_72_keeps_the_recorded_over_nine_line() -> void:
	var text := await _log_text(AiActRecorder.EPOCH_72_PLAYTEST_RULES,
		_unit("Lucky", ["Lucky"], "aof", "halflings"), 3.0)
	assert_str(text) \
		.override_failure_message("below 73 the recorded 9\" wording must stay — got: %s" % text.strip_edges()) \
		.contains("Lucky") \
		.contains("from over 9\"")


## Gated control: Devout Boost (Skirmish book) keeps its 9" condition, so its band stays at 73.
func test_a_gated_alias_keeps_its_over_nine_line() -> void:
	var text := await _log_text(AiActRecorder.EPOCH_73_V36,
		_unit("Devout", ["Devout", "Devout Boost"], "gff", "blessed_sisters"), 10.0)
	assert_str(text) \
		.override_failure_message("the gated alias lost its 9\" band — got: %s" % text.strip_edges()) \
		.contains("Devout") \
		.contains("from over 9\"")
