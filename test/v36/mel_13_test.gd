extends GdUnitTestSuite
## v3.6 row MEL-13: Dodge is Melee Evasion while the unit is not Fatigued. A unit whose MOST models
## carry Dodge costs a melee attacker -1 to hit, but only while the unit is not Fatigued (the plain
## fatigued state; Shaken does not count for a defender). Both systems print the same text, so the gf
## and aof maps carry it as one entry each, on the Melee Evasion primitive. The behaviour is gated on
## EPOCH_73_V36: at epoch 72 a Dodge unit gets no penalty. Plain Melee Evasion keeps its old reading
## (no Fatigued gate, any epoch).

## RED proof (CI red at the RED commit, gdUnit shard 9): https://github.com/DutchMaxwell/Niemandsland/actions/runs/41600834110/job/125799141905
const E2EBoot := preload("res://test/e2e/e2e_boot.gd")

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _epoch_before: int


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_epoch_before = AiActRecorder.rules_epoch
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	RulesRegistry.reset_cache()
	await _runner.simulate_frames(4)


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch_before
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _unit(rules: Array, system: String, faction: String, fatigued: bool = false) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = "mel13_%d" % rules.size()
	u.unit_properties = {"player_id": 2, "name": "Dodger", "quality": 4, "defense": 4,
		"special_rules": rules, "game_system": system, "faction_folder": faction}
	u.is_fatigued = fatigued
	var m := ModelInstance.new()
	m.is_alive = true
	u.models.append(m)
	return u


func _melee_info(target: GameUnit, epoch: int) -> Dictionary:
	AiActRecorder.rules_epoch = epoch
	var striker := _unit([], "gf", "dark_elf_raiders")
	return _main._solo_hit_mod_info(striker, target, 0.0, true)


func test_dodge_resolves_to_the_melee_evasion_primitive_in_both_systems() -> void:
	for pair in [["gf", "dark_elf_raiders"], ["aof", "dark_elves"]]:
		assert_bool(RulesRegistry.has_primitive(pair[0], pair[1], "Dodge")) \
			.override_failure_message("%s / %s: Dodge must resolve to a primitive, not 'apply manually'" % [pair[0], pair[1]]) \
			.is_true()
		assert_str(str(RulesRegistry.lookup(pair[0], pair[1], "Dodge").get("primitive", ""))).is_equal("Melee Evasion")


func test_a_rested_dodge_unit_costs_the_attacker_one_to_hit_at_epoch_73() -> void:
	var info := _melee_info(_unit(["Dodge"], "gf", "dark_elf_raiders"), AiActRecorder.EPOCH_73_V36)
	assert_int(int(info.get("mod", 0))).override_failure_message("rested Dodge: -1 to hit (note: %s)" % info.get("note", "")).is_equal(-1)
	assert_str(str(info.get("note", ""))).contains("Dodge")


func test_a_fatigued_dodge_unit_gives_no_penalty_and_says_so_at_epoch_73() -> void:
	var info := _melee_info(_unit(["Dodge"], "aof", "dark_elves", true), AiActRecorder.EPOCH_73_V36)
	assert_int(int(info.get("mod", 0))).is_equal(0)
	assert_str(str(info.get("note", ""))) \
		.override_failure_message("the no-effect line must name Dodge and Fatigued (note: %s)" % info.get("note", "")) \
		.contains("Dodge: no effect") \
		.contains("Fatigued")


func test_a_dodge_unit_gives_no_penalty_at_epoch_72() -> void:
	var info := _melee_info(_unit(["Dodge"], "gf", "dark_elf_raiders"), AiActRecorder.EPOCH_72_PLAYTEST_RULES)
	assert_int(int(info.get("mod", 0))).is_equal(0)
	assert_str(str(info.get("note", ""))).not_contains("Dodge")


## Control: plain Melee Evasion has no Fatigued gate, at either epoch.
func test_plain_melee_evasion_keeps_its_penalty_while_fatigued_at_both_epochs() -> void:
	for epoch in [AiActRecorder.EPOCH_72_PLAYTEST_RULES, AiActRecorder.EPOCH_73_V36]:
		var info := _melee_info(_unit(["Melee Evasion"], "gf", "dark_elf_raiders", true), epoch)
		assert_int(int(info.get("mod", 0))).override_failure_message("epoch %d: Melee Evasion stays -1" % epoch).is_equal(-1)


