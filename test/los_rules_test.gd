extends GdUnitTestSuite
## Asgard Height-category derivation (LosRules.model_height_category) from a model's
## Tough + Hero/Fear, per the Asgard Age of Fantasy standard (p.5).


func _model(tough: int, rules: Array = []) -> ModelInstance:
	var m := ModelInstance.new()
	m.properties["tough"] = tough
	m.properties["special_rules"] = rules
	return m


func test_infantry_without_tough_is_h2() -> void:
	assert_int(LosRules.model_height_category(_model(1))).is_equal(2)


func test_tough3_is_h3_but_hero_tough3_is_h2() -> void:
	assert_int(LosRules.model_height_category(_model(3))).is_equal(3)
	assert_int(LosRules.model_height_category(_model(3, ["Hero"]))).is_equal(2)


func test_tough6_is_h4_but_hero_tough6_is_h3() -> void:
	assert_int(LosRules.model_height_category(_model(6))).is_equal(4)
	assert_int(LosRules.model_height_category(_model(6, ["Hero"]))).is_equal(3)


func test_large_monster_tough12_is_h5() -> void:
	assert_int(LosRules.model_height_category(_model(12))).is_equal(5)


func test_titan_needs_tough18_and_fear() -> void:
	# Fear is parsed as "Fear(3)"; has_special_rule matches by prefix.
	assert_int(LosRules.model_height_category(_model(18, ["Fear(3)"]))).is_equal(6)
	# Tough 18 without Fear is only a Large Monster (H5).
	assert_int(LosRules.model_height_category(_model(18))).is_equal(5)


func test_null_model_defaults_to_h2() -> void:
	assert_int(LosRules.model_height_category(null)).is_equal(2)
