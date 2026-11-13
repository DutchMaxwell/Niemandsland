extends GdUnitTestSuite
## One-core P3 step 62 (O14 (1b)): the transport doors - Disembark, Unload, Embark, Stay aboard - spend an activation, so
## with NML_ONE_CORE_ACTIVATION on a lifecycle unit whose activation is not open is refused there, with the drag gate's
## sentences: "Activate <Unit> first." (O15 (1)), or the O5 sentence while another unit's activation is open.
## Real: the main scene, its radial controller's dispatch, the army manager's transport state, the NmlCore extension.
## Constructed: bare units (E2EBoot.make_unit) with an OPRUnit profile; the truck/cargo/spare fixture of
## e2e_embark_activation_test.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")

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
	_main.opr_army_manager.current_round = 1
	CoreActivation._env = 1   # the flag ON; the flag-off case resets it itself


func after_test() -> void:
	RulesRegistry.reset_cache()
	CoreActivation.reset_all(_main)
	CoreActivation._env = -1
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _unit(uname: String, at: Vector3, rules: Array = [], pid: int = 1) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, uname, [at])
	u.unit_properties["special_rules"] = rules
	var src := OPRApiClient.OPRUnit.new()
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Rifle"
	w.range_value = 24
	src.weapons.append(w)
	u.source_data = src
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## A Transport(6) truck at the origin, its cargo (aboard or beside it) and an idle spare, so the round stays open.
func _truck_and_cargo(aboard: bool) -> Array:
	var truck := _unit("Truck", Vector3.ZERO, ["Transport(6)"])
	var cargo := _unit("Riders", Vector3(0.04, 0, 0))
	_unit("Spare", Vector3(1.0, 0, 0))
	if aboard:
		_main.opr_army_manager.set_unit_embarked(cargo, truck, true)
	return [truck, cargo]


func _lines(text: String) -> int:
	return _main.battle_log.entries().filter(func(e: Dictionary) -> bool: return str(e["text"]) == text).size()


func _act(action: String, context: Dictionary) -> void:
	await _main.radial_menu_controller._on_action_selected(action, context)


func test_disembark_needs_the_cargos_own_start() -> void:
	var tc := _truck_and_cargo(true)
	await _act("disembark", {"disembark_unit": tc[1]})
	assert_object(_main.opr_army_manager.transport_of(tc[1])).override_failure_message("disembarked").is_equal(tc[0])
	assert_int(_lines("Activate Riders first.")).is_equal(1)
	assert_bool(CoreActivation.open_session(_main, tc[1])).override_failure_message("no session").is_true()
	await _act("disembark", {"disembark_unit": tc[1]})
	assert_object(_main.opr_army_manager.transport_of(tc[1])).override_failure_message("still aboard").is_null()


## Unload is the CARGO's activation: the transport's own open activation does not let the cargo out.
func test_unload_asks_the_cargo_not_the_transport() -> void:
	var tc := _truck_and_cargo(true)
	assert_bool(CoreActivation.open_session(_main, tc[0])).override_failure_message("no session").is_true()
	await _act("unload_cargo_0", {"cargo_units": [tc[1]], "game_unit": tc[0]})
	assert_object(_main.opr_army_manager.transport_of(tc[1])).override_failure_message("unloaded").is_equal(tc[0])
	assert_int(_lines("Finish Truck's activation first.")).is_equal(1)


func test_embark_while_another_activation_is_open_names_it() -> void:
	var tc := _truck_and_cargo(false)
	CoreActivation.open_session(_main, _unit("Alpha", Vector3(-1.0, 0, 0)))
	await _act("embark_0", {"game_unit": tc[1], "embark_targets": [tc[0]]})
	assert_object(_main.opr_army_manager.transport_of(tc[1])).override_failure_message("embarked").is_null()
	assert_int(_lines("Finish Alpha's activation first.")).is_equal(1)


