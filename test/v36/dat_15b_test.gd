extends GdUnitTestSuite
## DAT-15b (0.3.15, rules 3.6): the orcs' own "Ravage Aura" entry hands its rating out too.
## The faction-level entry overrides the common one on lookup, so the 3.6 common grant only reaches
## orc units once the faction entry carries it as well. From EPOCH_73_V36 the aura names its grant
## from the map, so the unit and every attached Hero see "Ravage(+1)"; below the epoch the strip
## fallback stays byte-identical and hands out the bare "Ravage".

const SYSTEM := "aof"
const FACTION := "orcs"


func before_test() -> void:
	RulesRegistry.reset_cache()


func after_test() -> void:
	RulesRegistry.reset_cache()


func _member(rules: Array) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = "u_%d" % rules.size()
	u.unit_properties = {"player_id": 1, "name": "M", "quality": 4, "defense": 4,
		"special_rules": rules, "game_system": SYSTEM, "faction_folder": FACTION}
	var m := ModelInstance.new()
	m.is_alive = true
	u.models.append(m)
	return u


## The import shape: the host carries the aura, the joined hero carries none of it.
func _aura_unit() -> Array:
	var host := _member(["Ravage Aura"])
	var hero := _member(["Hero"])
	host.unit_properties["attached_heroes"] = [hero]
	return [host, hero]


func _expand(members: Array) -> void:
	var host: GameUnit = members[0]
	OPRArmyManager.expand_auras_of([host], {host: host})


func _rules_of(unit: GameUnit) -> Array:
	return (unit.get_special_rules() as Array).duplicate()


func test_epoch_73_grants_the_rated_rule_to_every_member() -> void:
	var epoch0: int = AiActRecorder.rules_epoch
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var members := _aura_unit()
	_expand(members)
	for m in members:
		var gu := m as GameUnit
		var rules := _rules_of(gu)
		assert_bool(rules.has("Ravage(+1)")).override_failure_message(
			"%s did not receive 'Ravage(+1)': %s" % [gu.unit_properties.get("name", "?"), rules]).is_true()
		assert_bool(rules.has("Ravage")).override_failure_message(
			"%s kept the unrated 'Ravage': %s" % [gu.unit_properties.get("name", "?"), rules]).is_false()
		assert_int(AiEv.unit_rating(gu, "Ravage")).override_failure_message(
			"%s reads no rating on Ravage" % gu.unit_properties.get("name", "?")).is_equal(1)
	AiActRecorder.rules_epoch = epoch0


func test_epoch_72_keeps_the_bare_grant() -> void:
	var epoch0: int = AiActRecorder.rules_epoch
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var members := _aura_unit()
	_expand(members)
	for m in members:
		var gu := m as GameUnit
		var rules := _rules_of(gu)
		assert_bool(rules.has("Ravage")).override_failure_message(
			"%s lost the bare 'Ravage' below the epoch: %s" % [gu.unit_properties.get("name", "?"), rules]).is_true()
		assert_bool(rules.has("Ravage(+1)")).override_failure_message(
			"%s gained the rating below the epoch: %s" % [gu.unit_properties.get("name", "?"), rules]).is_false()
		assert_int(AiEv.unit_rating(gu, "Ravage")).is_equal(0)
	AiActRecorder.rules_epoch = epoch0
