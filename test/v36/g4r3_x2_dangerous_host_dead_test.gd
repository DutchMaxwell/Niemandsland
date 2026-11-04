extends GdUnitTestSuite
## AI-G4 round 3, row R3-X2-table (rules 3.6, EPOCH_73_V36, lead ruling 2): when a charger's host dies in its own
## Dangerous-terrain test while a joined hero lives, the unit is NOT destroyed — the hero goes on with the charge as
## the unit. The table ended the charge right after the test because `is_destroyed()` counts the host's models only.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254

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
	_main.solo_ai_slots = {1: true, 2: true}   # both seats AI: saves and strike-backs auto-resolve, no dialog
	_main._ensure_solo_controller()
	_main.solo_controller.ai_slot = 2
	_main.solo_controller.human_slot = 1
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	_main._solo_batch = true
	# The charge path crosses a Dangerous-terrain strip between the charger and its target.
	_main.solo_controller.terrain_type_at = func(p: Vector3) -> int:
		return TerrainRules.TerrainType.DANGEROUS if absf(p.x - 4.0 * INCH) < 1.5 * INCH \
			else TerrainRules.TerrainType.NONE


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0   # statics leak across gdUnit tests — restore
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _club(attacks: int) -> OPRApiClient.OPRUnit:
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Club"
	w.range_value = 0
	w.attacks = attacks
	w.count = 1
	var src := OPRApiClient.OPRUnit.new()
	src.weapons = [w]
	return src


func _unit(pid: int, unit_name: String, x_in: float, wounds: int, attacks: int) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, [Vector3(x_in * INCH, 0, 0)])
	var model := u.models[0] as ModelInstance
	model.model_index = 0
	model.wounds_max = wounds
	model.wounds_current = wounds
	u.source_type = "opr"
	u.source_data = _club(attacks)
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func _join(host: GameUnit, hero: GameUnit) -> void:
	host.unit_properties["attached_heroes"] = [hero]
	hero.unit_properties["attached_to"] = host


func _log_text() -> String:
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


## The first `dice` faces this seed rolls on the tray, as the number of 1s (each wounds the unit).
func _seed_with_ones(dice: int, min_ones: int, max_ones: int) -> int:
	for s in range(5000):
		_main._tray_rng.seed = s
		var ones := 0
		for i in dice:
			if _main._tray_rng.randi_range(1, 6) == 1:
				ones += 1
		if ones >= min_ones and ones <= max_ones:
			return s
	return -1


## The REAL charge: the planner sends the AI unit at the target through the Dangerous strip, the table rolls the test
## and either goes on with the melee or stops. A 1-wound host joined by a 3-wound hero rolls 4 dice.
func _charge(epoch: int, seed_ones: Array) -> String:
	AiActRecorder.rules_epoch = epoch
	var host := _unit(2, "Sisters", 0.0, 1, 4)
	var hero := _unit(2, "Leader", 0.5, 3, 4)
	_join(host, hero)
	_unit(1, "Guard", 8.0, 10, 0)
	var s: int = _seed_with_ones(4, int(seed_ones[0]), int(seed_ones[1]))
	assert_int(s).is_greater_equal(0)
	_main._tray_rng.seed = s
	await _main._solo_activate_one_ai()
	await E2EBoot.settle(get_tree())
	var text := _log_text()
	return text


func test_a_joined_hero_goes_on_with_the_charge_when_the_host_dies_in_the_dangerous_test() -> void:
	var text: String = await _charge(AiActRecorder.EPOCH_73_V36, [1, 3])
	assert_str(text).contains("Sisters loses a model")   # the scenario bites: the host died in its own test
	assert_str(text).override_failure_message("the charge stopped with a living hero:\n%s" % text).contains("Melee result:")
	assert_str(text).contains("Leader strikes with Club at Guard")   # the hero is the unit that fights


## Below 73 the table still stops at the host's death (byte-identical).
func test_below_epoch_73_the_charge_still_ends_with_the_host() -> void:
	var text: String = await _charge(AiActRecorder.EPOCH_73_V36 - 1, [1, 3])
	assert_str(text).contains("Sisters loses a model")
	assert_str(text).not_contains("Melee result:")


## Control: when the dice kill the host AND its joined hero the whole unit is gone, so the charge ends.
func test_a_unit_wiped_by_the_dangerous_test_still_ends_the_charge() -> void:
	var text: String = await _charge(AiActRecorder.EPOCH_73_V36, [4, 4])
	assert_str(text).contains("Sisters destroyed")
	assert_str(text).contains("Leader destroyed")   # the scenario bites: the hero died too
	assert_str(text).not_contains("Melee result:")
