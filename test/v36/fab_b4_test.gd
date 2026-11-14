extends GdUnitTestSuite
## Rules 3.6 wave, row FAB-B4: a HUMAN charge resolves from its real pre-charge base-edge gap, so the
## distance-gated 3.6 melee rules see the true value instead of 0". At EPOCH_73_V36 a Warding defender
## charged from over 6" gets its 6+ ignore, Valiant charged from within 6" loses its share, and a
## weaponless AI defender takes no phantom Fatigue. Below 73 both behaviours stay as they were.
## The charge is driven through the live table path (_run_human_attack) at real model positions.

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
	_main.solo_ai_slots = {2: true}   # pid 1 is the human charger, pid 2 the AI defender
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main._solo_batch = true
	_main._solo_auto_saves = true   # the AI's strike-back rolls the human's saves without a prompt


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0   # statics leak across gdUnit tests — restore
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## One model of a gf unit at `x_in` from the origin; `attacks` > 0 gives it a melee weapon.
func _unit(pid: int, unit_name: String, x_in: float, attacks: int = 0, rules: Array = [],
		defense: int = 4, wound_pool: int = 1, faction: String = "") -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, [Vector3(x_in * INCH, 0.0, 0.0)])
	var model := u.models[0] as ModelInstance
	model.wounds_max = wound_pool
	model.wounds_current = wound_pool
	var source := OPRApiClient.OPRUnit.new()
	if attacks > 0:
		var weapon := OPRApiClient.OPRWeapon.new()
		weapon.name = "Blade"
		weapon.range_value = 0
		weapon.attacks = attacks
		source.weapons = [weapon]
	u.source_type = "opr"
	u.source_data = source
	u.unit_properties["special_rules"] = rules.duplicate()
	for m in u.models:
		(m as ModelInstance).properties["special_rules"] = rules.duplicate()
	u.unit_properties["defense"] = defense
	u.unit_properties["game_system"] = "gf"
	if not faction.is_empty():
		u.unit_properties["faction_folder"] = faction
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func _log_text() -> String:
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


## The live charge: real positions, the real snap/pile-in/melee order, the real pre-charge gap read.
func _charge(charger: GameUnit, target: GameUnit, epoch: int) -> String:
	AiActRecorder.rules_epoch = epoch
	_main.seed_tray_rng(7)
	await E2EBoot.start_activation(_main, charger)   # the explicit activation a player opens first
	await _main._run_human_attack(charger, target, true, true)
	var text := _log_text()
	await E2EBoot.settle(get_tree())
	return text


## A 20-attack human charger into a Warding defender 10" away (base-edge gap ~8.7", outside 6").
func _warding_charge(epoch: int) -> String:
	var charger := _unit(1, "Charger", 0.0, 20)
	var target := _unit(2, "Wardens", 10.0, 0, ["Warding"], 6, 30, "knight_brothers")
	return await _charge(charger, target, epoch)


func test_warding_gets_its_six_plus_when_charged_from_over_six_at_epoch_73() -> void:
	var text: String = await _warding_charge(AiActRecorder.EPOCH_73_V36)
	assert_str(text).override_failure_message("the Warding gate must open on a 10\" charge: %s" % text) \
		.contains("ignores wounds on 6+ (charged from over 6in)")
	assert_str(text).override_failure_message("the gate must not shut the rule: %s" % text) \
		.not_contains("no 6+ ignore")


func test_warding_keeps_the_old_read_at_epoch_72() -> void:
	var text: String = await _warding_charge(AiActRecorder.EPOCH_72_PLAYTEST_RULES)
	assert_str(text).override_failure_message("epoch 72 keeps the unconditional 6+: %s" % text) \
		.contains("Warding dice (6+)")
	assert_str(text).override_failure_message("epoch 72 has no charge distance gate: %s" % text) \
		.not_contains("charged from over 6in")


## A Fear(1) charger wins the tally without any dice, leaving the weaponless defender as the loser.
func _valiant_charge(x_in: float, epoch: int) -> String:
	var charger := _unit(1, "Charger", 0.0, 0, ["Fear(1)"])
	var target := _unit(2, "Valiant Guard", x_in, 0, ["Valiant"], 4, 9)
	return await _charge(charger, target, epoch)


func test_valiant_charged_from_within_six_loses_its_bonus_at_epoch_73() -> void:
	var text: String = await _valiant_charge(4.0, AiActRecorder.EPOCH_73_V36)
	assert_str(text).override_failure_message("the Valiant share drops inside the 6\" band: %s" % text) \
		.contains("Valiant counts only beyond the gate")


