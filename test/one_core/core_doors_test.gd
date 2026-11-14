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


## ---- step 65b: the regiment re-rank doors (the radial's frontage entry, the B key) ----

## A formed regiment block of six models at frontage 5 for this table's unit `uname` (regiment_frontage_cycle_test's
## fixture on the real army manager).
func _regiment(uname: String, x: float) -> RegimentTray:
	var at: Array = []
	for i in 6:
		at.append(Vector3(x + 0.03 * i, 0, 0))
	var gu := E2EBoot.make_unit(_main, 1, uname, at)
	var src := OPRApiClient.OPRUnit.new()
	src.weapons.append(OPRApiClient.OPRWeapon.new())
	gu.source_data = src
	_main.opr_army_manager.game_units[gu.unit_id] = gu
	var members := RegimentTray.collect_members(gu)
	var tray := RegimentTray.new()
	_main.add_child(tray)
	tray.form(members.nodes, members.footprints, 5)
	tray.set_meta("regiment", Regiment.new(gu, tray, 5))
	gu.unit_properties["frontage"] = 5
	_main.opr_army_manager.regiments[gu.unit_id] = tray.get_meta("regiment")
	return tray


## The B key on the selection `trays` (main's own key handler; B is never an echo).
func _press_b(trays: Array) -> void:
	_main.object_manager._selected_objects.assign(trays)
	var ev := InputEventKey.new()
	ev.keycode = KEY_B
	ev.pressed = true
	_main._unhandled_key_input(ev)


## Step 65b (O14 (1b)): a block that was not started is not re-ranked by either door - frontage 5 stays, one
## "Activate <Unit> first." per press, also when two refused blocks are selected; after the Start both doors re-rank.
func test_the_rerank_doors_need_the_start() -> void:
	var tray := _regiment("Spears", 0.0)
	var other := _regiment("Pikes", 0.5)
	await _act("regiment_frontage", {"regiment_tray": tray})
	assert_int(tray.frontage).override_failure_message("re-ranked from the radial without a Start").is_equal(5)
	_press_b([tray, other])
	assert_int(tray.frontage + other.frontage).override_failure_message("re-ranked by B without a Start").is_equal(10)
	assert_int(_lines("Activate Spears first.")).override_failure_message("one line per press").is_equal(2)
	assert_int(_lines("Activate Pikes first.")).is_equal(0)
	assert_bool(CoreActivation.open_session(_main, (tray.get_meta("regiment") as Regiment).game_unit)).is_true()
	await _act("regiment_frontage", {"regiment_tray": tray})
	assert_int(tray.frontage).override_failure_message("no radial re-rank after the Start").is_equal(4)
	_press_b([tray, other])
	assert_int(tray.frontage).override_failure_message("no B re-rank after the Start").is_equal(3)
	assert_int(other.frontage).override_failure_message("B re-ranked a block that was not started").is_equal(5)
	assert_int(_lines("Activate Pikes first.") + _lines("Finish Spears's activation first.")) \
		.override_failure_message("a refusal line although a block re-ranked").is_equal(0)


## Step 65b: flag off, both doors re-rank as today and say nothing.
func test_with_the_flag_off_the_rerank_doors_work_as_today() -> void:
	CoreActivation._env = 0
	var tray := _regiment("Spears", 0.0)
	await _act("regiment_frontage", {"regiment_tray": tray})
	_press_b([tray])
	assert_int(tray.frontage).is_equal(3)
	assert_int(_lines("Activate Spears first.")).is_equal(0)


## Screen point whose y=0 table-plane ray hit is (wx, wz).
func _screen(wx: float, wz: float) -> Vector2:
	return _main.get_viewport().get_camera_3d().unproject_position(Vector3(wx, 0.0, wz))


## A real drag of `tray` by 0.1 m along x (ObjectManager's own start/update/stop); the block's moved distance.
func _drag_block(tray: RegimentTray) -> float:
	var om: Node3D = _main.object_manager
	om._selected_objects.assign([tray])
	var from: Vector3 = tray.global_position
	om._start_dragging(_screen(from.x, from.z))
	om._update_drag(_screen(from.x + 0.1, from.z))
	await _runner.simulate_frames(1)
	om._stop_dragging()
	await _runner.simulate_frames(2)
	return tray.global_position.distance_to(from)


## Step 65b (step 30's gap): a block is dragged as its tray, which carries no "game_unit" meta; the drag gate finds the
## unit through the tray's Regiment, so a block that was not started does not move and says why; after the Start it
## does.
func test_a_block_that_was_not_started_cannot_be_dragged() -> void:
	var tray := _regiment("Spears", 0.0)
	assert_float(await _drag_block(tray)).override_failure_message("dragged without a Start").is_less(0.001)
	assert_int(_lines("Activate Spears first.")).is_equal(1)
	assert_bool(CoreActivation.open_session(_main, (tray.get_meta("regiment") as Regiment).game_unit)).is_true()
	assert_float(await _drag_block(tray)).override_failure_message("no drag after the Start").is_greater(0.05)


