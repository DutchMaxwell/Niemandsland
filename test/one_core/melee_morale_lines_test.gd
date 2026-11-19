extends GdUnitTestSuite
## After a melee the core's morale lines and dice labels are the table's, word for word: the Fearless recovery die (its kind
## "fearless" and the line "<unit> is Fearless — recovery die (4+) holds"), the Morale(X) and Banner line before the test die, the
## No Retreat self-wound dice (kind "no_retreat" and its line) and the Sergeant strike line. Seed for seed, one AI charge on the
## table (`_run_ai_melee`, the door off) against the same charge through the core's charge door (`takes_ai_charge` +
## `run_ai_charge`): survivors, wounds, end positions (within 0.01"), Shaken, Fatigue, the tray RNG after, the battle-log lines
## in order AND the tray's roll records (kind, count, target, faces) in order.
## Real: the main scene, NmlCore, the planner's own charge move, `_run_ai_melee`. Constructed: OPR units (ParityTable) at both
## seats AI, the melee slice gate opened for this process only (the shipped slice takes no rule yet; widening it is another task).
## RED on main: every case differs on the lines (and, for Fearless / No Retreat, on the roll kind). The state keys are equal
## there too, so a green here is the words and labels, never a change of dice or state.
## NML_ONE_CORE_SEEDS overrides 16.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")
const INCH := 0.0254
const SIDE := {"quality": 4, "defense": 4, "tough": 1, "z_step_in": 1.3, "game_system": "gf",
	"faction_folder": "robot_legions", "rules": []}
const BLADE := {"name": "Blade", "range_in": 0, "attacks": 2, "count": 10, "rules": []}
## The planted rule per case. `line` is the table's own wording (a substring of one of its lines): a seed counts as `fired` when the
## table wrote it, so a case that never reaches its rule cannot pass for equal.
const CASES := {
	"fearless_target": {"att": {}, "def": {"rules": ["Fearless"]}, "line": "Def is Fearless — recovery die (4+) "},
	"fearless_charger": {"att": {"quality": 5, "tough": 2, "rules": ["Fearless"]}, "def": {}, "line": "Att is Fearless — recovery die (4+) "},
	"morale_rating_target": {"att": {}, "def": {"rules": ["Morale(6)"]}, "line": "Morale(6): Def gets +6 to morale test rolls (passes on 2+)"},
	"banner_target": {"att": {}, "def": {"rules": ["Banner"]}, "line": "Banner: Def gets +1 to morale test rolls (passes on "},
	"no_retreat_target": {"att": {}, "def": {"rules": ["No Retreat"]}, "line": "Def has No Retreat — the test counts as passed; "},
	"sergeant_charger": {"att": {"rules": ["Sergeant"]}, "def": {}, "line": "Sergeant: Att strikes "},
}

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _melee_slice_before: Variant


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {1: true, 2: true}
	_main._ensure_solo_controller()
	_main.solo_controller.ai_slot = 2
	_main.solo_controller.human_slot = 1
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	_main._solo_batch = true
	_main._solo_auto_saves = true
	_main._solo_fast = true
	_main._autosave_controller.set_lesson_paused(true)
	CoreActivation._env = 1
	CoreActivation._charge_env = 1
	CoreActivation.ai_charges = 0
	# The melee slice gate opened for this process only (an empty deny list takes every registry-mapped rule); no file is touched.
	_melee_slice_before = CoreSlice._cache_by_path.get(CoreSlice.MELEE_PATH)
	CoreSlice._cache_by_path[CoreSlice.MELEE_PATH] = {"mode": "deny", "primitives": {}, "attached": false, "inert": {},
		"deny_names": {}, "unmapped_inert": false}


func after_test() -> void:
	if _melee_slice_before == null:
		CoreSlice._cache_by_path.erase(CoreSlice.MELEE_PATH)
	else:
		CoreSlice._cache_by_path[CoreSlice.MELEE_PATH] = _melee_slice_before
	CoreShadow.tapping = false
	CoreShadow.tap.clear()
	CoreActivation._charge_landing = false
	CoreActivation.reset_all(_main)
	CoreActivation._env = -1
	CoreActivation._charge_env = -1
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _free(units: Array) -> void:
	for u in units:
		_main.opr_army_manager.game_units.erase((u as GameUnit).unit_id)
		for m in (u as GameUnit).models:
			if (m as ModelInstance).node != null and is_instance_valid((m as ModelInstance).node):
				(m as ModelInstance).node.free()
	_main.solo_controller._peeked_unit = null


func _pos(u: GameUnit) -> Array:
	var a: Array = u.get_alive_models().map(func(m: ModelInstance) -> Vector2: return Vector2(m.node.global_position.x, m.node.global_position.z) / INCH)
	a.sort()
	return a


