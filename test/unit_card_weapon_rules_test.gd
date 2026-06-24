extends GdUnitTestSuite
## Verifies the unit card shows weapon special rules for dictionary-format weapons
## (the format remote/networked units carry), so enemy weapon rules are visible in MP.

const UnitCardScript := preload("res://scripts/unit_card.gd")


func _card():
	return auto_free(UnitCardScript.new())


func test_dict_weapon_shows_string_rules() -> void:
	var card = _card()
	var w := {"name": "Rifle", "range": 24, "attacks": 1, "specialRules": ["AP(1)", "Blast(3)"]}
	var s: String = card._format_dict_weapon(w)
	assert_str(s).contains("Rifle")
	assert_str(s).contains("AP(1)")
	assert_str(s).contains("Blast(3)")


func test_dict_weapon_shows_object_rules() -> void:
	var card = _card()
	var w := {"name": "Cannon", "range": 30, "attacks": 2,
		"specialRules": [{"name": "AP", "rating": 2}, {"name": "Deadly", "rating": 3}]}
	var s: String = card._format_dict_weapon(w)
	assert_str(s).contains("AP(2)")
	assert_str(s).contains("Deadly(3)")


func test_dict_weapon_snake_case_key() -> void:
	var card = _card()
	var w := {"name": "Blade", "range": 0, "attacks": 3, "special_rules": ["Rending"]}
	var s: String = card._format_dict_weapon(w)
	assert_str(s).contains("Rending")


func test_dict_weapon_without_rules_is_clean() -> void:
	var card = _card()
	var w := {"name": "Pistol", "range": 12, "attacks": 1}
	var s: String = card._format_dict_weapon(w)
	assert_str(s).contains("Pistol")
	assert_str(s).not_contains("()")


# ===== #74: an Aura (or any rule) whose text grants another rule shows that rule's description =====

func test_aura_rule_cascade_shows_granted_rule_description() -> void:
	var card = _card()
	var am: OPRArmyManager = auto_free(OPRArmyManager.new())
	am.rule_descriptions = {
		"Fearless": "This model passes morale tests on a 4+.",
		"Inspiring": "Friendly units within 6\" gain Fearless.",
	}
	card.army_manager = am
	var cascade: String = card._referenced_rules_cascade(am.rule_descriptions["Inspiring"], "Inspiring")
	# The granted "depth" rule + its explanation are revealed.
	assert_str(cascade).contains("Fearless")
	assert_str(cascade).contains("passes morale tests")


func test_cascade_excludes_hovered_rule_and_its_base() -> void:
	var card = _card()
	var am: OPRArmyManager = auto_free(OPRArmyManager.new())
	am.rule_descriptions = {"Tough": "This model can take extra wounds."}
	card.army_manager = am
	# A Tough(3) whose own text mentions "Tough" must not re-list Tough as a depth rule.
	var cascade: String = card._referenced_rules_cascade("This model has Tough and is hard to kill.", "Tough(3)")
	assert_str(cascade).is_empty()