## ---- step 68 (O16): the effects that add, remove or re-host a unit commit the activation like a die ----

## The activation buttons the presented card shows, sorted.
func _card_buttons() -> Array:
	var out: Array = []
	for n: Node in _main.unit_dock.find_children("*", "Button", true, false):
		var b := n as Button
		if b.is_visible_in_tree() and b.text in ["Activate", "End activation", "Cancel"]:
			out.append(b.text)
	out.sort()
	return out


## The Reinforcement sacrifice has no undo, so it closes Cancel for the unit (its card keeps only "End activation"); with
## ANOTHER unit's activation open it is refused with the O5 sentence and nothing dies.
func test_the_reinforcement_sacrifice_commits_the_activation_and_waits_for_a_free_table() -> void:
	_main._solo_batch = true
	var rats := _unit("Rats", Vector3.ZERO, ["Reinforcement"])
	rats.is_shaken = true
	var alpha := _unit("Alpha", Vector3(1.0, 0, 0))
	assert_bool(CoreActivation.open_session(_main, alpha)).is_true()
	await _main.solo_begin_reinforcement(rats)
	assert_int(_lines("Finish Alpha's activation first.")).is_equal(1)
	assert_int(rats.get_alive_count()).override_failure_message("the sacrifice ran with another unit open").is_equal(1)
	CoreActivation.close_session(_main, alpha.unit_id)
	assert_bool(CoreActivation.open_session(_main, rats)).is_true()
	_main.unit_dock.present_unit(rats)
	await E2EBoot.settle(get_tree())
	assert_array(_card_buttons()).is_equal(["Cancel", "End activation"])
	await _main.solo_begin_reinforcement(rats)
	await E2EBoot.settle(get_tree())
	assert_int(rats.get_alive_count()).override_failure_message("no sacrifice").is_equal(0)
	assert_bool(CoreActivation.can_cancel(rats.unit_id)).override_failure_message("Cancel stays after the sacrifice").is_false()
	assert_array(_card_buttons()).is_equal(["End activation"])


## Disembark and Unload take the unit out of its transport (no un-disembark exists): either closes the unit's own Cancel,
## before begin_activation runs, and keeps the reason.
func test_disembark_and_unload_commit_the_activation() -> void:
	var tc := _truck_and_cargo(true)
	assert_bool(CoreActivation.open_session(_main, tc[1])).is_true()
	assert_bool(CoreActivation.can_cancel((tc[1] as GameUnit).unit_id)).is_true()
	await _act("disembark", {"disembark_unit": tc[1]})
	assert_bool(CoreActivation.can_cancel((tc[1] as GameUnit).unit_id)).override_failure_message("Cancel stays after Disembark").is_false()
	assert_str(str(CoreActivation._sessions[(tc[1] as GameUnit).unit_id].get("committed", ""))).is_equal("disembark")
	CoreActivation.reset_all(_main)
	var tu := _truck_and_cargo(true)
	assert_bool(CoreActivation.open_session(_main, tu[1])).is_true()
	await _act("unload_cargo_0", {"cargo_units": [tu[1]], "game_unit": tu[0]})
	assert_bool(CoreActivation.can_cancel((tu[1] as GameUnit).unit_id)).override_failure_message("Cancel stays after Unload").is_false()
	assert_str(str(CoreActivation._sessions[(tu[1] as GameUnit).unit_id].get("committed", ""))).is_equal("unload")


## A commit closes THAT unit's Cancel only (two sessions are set up by hand: the lock never lets the doors meet two), and
## committing twice changes nothing.
func test_a_commit_closes_only_its_own_units_cancel() -> void:
	var a := _unit("Alpha", Vector3.ZERO)
	var b := _unit("Bravo", Vector3(1.0, 0, 0))
	assert_bool(CoreActivation.open_session(_main, a)).is_true()
	assert_bool(CoreActivation.open_session(_main, b)).is_true()
	CoreActivation.note_commit(_main, a, "reinforcement")
	CoreActivation.note_commit(_main, a, "disembark")
	assert_bool(CoreActivation.can_cancel(a.unit_id)).is_false()
	assert_bool(CoreActivation.can_cancel(b.unit_id)).override_failure_message("another unit's Cancel went too").is_true()
	assert_str(str(CoreActivation._sessions[a.unit_id]["committed"])).is_equal("reinforcement")
