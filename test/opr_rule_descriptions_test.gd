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


# =============================================================================
# NML-1126: rule-text provenance — a failed fetch must be LOUD and STAMPED
# =============================================================================
## The descriptions this suite exercises above exist only because a live army-forge fetch
## succeeded. When it does not, the old code did `push_warning` + `return` and the game played
## on with `rule_descriptions` empty — so the description-driven move modifiers
## (movement_range_controller.gd) were silently off and the row was banked anyway (NML-1114).
## These two tests hold the new contract: any failure on the fetch path flips
## `rule_text_ok` to false for the rest of the process, and a fetch that really delivered
## text stamps the source as "api".


func test_a_failed_rule_text_fetch_stamps_rule_text_not_ok() -> void:
	OPRApiClientScript.reset_rule_text_stamp()
	assert_bool(OPRApiClientScript.rule_text_ok).is_true()   # the clean reading to start from

	# STUB THE FETCH TO FAIL, without a network and without touching the API: an HTTPRequest
	# that is not inside the tree answers request() with ERR_UNCONFIGURED (measured: 3), which
	# is exactly the `error != OK` branch of _fetch_common_rules. The push_error it raises is
	# the point of the change and does not fail the test (gdUnit reports 0 errors for it).
	var client = auto_free(OPRApiClientScript.new())
	client._book_http_request = auto_free(HTTPRequest.new())
	var army = OPRApiClientScript.OPRArmy.new()
	army.army_id = "w7qor7b2kuifcyvk"
	army.game_system_abbrev = "gf"
	await client._fetch_common_rules(army)

	assert_bool(army.rule_descriptions.is_empty()).is_true()      # nothing arrived, as expected
	assert_bool(OPRApiClientScript.rule_text_ok).is_false()       # ... and the process now SAYS so
	OPRApiClientScript.reset_rule_text_stamp()


func test_descriptions_that_really_land_stamp_the_source_as_api() -> void:
	OPRApiClientScript.reset_rule_text_stamp()
	assert_str(OPRApiClientScript.rule_text_source).is_equal("none")

	var client = auto_free(OPRApiClientScript.new())
	var army = OPRApiClientScript.OPRArmy.new()
	# An answer with no usable text leaves the source alone — a 200 is not the same as text.
	client._extract_rule_descriptions(army, {"specialRules": [{"name": "Shielded", "description": ""}]})
	assert_str(OPRApiClientScript.rule_text_source).is_equal("none")

	client._merge_common_descriptions(army, {"rules": [{"name": "Tough", "description": "extra hits"}]})
	assert_str(OPRApiClientScript.rule_text_source).is_equal("api")
	assert_bool(OPRApiClientScript.rule_text_ok).is_true()   # a success never flips the alarm
	OPRApiClientScript.reset_rule_text_stamp()
