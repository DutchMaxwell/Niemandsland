extends GdUnitTestSuite
## Rules 3.6 wave, row MOR-13 (lead ruling D-SPELL-LOS): the friendly casters that boost a cast and the
## enemy casters that resist it count within 18" of the caster, whether the caster's unit sees them or
## not. Rules 3.5 (the frozen EPOCH_72 leg) still asked for a line of sight; those cases stay as
## `_at_epoch_72` controls. The pool builder is SoloController._aura_casters, read here on a bare
## controller (the test/solo_shaken_caster_support_test.gd fixture style, no scene boot) whose sight
## checker sees nobody. The battle-log lines are proven end to end in
## test/e2e/e2e_no_tick_online_cast_test.gd, next to their own `_at_epoch_72` pins.

const INCH_M := 0.0254

var _epoch0: int


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0   # statics leak across gdUnit tests: restore


func _unit(pid: int, uid: String, x_in: float) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = uid
	u.unit_properties = {"player_id": pid, "name": uid, "quality": 4, "defense": 4, "special_rules": ["Caster(2)"]}
	var m := ModelInstance.new()
	m.is_alive = true
	var n: Node3D = auto_free(Node3D.new())
	add_child(n)
	n.global_position = Vector3(x_in * INCH_M, 0, 0)
	m.node = n
	u.models.append(m)
	u.initialize_caster_points()
	return u


## A caster of P2 at the origin, a friendly caster of P2 10" east and an enemy caster of P1 10" west, both
## holding tokens, well inside 18". The sight checker answers "no" for every pair: a wall between all.
func _hidden_table() -> Dictionary:
	var caster := _unit(2, "caster", 0.0)
	var helper := _unit(2, "helper", 10.0)
	var foe := _unit(1, "foe", -10.0)
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {caster.unit_id: caster, helper.unit_id: helper, foe.unit_id: foe}
	var solo: SoloController = auto_free(SoloController.new())
	add_child(solo)
	solo.setup(army, null, null, 1, 2)
	solo.unit_los_checker = func(_a: GameUnit, _b: GameUnit) -> bool: return false
	return {"solo": solo, "caster": caster}


## The unit ids of `slot`'s casters in the caster's boost (own slot) or resist (enemy slot) pool.
func _pool_ids(table: Dictionary, slot: int) -> Array:
	var ids: Array = []
	for h in (table["solo"] as SoloController)._aura_casters(slot, table["caster"], table["caster"]):
		ids.append(((h as Dictionary)["unit"] as GameUnit).unit_id)
	return ids


# Controls first: see the declaration-order note in test/solo_shaken_caster_support_test.gd.
func test_a_hidden_friendly_caster_stays_out_of_the_boost_pool_at_epoch_72() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var ids := _pool_ids(_hidden_table(), 2)
	assert_array(ids).override_failure_message("rules 3.5 needs a line of sight, the hidden helper joined: %s" % str(ids)) \
		.not_contains(["helper"])


func test_a_hidden_enemy_caster_stays_out_of_the_resist_pool_at_epoch_72() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var ids := _pool_ids(_hidden_table(), 1)
	assert_array(ids).override_failure_message("rules 3.5 needs a line of sight, the hidden foe joined: %s" % str(ids)) \
		.not_contains(["foe"])


func test_a_hidden_friendly_caster_joins_the_boost_pool_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var ids := _pool_ids(_hidden_table(), 2)
	assert_array(ids).override_failure_message("rules 3.6: a friendly caster 10\" away boosts unseen, pool: %s" % str(ids)) \
		.contains(["helper"])


func test_a_hidden_enemy_caster_joins_the_resist_pool_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var ids := _pool_ids(_hidden_table(), 1)
	assert_array(ids).override_failure_message("rules 3.6: an enemy caster 10\" away resists unseen, pool: %s" % str(ids)) \
		.contains(["foe"])
