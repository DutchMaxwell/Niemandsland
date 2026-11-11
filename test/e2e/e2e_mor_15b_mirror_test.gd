extends GdUnitTestSuite
## MOR-15b e2e — the durable `spell_records` mirror is never behind the live
## `_solo_mods_of_chain` fold at epochs 72 and 73. Joins the caster to a host, records a
## round casting modifier on the host and the real once casting debuff on the caster (Burn the
## Heretic, blessed_sisters), spends the once record through the real resolver, and compares
## `SoloController.caster_casting_net` against the fold the human cast block used. A Shaken
## Spell Conduit must not lower the target in either reading.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const SYSTEM := "gff"
const FACTION := "blessed_sisters"
const SPELL := "Burn the Heretic"

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _epoch0: int
var _solo: SoloController


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_epoch0 = AiActRecorder.rules_epoch


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null
	_solo = null


func _unit(unit_name: String, rules: Array, pos: Vector3) -> GameUnit:
	var opr := OPRApiClient.OPRUnit.new()
	opr.name = unit_name
	opr.size = 1
	opr.quality = 4
	opr.defense = 4
	opr.special_rules.assign(rules)
	opr.game_system = SYSTEM
	opr.base_size_round = 25
	var nodes: Array[Node3D] = []
	var node := Node3D.new()
	_main.object_manager.add_child(node)
	node.global_position = pos
	nodes.append(node)
	var gu: GameUnit = EquipmentDistributor.create_from_opr_unit(opr, nodes, 1)
	gu.unit_properties["faction_folder"] = FACTION
	gu.unit_properties["game_system"] = SYSTEM
	_main.opr_army_manager.game_units[gu.unit_id] = gu
	return gu


func _old_fold_net(caster: GameUnit) -> int:
	var net := 0
	for rd in AiSpell.mods_for(_main._solo_mods_of_chain(caster), "casting", false):
		net += int((rd as Dictionary).get("casting_mod", 0))
	return net


func _assert_mirror_matches(caster: GameUnit, epoch: int, expected: int) -> void:
	AiActRecorder.rules_epoch = epoch
	assert_int(SoloController.caster_casting_net(caster)["net"]) \
		.override_failure_message("mirror disagrees with the live fold at epoch %d" % epoch) \
		.is_equal(_old_fold_net(caster))
	assert_int(SoloController.caster_casting_net(caster)["net"]).is_equal(expected)


func test_the_mirror_never_lags_the_live_fold_at_72_and_73(timeout := 180000) -> void:
	var host := _unit("Host", ["Caster(2)"], Vector3.ZERO)
	var caster := _unit("Caster Hero", ["Caster(2)"], Vector3(0, 0, 0.2))
	var conduit := _unit("Conduit", ["Spell Conduit"], Vector3(0, 0, 0.4))
	conduit.is_shaken = true
	EquipmentDistributor.attach_hero_to_unit(caster, host)

	_main._solo_record_spell_mod(host, "Casting Buff",
		{"modifier": {"casting_mod": -1}, "duration": "round"})
	var spell := SpellsRegistry.entry_for(SYSTEM, FACTION, SPELL)
	assert_bool(spell.is_empty()).override_failure_message("spell data missing for %s" % SPELL).is_false()
	_main._solo_record_spell_mod(caster, SPELL, spell["effect"])
	_assert_mirror_matches(caster, 72, -4)
	_assert_mirror_matches(caster, 73, -4)

	_main._solo_spend_once_mods(caster, ["casting"], false)
	assert_array(_main._solo_mods_of_chain(caster)) \
		.override_failure_message("the once record survived its spend").has_size(1)
	_assert_mirror_matches(caster, 72, -1)
	_assert_mirror_matches(caster, 73, -1)

	_solo = auto_free(SoloController.new())
	add_child(_solo)
	_solo.army_manager = _main.opr_army_manager
	var reading := _solo.caster_conduit(caster)
	assert_object(reading.get("unit")).override_failure_message("a Shaken conduit was used").is_null()
	assert_int((reading.get("shaken", []) as Array).size()).is_equal(1)
	AiActRecorder.rules_epoch = 73
	assert_int(SoloController.caster_casting_net(caster)["target"]).is_equal(5)
	assert_int(_solo.caster_cast_target(caster)) \
		.override_failure_message("the Shaken conduit lowered the target").is_equal(5)
	assert_int(SoloController.planned_cast_target(caster, 0)).is_equal(5)
	AiActRecorder.rules_epoch = 72
	assert_int(SoloController.planned_cast_target(caster, 0)) \
		.override_failure_message("below 73 the planner must stay blind").is_equal(4)
