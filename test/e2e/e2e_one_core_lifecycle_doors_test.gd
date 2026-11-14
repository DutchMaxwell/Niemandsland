extends GdUnitTestSuite
## One-core P3 step 70 (b) (O14 (1b)): every door group of steps 62-65b is closed to a human unit whose activation was not
## started - flag on, an AI seat, the real doors. One case per group, each says "Activate <Unit> first." (the Pass door
## needs no Start of its own and names an OPEN activation instead) and leaves the unit and its spends untouched:
##  62 the transport doors, 63 the attack / cast / spot / auto windows (before the Utility Buff spend), 64 Speed Feat and
##  Pass, 65 the formation tools and the group turn, 65b the regiment re-rank doors.
## Real: the main scene, the radial dispatch, the object manager's tools, the registry. Constructed: bare units.

const INCH := 0.0254
const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")

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
	_main.solo_controller.ai_slot = 2
	_main.solo_controller.human_slot = 1
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	_main._solo_batch = true
	_main._autosave_controller.set_lesson_paused(true)
	CoreActivation._env = 1


func after_test() -> void:
	RulesRegistry.reset_cache()
	CoreActivation.reset_all(_main)
	CoreActivation._env = -1
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## A bare unit of seat `pid` with one rifle, registered with the army manager.
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


func _lines(text: String) -> int:
	return _main.battle_log.entries().filter(func(e: Dictionary) -> bool: return str(e["text"]) == text).size()


func _act(action: String, context: Dictionary) -> void:
	await _main.radial_menu_controller._on_action_selected(action, context)


## 62: a transport's cargo that was not started does not disembark; the truck stays its carrier.
func test_62_the_transport_doors_need_the_start() -> void:
	var truck := _unit("Truck", Vector3.ZERO, ["Transport(6)"])
	var cargo := _unit("Riders", Vector3(0.04, 0, 0))
	_unit("Spare", Vector3(1.0, 0, 0))
	_main.opr_army_manager.set_unit_embarked(cargo, truck, true)
	await _act("disembark", {"disembark_unit": cargo})
	assert_object(_main.opr_army_manager.transport_of(cargo)).override_failure_message("disembarked without a Start").is_same(truck)
	assert_int(_lines("Activate Riders first.")).is_equal(1)
	assert_bool(cargo.is_activated).is_false()


## 63: Shoot, Cast, Spot and Auto answer before the window opens and BEFORE the Utility Buff is spent.
func test_63_the_windows_need_the_start() -> void:
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
	await _main.solo_begin_targeting(u, false)
	await _main.solo_begin_cast(u)
	await _main.solo_begin_spot(u)
	await _main.solo_begin_auto(u, AiDecision.Action.ADVANCE)
	assert_int(_lines("Activate Marshal first.")).override_failure_message("lines: %s" % [_main.battle_log.entries().slice(-4)]).is_equal(4)
	assert_bool(_main._solo_target_mode.is_empty()).override_failure_message("a window opened").is_true()
	assert_bool(u.unit_properties.has("utility_buff_round")).override_failure_message("the buff was spent").is_false()
	assert_array(_main._solo_spell_mods.get(friend.get_instance_id(), [])).override_failure_message("a record landed").is_empty()


## 64: the Speed Feat is spent INSIDE an activation (no Start: refused, latch unset); Pass needs no Start of its own but
## never passes the turn while another unit's activation is open.
func test_64_speed_feat_needs_the_start_and_pass_waits_for_an_open_activation() -> void:
	var u := _unit("Boyz", Vector3.ZERO, ["Speed Feat"])
	u.unit_properties["game_system"] = "aof"
	u.unit_properties["faction_folder"] = "orcs"
	_main.solo_spend_speed_feat(u)
	assert_int(_lines("Activate Boyz first.")).is_equal(1)
	assert_bool(u.unit_properties.has("speed_feat_used_speed_feat")).override_failure_message("the feat was spent").is_false()
	var carrier := _unit("Wachtturm", Vector3(-0.3, 0, 0.2), ["Delayed Action"])
	var other := _unit("Alpha", Vector3(-0.3, 0, 0.4))
	for i in 3:
		_unit("Raider%d" % (i + 1), Vector3(0.3, 0, -0.2 - 0.12 * i), [], 2)
	CoreActivation.open_session(_main, other)
	await _main.solo_begin_pass(carrier)
	assert_int(_lines("Finish Alpha's activation first.")).is_equal(1)
	assert_bool(SoloController.delayed_action_used_this_round(carrier, 1)).override_failure_message("the turn passed").is_false()


## 65: the re-form tools and the group turn of a unit that was not started move nothing and say so.
func test_65_the_formation_tools_need_the_start() -> void:
	var u := ParityTable._make_unit(_main, {"player": 1, "name": "Rifles", "models": 4, "x_in": 0.0, "z_step_in": 1.2,
		"quality": 4, "defense": 4, "tough": 1, "game_system": "gf", "faction_folder": "robot_legions", "rules": []},
		{"name": "Rifle", "range_in": 24, "attacks": 1, "count": 4, "rules": []})
	var nodes: Array = u.models.map(func(m: ModelInstance) -> Node3D: return m.node)
	var at: Array = nodes.map(func(n: Node3D) -> Array: return [n.global_position, n.rotation.y])
	var om: Node3D = _main.object_manager
	om._selected_objects.assign(nodes)
	om.arrange_selected_in_rows(1)
	om.begin_rotation_capture()
	om.rotate_selected_group(90.0)
	om.commit_rotation_capture()
	assert_array(nodes.map(func(n: Node3D) -> Array: return [n.global_position, n.rotation.y])).override_failure_message("a tool moved the unit").is_equal(at)
	assert_int(_lines("Activate Rifles first.")).override_failure_message("lines: %s" % [_main.battle_log.entries().slice(-3)]).is_equal(2)


## 65b: a regiment block that was not started is not re-ranked, by the radial entry or by the B key.
func test_65b_the_rerank_doors_need_the_start() -> void:
	var at: Array = []
	for i in 6:
		at.append(Vector3(0.03 * i, 0, 0))
	var gu := E2EBoot.make_unit(_main, 1, "Spears", at)
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
	await _act("regiment_frontage", {"regiment_tray": tray})
	_main.object_manager._selected_objects.assign([tray])
	var ev := InputEventKey.new()
	ev.keycode = KEY_B
	ev.pressed = true
	_main._unhandled_key_input(ev)
	assert_int(tray.frontage).override_failure_message("re-ranked without a Start").is_equal(5)
	assert_int(_lines("Activate Spears first.")).is_equal(2)
