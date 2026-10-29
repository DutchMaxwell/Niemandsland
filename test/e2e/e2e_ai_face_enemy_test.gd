extends GdUnitTestSuite
## E2E — Automodus decision 14 wiring: only a designated AI seat turns its models to face the enemy.
## A hotseat Automatic table (two humans, no AI seat) builds the same SoloController for GEOMETRY, and
## its ai_slot falls back to 2 (main._solo_ai_slot) — a HUMAN side. The battle start must leave it alone.
##
## Real: scenes/main.tscn with its real _ready(), the real OPRArmyManager phase flip (start_game, the one
## door every Start funnels through), the real _ensure_solo_controller wiring and the real 6x4 ft table.
## Constructed: the GameUnits and their model nodes (E2EBoot.make_unit — no network, no R2 GLBs in CI).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _register(pid: int, unit_name: String, at: Vector3) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, [at, at + Vector3(0.04, 0.0, 0.0)])
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func _yaws(u: GameUnit) -> Array:
	var out: Array = []
	for m in u.models:
		out.append((m as ModelInstance).node.rotation.y)
	return out


## Solo, player 2 = NACHTMAHR, deployed facing +Z (away from the human): the battle start turns it to -Z.
func test_the_ai_seat_faces_the_enemy_at_the_battle_start(timeout := 120000) -> void:
	_main.solo_ai_slots = {2: true}
	var human := _register(1, "Wachtturm", Vector3(0.0, 0.0, -0.4))
	var ai := _register(2, "Raider", Vector3(0.0, 0.0, 0.4))
	_main._ensure_solo_controller()
	_main.opr_army_manager.start_game()
	for y in _yaws(ai):
		var off := absf(rad_to_deg(angle_difference(float(y), PI)))
		assert_float(off).override_failure_message("NACHTMAHR's model faces %.1f deg off the human army" % off) \
			.is_less_equal(5.0)
	for y in _yaws(human):
		assert_float(float(y)).is_equal(0.0)


## Hotseat Automatic: the geometry controller exists and points ai_slot at player 2, a human. Nobody turns.
func test_a_hotseat_table_turns_no_model(timeout := 120000) -> void:
	_main.solo_ai_slots = {}
	_main.opr_army_manager.rules_automation = RulesAutomation.Level.AUTOMATIC
	var p1 := _register(1, "Wachtturm", Vector3(0.0, 0.0, -0.4))
	var p2 := _register(2, "Raider", Vector3(0.0, 0.0, 0.4))
	_main._ensure_solo_controller()
	assert_object(_main.solo_controller).override_failure_message("premise: the geometry controller exists").is_not_null()
	assert_int(int(_main.solo_controller.ai_slot)).override_failure_message("premise: ai_slot points at a human side").is_equal(2)
	_main.opr_army_manager.start_game()
	for y in _yaws(p2) + _yaws(p1):
		assert_float(float(y)).override_failure_message("a human model was turned on a hotseat table: yaw %f" % float(y)) \
			.is_equal(0.0)
