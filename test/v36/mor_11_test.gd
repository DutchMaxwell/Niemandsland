extends GdUnitTestSuite
## Rules 3.6 row MOR-11: the battle simulation's morale ESTIMATE reads the same Tough(9)+ Hero
## aura the table's morale test uses (friendly, alive, not Shaken, within 6" base edge to base
## edge). Below EPOCH_73_V36 the estimate keeps the unit's own Quality, unchanged. The core twin
## is core/nml-core/src/tests/sim/v36_mor_11.rs.

const IN2M := 0.0254

var _epoch0: int


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch
	# The expected-morale read below is deterministic only with the aifix dither OFF (a static another suite may leave on).
	BattleSim.morale_by_probability = false
	BattleSim._morale_round = 1


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0   # statics leak across gdUnit tests — restore


## A single-model unit of `quality` carrying `rules` at `position`.
func _unit(pid: int, unit_name: String, position: Vector3, quality: int, rules: Array) -> GameUnit:
	var unit := GameUnit.new()
	unit.unit_id = unit_name.to_lower().replace(" ", "_")
	unit.unit_properties = {"player_id": pid, "name": unit_name, "quality": quality,
		"defense": 4, "special_rules": rules}
	var model := ModelInstance.new()
	model.is_alive = true
	model.wounds_current = 1
	model.unit = unit
	var node := Node3D.new()
	add_child(node)
	node.global_position = position
	model.node = node
	unit.models.append(model)
	unit.source_type = "opr"
	unit.source_data = OPRApiClient.OPRUnit.new()
	return unit


## The captured snapshot of the squad with a Q3 Tough(9) Hero at `hero_pos`.
func _squad_state(hero_pos: Vector3) -> Dictionary:
	var squad := _unit(2, "Squad", Vector3.ZERO, 4, [])
	var hero := _unit(2, "Warlord", hero_pos, 3, ["Hero", "Tough(9)"])
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {squad.unit_id: squad, hero.unit_id: hero}
	return BattleSim.capture(army)["units"]["squad"]


func test_a_nearby_tough_hero_lifts_the_estimate_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var su := _squad_state(Vector3(7 * IN2M, 0, 0))
	assert_int(int(su.get("aura_quality", 0))).is_equal(3)
	assert_bool(BattleSim._morale_fails_expected(su)).is_false()


func test_the_own_quality_estimate_holds_at_epoch_72() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var su := _squad_state(Vector3(7 * IN2M, 0, 0))
	assert_bool(su.has("aura_quality")).is_false()
	assert_bool(BattleSim._morale_fails_expected(su)).is_true()


func test_a_hero_seven_inches_away_does_not_lift_the_estimate() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var su := _squad_state(Vector3(9 * IN2M, 0, 0))
	assert_bool(BattleSim._morale_fails_expected(su)).is_true()


func test_a_shaken_hero_does_not_lift_the_estimate() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var squad := _unit(2, "Squad", Vector3.ZERO, 4, [])
	var hero := _unit(2, "Warlord", Vector3(7 * IN2M, 0, 0), 3, ["Hero", "Tough(9)"])
	hero.is_shaken = true
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {squad.unit_id: squad, hero.unit_id: hero}
	var su: Dictionary = BattleSim.capture(army)["units"]["squad"]
	assert_bool(BattleSim._morale_fails_expected(su)).is_true()


## Control: a joined Hero is no aura — the estimate keeps the unit's own Q4 at both epochs.
func test_a_joined_hero_is_no_aura() -> void:
	for epoch in [AiActRecorder.EPOCH_72_PLAYTEST_RULES, AiActRecorder.EPOCH_73_V36]:
		AiActRecorder.rules_epoch = epoch
		var squad := _unit(2, "Squad", Vector3.ZERO, 4, [])
		var hero := _unit(2, "Warlord", Vector3(7 * IN2M, 0, 0), 3, ["Hero", "Tough(9)"])
		squad.unit_properties["attached_heroes"] = [hero]
		hero.unit_properties["attached_to"] = squad
		var army: OPRArmyManager = auto_free(OPRArmyManager.new())
		army.game_units = {squad.unit_id: squad, hero.unit_id: hero}
		var su: Dictionary = BattleSim.capture(army)["units"]["squad"]
		assert_bool(su.has("aura_quality")).is_false()
		assert_bool(BattleSim._morale_fails_expected(su)).is_true()