## The EV twin (FAB-C10): AiEv.ctx_for must read the same -1 the table reads. The unit carries a
## non-"Melee Evasion" entry on that primitive (Dodge), so the estimate has to walk the primitive.
func _ctx(target: GameUnit, epoch: int) -> Dictionary:
	AiActRecorder.rules_epoch = epoch
	return AiEv.ctx_for(target)


func _melee_profiles() -> Array:
	return [{"name": "Blades", "attacks": 10, "ap": 0, "deadly": 0, "relentless": false,
		"blast": 0, "reliable": false, "surge": false, "rending": false, "bane": false,
		"thrust": false, "counter": false, "range": 0, "rules": []}]


func _priced(target: GameUnit, epoch: int) -> float:
	return AiEv.melee_ev(_melee_profiles(), {"quality": 4, "models": 5}, _ctx(target, epoch), false)



func test_ai_estimate_prices_a_rested_dodge_unit_at_epoch_73() -> void:
	var dodger := _unit(["Dodge"], "gf", "dark_elf_raiders")
	var plain := _unit([], "gf", "dark_elf_raiders")
	var me := _unit(["Melee Evasion"], "gf", "dark_elf_raiders")
	var ctx := _ctx(dodger, AiActRecorder.EPOCH_73_V36)
	assert_bool(bool(ctx.get("melee_evasion", false))).override_failure_message("the EV context must carry Dodge as Melee Evasion").is_true()
	assert_float(_priced(dodger, AiActRecorder.EPOCH_73_V36)).is_equal_approx(_priced(me, AiActRecorder.EPOCH_73_V36), 0.0001)
	assert_bool(_priced(dodger, AiActRecorder.EPOCH_73_V36) < _priced(plain, AiActRecorder.EPOCH_73_V36)).override_failure_message("a rested Dodge unit must cost the attacker -1 to hit").is_true()


func test_ai_estimate_prices_no_dodge_while_fatigued_at_epoch_73() -> void:
	var dodger := _unit(["Dodge"], "gf", "dark_elf_raiders", true)
	var plain := _unit([], "gf", "dark_elf_raiders")
	assert_bool(bool(_ctx(dodger, AiActRecorder.EPOCH_73_V36).get("melee_evasion", false))).override_failure_message("a Fatigued Dodge unit gives no -1").is_false()
	assert_float(_priced(dodger, AiActRecorder.EPOCH_73_V36)).is_equal_approx(_priced(plain, AiActRecorder.EPOCH_73_V36), 0.0001)


func test_ai_estimate_prices_no_dodge_at_epoch_72() -> void:
	var dodger := _unit(["Dodge"], "gf", "dark_elf_raiders")
	var plain := _unit([], "gf", "dark_elf_raiders")
	assert_bool(bool(_ctx(dodger, AiActRecorder.EPOCH_72_PLAYTEST_RULES).get("melee_evasion", false))).override_failure_message("the Dodge entry is inert below epoch 73").is_false()
	assert_float(_priced(dodger, AiActRecorder.EPOCH_72_PLAYTEST_RULES)).is_equal_approx(_priced(plain, AiActRecorder.EPOCH_72_PLAYTEST_RULES), 0.0001)


## Control: plain Melee Evasion keeps its -1 at both epochs (no regression from the primitive walk).
func test_ai_estimate_keeps_plain_melee_evasion_at_both_epochs() -> void:
	var plain := _unit([], "gf", "dark_elf_raiders")
	for epoch in [AiActRecorder.EPOCH_72_PLAYTEST_RULES, AiActRecorder.EPOCH_73_V36]:
		var me := _unit(["Melee Evasion"], "gf", "dark_elf_raiders")
		assert_bool(bool(_ctx(me, epoch).get("melee_evasion", false))).override_failure_message("epoch %d: plain Melee Evasion stays on" % epoch).is_true()
		assert_bool(_priced(me, epoch) < _priced(plain, epoch)).override_failure_message("epoch %d: plain Melee Evasion stays -1" % epoch).is_true()
