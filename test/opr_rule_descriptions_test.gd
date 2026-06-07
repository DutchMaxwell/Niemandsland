extends GdUnitTestSuite
## Tests the OPR special-rule description integration (army-forge API): game-system
## id mapping, army-book extraction, common-rule merge precedence, and the
## parameterised-rule lookup fallback (Tough(3) -> Tough).

const OPRApiClientScript := preload("res://scripts/opr_api_client.gd")


func test_game_system_id_mapping() -> void:
	assert_int(OPRApiClientScript._game_system_id("gf")).is_equal(2)
	assert_int(OPRApiClientScript._game_system_id("gff")).is_equal(3)
	assert_int(OPRApiClientScript._game_system_id("aof")).is_equal(4)
	assert_int(OPRApiClientScript._game_system_id("aofs")).is_equal(5)
	assert_int(OPRApiClientScript._game_system_id("aofr")).is_equal(6)
	assert_int(OPRApiClientScript._game_system_id("bogus")).is_equal(2)  # default GF


func test_extract_rule_descriptions_from_book() -> void:
	var client = auto_free(OPRApiClientScript.new())
	var army = OPRApiClientScript.OPRArmy.new()
	var book := {"specialRules": [{"name": "Shielded", "description": "+1 to defense rolls."}]}
	client._extract_rule_descriptions(army, book)
	assert_str(army.rule_descriptions.get("Shielded", "")).contains("+1 to defense")


func test_common_rules_do_not_override_army_book() -> void:
	var client = auto_free(OPRApiClientScript.new())
	var army = OPRApiClientScript.OPRArmy.new()
	army.rule_descriptions["Tough"] = "ARMY-SPECIFIC"
	var common := {
		"rules": [{"name": "Tough", "description": "COMMON"}, {"name": "AP", "description": "ignores armor"}],
		"traits": [{"name": "Suppressor", "description": "-1 to hit"}],
	}
	client._merge_common_descriptions(army, common)
	assert_str(army.rule_descriptions["Tough"]).is_equal("ARMY-SPECIFIC")  # army-book wins
	assert_str(army.rule_descriptions["AP"]).contains("ignores armor")     # common added
	assert_str(army.rule_descriptions["Suppressor"]).contains("-1 to hit") # traits merged too


func test_get_rule_description_parameterised_fallback() -> void:
	var army = OPRApiClientScript.OPRArmy.new()
	army.rule_descriptions["Tough"] = "Takes extra hits to kill."
	assert_str(OPRApiClientScript.get_rule_description("Tough(3)", army)).is_equal("Takes extra hits to kill.")
	assert_str(OPRApiClientScript.get_rule_description("Tough", army)).is_equal("Takes extra hits to kill.")
	assert_str(OPRApiClientScript.get_rule_description("Fearless", army)).is_equal("")
	assert_str(OPRApiClientScript.get_rule_description("Tough(3)", null)).is_equal("")
