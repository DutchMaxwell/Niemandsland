extends GdUnitTestSuite
## Auto buff-tokens from special rules (0.3.5.0): on army import, scan special_rules and derive the
## buff tokens to auto-create — curated map + an aura/buff/(+1 -1/re-roll) heuristic, passive rules
## skipped, numbered rules collapsed to the base name, deduped. Pure derivation; the import hook
## then define()s + broadcasts each (idempotent via TokenLibrary.has).


func _names(tokens: Array) -> Array:
	var n: Array = []
	for t in tokens:
		n.append(t.name)
	n.sort()
	return n


func test_curated_rule_creates_token() -> void:
	var t := OPRArmyManager.buff_tokens_from_rules(["Furious"])
	assert_int(t.size()).is_equal(1)
	assert_str(t[0].name).is_equal("Furious")
	assert_bool(t[0].is_counter).is_false()


func test_aura_and_buff_names_qualify() -> void:
	# The HDF army's custom auras aren't in the curated map, but read as aura/buff -> tokens.
	var t := OPRArmyManager.buff_tokens_from_rules(["Hold the Line Boost Aura", "Precision Shooter Buff"])
	assert_array(_names(t)).is_equal(["Hold the Line Boost Aura", "Precision Shooter Buff"])


func test_description_plus_minus_qualifies() -> void:
	# Not in the map, not aura/buff named, but the description grants +1 -> token, effect = desc.
	var t := OPRArmyManager.buff_tokens_from_rules(["Fortified"], {"Fortified": "+1 to Defense in cover"})
	assert_int(t.size()).is_equal(1)
	assert_str(t[0].effect).is_equal("+1 to Defense in cover")


func test_passive_rules_skipped() -> void:
	var t := OPRArmyManager.buff_tokens_from_rules(["Tough(3)", "Hero", "Fast", "Impact(3)", "Caster(2)", "Hold the Line"])
	assert_array(t).is_empty()


func test_numbered_rule_collapses_to_base() -> void:
	var t := OPRArmyManager.buff_tokens_from_rules(["Fear(2)"])
	assert_int(t.size()).is_equal(1)
	assert_str(t[0].name).is_equal("Fear")
	assert_bool(t[0].is_counter).is_true()


func test_dedupes_repeated_rules() -> void:
	var t := OPRArmyManager.buff_tokens_from_rules(["Furious", "Furious", "Furious"])
	assert_int(t.size()).is_equal(1)