func test_valiant_keeps_the_old_read_at_epoch_72() -> void:
	var text: String = await _valiant_charge(4.0, AiActRecorder.EPOCH_72_PLAYTEST_RULES)
	assert_str(text).override_failure_message("epoch 72 keeps the unconditional Valiant reading: %s" % text) \
		.not_contains("Valiant counts only beyond the gate")


func test_a_weaponless_defender_is_not_fatigued_by_a_human_charge_at_epoch_73() -> void:
	var charger := _unit(1, "Charger", 0.0)
	var target := _unit(2, "Artillery", 10.0, 0, [], 4, 9)
	await _charge(charger, target, AiActRecorder.EPOCH_73_V36)
	assert_bool(target.is_fatigued).override_failure_message(
		"a defender with no melee weapon takes no phantom Fatigue\n" + _log_text()).is_false()


func test_a_weaponless_defender_is_still_fatigued_at_epoch_72() -> void:
	var charger := _unit(1, "Charger", 0.0)
	var target := _unit(2, "Artillery", 10.0, 0, [], 4, 9)
	await _charge(charger, target, AiActRecorder.EPOCH_72_PLAYTEST_RULES)
	assert_bool(target.is_fatigued).override_failure_message(
		"epoch 72 keeps today's behaviour: the empty strike-back slot tires the defender").is_true()


func test_a_defender_with_a_melee_weapon_is_still_fatigued_at_epoch_73() -> void:
	var charger := _unit(1, "Charger", 0.0, 4)
	var target := _unit(2, "Foe", 10.0, 2, [], 4, 9)
	await _charge(charger, target, AiActRecorder.EPOCH_73_V36)
	assert_bool(target.is_fatigued).override_failure_message(
		"a defender that struck back is Fatigued\n" + _log_text()).is_true()


## The player's real path: a manual melee pick is only legal within 1" of base contact, so the charger was
## DRAGGED into reach first. The pre-charge gap then lives in the MoveLedger (the polyline's first point),
## not in the models' spots. `from_in` < 0 records no move (the unit did not drag).
func _dragged_warding_charge(epoch: int, from_in: float) -> String:
	AiActRecorder.rules_epoch = epoch
	var charger := _unit(1, "Charger", 8.5, 20)   # where the drag ended: ~0.2" off the Wardens' base
	var target := _unit(2, "Wardens", 10.0, 0, ["Warding"], 6, 30, "knight_brothers")
	if from_in >= 0.0:
		(charger.models[0] as ModelInstance).node.set_meta("network_id", 7)
		_main.move_trails.ledger.record(1, charger.unit_id, "Charger", 7,
			PackedVector2Array([Vector2(from_in * INCH, 0.0), Vector2(8.5 * INCH, 0.0)]),
			_main.opr_army_manager.current_round)
	assert_str(_main._solo_validate_target(charger, target, true)) \
		.override_failure_message("the dragged charger must be a legal manual pick").is_equal("")
	_main.seed_tray_rng(7)
	await E2EBoot.start_activation(_main, charger)   # the explicit activation a player opens first
	await _main._solo_split_or_attack(charger, target, true)
	var text := _log_text()
	await E2EBoot.settle(get_tree())
	return text


func test_a_dragged_charge_from_over_six_opens_warding_at_epoch_73() -> void:
	var text: String = await _dragged_warding_charge(AiActRecorder.EPOCH_73_V36, 0.0)
	assert_str(text).override_failure_message("a drag from ~8.7in out is a charge from over 6in: %s" % text) \
		.contains("ignores wounds on 6+ (charged from over 6in)")


func test_a_dragged_charge_from_within_six_keeps_warding_shut_at_epoch_73() -> void:
	var text: String = await _dragged_warding_charge(AiActRecorder.EPOCH_73_V36, 4.0)
	assert_str(text).override_failure_message("a drag from ~4.7in out stays inside the 6in gate: %s" % text) \
		.contains("no 6+ ignore")
	assert_str(text).not_contains("charged from over 6in")


func test_a_charge_without_a_ledger_move_reads_its_current_gap_at_epoch_73() -> void:
	var text: String = await _dragged_warding_charge(AiActRecorder.EPOCH_73_V36, -1.0)
	assert_str(text).override_failure_message("no ledger move = the unit did not drag, ~0.2in is right: %s" % text) \
		.contains("no 6+ ignore")


func test_a_dragged_charge_keeps_the_old_read_at_epoch_72() -> void:
	var text: String = await _dragged_warding_charge(AiActRecorder.EPOCH_72_PLAYTEST_RULES, 0.0)
	assert_str(text).override_failure_message("epoch 72 keeps the unconditional 6+: %s" % text) \
		.contains("Warding dice (6+)")
	assert_str(text).not_contains("charged from over 6in")
