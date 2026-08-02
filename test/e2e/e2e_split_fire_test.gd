extends GdUnitTestSuite
## E2E — #226 SPLIT FIRE (GF v3.5.1 p.8: "Each group may be fired at a different target,
## however you may fire only at up to two different targets"): the declared split resolves
## each weapon group at ITS target and completes the activation exactly once. Drives the
## real volley resolvers on main.tscn (the dialog itself is player-side; headless bypasses).

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


func _armed(pid: int, unit_name: String, pos: Vector3, weapon_names: Array) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, [pos])
	var opr := OPRApiClient.OPRUnit.new()
	var ws: Array[OPRApiClient.OPRWeapon] = []
	for wn in weapon_names:
		var w := OPRApiClient.OPRWeapon.new()
		w.name = str(wn)
		w.range_value = 24
		w.attacks = 2
		ws.append(w)
	opr.weapons = ws
	u.source_type = "opr"
	u.source_data = opr
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func test_declared_split_fires_each_group_at_its_target(timeout := 240000) -> void:
	var shooter := _armed(1, "Tank", Vector3.ZERO, ["Rifle", "Cannon"])
	var foe_a := _armed(2, "FoeA", Vector3(8.0 * INCH, 0, 0), [])
	var foe_b := _armed(2, "FoeB", Vector3(0, 0, 8.0 * INCH), [])
	await _main._run_human_attack_split(shooter, foe_a, foe_b, ["Cannon"])
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	assert_str(text).contains("Split fire: Tank fires at FoeA and FoeB")
	assert_str(text) \
		.override_failure_message("#226 — the A-volley did not fire the unchecked weapon at FoeA (log: %s)" % text.strip_edges()) \
		.contains("fires Rifle at FoeA")
	assert_str(text).contains("fires Cannon at FoeB")
	assert_str(text).not_contains("fires Cannon at FoeA")
	assert_str(text).not_contains("fires Rifle at FoeB")
	assert_bool(shooter.is_activated).is_true()   # completed exactly once, after volley B
	await E2EBoot.settle(get_tree())   # the activation's trailing bookkeeping, before gdUnit reads