func test_stay_aboard_needs_the_start() -> void:
	var tc := _truck_and_cargo(true)
	await _act("stay_embarked", {"disembark_unit": tc[1]})
	assert_int(_lines("Activate Riders first.")).is_equal(1)
	assert_bool((tc[1] as GameUnit).is_activated).override_failure_message("the stay was spent").is_false()
	assert_int(_lines("Riders stays aboard")).is_equal(0)


func test_with_the_flag_off_disembark_needs_no_start() -> void:
	CoreActivation._env = 0
	var tc := _truck_and_cargo(true)
	await _act("disembark", {"disembark_unit": tc[1]})
	assert_object(_main.opr_army_manager.transport_of(tc[1])).is_null()


## ---- step 63: attack, cast, spot and the auto verbs ----

const INCH := 0.0254


## A human Utility Buff bearer (the Defense Buff entry of e2e_defense_buff_record_test) beside a friend it could buff,
## 12" from an enemy it could spot.
func _buffer() -> GameUnit:
	RulesRegistry.reset_cache()
	RulesRegistry._cache["aof"] = {"factions": {"human_empire": {
		"Defense Buff": {"primitive": "Utility Buff", "rated": false, "book_version": "3.5.3",
			"params": {"def_mod": 1, "target": "friendly", "max_targets": 1, "range_in": 12, "once": true}},
	}}, "common": {}}
	var u := _unit("Marshal", Vector3.ZERO, ["Defense Buff"])
	var friend := _unit("Line Infantry", Vector3(6.0 * INCH, 0, 0))
	for g in [u, friend]:
		g.unit_properties["game_system"] = "aof"
		g.unit_properties["faction_folder"] = "human_empire"
	_unit("Raiders", Vector3(12.0 * INCH, 0, 0), [], 2)
	return u


func _spot_lines() -> int:
	return _main.battle_log.entries().filter(func(e: Dictionary) -> bool: return str(e["text"]).contains("to spot")).size()


## Shoot opens nothing and spends nothing (the Utility Buff stamp) before the Start; after it, the pick opens.
func test_shoot_without_a_start_spends_nothing() -> void:
	var u := _buffer()
	await _main.solo_begin_targeting(u, false)
	assert_int(_lines("Activate Marshal first.")).is_equal(1)
	assert_bool(_main._solo_target_mode.is_empty()).override_failure_message("a pick opened").is_true()
	assert_bool(u.unit_properties.has("utility_buff_round")).override_failure_message("the buff was spent").is_false()
	CoreActivation.open_session(_main, u)
	await _main.solo_begin_targeting(u, false)
	assert_object(_main._solo_target_mode.get("unit")).override_failure_message("no pick after the Start").is_same(u)


## Cast, Spot and the auto verbs say the same sentence before the Start; after it, Cast and Spot open as today.
func test_cast_spot_and_auto_without_a_start_are_refused() -> void:
	var u := _buffer()
	await _main.solo_begin_cast(u)
	await _main.solo_begin_spot(u)
	await _main.solo_begin_auto(u, AiDecision.Action.ADVANCE)
	assert_int(_lines("Activate Marshal first.")).is_equal(3)
	assert_int(_lines("Marshal has no caster with spell tokens")).override_failure_message("the cast door ran").is_equal(0)
	assert_int(_spot_lines()).override_failure_message("the spot door ran").is_equal(0)
	assert_bool(_main._solo_target_mode.is_empty()).override_failure_message("a mode opened").is_true()
	CoreActivation.open_session(_main, u)
	await _main.solo_begin_cast(u)
	await _main.solo_begin_spot(u)
	assert_int(_lines("Marshal has no caster with spell tokens")).is_equal(1)
	assert_int(_spot_lines()).is_equal(1)
	assert_int(_lines("Activate Marshal first.")).is_equal(3)


func test_with_the_flag_off_the_windows_open_without_a_start() -> void:
	CoreActivation._env = 0
	var u := _buffer()
	await _main.solo_begin_cast(u)
	await _main.solo_begin_spot(u)
	_main._solo_end_targeting()
	await _main.solo_begin_targeting(u, false)
	assert_int(_lines("Marshal has no caster with spell tokens")).is_equal(1)
	assert_int(_spot_lines()).is_equal(1)
	assert_object(_main._solo_target_mode.get("unit")).is_same(u)


