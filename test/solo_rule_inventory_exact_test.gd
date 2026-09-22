extends GdUnitTestSuite
## The AI handoff inventory classifies rule names by EXACT name (NML-1112, GameUnit.rule_name_matches),
## never by prefix: "Fearsome Made-Up Rule" is not "Fear", so it must land in the NOT automated class,
## while the rated form "Fear(2)" and the spell-grant form "Fear (spell)" still count as Fear.


func test_a_name_that_only_starts_with_a_modeled_token_is_not_resolved() -> void:
	var inv := SoloController.classify_rule_inventory(["Fearsome Made-Up Rule"], ["Fear"], [])
	assert_dict(inv["unknown"]).contains_key_value("Fearsome Made-Up Rule", 1)
	assert_dict(inv["resolved"]).is_empty()


func test_rated_and_spell_forms_of_a_modeled_rule_stay_resolved() -> void:
	var inv := SoloController.classify_rule_inventory(["Fear(2)", "Fear (spell)", "Tough(3)"], ["Fear", "Tough"], [])
	assert_dict(inv["unknown"]).is_empty()
	assert_dict(inv["resolved"]).contains_key_value("Fear", 2)
	assert_dict(inv["resolved"]).contains_key_value("Tough", 1)
