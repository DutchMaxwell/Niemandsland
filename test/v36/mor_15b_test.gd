extends GdUnitTestSuite
## Rules 3.6 wave, row MOR-15b: from EPOCH_73_V36 the AI caster prices its boost and the
## enemy's interference at its REAL cast target (the same casting net the human cast block
## folds), not the blind 4+. Below 73 every plan stays exactly as before (the core's
## `priced_net = 0`). Pure unit test: the registry/map entries build the units; no scene boot.
## The core twin is `casting_net_of` + `cast_phase` in core/nml-core/src/sim.rs (MOR-15).

const SYSTEM := "gf"
const FACTION := "eternal_dynasty"
const EV := 2.0
const POOL := 8

var _epoch0: int


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0   # statics leak across gdUnit tests — restore
	RulesRegistry.reset_cache()


## A real GameUnit at `pos` (metres); `weapon_rules` ride the weapon list, `rules` the unit's
## own special rules. The casting_mod value is never hand-written — the registry supplies it.
func _unit(pid: int, unit_name: String, pos: Vector3, rules: Array = [],
		weapon_rules: Array = [], faction: String = FACTION) -> GameUnit:
	var unit := GameUnit.new()
	unit.unit_id = unit_name.to_lower().replace(" ", "_")
	unit.unit_properties = {"player_id": pid, "name": unit_name, "quality": 4, "defense": 4,
		"special_rules": rules, "game_system": SYSTEM, "faction_folder": faction}
	var model := ModelInstance.new()
	model.is_alive = true
	model.wounds_current = 1
	model.unit = unit
	var node := Node3D.new()
	add_child(node)
	node.global_position = pos
	model.node = node
	unit.models.append(model)
	var opr := OPRApiClient.OPRUnit.new()
	if not weapon_rules.is_empty():
		var w := OPRApiClient.OPRWeapon.new()
		w.name = "Rod"
		w.range_value = 12
		w.attacks = 1
		w.special_rules.assign(weapon_rules)
		opr.weapons.append(w)
	unit.source_type = "opr"
	unit.source_data = opr
	return unit


func _controller(units: Array) -> SoloController:
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	for u in units:
		army.game_units[(u as GameUnit).unit_id] = u
	army.current_round = 1
	var solo: SoloController = auto_free(SoloController.new())
	add_child(solo)
	solo.setup(army, null, null, 1, 2)
	return solo


## The real map entry of a friendly utility buff, in the exact record shape the live
## token placement writes (main.gd `_solo_record_spell_mod`).
func _buff_record(unit: GameUnit, rule: String) -> void:
	var entry := RulesRegistry.lookup(SYSTEM, FACTION, rule)
	var params: Dictionary = entry.get("params", {})
	unit.unit_properties["spell_records"] = [{
		"spell": rule, "hit_mod": 0, "def_mod": 0,
		"casting_mod": int(params.get("casting_mod", 0)), "morale_mod": 0,
		"range_in": 0, "advance_in": 0, "rush_in": 0,
		"grants_rule": "", "scope": "", "beneficiary": "", "duration": "round"}]


func test_at_73_a_casting_buff_prices_fewer_boost_tokens() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var plain := _unit(1, "Plain", Vector3.ZERO, ["Caster(1)"])
	var buffed := _unit(1, "Buffed", Vector3.ZERO, ["Caster(1)"])
	_buff_record(buffed, "Casting Buff")
	var solo := _controller([plain, buffed])
	var plain_target := solo.caster_cast_target(plain, true)
	var buffed_target := solo.caster_cast_target(buffed, true)
	assert_int(plain_target).override_failure_message("a plain caster plans at 4+").is_equal(4)
	assert_int(buffed_target).override_failure_message(
		"the +1 Casting Buff must price the plan at 3+").is_equal(3)
	var plain_boost := AiSpell.plan_boost(EV, POOL, 0, plain_target)
	var buffed_boost := AiSpell.plan_boost(EV, POOL, 0, buffed_target)
	var boost_msg := "the buffed caster must buy FEWER boost tokens (%d vs %d)" % [buffed_boost, plain_boost]
	assert_int(buffed_boost).override_failure_message(boost_msg).is_less(plain_boost)
	# The same priced target feeds the enemy's counter: a higher base target costs more
	# interference tokens than the buffed 3+.
	var plain_inter := AiSpell.plan_interference(EV, POOL, 0, plain_target)
	var buffed_inter := AiSpell.plan_interference(EV, POOL, 0, buffed_target)
	var inter_msg := "the interference plan must move with the priced target (%d vs %d)" % [buffed_inter, plain_inter]
	assert_int(buffed_inter).override_failure_message(inter_msg).is_not_equal(plain_inter)


func test_at_73_a_weapon_borne_amplifier_prices_the_same_net() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var plain := _unit(1, "Plain", Vector3.ZERO, ["Caster(1)"])
	var amp := _unit(1, "Amplified", Vector3.ZERO, ["Caster(1)"], ["Spell Amplifier"])
	var solo := _controller([plain, amp])
	assert_int(solo.caster_cast_target(amp, true)).override_failure_message(
		"the weapon-borne +1 is part of the same net").is_equal(3)
	assert_int(solo.caster_cast_target(plain, true)).is_equal(4)


func test_at_73_a_spell_conduit_prices_the_same_net() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var caster := _unit(1, "Caster", Vector3.ZERO, ["Caster(1)"])
	var conduit := _unit(1, "Conduit", Vector3(0.1, 0.0, 0.0), ["Spell Conduit"], [], "blessed_sisters")
	var solo := _controller([caster, conduit])
	assert_int(solo.caster_cast_target(caster, true)).override_failure_message(
		"a friendly Spell Conduit within range is part of the same net").is_equal(3)


func test_at_72_both_price_blind_as_before() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var plain := _unit(1, "Plain", Vector3.ZERO, ["Caster(1)"])
	var buffed := _unit(1, "Buffed", Vector3.ZERO, ["Caster(1)"])
	_buff_record(buffed, "Casting Buff")
	var solo := _controller([plain, buffed])
	var plain_target := solo.caster_cast_target(plain, true)
	var buffed_target := solo.caster_cast_target(buffed, true)
	assert_int(plain_target).is_equal(4)
	assert_int(buffed_target).override_failure_message(
		"below 73 the planner stays blind: 4+ for both").is_equal(4)
	assert_int(AiSpell.plan_boost(EV, POOL, 0, buffed_target)).is_equal(
		AiSpell.plan_boost(EV, POOL, 0, plain_target))


func test_the_human_target_still_folds_below_73() -> void:
	# Pattern 12: the epoch gate is PLANNER-only. The human resolver always folded the
	# casting net, so its target must not move when the planner goes blind.
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var buffed := _unit(1, "Buffed", Vector3.ZERO, ["Caster(1)"])
	_buff_record(buffed, "Casting Buff")
	var solo := _controller([buffed])
	assert_int(solo.caster_cast_target(buffed, true)).override_failure_message(
		"the planner is blind below 73").is_equal(4)
	assert_int(solo.caster_cast_target(buffed)).override_failure_message(
		"the human target still folds the +1 below 73").is_equal(3)
