extends GdUnitTestSuite
## One-core P3 step 39 (the human gate, shooting): one human activation of a plain unit - Advance 4" + shoot, or Hold +
## shoot - through the window door `_run_human_attack`. The table run (flag off) is the table's own human volley; the core
## run (flag on) presses "Activate", places the models through the drop door `attacked_unit_drag_refused` and shoots
## through CoreActivation.human_shoot. Seed for seed they must agree: the surviving models, Shaken, the tray RNG after and
## the battle-log lines, (category, text) in order - except ONE line pair, whitelisted by design (Q17): the table's
## "<Unit>: N/M models with line of sight + range" against the core's announce line "<Unit> fires at <Target>".
## Real: the main scene, NmlCore, the table's human volley, move and sight code. Constructed: plain shooters vs 5 at 12"
## (the seed picks the shooters' shape, SHAPES), the AI's unit already activated (it has no reply) and a spare unit of the
## shooter's side still to act (the round does not turn), no save prompt waits.
## NML_ONE_CORE_SEEDS overrides the 200 seeds (1000 locally).

const INCH := 0.0254
const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")
const SIDE := {"quality": 4, "defense": 4, "tough": 1, "z_step_in": 1.2, "game_system": "gf",
	"faction_folder": "robot_legions", "rules": []}
const RIFLE := {"name": "Rifle", "range_in": 24, "attacks": 1, "count": 10, "rules": []}
## Seed `s`'s shooters: [models, copies of their one Rifle]; every second pass of the list the models carry their own loadout.
const SHAPES := [[10, 10], [5, 1], [5, 3], [5, 5], [5, 7]]

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
	_main._solo_batch = true   # tray faces from the seeded tray RNG, no physics settle
	_main._solo_auto_saves = true
	_main._solo_fast = true
	_main._autosave_controller.set_lesson_paused(true)   # a long run's periodic autosave would add its own log line


func after_test() -> void:
	CoreActivation.reset_all(_main)
	CoreActivation._env = -1
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## One seed, one run, on fresh units. Returns what the comparison reads.
func _run(s: int, moved: bool, core_run: bool) -> Dictionary:
	var sh: Array = SHAPES[s % SHAPES.size()]
	var att: GameUnit = ParityTable._make_unit(_main, SIDE.merged({"player": 1, "name": "Att%d" % (s % SHAPES.size()),
		"models": sh[0], "x_in": 0.0}), RIFLE.merged({"count": sh[1]}, true))
	if s % (2 * SHAPES.size()) >= SHAPES.size():   # the models carry their own loadout: the last `copies` the Rifle
		for i in att.models.size():
			(att.models[i] as ModelInstance).properties["weapons"] = [{"name": "Rifle" if i >= att.models.size() - sh[1] else "CCW",
				"attacks": 1}]
	var foe: GameUnit = ParityTable._make_unit(_main, SIDE.merged({"player": 2, "name": "Def", "models": 5, "x_in": 12.0}),
		{"name": "Rifle", "range_in": 24, "attacks": 1, "count": 5, "rules": []})   # a plain target carries a profile
	foe.is_activated = true   # the AI has nothing left to do: no reply, in either run
	var spare: GameUnit = ParityTable._make_unit(_main, SIDE.merged({"player": 1, "name": "Spare", "models": 1, "x_in": 40.0}),
		{})   # a unit of the shooter's side still to act: the round does not turn after the volley
	_main.opr_army_manager.current_round = 1
	for m in att.models:
		m.node.set_meta("network_id", 901 + att.models.find(m))
		m.node.set_meta("model_instance", m)
	CoreActivation._env = 1 if core_run else 0
	if core_run:
		assert_bool(_main.core_activation_start(att)).override_failure_message("seed %d: no Start" % s).is_true()
	for m in att.get_alive_models() if moved else []:   # every shooter 4" toward the foe, same in both runs
		m.node.global_position.x += 4.0 * INCH
	if core_run and moved:
		assert_bool(_main.attacked_unit_drag_refused(att, 4.0)).override_failure_message("seed %d: the drop was refused" % s).is_false()
	var lines: Array = []
	var on_entry := func(e: Dictionary) -> void: lines.append("%d|%s" % [int(e["category"]), str(e["text"])])
	_main.battle_log.entry_added.connect(on_entry)
	_main.seed_tray_rng(s)
	await _main._run_human_attack(att, foe, false)
	_main.battle_log.entry_added.disconnect(on_entry)
	var survivors: Array = foe.get_alive_models().map(func(m: ModelInstance) -> Vector3: return m.node.global_position)
	survivors.sort()
	var out := {"survivors": survivors, "shaken": foe.is_shaken, "rng": _main._tray_rng.state, "lines": lines,
		"shot": int(att.unit_properties.get("shot_round", -1))}
	CoreActivation.close_session(_main, att.unit_id)
	for u in [att, foe, spare]:
		_main.opr_army_manager.game_units.erase((u as GameUnit).unit_id)
		for m in (u as GameUnit).models:
			(m as ModelInstance).node.free()
	return out