## Whether two sorted position lists agree within 0.01" per model.
func _near(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if (a[i] as Vector2).distance_to(b[i]) > 0.01:
			return false
	return true


## One AI charge: `Att` (seat 2, 5 models) from x = 0 at `Def` (seat 1, 8 models) 7" away, `case`'s rules planted. `core_run` = the
## board is captured before the move (the body's capture) and the door takes the charge, else the table fights.
func _run(s: int, core_run: bool, case: Dictionary) -> Dictionary:
	var att := ParityTable._make_unit(_main, SIDE.merged({"player": 2, "name": "Att", "models": 5, "x_in": 0.0}, true).merged(case["att"], true),
		BLADE.merged({"count": 5}))
	var foe := ParityTable._make_unit(_main, SIDE.merged({"player": 1, "name": "Def", "models": 8, "x_in": 7.0, "z_step_in": 1.4}, true).merged(case["def"], true),
		BLADE.merged({"count": 8, "attacks": 1}))
	# Ties in the casualty pick break on the last float bit (table node vs core): nudge every defender by its own few thousandths.
	for i in foe.models.size():
		(foe.models[i] as ModelInstance).node.global_position.z += float((i * 7) % 5) * 0.0001
	var lines: Array = []
	var tap := func(e: Dictionary) -> void:
		lines.append("%s|%s" % [BattleLog.Category.keys()[int(e["category"])], str(e["text"])])
	_main.battle_log.entry_added.connect(tap)
	_main.seed_tray_rng(s)
	CoreShadow.tap.clear()
	CoreShadow.tapping = true   # the table's own tray tap: every die this charge throws, in order
	var charges := CoreActivation.ai_charges
	var sc: SoloController = _main.solo_controller
	var h := CoreActivation.capture(_main) if core_run else 0
	_main._solo_core_ai_h = h
	var from_in: float = sc.charge_from_in(att, foe, MoveIntent.distance_inches(sc.unit_centre(att), sc.unit_centre(foe)))
	sc._charge_move(att, foe, 12.0)
	att.unit_properties["moved_round"] = 1
	var report := {"unit": att, "target": foe, "action": AiDecision.Action.CHARGE, "charge_from_in": from_in, "moved": true}
	# The body's hand-over (`_solo_activate_one_ai_body`): the door when it takes the charge, else the table's own melee.
	if not (CoreActivation.takes_ai_charge(_main, att, report) and await CoreActivation.run_ai_charge(_main, att, report)):
		await _main._run_ai_melee(report)
	CoreShadow.tapping = false
	_main._solo_core_ai_h = 0
	if h != 0:
		sc._core_node_ready().release(h)
	_main.battle_log.entry_added.disconnect(tap)
	var rolls: Array = CoreShadow.tap.map(func(r: Dictionary) -> Array: return [r["kind"], r["count"], r["target"], r["faces"]])
	var out := {"att": _pos(att), "foe": _pos(foe), "wounds": [_main._solo_unit_wounds_now(att), _main._solo_unit_wounds_now(foe)],
		"alive": [att.get_alive_count(), foe.get_alive_count()], "shaken": [att.is_shaken, foe.is_shaken],
		"fatigued": [att.is_fatigued, foe.is_fatigued], "rng": _main._tray_rng.state, "lines": lines, "rolls": rolls,
		"core": CoreActivation.ai_charges - charges}
	_free([att, foe])
	await _main.get_tree().process_frame
	return out


## One case over every seed: state, lines and rolls equal; the planted rule's line stood in at least one table run.
func _sweep(name: String) -> void:
	var case: Dictionary = CASES[name]
	var seeds := int(OS.get_environment("NML_ONE_CORE_SEEDS")) if OS.has_environment("NML_ONE_CORE_SEEDS") else 16
	var bad: Array = []
	var fired := 0
	for s in seeds:
		var table := await _run(s, false, case)
		var core := await _run(s, true, case)
		if (table["lines"] as Array).any(func(l: String) -> bool: return l.contains(str(case["line"]))):
			fired += 1
		if int(core["core"]) != 1 or int(table["core"]) != 0:
			bad.append("seed %d: the door took it %d times (table run %d)" % [s, core["core"], table["core"]])
		for k in ["att", "foe"]:
			if not _near(table[k], core[k]):
				bad.append("seed %d: %s positions: table %s, core %s" % [s, k, table[k], core[k]])
		for k in ["wounds", "alive", "shaken", "fatigued", "rng"]:
			if table[k] != core[k]:
				bad.append("seed %d: %s: table %s, core %s" % [s, k, table[k], core[k]])
		for k in ["lines", "rolls"]:
			if table[k] != core[k]:
				bad.append("seed %d: %s: %s" % [s, k, _first_diff(table[k], core[k])])
	print("MELEE_MORALE_LINES %s seeds=%d fired=%d mismatches=%d" % [name, seeds, fired, bad.size()])
	assert_int(fired).override_failure_message("%s: the table never wrote %s in %d seeds: the sweep compares nothing" % [
		name, str(case["line"]), seeds]).is_greater(0)
	assert_array(bad).override_failure_message("core vs table:\n" + "\n".join(bad.slice(0, 6))).is_empty()


## The first index two ordered lists differ at, with both entries (the table's first).
func _first_diff(table: Array, core: Array) -> String:
	for i in maxi(table.size(), core.size()):
		var a: Variant = table[i] if i < table.size() else "<none>"
		var b: Variant = core[i] if i < core.size() else "<none>"
		if a != b:
			return "#%d table %s / core %s (table %d entries, core %d)" % [i, a, b, table.size(), core.size()]
	return "equal"


## RED on main: the table says "Def is Fearless — recovery die (4+) holds|fails" and rolls the die as kind "fearless"; the
## core said "Def passes morale" only and asked for the die as "attack".
func test_fearless_target_says_the_tables_line_and_kind() -> void:
	await _sweep("fearless_target")


func test_fearless_charger_says_the_tables_line_and_kind() -> void:
	await _sweep("fearless_charger")


## RED on main: the table's "Morale(6): Def gets +6 to morale test rolls (passes on 2+)" before the test die was missing.
func test_morale_rating_says_the_tables_line() -> void:
	await _sweep("morale_rating_target")


func test_banner_says_the_tables_line() -> void:
	await _sweep("banner_target")


## RED on main: no "has No Retreat" line, and the self-wound dice were asked for as "attack" instead of "no_retreat".
func test_no_retreat_says_the_tables_line_and_kind() -> void:
	await _sweep("no_retreat_target")


## RED on main: the bearer's "Sergeant: Att strikes N hit(s) with AP(+1)" was not said before its save batch.
func test_sergeant_says_the_tables_line() -> void:
	await _sweep("sergeant_charger")
