extends GdUnitTestSuite
## FAB-B7 e2e — a joined hero's Fear(X) counts in the melee result: the chain fights as one, so the
## side's score carries the host's Fear plus every living attached hero's, from EPOCH_73_V36. Below
## 73 the host-only read stands. `_solo_melee_scores` is the ONE scoring seam both melee doors use.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const SYSTEM := "gff"
const FACTION := "blessed_sisters"

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _epoch0: int


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


## The charger took 0 and the defender 2; the charger's joined hero carries Fear(2), so at 73 the
## charger scores 0 + 2 against the defender's 2 — a tie (equal scores). Below 73 the hero's Fear
## stays out and the charger scores 0 against 2 — the charger loses.
func test_a_joined_hero_fear_counts_for_the_chain_from_73(timeout := 180000) -> void:
	var charger := _unit("Charger", [], Vector3.ZERO)
	var hero := _unit("Fear Hero", ["Fear(2)"], Vector3(0, 0, 0.2))
	var defender := _unit("Defender", [], Vector3(0, 0, 2.0))
	EquipmentDistributor.attach_hero_to_unit(hero, charger)
	assert_int(_main._solo_chain_fear(charger)) \
		.override_failure_message("the attached Fear hero was not folded") \
		.is_equal(int(AiEv.unit_rating(charger, "Fear")) + int(AiEv.unit_rating(hero, "Fear")))

	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var at73: Array = _main._solo_melee_scores(charger, 0, defender, 2)
	assert_int(int(at73[0])).override_failure_message("73: the hero's Fear did not join the chain") \
		.is_equal(int(at73[1]))

	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var at72: Array = _main._solo_melee_scores(charger, 0, defender, 2)
	assert_int(int(at72[0])).override_failure_message("72: the hero's Fear must stay out") \
		.is_equal(int(AiEv.unit_rating(charger, "Fear")))
	assert_int(int(at72[0])).is_less(int(at72[1]))
