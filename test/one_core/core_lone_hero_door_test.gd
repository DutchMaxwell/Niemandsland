extends GdUnitTestSuite
## A volley at a lone hero (the target's own models are all dead, a joined hero lives and is shot as the unit) through the AI door.
## From EPOCH_83_LONE_HERO_TARGET the core shoots it as the hero and the step path says the table's Hero line and "fires at <host>"
## (sim.rs); below 83 the core would shoot the dead host, so `CoreSlice` keeps such a target on the table. The same seed through the
## table and through the core must roll the same dice and read the same up to the hero's saves. Known differences after that, NOT
## asserted (follow-up, lane dlines): the core names the hero where the table names the host in "fires <weapon> at", the defense and
## morale labels and the wound line, and lacks the table's half-strength trigger line and "Hero X tests on behalf of". Those two
## missing lines keep the target on the table in the shipped slice (`CoreSlice.lone_hero_lines_done`, false); this suite bypasses it.
## Real: the main scene, NmlCore, the AI body's volley call (`_run_ai_shooting`) on a captured board.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _epoch_before: int


func before_test() -> void:
	_epoch_before = AiActRecorder.rules_epoch
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {1: true, 2: true}   # both seats AI: saves auto-resolve, no dialog
	_main._ensure_solo_controller()
	_main.solo_controller.ai_slot = 2
	_main.solo_controller.human_slot = 1
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	_main._solo_batch = true
	CoreActivation._env = 1
	CoreSlice.lone_hero_lines_done = true   # the slice keeps such a target on the table until the table's other lines are done: bypassed here only
	RulesRegistry.reset_cache()


func after_test() -> void:
	CoreSlice.lone_hero_lines_done = false
	AiActRecorder.rules_epoch = _epoch_before
	CoreActivation.reset_all(_main)
	CoreActivation._env = -1
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null
	RulesRegistry.reset_cache()


## One heavy rifle volley (30 attacks, Q2+) at a human chain 10" away: the host's only model is dead, the joined hero (Def 6+,
## 30 wounds) lives. `core` = the board is captured first (the door takes the volley when the slice lets it); else the table shoots.
## Returns the battle log's lines this volley wrote.
func _volley(core: bool) -> Array:
	var from: int = _main.battle_log.entries().size()
	var gunners := E2EBoot.make_unit(_main, 2, "Gunners", [Vector3.ZERO, Vector3(0.02, 0.0, 0.0)])
	gunners.unit_properties.merge({"game_system": "gf", "special_rules": [], "quality": 2}, true)
	var rifle := OPRApiClient.OPRWeapon.new()
	rifle.name = "Rifle"
	rifle.range_value = 24
	rifle.attacks = 30
	rifle.count = 1
	var opr := OPRApiClient.OPRUnit.new()
	opr.weapons.append(rifle)
	gunners.source_type = "opr"
	gunners.source_data = opr
	var host := E2EBoot.make_unit(_main, 1, "Cultists", [Vector3(10.0 * INCH, 0.0, 0.0)])
	(host.models[0] as ModelInstance).is_alive = false
	var hero := E2EBoot.make_unit(_main, 1, "Champion", [Vector3(10.5 * INCH, 0.0, 0.0)])
	hero.unit_properties["defense"] = 6
	hero.models[0].wounds_max = 30
	hero.models[0].wounds_current = 30
	for u in [host, hero]:
		(u as GameUnit).unit_properties.merge({"game_system": "gf", "faction_folder": "saurian_starhosts"}, true)
	host.unit_properties["special_rules"] = []
	hero.unit_properties["special_rules"] = ["Hero"]
	host.unit_properties["attached_heroes"] = [hero]
	hero.unit_properties["attached_to"] = host
	for u in [gunners, host, hero]:
		_main.opr_army_manager.game_units[(u as GameUnit).unit_id] = u
	_main._tray_rng.seed = 11
	CoreActivation.ai_runs = 0
	_main._solo_core_ai_h = CoreActivation.capture(_main) if core else 0
	await _main._run_ai_shooting(ActIntent.blank_report(gunners))
	if _main._solo_core_ai_h != 0:
		_main.solo_controller._core_node_ready().release(_main._solo_core_ai_h)
	_main._solo_core_ai_h = 0
	var lines: Array = []
	for e in _main.battle_log.entries().slice(from):
		lines.append(str((e as Dictionary)["text"]))
	await E2EBoot.settle(get_tree())
	for u in [gunners, host, hero]:   # the next volley (the other side) starts from an empty table
		_main.opr_army_manager.game_units.erase((u as GameUnit).unit_id)
		for m in (u as GameUnit).models:
			if (m as ModelInstance).node != null and is_instance_valid((m as ModelInstance).node):
				(m as ModelInstance).node.free()
	_main.solo_controller._peeked_unit = null
	return lines


## "AI (<owner>) defends: 6 5 -> ..." and "AI (<owner>): 6 5 -> ..." without the owner label, the dice themselves.
func _dice(lines: Array) -> Array:
	var rx := RegEx.create_from_string("^AI \\([^)]*\\)( defends)?: ")
	return lines.filter(func(l: String) -> bool: return l.begins_with("AI (")).map(func(l: String) -> String: return rx.sub(l, ""))


## RED: without the core's Hero line (the tray's `say`) the first line is the core's "Gunners fires at Champion" and the Hero line
## is missing; without the epoch gate in CoreSlice (second test) the 82 case would be taken by the core.
func test_the_core_reads_like_the_table_up_to_the_heros_saves(timeout := 120000) -> void:
	var table := await _volley(false)
	var table_dice := _dice(table)
	var core := await _volley(true)
	assert_int(CoreActivation.ai_runs).override_failure_message("the core did not take the volley (the table shot): %s" % [core]).is_equal(1)
	assert_array(core.slice(0, 2)).override_failure_message("table %s\ncore %s" % [table.slice(0, 2), core.slice(0, 2)]).is_equal(table.slice(0, 2))
	assert_str(core[0]).starts_with("Hero: Champion is the unit now")
	assert_array(_dice(core)).override_failure_message("the same seed rolls the same dice: table %s core %s" % [table_dice, _dice(core)]).is_equal(table_dice)
	assert_bool(core.has("Champion saves on 6+") and table.has("Champion saves on 6+")).override_failure_message("the save line names the hero on both sides").is_true()


## Below 83 the core would shoot the dead host: the same volley under a replay stamp stays on the table, which still says the line.
func test_an_older_stamp_stays_on_the_table(timeout := 120000) -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_83_LONE_HERO_TARGET - 1
	var lines := await _volley(true)
	assert_int(CoreActivation.ai_runs).override_failure_message("the core took a lone-hero volley below 83").is_equal(0)
	assert_str("\n".join(lines)).contains("Hero: Champion is the unit now")
