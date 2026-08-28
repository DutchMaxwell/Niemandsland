extends GdUnitTestSuite
## NML-1112: the special-rule lookup matches the EXACT rule name or its parametrised form —
## never a bare prefix. Before this wave `has_special_rule` used `begins_with`, so "Fear" also
## answered true on a "Fearless" unit, "Ambush" on an "Ambush Beacon" and "Caster" on a
## "Caster Group" — and every gate built on it fired for the wrong rule.


func _unit(rules: Array) -> GameUnit:
	var gu := GameUnit.new()
	gu.unit_properties["special_rules"] = rules
	return gu


func _model(rules: Array) -> ModelInstance:
	var mi := ModelInstance.new()
	mi.properties["special_rules"] = rules
	return mi


# ===== the collision the ticket names =====

func test_fearless_is_not_fear() -> void:
	assert_bool(_unit(["Fearless"]).has_special_rule("Fear")) \
		.override_failure_message("'Fearless' is a rule of its own — a 'Fear' query must say no") \
		.is_false()
	assert_bool(_unit(["Fearless"]).has_special_rule("Fearless")).is_true()


func test_parametrised_form_still_matches_its_base_name() -> void:
	assert_bool(_unit(["Tough(3)"]).has_special_rule("Tough")) \
		.override_failure_message("'Tough(3)' IS the Tough rule — the parametrised form must match") \
		.is_true()
	assert_bool(_unit(["Fear(2)"]).has_special_rule("Fear")).is_true()
	assert_bool(_unit(["Caster(1)"]).has_special_rule("Caster")).is_true()
	# The full parametrised string is a legal query too (core_selfplay_caster_test relies on it).
	assert_bool(_unit(["Caster(1)"]).has_special_rule("Caster(1)")).is_true()


# ===== the same-family names the audit found in the two list pools =====

func test_longer_same_family_names_never_answer_for_the_base_rule() -> void:
	assert_bool(_unit(["Caster Group"]).has_special_rule("Caster")).is_false()
	assert_bool(_unit(["Ambush Beacon"]).has_special_rule("Ambush")).is_false()
	assert_bool(_unit(["Reanimation Aura"]).has_special_rule("Reanimation")).is_false()
	assert_bool(_unit(["Unpredictable Fighter"]).has_special_rule("Unpredictable")).is_false()
	assert_bool(_unit(["Counter-Attack"]).has_special_rule("Counter")).is_false()
	assert_bool(_unit(["Shred in Melee"]).has_special_rule("Shred")).is_false()
	assert_bool(_unit(["Versatile Reach Aura"]).has_special_rule("Versatile Reach")).is_false()
	assert_bool(_unit(["Takedown Shot"]).has_special_rule("Takedown")).is_false()


# ===== the " (spell)" grant suffix stays visible (main.SOLO_SPELL_GRANT_SUFFIX) =====

func test_spell_granted_rules_still_answer_for_their_base_name() -> void:
	assert_bool(_unit(["Relentless (spell)"]).has_special_rule("Relentless")) \
		.override_failure_message("a spell-granted rule is the rule — the ' (spell)' mark is a suffix") \
		.is_true()
	assert_bool(_unit(["Rapid Rush (spell)"]).has_special_rule("Rapid Rush")).is_true()
	# ... but the suffix must not turn the grant into a licence for a shorter name.
	assert_bool(_unit(["Fearless (spell)"]).has_special_rule("Fear")).is_false()


# ===== dictionary-shaped rules take the same path =====

func test_dictionary_rules_match_exactly_too() -> void:
	assert_bool(_unit([{"name": "Fearless"}]).has_special_rule("Fear")).is_false()
	assert_bool(_unit([{"name": "Tough(3)"}]).has_special_rule("Tough")).is_true()


# ===== ModelInstance carries the same semantics =====

func test_model_instance_matches_the_same_way() -> void:
	assert_bool(_model(["Fearless"]).has_special_rule("Fear")) \
		.override_failure_message("ModelInstance must not drift from GameUnit") \
		.is_false()
	assert_bool(_model(["Tough(3)"]).has_special_rule("Tough")).is_true()
	assert_bool(_model(["Caster Group"]).has_special_rule("Caster")).is_false()


# ===== the shared matcher itself =====

func test_rule_name_matches_is_the_single_truth() -> void:
	assert_bool(GameUnit.rule_name_matches("Tough(3)", "Tough")).is_true()
	assert_bool(GameUnit.rule_name_matches("Tough", "Tough")).is_true()
	assert_bool(GameUnit.rule_name_matches(" Tough ", "Tough")).is_true()
	assert_bool(GameUnit.rule_name_matches("Toughness", "Tough")).is_false()
	assert_bool(GameUnit.rule_name_matches("Fearless", "Fear")).is_false()
	assert_bool(GameUnit.rule_name_matches("Fear", "Fearless")).is_false()
	assert_bool(GameUnit.rule_name_matches("", "Fear")).is_false()


# ===== the weapon-rule reader shares the semantics =====

func _w(rules: Array) -> Dictionary:
	return {"name": "Blade", "range_value": 12, "attacks": 2, "count": 1, "special_rules": rules}


func test_weapon_rule_reader_matches_exactly() -> void:
	var marked := AiShooting.profiles_in_range([_w(["Rending Mark", "Unstoppable in Melee"])], 6.0)
	assert_bool(bool(marked[0]["rending"])) \
		.override_failure_message("'Rending Mark' is not Rending — the weapon reader must say no") \
		.is_false()
	assert_bool(bool(marked[0]["unstoppable"])).is_false()
	var plain := AiShooting.profiles_in_range([_w(["Rending", "Unstoppable"])], 6.0)
	assert_bool(bool(plain[0]["rending"])).is_true()
	assert_bool(bool(plain[0]["unstoppable"])).is_true()