## The resolving doors behind the windows repeat the gate (a refusal there is a defect, reported by push_error): called
## without a Start, none of them runs its committed door - no activation-wounds snapshot (begin_activation), no spend.
## Not awaited: refused, each returns at once; a missing gate must not hang the run on the dice it would roll.
func test_the_resolving_doors_refuse_without_a_start() -> void:
	var u := _unit("Marshal", Vector3.ZERO)
	var foe := _unit("Raiders", Vector3(12.0 * INCH, 0, 0), [], 2)
	var foe2 := _unit("Scouts", Vector3(14.0 * INCH, 0, 0), [], 2)
	_main._run_human_attack(u, foe, false)
	_main._run_human_attack_split(u, foe, foe2, [])
	_main._run_player_intent(u, AiDecision.Action.ADVANCE, null, Vector3(0.1, 0, 0))
	_main._run_human_cast(u, u, {"name": "Bolt", "threshold": 1}, [foe])
	assert_int(_lines("Activate Marshal first.")).is_equal(4)
	assert_bool(_main._solo_activation_wounds_start.has(u.get_instance_id())) \
		.override_failure_message("begin_activation ran").is_false()
	assert_int(_lines("Marshal: not enough tokens for Bolt")).override_failure_message("the cast spent").is_equal(0)


## ---- step 64: Pass and Speed Feat, the spends that are not activations ----

const SPEED_FLAG := "speed_feat_used_speed_feat"


## A human Delayed Action carrier, a second human unit and three AI units: the pass is legal (3 > 2).
func _pass_board() -> Array:
	_main._solo_batch = true   # no dialogs in a headless pump
	var carrier := _unit("Wachtturm", Vector3(-0.3, 0, 0.2), ["Delayed Action"])
	var other := _unit("Alpha", Vector3(-0.3, 0, 0.4))
	for i in 3:
		_unit("Raider%d" % (i + 1), Vector3(0.3, 0, -0.2 - 0.12 * i), [], 2)
	return [carrier, other]


func _passed(carrier: GameUnit) -> bool:
	return SoloController.delayed_action_used_this_round(carrier, _main.opr_army_manager.current_round)


func test_pass_while_another_activation_is_open_names_it() -> void:
	var b := _pass_board()
	CoreActivation.open_session(_main, b[1])
	await _main.solo_begin_pass(b[0])
	assert_int(_lines("Finish Alpha's activation first.")).is_equal(1)
	assert_bool(_passed(b[0])).override_failure_message("the pass was stamped").is_false()
	assert_int(_main.battle_log.entries().filter(func(e: Dictionary) -> bool: return str(e["text"]).contains("passes the turn")).size()) \
		.override_failure_message("the turn passed").is_equal(0)


func test_pass_with_no_activation_open_works_as_today() -> void:
	var b := _pass_board()
	await _main.solo_begin_pass(b[0])
	assert_bool(_passed(b[0])).override_failure_message("the pass was refused").is_true()
	assert_int(_lines("Activate Wachtturm first.")).is_equal(0)
	await E2EBoot.settle(get_tree())


## The registry's AoF orc "Speed Feat" (Quick, once per game), as e2e_speed_feat_radial_test reads it.
func test_speed_feat_needs_the_start() -> void:
	var u := _unit("Boyz", Vector3.ZERO, ["Speed Feat"])
	u.unit_properties["game_system"] = "aof"
	u.unit_properties["faction_folder"] = "orcs"
	_main.solo_spend_speed_feat(u)
	assert_int(_lines("Activate Boyz first.")).is_equal(1)
	assert_bool(bool(u.unit_properties.get(SPEED_FLAG, false))).override_failure_message("the feat was spent").is_false()
	CoreActivation.open_session(_main, u)
	_main.solo_spend_speed_feat(u)
	assert_bool(bool(u.unit_properties.get(SPEED_FLAG, false))).override_failure_message("no spend after the Start").is_true()
