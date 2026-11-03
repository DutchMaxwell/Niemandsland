extends GdUnitTestSuite
## Rules 3.6 wave, row MOR-09b: the table twin and the AI estimate gate only the Valiant-family
## share by distance. A plain Banner keeps its +1 inside the band; Valiant loses it inside 9"/6".
## "Valiant" also needs a strict model majority from epoch 73; the 3.5 spellings keep their shape.

const Boot := preload("res://test/e2e/e2e_boot.gd")

var _runner: GdUnitSceneRunner
var _main: Node
var _roots: Array
var _epoch_before: int
var _unit_seq := 0


func before_test() -> void:
	_epoch_before = AiActRecorder.rules_epoch
	Boot.arm_harness_mode()
	_roots = Boot.root_children(get_tree())
	_runner = scene_runner(Boot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main._solo_batch = true


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch_before
	Boot.free_stray_root_nodes(get_tree(), _roots)
	_main = null
	_runner = null


## A Quality 4 unit of `models` models for player 1, registered on the board.
func _board_unit(models: int, rules: Array, unit_name: String = "Victim") -> GameUnit:
	var spots: Array = []
	for i in range(models):
		spots.append(Vector3(0.05 + 0.03 * i, 0, 0))
	var u := Boot.make_unit(_main, 1, unit_name, spots)
	u.unit_properties["game_system"] = "gf"
	u.unit_properties["special_rules"] = rules
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## A scene-free unit for the static reads and the AI estimate (real registry, no hand-written params).
func _pure_unit(rules: Array, models: int = 1, faction: String = "") -> GameUnit:
	var u := GameUnit.new()
	_unit_seq += 1
	u.unit_id = "pure%d" % _unit_seq
	u.unit_properties = {"player_id": 1, "name": "Pure", "quality": 4, "defense": 4,
		"game_system": "gf", "special_rules": rules}
	if not faction.is_empty():
		u.unit_properties["faction_folder"] = faction
	for i in range(models):
		var m := ModelInstance.new()
		m.is_alive = true
		u.models.append(m)
	return u


## Seeds the tray so its first die is a 3: a pass on 3+ (with the +1), a fail on 4+ (without).
func _seed_first_die_three() -> void:
	var rng := RandomNumberGenerator.new()
	for candidate in range(200):
		rng.seed = candidate
		if rng.randi_range(1, 6) == 3:
			_main.seed_tray_rng(candidate)
			return
	fail("no seed rolls a 3 first")


func _log_text() -> String:
	var out := ""
	for entry in _main.battle_log.entries():
		out += str(entry["text"]) + "\n"
	return out


func _melee_profile() -> Dictionary:
	return {"name": "Blades", "attacks": 6, "ap": 0, "deadly": 0, "range": 0, "rules": []}


func test_a_plain_banner_unit_shot_at_five_keeps_its_bonus_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var target := _board_unit(1, ["Banner"])
	_seed_first_die_three()
	var passed: bool = await _main._solo_morale_test(target, "Victim", false, "", 5.0, -1.0)
	assert_bool(passed).override_failure_message(
		"a plain Banner keeps its +1 inside 9\"\n" + _log_text()).is_true()
	assert_str(_log_text()).contains("gets +1 to morale test rolls")
	assert_str(_log_text()).not_contains("Valiant counts only beyond the gate")


func test_valiant_shot_at_five_loses_the_bonus_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var target := _board_unit(1, ["Valiant"])
	_seed_first_die_three()
	var passed: bool = await _main._solo_morale_test(target, "Victim", false, "", 5.0, -1.0)
	assert_bool(passed).override_failure_message(
		"Valiant inside 9\" must lose the share\n" + _log_text()).is_false()
	assert_bool(target.is_shaken).is_true()
	assert_str(_log_text()).contains("Valiant counts only beyond the gate")


func test_valiant_shot_at_ten_keeps_the_bonus_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var target := _board_unit(1, ["Valiant"])
	_seed_first_die_three()
	var passed: bool = await _main._solo_morale_test(target, "Victim", false, "", 10.0, -1.0)
	assert_bool(passed).override_failure_message(
		"Valiant over 9\" keeps the +1\n" + _log_text()).is_true()
	assert_str(_log_text()).contains("gets +1 to morale test rolls")
	assert_str(_log_text()).not_contains("Valiant counts only beyond the gate")


func test_a_minority_valiant_carrier_gets_nothing_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var majority := _pure_unit(["Valiant"], 1)
	assert_int(SoloController.valiant_bonus_of(majority)).is_equal(1)
	assert_int(SoloController.morale_bonus_of(majority)).is_equal(1)
	var minority := _pure_unit(["Valiant"], 1)
	minority.unit_properties["attached_heroes"] = [_pure_unit([], 1)]
	assert_int(SoloController.valiant_bonus_of(minority)).is_equal(0)
	assert_int(SoloController.morale_bonus_of(minority)).is_equal(0)


func test_epoch_72_keeps_the_old_valiant_reading() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var target := _board_unit(1, ["Valiant"])
	_seed_first_die_three()
	var passed: bool = await _main._solo_morale_test(target, "Victim", false, "", 5.0, -1.0)
	assert_bool(passed).override_failure_message(
		"epoch 72 keeps the unconditional Valiant reading\n" + _log_text()).is_true()
	assert_str(_log_text()).contains("gets +1 to morale test rolls")
	assert_str(_log_text()).not_contains("Valiant counts only beyond the gate")


func test_below_epoch_73_the_ai_estimate_keeps_the_plain_banner_read() -> void:
	var epoch := AiActRecorder.rules_epoch
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var alias := AiEv.ctx_for(_pure_unit(["Hive Bond"], 1, "alien_hives"))
	var plain := AiEv.ctx_for(_pure_unit(["Banner"], 1))
	AiActRecorder.rules_epoch = epoch
	assert_int(int(alias.get("morale_bonus", -1))).is_equal(0)
	assert_int(int(alias.get("valiant_bonus", -1))).is_equal(0)
	assert_int(int(plain.get("morale_bonus", -1))).is_equal(1)


const INCH := 0.0254


## A melee unit for the charge-call-site test: `models` models at `x` inches,
## one melee weapon with `attacks` per model, the given rules.
func _melee_unit(pid: int, unit_name: String, x: float, models: int, weapon: String,
		rules: Array, defense: int, tough: int = 1, attacks: int = 1) -> GameUnit:
	var positions: Array = []
	for i in range(models):
		positions.append(Vector3(x * INCH, 0.0, 0.02 * i))
	var u := Boot.make_unit(_main, pid, unit_name, positions)
	var w := OPRApiClient.OPRWeapon.new()
	w.name = weapon
	w.range_value = 0
	w.attacks = attacks
	var opr := OPRApiClient.OPRUnit.new()
	var ws: Array[OPRApiClient.OPRWeapon] = [w]
	opr.weapons = ws
	u.source_type = "opr"
	u.source_data = opr
	u.unit_properties["game_system"] = "gf"
	u.unit_properties["special_rules"] = rules + (["Tough(%d)" % tough] if tough > 1 else [])
	u.unit_properties["defense"] = defense
	for m in u.models:
		(m as ModelInstance).wounds_max = tough
		(m as ModelInstance).wounds_current = tough
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## MOR-09b: the band belongs to the unit that was CHARGED. A Valiant charger
## that loses the melee inside 6" is not "charged", so its own test keeps the +1.
func test_a_valiant_charger_inside_the_band_keeps_its_bonus(timeout := 90000) -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	_main.solo_ai_slots = {1: true, 2: true}
	var charger := _melee_unit(2, "Charger", 0.0, 1, "Blade", ["Valiant"], 2, 9, 0)
	var defender := _melee_unit(1, "Defender", 1.0, 1, "Spikes", [], 6, 9, 30)
	_main.seed_tray_rng(7)
	await _main._run_ai_melee({"unit": charger, "target": defender, "charge_from_in": 1.0})
	assert_str(_log_text()).not_contains("Charger gets no +1 from a charge from 6")
	assert_str(_log_text()).contains("Banner: Charger gets +1 to morale test rolls")


## MOR-09b: a Valiant HERO does not lift a Valiant-less host past the majority.
func test_a_valiant_hero_does_not_lift_a_plain_host_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var host := _pure_unit([], 3)
	host.unit_properties["attached_heroes"] = [_pure_unit(["Valiant"], 1)]
	assert_int(SoloController.valiant_bonus_of(host)).is_equal(0)
	assert_int(SoloController.morale_bonus_of(host)).is_equal(0)
	var valiant_host := _pure_unit(["Valiant"], 3)
	valiant_host.unit_properties["attached_heroes"] = [_pure_unit([], 1)]
	assert_int(SoloController.valiant_bonus_of(valiant_host)).is_equal(1)
	assert_int(SoloController.morale_bonus_of(valiant_host)).is_equal(1)


func test_the_ai_charge_estimate_prices_the_valiant_gate() -> void:
	var epoch := AiActRecorder.rules_epoch
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var us := AiEv.ctx_for(_pure_unit(["Valiant"], 1))
	assert_int(int(us.get("morale_bonus", 0))).is_equal(1)
	assert_int(int(us.get("valiant_bonus", 0))).is_equal(1)
	var our_melee := [_melee_profile()]
	var their_melee := [_melee_profile()]
	var them := AiEv.ctx_for(_pure_unit([], 1))
	var near: float = AiEv.charge_score(our_melee, us, their_melee, them, 5.0)
	var far: float = AiEv.charge_score(our_melee, us, their_melee, them, 10.0)
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var old_near: float = AiEv.charge_score(our_melee, us, their_melee, them, 5.0)
	AiActRecorder.rules_epoch = epoch
	assert_bool(far > near).override_failure_message(
		"inside 6\" the Valiant share must not relax the weight (near=%f far=%f)" % [near, far]).is_true()
	assert_float(old_near).is_equal_approx(far, 0.0001)


## FAB-C20/C-F21: the positive morale line names the Banner-family entry that actually paid, not the
## generic word "Banner". Numbers and the pass target stay put.
func test_a_valiant_unit_names_valiant_in_the_positive_morale_line() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var target := _board_unit(1, ["Valiant"])
	_seed_first_die_three()
	var passed: bool = await _main._solo_morale_test(target, "Victim", false, "", 10.0, -1.0)
	assert_bool(passed).override_failure_message(
		"Valiant over 9\" keeps its +1\n" + _log_text()).is_true()
	assert_str(_log_text()).override_failure_message(
		"the line must name Valiant, not Banner (log: %s)" % _log_text()) \
		.contains("Valiant: Victim gets +1 to morale test rolls (passes on 3+)")


func test_hold_the_line_names_itself_in_the_positive_morale_line() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var target := _board_unit(1, ["Hold the Line"])
	target.unit_properties["faction_folder"] = "human_defense_force"
	_seed_first_die_three()
	var passed: bool = await _main._solo_morale_test(target, "Victim", false, "", 10.0, -1.0)
	assert_bool(passed).override_failure_message(
		"Hold the Line keeps its +1 over 9\"\n" + _log_text()).is_true()
	assert_str(_log_text()).override_failure_message(
		"the line must name Hold the Line, not Banner (log: %s)" % _log_text()) \
		.contains("Hold the Line: Victim gets +1 to morale test rolls (passes on 3+)")


func test_bravery_names_itself_in_the_positive_morale_line() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var target := _board_unit(1, ["Bravery"])
	_seed_first_die_three()
	var passed: bool = await _main._solo_morale_test(target, "Victim", false, "", 10.0, -1.0)
	assert_bool(passed).override_failure_message(
		"Bravery keeps its +1\n" + _log_text()).is_true()
	assert_str(_log_text()).override_failure_message(
		"the line must name Bravery, not Banner (log: %s)" % _log_text()) \
		.contains("Bravery: Victim gets +1 to morale test rolls (passes on 3+)")


## The literal Banner entry still says "Banner", and the Morale(X) form keeps the entry's name.
func test_plain_banner_and_the_morale_rating_form_keep_their_names() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var plain := _board_unit(1, ["Banner"])
	_seed_first_die_three()
	var passed: bool = await _main._solo_morale_test(plain, "Victim", false, "", 10.0, -1.0)
	assert_bool(passed).is_true()
	assert_str(_log_text()).contains("Banner: Victim gets +1 to morale test rolls (passes on 3+)")
	var rated := _board_unit(1, ["Morale(2)", "Hold the Line"], "Rated")
	rated.unit_properties["faction_folder"] = "human_defense_force"
	_seed_first_die_three()
	var rated_passed: bool = await _main._solo_morale_test(rated, "Rated", false, "", 10.0, -1.0)
	assert_bool(rated_passed).override_failure_message(
		"Morale(2) + Hold the Line passes on 2+\n" + _log_text()).is_true()
	assert_str(_log_text()).contains(
		"Morale(2) + Hold the Line: Rated gets +3 to morale test rolls (passes on 2+)")
