extends GdUnitTestSuite
## Versatile Expert (rules 3.6): the pick lasts until the end of the unit's OWN activation, so a strike-back
## inside the enemy's activation neither picks nor latches; a charge in its own activation still does.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254
const ALL := 0

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
	_main.solo_ai_slots = {1: true, 2: true}
	_main._ensure_solo_controller()
	_main.solo_controller.human_slot = 1
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main._solo_batch = true
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _unit(pid: int, uname: String, n_models: int, unit_rules: Array, weapons: Array = [], defense: int = 4, wounds: int = 9) -> GameUnit:
	var pos: Array = []
	for i in range(n_models):
		pos.append(Vector3(0.5 * INCH, 0, (i - 0.5 * n_models) * 0.7 * INCH) if pid == 2 else Vector3(0, 0, i * 0.7 * INCH))
	var u := E2EBoot.make_unit(_main, pid, uname, pos)
	for m in u.models:
		(m as ModelInstance).wounds_max = wounds
		(m as ModelInstance).wounds_current = wounds
	var src := OPRApiClient.OPRUnit.new()
	var ws: Array[OPRApiClient.OPRWeapon] = []
	if weapons.is_empty():
		weapons = [{"name": "Probe Blade", "range": 0, "attacks": 2, "rules": []}]
	for wd in weapons:
		var w := OPRApiClient.OPRWeapon.new()
		w.name = str(wd["name"])
		w.range_value = int(wd["range"])
		w.attacks = int(wd["attacks"])
		w.count = 1
		for r in wd["rules"]:
			w.special_rules.append(r)
		ws.append(w)
	src.weapons = ws
	u.source_type = "opr"
	u.source_data = src
	u.unit_properties["game_system"] = "gf"
	u.unit_properties["faction_folder"] = "orc_marauders"
	u.unit_properties["special_rules"] = unit_rules
	u.unit_properties["defense"] = defense
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func _log_text() -> String:
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


func _expert(pid: int) -> GameUnit:
	return _unit(pid, "Experts", 2, ["Versatile Expert"], [{"name": "Blade", "range": 0, "attacks": 4, "rules": []}])


func test_strike_back_in_enemy_activation_neither_picks_nor_latches() -> void:
	var u := _expert(2)
	var enemy := _unit(1, "Chargers", 2, [])
	_main.opr_army_manager.current_round = 1
	_main.seed_tray_rng(2)
	await _main._solo_melee_strike_phase(u, enemy, false, ALL, 0.0)
	assert_str(_log_text()).not_contains(" picks ")
	assert_bool(_main._solo_versatile_latch_read(u).is_empty()).is_true()
	await E2EBoot.settle(get_tree())


func test_charge_in_own_activation_still_picks_and_latches() -> void:
	var u := _expert(1)
	var foe := _unit(2, "Anvils", 2, [], [], 4, 30)
	_main.opr_army_manager.current_round = 1
	_main.seed_tray_rng(2)
	await _main._solo_melee_strike_phase(u, foe, true, ALL, 3.0)
	assert_str(_log_text()).contains(" picks ")
	assert_bool(_main._solo_versatile_latch_read(u).is_empty()).is_false()
	await E2EBoot.settle(get_tree())
