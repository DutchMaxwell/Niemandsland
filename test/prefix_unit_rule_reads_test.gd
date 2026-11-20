extends GdUnitTestSuite
## NML-1112 exact rule names for UNIT-level reads of the solo AI (Plan H follow-up of #3156): the hold-only gate (Immobile / Artillery) and the Counter strike-first gate matched by PREFIX.
## Counter keeps its two data aliases ("Counter-Attack", "Counter in Melee": the Rust core stamps them by name, e2e_counter_attack_alias_test) but a label that only GRANTS the rule
## ("Counter in Melee Aura", "Counter in Melee Buff", "Counter-Attack Aura") is no bearer. Immobile / Artillery have no extending name today; the Rust twin (menu.rs `forces_hold`)
## is exact now as well. No epoch: no recorded unit carries such a label, and these reads steer the AI's menu, they roll nothing.
## RED: put the `begins_with` reads back -> the label rows below count as the rule.

var _epoch0: int


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0
	RulesRegistry.reset_cache()


func test_the_hold_only_rule_reads_the_exact_names() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36 - 1   # below 3.6 Artillery holds too
	assert_str(SoloController.hold_only_rule(["Immobile"])).is_equal("Immobile")
	assert_str(SoloController.hold_only_rule([" Artillery"])).is_equal("Artillery")
	assert_str(SoloController.hold_only_rule(["Immobile (spell)"])).override_failure_message("a grant mark is the rule").is_equal("Immobile")
	for label in ["Immobile Mark", "Immobile Aura", "Artillery Mark", "Artillery Aura"]:
		assert_str(SoloController.hold_only_rule([label])).override_failure_message("%s only labels a grant" % label).is_empty()


func _unit_with(rules: Array) -> GameUnit:
	var gu := GameUnit.new()
	gu.unit_properties = {"player_id": 1, "name": "Squad", "quality": 4, "defense": 4, "special_rules": rules, "game_system": "gf", "faction_folder": "testfac"}
	return gu


## The entry's `hold_only` param decides only for a real bearer; a label carrier keeps the default.
func test_the_hold_only_param_reads_the_exact_names() -> void:
	RulesRegistry.reset_cache()
	RulesRegistry._cache["gf"] = {"factions": {"testfac": {
		"Immobile": {"primitive": "Immobile", "rated": false, "book_version": "3.5.3", "params": {"hold_only": false}},
		"Artillery": {"primitive": "Artillery", "rated": false, "book_version": "3.5.3", "params": {"hold_only": false}}}}, "common": {}}
	assert_bool(SoloController.hold_only_param(_unit_with(["Immobile"]))).override_failure_message("the bearer reads its entry").is_false()
	assert_bool(SoloController.hold_only_param(_unit_with(["Artillery"]))).is_false()
	for label in ["Immobile Mark", "Artillery Aura"]:
		assert_bool(SoloController.hold_only_param(_unit_with([label]))).override_failure_message("%s is no bearer: the default stands" % label).is_true()


func test_the_counter_gate_keeps_its_aliases_and_drops_the_grant_labels() -> void:
	for yes in ["Counter", "Counter (spell)", "Counter-Attack", "Counter in Melee"]:
		assert_bool(SoloController.has_counter([], [yes])).override_failure_message("%s is the rule or its alias" % yes).is_true()
	for no in ["Counter in Melee Aura", "Counter in Melee Buff", "Counter-Attack Aura", "Countermeasure"]:
		assert_bool(SoloController.has_counter([], [no])).override_failure_message("%s only labels a grant" % no).is_false()
