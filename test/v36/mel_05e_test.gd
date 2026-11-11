extends GdUnitTestSuite
## Rules 3.6 wave, row MEL-05e: the AI's charge estimate stops pricing the Counter Impact cut at
## epoch 73 and counts the Counter strike-first only for a defender that actually strikes back
## (fresh, not Shaken, a usable melee weapon). Epoch 72 keeps today's value. The policy half is the
## AI's Counter decision itself: a unit that cannot strike back does not Counter first, and the
## battle log names it through the MEL-05 Counter lines.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254

var _epoch0: int
var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0   # statics leak across gdUnit tests
	GraphicsSettings.combat_stage_hold_s = 2.5
	if _main != null:
		E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
		_main = null
		_runner = null


## `models` alive models, one melee weapon carrying `weapon_rules`.
func _unit(models: int, weapon_rules: Array, unit_name: String = "Defender") -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = unit_name.to_lower()
	u.unit_properties = {"player_id": 1, "name": unit_name, "quality": 4, "defense": 4, "special_rules": []}
	for i in range(models):
		var mi := ModelInstance.new()
		mi.is_alive = true
		u.models.append(mi)
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Blade"
	w.range_value = 0
	w.attacks = 1
	w.count = models
	w.special_rules.assign(weapon_rules)
	var ws: Array[OPRApiClient.OPRWeapon] = [w]
	var opr := OPRApiClient.OPRUnit.new()
	opr.weapons = ws
	u.source_type = "opr"
	u.source_data = opr
	return u


func _profiles(unit: GameUnit) -> Array:
	var weapons: Array = (unit.source_data as OPRApiClient.OPRUnit).weapons
	return AiShooting.melee_profiles(weapons)


func _ctx(unit: GameUnit) -> Dictionary:
	return AiEv.ctx_for(unit, false, 0)


func test_the_impact_estimate_ignores_counter_models_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var att := {"quality": 4, "impact": 3, "models": 2}
	var plain := {"defense": 4, "tough": 1, "models": 5}
	var countered := {"defense": 4, "tough": 1, "models": 5, "counter_models": 3}
	assert_float(AiEv.impact_ev(att, countered)).is_equal_approx(AiEv.impact_ev(att, plain), 0.0001)


func test_counter_does_not_strip_the_heavy_impact_pool_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var att := {"quality": 4, "models": 2, "impact": 1, "heavy_impact": 1}
	var plain := {"defense": 4, "tough": 1, "models": 5}
	var countered := {"defense": 4, "tough": 1, "models": 5, "counter_models": 2}
	assert_float(AiEv.impact_ev(att, countered)).is_equal_approx(AiEv.impact_ev(att, plain), 0.0001)


func test_a_fresh_counter_defender_prices_higher_than_a_fatigued_one_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var us_unit := _unit(5, [], "Attacker")
	var us := _ctx(us_unit)
	var our_melee := _profiles(us_unit)
	var fresh := _unit(5, ["Counter"], "Fresh")
	var tired := _unit(5, ["Counter"], "Tired")
	tired.is_fatigued = true
	var fresh_score := AiEv.charge_score(our_melee, us, _profiles(fresh), _ctx(fresh))
	var tired_score := AiEv.charge_score(our_melee, us, _profiles(tired), _ctx(tired))
	assert_bool(fresh_score < tired_score) \
		.override_failure_message("a fresh Counter defender thins our charge; a Fatigued one does not").is_true()


func test_a_counter_unit_without_a_usable_melee_weapon_does_not_counter_first_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var u := _unit(2, ["Counter", "Limited"])
	u.unit_properties["limited_used"] = ["Blade"]
	assert_bool(SoloController.counter_strikes_first(u)).is_false()


## CONTROL: below epoch 73 nothing changes — a spent Limited Counter weapon still Counters first.
func test_a_spent_limited_counter_unit_still_counters_first_at_epoch_72() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var u := _unit(2, ["Counter", "Limited"])
	u.unit_properties["limited_used"] = ["Blade"]
	assert_bool(SoloController.counter_strikes_first(u)).is_true()


func test_the_ai_does_not_counter_a_defender_that_cannot_strike_back_at_epoch_73(timeout := 90000) -> void:
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
	var charger := _e2e_unit(2, "Charger", 0.0, [])
	var defender := _e2e_unit(1, "Defender", 1.0, ["Counter", "Limited"])
	_main.solo_controller.mark_limited_used(defender,
		AiShooting.melee_profiles((defender.source_data as OPRApiClient.OPRUnit).weapons)[0])
	_main.seed_tray_rng(7)
	await _main._run_ai_melee({"unit": charger, "target": defender, "charge_from_in": 1.0})
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	assert_str(text).not_contains("Counter: Defender strikes first")
	assert_str(text).contains("Counter: Defender declines to strike first")
	assert_str(text).contains("melee weapons are all spent (Limited) — cannot strike back")
	await E2EBoot.settle(get_tree())


## A Tough(9) one-model unit at `x` inches with one melee weapon carrying `weapon_rules`.
func _e2e_unit(pid: int, unit_name: String, x: float, weapon_rules: Array) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, [Vector3(x * INCH, 0.0, 0.0)])
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Blade"
	w.range_value = 0
	w.attacks = 1
	w.count = 1
	w.special_rules.assign(weapon_rules)
	var ws: Array[OPRApiClient.OPRWeapon] = [w]
	var src := OPRApiClient.OPRUnit.new()
	src.weapons = ws
	u.source_type = "opr"
	u.source_data = src
	u.unit_properties["special_rules"] = ["Tough(9)"]
	for m in u.models:
		(m as ModelInstance).wounds_max = 9
		(m as ModelInstance).wounds_current = 9
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u
