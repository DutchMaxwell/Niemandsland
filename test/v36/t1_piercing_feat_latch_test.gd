extends GdUnitTestSuite
## Audit finding T-1 (rules 3.6, EPOCH_73_V36): the Ogres item feat "Piercing Feat" grants +1 AP on every attack of
## the bearer's FIRST attacking exchange, then never again. The core grants it that way; the table's conditional-AP
## read has no arm for the feat's `any_attack` condition, so the bearer got nothing, ever.

const Boot := preload("res://test/e2e/e2e_boot.gd")
const CONTEXTS := ["aof", "aofr", "aofs"]
const WEAPON := {"name": "Club", "attacks": 6, "ap": 0, "rules": []}
const TRAP := {"name": "Trap", "ap": 0, "deadly": 0, "rules": []}
const PART := [{"name": "Piercing Feat", "bonus": 1}]
const INCH := 0.0254
const PAID := "Piercing Feat: AP(+1)"   # the table's per-attack AP trace line
const SPEND := "Piercing Feat: %s spends its once-per-game feat on this attack"

var _runner: GdUnitSceneRunner
var _main: Node
var _roots: Array
var _epoch0: int


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch
	Boot.arm_harness_mode()
	_roots = Boot.root_children(get_tree())
	_runner = scene_runner(Boot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {1: true, 2: true}   # both seats AI: saves and strike-backs auto-resolve, no dialog
	_main._ensure_solo_controller()
	_main.solo_controller.ai_slot = 2
	_main.solo_controller.human_slot = 1
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	_main._solo_batch = true


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0   # statics leak across gdUnit tests - restore
	Boot.free_stray_root_nodes(get_tree(), _roots)
	_main = null
	_runner = null


## One alive model; the bearer carries the feat through an item grant, the way the import records an Ogres upgrade.
func _plain(system: String, bearer: bool) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = "t1_%s_%s" % [system, bearer]
	u.unit_properties = {"player_id": 2, "name": "Fixture", "quality": 4, "defense": 4,
		"special_rules": [], "game_system": system, "faction_folder": "ogres"}
	if bearer:
		u.unit_properties["item_grants"] = {"Doom of Kingdoms": ["Piercing Feat"]}
	var model := ModelInstance.new()
	model.is_alive = true
	u.models.append(model)
	return u


func test_the_feat_pays_its_ap_while_unspent_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	for system in CONTEXTS:
		var bearer := _plain(system, true)
		var foe := _plain(system, false)
		assert_array(_main._solo_conditional_ap_parts(WEAPON, bearer, foe, false, 10.0, false)).is_equal(PART)
		assert_array(_main._solo_conditional_ap_parts(WEAPON, bearer, foe, false, -1.0, true)).is_equal(PART)


func test_a_spent_latch_pays_nothing() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	for system in CONTEXTS:
		var bearer := _plain(system, true)
		var foe := _plain(system, false)
		bearer.unit_properties[SoloController.shot_feat_flag("Piercing Feat")] = true
		assert_array(_main._solo_conditional_ap_parts(WEAPON, bearer, foe, false, 10.0, false)).is_empty()
		assert_array(_main._solo_conditional_ap_parts(WEAPON, bearer, foe, false, -1.0, true)).is_empty()


func test_below_epoch_73_nothing_changes() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36 - 1
	for system in CONTEXTS:
		var bearer := _plain(system, true)
		var foe := _plain(system, false)
		assert_array(_main._solo_conditional_ap_parts(WEAPON, bearer, foe, false, 10.0, false)).is_empty()
		assert_array(_main._solo_conditional_ap_parts(WEAPON, bearer, foe, false, -1.0, true)).is_empty()


func test_a_hit_source_without_attacks_gets_no_feat() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	for system in CONTEXTS:
		var bearer := _plain(system, true)
		assert_array(_main._solo_conditional_ap_parts(TRAP, bearer, bearer, false, -1.0, true)).is_empty()


func _weapon(weapon_name: String, range_in: int, attacks: int) -> OPRApiClient.OPRWeapon:
	var w := OPRApiClient.OPRWeapon.new()
	w.name = weapon_name
	w.range_value = range_in
	w.attacks = attacks
	w.count = 1
	return w


## One 10-wound model with a real Club (and a Rifle) profile; the bearer is an Ogres unit with the item grant.
func _unit(pid: int, unit_name: String, x_in: float, bearer: bool) -> GameUnit:
	var u := Boot.make_unit(_main, pid, unit_name, [Vector3(x_in * INCH, 0, 0)])
	var model := u.models[0] as ModelInstance
	model.model_index = 0
	model.wounds_max = 10
	model.wounds_current = 10
	var ws: Array[OPRApiClient.OPRWeapon] = [_weapon("Club", 0, 6), _weapon("Rifle", 24, 4)]
	var src := OPRApiClient.OPRUnit.new()
	src.weapons = ws
	u.source_type = "opr"
	u.source_data = src
	if bearer:
		u.unit_properties["game_system"] = "aof"
		u.unit_properties["faction_folder"] = "ogres"
		u.unit_properties["item_grants"] = {"Doom of Kingdoms": ["Piercing Feat"]}
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func _count(needle: String) -> int:
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text.count(needle)


## The Guard charges the bearer: the bearer's strike-back is its attack.
func _charge(guard: GameUnit, bearer: GameUnit) -> void:
	guard.is_fatigued = false
	bearer.is_fatigued = false
	Boot.place_unit_at(guard, Vector3(1.0 * INCH, 0, 0))
	_main.seed_tray_rng(11)
	await _main._run_ai_melee({"unit": guard, "target": bearer, "charge_from_in": 1.0, "dangerous_wounds_taken": 0})
	await Boot.settle(get_tree())


## One AI volley by the bearer, in the shape `_run_ai_shooting` builds.
func _volley(bearer: GameUnit, guard: GameUnit) -> void:
	Boot.place_unit_at(guard, Vector3(10.0 * INCH, 0, 0))
	var profiles: Array = AiShooting.profiles_in_range([_weapon("Rifle", 24, 4)], 0.0)
	var shots: Array = [{"member": bearer, "quality": bearer.get_quality(),
		"alive": bearer.get_alive_count(), "max": bearer.models.size(),
		"reach": 24, "profile": profiles[0]}]
	_main.seed_tray_rng(5)
	await _main._solo_resolve_ai_volley(bearer, guard, shots, false)
	await Boot.settle(get_tree())


func test_a_volley_spends_the_latch_and_the_next_shot_pays_nothing() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var bearer := _unit(2, "Horde", 0.0, true)
	var guard := _unit(1, "Guard", 1.0, false)
	await _volley(bearer, guard)
	assert_int(_count(PAID)).override_failure_message("the first volley did not pay the feat").is_equal(1)
	assert_int(_count(SPEND % bearer.get_name())).is_equal(1)
	assert_bool(bool(bearer.unit_properties.get(SoloController.shot_feat_flag("Piercing Feat"), false))).is_true()
	assert_array(_main._solo_conditional_ap_parts(WEAPON, bearer, guard, false, 10.0, false)).is_empty()
	await _volley(bearer, guard)
	assert_int(_count(PAID)).override_failure_message("the second volley paid the spent feat again").is_equal(1)


func test_the_first_strike_back_spends_it_and_the_next_attacks_pay_nothing() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var bearer := _unit(2, "Horde", 0.0, true)
	var guard := _unit(1, "Guard", 1.0, false)
	await _charge(guard, bearer)
	assert_int(_count(PAID)).override_failure_message("the first strike-back did not pay the feat").is_equal(1)
	assert_int(_count(SPEND % bearer.get_name())).is_equal(1)
	assert_array(_main._solo_conditional_ap_parts(WEAPON, bearer, guard, false, -1.0, true)).is_empty()
	await _charge(guard, bearer)
	assert_int(_count(PAID)).override_failure_message("the second strike-back paid the spent feat again").is_equal(1)
	await _volley(bearer, guard)
	assert_int(_count(PAID)).override_failure_message("a later shot paid the spent feat").is_equal(1)


func test_the_spent_latch_is_written_to_the_act_ledger() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var bearer := _unit(2, "Horde", 0.0, true)
	var guard := _unit(1, "Guard", 1.0, false)
	assert_bool((AiActRecorder._ledger_of(bearer) as Dictionary).has("feats_used")).is_false()
	await _charge(guard, bearer)
	assert_array((AiActRecorder._ledger_of(bearer) as Dictionary).get("feats_used", [])).is_equal(["Piercing Feat"])
