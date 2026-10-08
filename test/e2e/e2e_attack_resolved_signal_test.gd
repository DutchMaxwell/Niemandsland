extends GdUnitTestSuite
## E2E — the lesson combat seams (tutorial D2): when a human attack finishes resolving, main emits
## human_attack_resolved(attacker, melee) exactly once with the branch that ran; when a human cast
## finishes, main emits human_cast_resolved(unit). LessonFacts counts these against lesson tags.
## Drives the real resolver on main.tscn (the dialogs are player-side; headless bypasses them).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _armed(pid: int, unit_name: String, pos: Vector3) -> GameUnit:
	var u: GameUnit = E2EBoot.make_unit(_main, pid, unit_name, [pos])
	var opr := OPRApiClient.OPRUnit.new()
	var ws: Array[OPRApiClient.OPRWeapon] = []
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Rifle"
	w.range_value = 24
	w.attacks = 2
	ws.append(w)
	opr.weapons = ws
	u.source_type = "opr"
	u.source_data = opr
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func test_shooting_attack_emits_resolved_signal_once(timeout := 240000) -> void:
	var shooter := _armed(1, "Shooter", Vector3.ZERO)
	var foe := _armed(2, "Foe", Vector3(8.0 * INCH, 0, 0))
	var calls: Array = []
	_main.human_attack_resolved.connect(func(attacker: GameUnit, melee: bool) -> void:
		calls.append({"attacker": attacker, "melee": melee}))
	await _main._run_human_attack(shooter, foe, false)
	assert_int(calls.size()).is_equal(1)
	assert_bool(bool(calls[0]["melee"])) \
		.override_failure_message("a shooting volley must report melee=false") \
		.is_false()
	assert_object(calls[0]["attacker"]).is_same(shooter)
	await E2EBoot.settle(get_tree())
