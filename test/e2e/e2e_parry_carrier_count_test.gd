extends GdUnitTestSuite
## Parry (3.6): X dice per model that carries the Parry weapon, not per model of the unit.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254
const SEED := Vector3(0.03, 0.0, 0.03)

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _epoch0: int


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {1: true, 2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main._solo_batch = true
	RulesRegistry.reset_cache()


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0
	GraphicsSettings.combat_stage_hold_s = 2.5
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null
	RulesRegistry.reset_cache()


func _weapon(wname: String, reach: int, attacks: int, rules: Array, count: int = 1) -> OPRApiClient.OPRWeapon:
	var w := OPRApiClient.OPRWeapon.new()
	w.name = wname
	w.range_value = reach
	w.attacks = attacks
	w.count = count
	w.special_rules.assign(rules)
	return w


func _unit(pid: int, unit_name: String, x: float, models: int, weapons: Array, rules: Array, defense: int = 4,
		tough: int = 1, quality: int = 4) -> GameUnit:
	var positions: Array = []
	for i in range(models):
		positions.append(Vector3(x * INCH, 0.0, 0.02 * i))
	var u := E2EBoot.make_unit(_main, pid, unit_name, positions)
	var ws: Array[OPRApiClient.OPRWeapon] = []
	for w in weapons:
		ws.append(w)
	var opr := OPRApiClient.OPRUnit.new()
	opr.weapons = ws
	u.source_type = "opr"
	u.source_data = opr
	u.unit_properties["special_rules"] = rules + (["Tough(%d)" % tough] if tough > 1 else [])
	u.unit_properties["defense"] = defense
	u.unit_properties["quality"] = quality
	for m in u.models:
		(m as ModelInstance).wounds_max = tough
		(m as ModelInstance).wounds_current = tough
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u



# Parry(1) carried by 1 of 3 models gets 1 die; all 3 carry Parry(2) gets 6 (control).
func test_parry_dice_count_follows_models_that_carry_the_rule() -> void:
	# 3 living models, the Parry(1) weapon is carried by 1 of them (count 1): 3.6 says X dice per model WITH the rule
	var d := _unit(1, "Parrier", 0.0, 3, [_weapon("Sword", 0, 1, ["Parry(1)"], 1), _weapon("Hand", 0, 1, [], 2)], [])
	var got: int = _main._solo_melee_parry_dice(d)
	assert_int(got).override_failure_message("count-1 weapon on 3 models: got %d" % got).is_equal(1)


func test_parry_dice_all_carriers() -> void:
	var d := _unit(1, "Parrier", 0.0, 3, [_weapon("Sword", 0, 1, ["Parry(2)"], 3)], [])
	assert_int(_main._solo_melee_parry_dice(d)).is_equal(6)


## The AI estimate's Parry dice: `AiEv._parry_cancels` against more hits than any roll here can cancel, times 6.
func _estimate_dice(d: GameUnit) -> int:
	return roundi(AiEv._parry_cancels(AiEv.ctx_for(d), 100.0) * 6.0)


func _keep_alive(d: GameUnit, alive: int) -> void:
	for i in range(d.models.size()):
		(d.models[i] as ModelInstance).is_alive = i < alive


# EPOCH_75_TABLE_FIXES: the AI estimate counts the dice path's Parry dice (carriers only), also after losses.
func test_the_estimate_counts_only_the_carriers_from_epoch_75() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_75_TABLE_FIXES
	var one := _unit(1, "One", 0.0, 5, [_weapon("Sword", 0, 1, ["Parry(1)"], 1), _weapon("Hand", 0, 1, [], 4)], [])
	assert_int(_estimate_dice(one)).override_failure_message("1 of 5 carries Parry(1): estimate %d dice, want 1"
		% _estimate_dice(one)).is_equal(1)
	var cases := [one,
		_unit(1, "Two", 0.0, 5, [_weapon("Sword", 0, 1, ["Parry(2)"], 2), _weapon("Hand", 0, 1, [], 3)], []),
		_unit(1, "All", 0.0, 5, [_weapon("Sword", 0, 1, ["Parry(1)"], 5)], []),
		_unit(1, "Rule", 0.0, 5, [_weapon("Hand", 0, 1, [], 5)], ["Parry(1)"])]
	for d in cases:
		for alive in [5, 2, 1]:
			_keep_alive(d, alive)
			var want: int = _main._solo_melee_parry_dice(d)
			assert_int(_estimate_dice(d)).override_failure_message("%s with %d alive: estimate %d dice, dice path %d"
				% [d.unit_id, alive, _estimate_dice(d), want]).is_equal(want)


# Records stamped 74 replay the old estimate: X dice per LIVING model, carrier or not.
func test_the_estimate_is_unchanged_below_epoch_75() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_74_CLIMB_COST
	var one := _unit(1, "One", 0.0, 5, [_weapon("Sword", 0, 1, ["Parry(1)"], 1), _weapon("Hand", 0, 1, [], 4)], [])
	assert_int(_estimate_dice(one)).is_equal(5)
	_keep_alive(one, 2)
	assert_int(_estimate_dice(one)).is_equal(2)
	assert_int(int(AiEv.ctx_for(one).get("parry_carrier_dice", 0))).is_equal(0)
