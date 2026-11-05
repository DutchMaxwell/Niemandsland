extends GdUnitTestSuite
## Rules 3.6 wave, AI gate AIG-G2 row R3 (human side): the move-through trigger of a Crossing Strike weapon
## had one caller, the AI activation, so a PLAYER's bearer never fired it (and from EPOCH_73_V36 its weapon no
## longer strikes in melee either). After the player's own drop, a solo-game bearer whose executed paths
## crossed an enemy unit now fires the weapon at the nearest crossed one, once per round, and the log names
## the book rule. The drop is the real handler (_on_units_dropped) fed the shape object_manager emits.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254
const LINE := "Crossing Strike: Zeppelins passes over Warriors"

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
	_main.solo_ai_slots = {2: true}   # slot 1 is the player, slot 2 the AI
	_main._ensure_solo_controller()
	_main.solo_controller.ai_slot = 2
	_main.solo_controller.human_slot = 1
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main._solo_batch = true


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0   # statics leak across gdUnit tests
	GraphicsSettings.combat_stage_hold_s = 2.5
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _unit(pid: int, unit_name: String, x: float, weapon_name: String, weapon_rules: Array) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, [Vector3(x * INCH, 0.0, 0.0)])
	var w := OPRApiClient.OPRWeapon.new()
	w.name = weapon_name
	w.range_value = 0
	w.attacks = 4
	w.special_rules.assign(weapon_rules)
	var opr := OPRApiClient.OPRUnit.new()
	opr.weapons = [w]
	u.source_type = "opr"
	u.source_data = opr
	u.unit_properties["defense"] = 4
	for m in u.models:
		(m as ModelInstance).wounds_max = 9
		(m as ModelInstance).wounds_current = 9
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func _log_text() -> String:
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


## The player drags `bird` from x0 to x1 (inches, along the table's centre line): the move record has the
## shape object_manager emits through selection_dropped, then the real handler runs.
func _drop(bird: GameUnit, x0: float, x1: float) -> void:
	var node: Node3D = (bird.models[0] as ModelInstance).node
	node.global_position = Vector3(x1 * INCH, 0.0, 0.0)
	var mv := {"node": node, "from": Vector3(x0 * INCH, 0.0, 0.0), "to": Vector3(x1 * INCH, 0.0, 0.0),
		"inches": absf(x1 - x0), "path": PackedVector2Array([Vector2(x0 * INCH, 0.0), Vector2(x1 * INCH, 0.0)]),
		"arc_in": absf(x1 - x0), "climb_in": 0.0, "radius_m": 0.02, "drop_id": 1}
	_main.seed_tray_rng(7)
	await _main._on_units_dropped([mv])


func _setup(epoch: int, weapon_rules: Array) -> GameUnit:
	AiActRecorder.rules_epoch = epoch
	var bird := _unit(1, "Zeppelins", -28.0, "Drop Bombs", weapon_rules)
	_unit(2, "Warriors", -10.0, "Spear", [])
	return bird


func test_a_players_bearer_moved_over_an_enemy_fires_its_weapon_at_epoch_73(timeout := 90000) -> void:
	var bird := _setup(AiActRecorder.EPOCH_73_V36, ["Crossing Strike"])
	await _drop(bird, -28.0, 2.0)
	assert_str(_log_text()).contains(LINE)
	assert_str(_log_text()).override_failure_message("the volley stayed silent").not_contains("Drop Bombs silent")
	assert_str(_log_text()).contains("Zeppelins fires Drop Bombs at Warriors")
	await E2EBoot.settle(get_tree())


func test_the_trigger_fires_once_per_round_for_the_players_bearer(timeout := 90000) -> void:
	var bird := _setup(AiActRecorder.EPOCH_73_V36, ["Crossing Strike"])
	await _drop(bird, -28.0, 2.0)
	await _drop(bird, 2.0, -28.0)   # back across the same enemy, same round
	assert_int(_log_text().count(LINE)).is_equal(1)
	await E2EBoot.settle(get_tree())


## Controls: below the gate, off the lane, and a weapon without the rule are all silent.
func test_the_players_drop_is_untouched_at_epoch_72(timeout := 90000) -> void:
	var bird := _setup(AiActRecorder.EPOCH_72_PLAYTEST_RULES, ["Crossing Strike"])
	await _drop(bird, -28.0, 2.0)
	assert_str(_log_text()).not_contains("Crossing Strike")
	await E2EBoot.settle(get_tree())


func test_a_drop_that_stops_short_of_the_enemy_is_silent_at_epoch_73(timeout := 90000) -> void:
	var bird := _setup(AiActRecorder.EPOCH_73_V36, ["Crossing Strike"])
	await _drop(bird, -28.0, -20.0)
	assert_str(_log_text()).not_contains("Crossing Strike")
	await E2EBoot.settle(get_tree())


func test_a_bearer_without_the_rule_is_silent_at_epoch_73(timeout := 90000) -> void:
	var bird := _setup(AiActRecorder.EPOCH_73_V36, [])
	await _drop(bird, -28.0, 2.0)
	assert_str(_log_text()).not_contains("passes over")
	await E2EBoot.settle(get_tree())
