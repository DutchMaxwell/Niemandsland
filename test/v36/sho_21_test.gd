extends GdUnitTestSuite
## Rules 3.6 wave, row SHO-21: Hazardous. From EPOCH_73_V36 the wound for an unmodified 1 to hit lands on
## the model that carries the weapon (a joined hero takes his own; a Tough model in a unit takes it on
## itself) and counts X when the weapon also has Blast(X) or Deadly(X). The EPOCH_72_PLAYTEST_RULES leg
## keeps today's behaviour: one wound per 1, allocated across the whole unit.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const WEAPON := "Plas Cannon"

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _epoch0: int


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main._solo_batch = true


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0   # statics leak across gdUnit tests — restore
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _index_of(needle: String) -> int:
	var entries: Array = _main.battle_log.entries()
	for i in range(entries.size()):
		if str((entries[i] as Dictionary)["text"]).contains(needle):
			return i
	return -1


## A unit of `models` models, each carrying WEAPON and `wounds` wounds (Tough(wounds) when above 1).
func _bearers(unit_name: String, models: int, wounds: int) -> GameUnit:
	var positions: Array = []
	for i in range(models):
		positions.append(Vector3(0.2, 0.0, 0.02 * i))
	var unit := E2EBoot.make_unit(_main, 2, unit_name, positions)
	_main.opr_army_manager.game_units[unit.unit_id] = unit
	for m in unit.models:
		var mi := m as ModelInstance
		mi.wounds_max = wounds
		mi.wounds_current = wounds
		mi.properties["weapons"] = [{"name": WEAPON, "attacks": 1}]
	return unit


## A one-model hero that joins `host`; only he carries WEAPON, the host's own models carry nothing.
func _join_hero(host: GameUnit, wounds: int) -> GameUnit:
	var hero := _bearers(host.get_name() + "Hero", 1, wounds)
	for m in host.models:
		(m as ModelInstance).properties["weapons"] = []
	host.unit_properties["attached_heroes"] = [hero]
	hero.unit_properties["attached_to"] = host
	return hero


func _profile(extra: Dictionary = {}) -> Dictionary:
	var p := {"name": WEAPON, "attacks": 3, "hazardous": true}
	p.merge(extra, true)
	return p


func _wounds_of(unit: GameUnit, index: int = 0) -> int:
	return int((unit.models[index] as ModelInstance).wounds_current)


func test_a_blast_self_wound_counts_x_on_the_bearer_at_epoch_73(timeout := 240000) -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var unit := _bearers("HazBlast", 1, 5)
	await _main._solo_hazardous_self_wounds(unit, _profile({"blast": 3}), [1, 4, 6])
	assert_int(_wounds_of(unit)) \
		.override_failure_message("one 1 on a Blast(3) Hazardous weapon must cost the bearer 3 wounds, left %d of 5" % _wounds_of(unit)) \
		.is_equal(2)
	await E2EBoot.settle(get_tree())


func test_a_deadly_self_wound_counts_x_on_the_bearer_at_epoch_73(timeout := 240000) -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var unit := _bearers("HazDeadly", 1, 5)
	await _main._solo_hazardous_self_wounds(unit, _profile({"deadly": 2}), [1, 1, 6])
	assert_int(_wounds_of(unit)) \
		.override_failure_message("two 1s on a Deadly(2) Hazardous weapon must cost the bearer 4 wounds, left %d of 5" % _wounds_of(unit)) \
		.is_equal(1)
	await E2EBoot.settle(get_tree())


func test_a_joined_hero_takes_his_own_hazardous_wound_at_epoch_73(timeout := 240000) -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var host := _bearers("HazHost", 2, 1)
	var hero := _join_hero(host, 3)
	await _main._solo_hazardous_self_wounds(host, _profile(), [1])
	assert_int(_wounds_of(hero)).override_failure_message("the hero carries the weapon and takes the wound himself").is_equal(2)
	assert_int(host.get_alive_count()).override_failure_message("the host's models are not wounded for the hero's weapon").is_equal(2)
	await E2EBoot.settle(get_tree())


func test_the_wound_lands_on_the_firing_model_of_a_tough_unit_at_epoch_73(timeout := 240000) -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var unit := _bearers("HazTough", 3, 3)
	for i in range(2):
		(unit.models[i] as ModelInstance).properties["weapons"] = []   # only the last model fires the Hazardous weapon
	await _main._solo_hazardous_self_wounds(unit, _profile(), [1])
	assert_int(_wounds_of(unit, 2)).override_failure_message("the firing model takes the wound itself").is_equal(2)
	assert_int(_wounds_of(unit, 0) + _wounds_of(unit, 1)).override_failure_message("the models that did not fire stay whole").is_equal(6)
	await E2EBoot.settle(get_tree())


func test_the_self_wound_line_names_the_bearer_model_and_x_at_epoch_73(timeout := 240000) -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var unit := _bearers("HazLogged", 1, 5)
	await _main._solo_hazardous_self_wounds(unit, _profile({"blast": 3}), [1])
	assert_int(_index_of("Hazardous: HazLogged model 1 takes 3 wounds (Blast/Deadly 3, Plas Cannon)")).is_greater_equal(0)
	await E2EBoot.settle(get_tree())


func test_a_blast_self_wound_is_one_wound_for_the_unit_at_epoch_72(timeout := 240000) -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var unit := _bearers("HazOld", 1, 5)
	await _main._solo_hazardous_self_wounds(unit, _profile({"blast": 3}), [1, 4, 6])
	assert_int(_wounds_of(unit)).is_equal(4)
	assert_int(_index_of("Hazardous: HazOld rolls 1 unmodified 1 to hit — takes 1 wound")).is_greater_equal(0)
	await E2EBoot.settle(get_tree())


func test_a_joined_heros_hazardous_wound_goes_to_the_unit_first_at_epoch_72(timeout := 240000) -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var host := _bearers("HazOldHost", 2, 1)
	var hero := _join_hero(host, 3)
	await _main._solo_hazardous_self_wounds(host, _profile(), [1])
	assert_int(host.get_alive_count()).override_failure_message("the old allocation wounds the host's own models first").is_equal(1)
	assert_int(_wounds_of(hero)).is_equal(3)
	await E2EBoot.settle(get_tree())
