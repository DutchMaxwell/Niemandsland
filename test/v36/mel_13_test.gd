extends GdUnitTestSuite
## v3.6 row MEL-13: Dodge is Melee Evasion while the unit is not Fatigued. A unit whose MOST models
## carry Dodge costs a melee attacker -1 to hit, but only while the unit is not Fatigued (the plain
## fatigued state; Shaken does not count for a defender). Both systems print the same text, so the gf
## and aof maps carry it as one entry each, on the Melee Evasion primitive. The behaviour is gated on
## EPOCH_73_V36: at epoch 72 a Dodge unit gets no penalty. Plain Melee Evasion keeps its old reading
## (no Fatigued gate, any epoch).

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