## The one whitelisted pair (Q17): the table's models-in-sight line against the core's announce line; each must be there
## exactly once and is taken out, so every other line is compared as it is.
func _without_the_declaration_pair(lines: Array, core_run: bool, s: int, bad: Array) -> Array:
	var is_pair := func(l: String) -> bool:
		return l.contains("models with line of sight + range") or l.contains("model with line of sight + range") \
			if not core_run else l.ends_with("|Att%d fires at Def" % (s % SHAPES.size()))
	var pair: Array = lines.filter(is_pair)
	if pair.size() != 1:
		bad.append("seed %d: %s run has %d declaration lines: %s" % [s, "core" if core_run else "table", pair.size(), pair])
	return lines.filter(func(l: String) -> bool: return not is_pair.call(l))


func _gate(moved: bool) -> void:
	var seeds := int(OS.get_environment("NML_ONE_CORE_SEEDS")) if OS.has_environment("NML_ONE_CORE_SEEDS") else 200
	var bad: Array = []
	var line_diffs: Array = []
	var hurt := 0
	var shaken := 0
	await _run(0, moved, false)   # warm-up: the AI's first turn of a game says its opening line once, in whichever run is first
	for s in seeds:
		var table := await _run(s, moved, false)
		var core := await _run(s, moved, true)
		hurt += 1 if (core["survivors"] as Array).size() < 5 else 0
		shaken += 1 if core["shaken"] else 0
		for k in ["survivors", "shaken", "rng", "shot"]:
			if table[k] != core[k]:
				bad.append("seed %d: %s: table %s, core %s" % [s, k, table[k], core[k]])
		var tl := _without_the_declaration_pair(table["lines"], false, s, bad)
		var cl := _without_the_declaration_pair(core["lines"], true, s, bad)
		if tl != cl:
			line_diffs.append("seed %d\n table %s\n core  %s" % [s, "\n       ".join(tl), "\n       ".join(cl)])
	print("ONE_CORE_HUMAN case=%s seeds=%d hurt=%d shaken=%d mismatches=%d line_diffs=%d" % ["advance" if moved else "hold",
		seeds, hurt, shaken, bad.size(), line_diffs.size()])
	assert_int(hurt).override_failure_message("no seed hurt the target: the gate compares nothing").is_greater(0)
	if not line_diffs.is_empty():
		print("ONE_CORE_HUMAN first line diff: ", line_diffs[0])
	assert_array(bad).override_failure_message("core vs table:\n" + "\n".join(bad.slice(0, 10))).is_empty()
	assert_array(line_diffs).override_failure_message("battle-log lines differ in %d seeds, first:\n%s" % [
		line_diffs.size(), "" if line_diffs.is_empty() else line_diffs[0]]).is_empty()


func test_advance_and_shoot_equals_the_table(timeout := 900000) -> void:
	await _gate(true)


func test_hold_and_shoot_equals_the_table(timeout := 900000) -> void:
	await _gate(false)
