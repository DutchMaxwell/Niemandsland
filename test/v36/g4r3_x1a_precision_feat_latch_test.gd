extends GdUnitTestSuite
## AI-G4 round 3, row R3-X1a (rules 3.6, EPOCH_73_V36, lead ruling 1): the Precision Feat is ONE once-per-game latch
## shared by shooting AND melee. The bearer uses it at its FIRST attack of any kind (a strike-back is an attack too),
## then it is spent and written to the act ledger (`feats_used`). The table's hit modifier read the Feat's
## `all_attacks` entry on every strike and every shot forever and never looked at `uses_per_game`.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254
const FEAT_NOTE := "Precision Feat +1"

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


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0   # statics leak across gdUnit tests — restore
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _weapon(weapon_name: String, range_in: int, attacks: int) -> OPRApiClient.OPRWeapon:
	var w := OPRApiClient.OPRWeapon.new()
	w.name = weapon_name
	w.range_value = range_in
	w.attacks = attacks
	w.count = 1
	return w


## One 10-wound model with a real Club (and a Rifle) profile, built the way the e2e suites build armed units.
func _unit(pid: int, unit_name: String, x_in: float, bearer: bool) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, [Vector3(x_in * INCH, 0, 0)])
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
		# The shape import gives a Feat carrier: the book section that prints the rule + the item grant.
		u.unit_properties["game_system"] = "aof"
		u.unit_properties["faction_folder"] = "ghostly_undead"
		u.unit_properties["item_grants"] = {"Relic": ["Precision Feat"]}
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func _log_text() -> String:
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


func _feat_count() -> int:
	return _log_text().count(FEAT_NOTE)


## The Guard charges the bearer: the bearer's strike-back is its attack.
func _charge(guard: GameUnit, bearer: GameUnit) -> void:
	guard.is_fatigued = false
	bearer.is_fatigued = false
	E2EBoot.place_unit_at(guard, Vector3(1.0 * INCH, 0, 0))
	_main.seed_tray_rng(11)
	await _main._run_ai_melee({"unit": guard, "target": bearer, "charge_from_in": 1.0, "dangerous_wounds_taken": 0})
	await E2EBoot.settle(get_tree())


## One AI volley by the bearer, in the shape `_run_ai_shooting` builds.
func _volley(bearer: GameUnit, guard: GameUnit) -> void:
	E2EBoot.place_unit_at(guard, Vector3(10.0 * INCH, 0, 0))
	var profiles: Array = AiShooting.profiles_in_range([_weapon("Rifle", 24, 4)], 0.0)
	var shots: Array = [{"member": bearer, "quality": bearer.get_quality(),
		"alive": bearer.get_alive_count(), "max": bearer.models.size(),
		"reach": 24, "profile": profiles[0]}]
	_main.seed_tray_rng(5)
	await _main._solo_resolve_ai_volley(bearer, guard, shots, false)
	await E2EBoot.settle(get_tree())


func test_the_feat_applies_to_the_first_strike_back_only_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var bearer := _unit(2, "Horde", 0.0, true)
	var guard := _unit(1, "Guard", 1.0, false)
	await _charge(guard, bearer)
	assert_int(_feat_count()).is_equal(1)   # the first attack of the bearer carries the +1
	await _charge(guard, bearer)
	assert_int(_feat_count()).override_failure_message("the spent Feat applied again:\n%s" % _log_text()).is_equal(1)


func test_a_volley_spends_the_latch_the_melee_then_finds_closed_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var bearer := _unit(2, "Horde", 0.0, true)
	var guard := _unit(1, "Guard", 1.0, false)
	await _volley(bearer, guard)
	assert_int(_feat_count()).is_equal(1)   # the bearer's first attack is the shot
	await _charge(guard, bearer)
	assert_int(_feat_count()).override_failure_message("the Feat spent on the shot applied in melee:\n%s" % _log_text()).is_equal(1)


func test_the_spent_latch_is_written_to_the_act_ledger_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var bearer := _unit(2, "Horde", 0.0, true)
	var guard := _unit(1, "Guard", 1.0, false)
	assert_bool((AiActRecorder._ledger_of(bearer) as Dictionary).has("feats_used")).is_false()
	await _charge(guard, bearer)
	assert_array((AiActRecorder._ledger_of(bearer) as Dictionary).get("feats_used", [])).is_equal(["Precision Feat"])


## Below 73 nothing changes: the Feat stays an every-attack bonus and the ledger stays silent.
func test_below_epoch_73_the_feat_is_unchanged() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36 - 1
	var bearer := _unit(2, "Horde", 0.0, true)
	var guard := _unit(1, "Guard", 1.0, false)
	await _charge(guard, bearer)
	await _charge(guard, bearer)
	assert_int(_feat_count()).is_equal(2)
	assert_bool((AiActRecorder._ledger_of(bearer) as Dictionary).has("feats_used")).is_false()
