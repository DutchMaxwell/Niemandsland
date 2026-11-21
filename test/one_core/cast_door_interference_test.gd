extends GdUnitTestSuite
## CC-14b: a foe's interference against an AI cast, table vs door. The same planned cast (the planner's own pool: `_aura_casters`)
## runs twice on fresh units and the same tray seed: once through the table's `_solo_resolve_ai_casts` (the foe's dialog spends the
## tokens itself), once through `CoreActivation.run_ai` with the report marked `cast_door` (the dialog only asks, the core spends).
## The foe answers the same count each time. Both must leave the same battle-log lines, tray rolls with their legs, unit state, spell
## records, rng and token counts. Real: the main scene, NmlCore, the table's resolver, tray and `InterferenceDialog`.
## Constructed: alien_hives units (a caster with a real spell book, a foe holding 2 spell tokens within 18").

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const Harness := preload("res://test/one_core/golden_witness_harness.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")

const MYSTIC := {"key": "my", "player": 2, "name": "Mystic", "models": 1, "quality": 4, "defense": 4, "tough": 1,
	"x_in": 0.0, "z_step_in": 1.2, "base_radius_in": 0.63, "game_system": "gf", "faction_folder": "alien_hives", "rules": ["Caster"]}
const HELPER := {"key": "hp", "player": 1, "name": "Helper", "models": 1, "quality": 4, "defense": 4, "tough": 1,
	"x_in": -4.0, "z_step_in": 1.2, "base_radius_in": 0.63, "game_system": "gf", "faction_folder": "alien_hives", "rules": ["Caster(2)"]}
const FOE := {"key": "foe", "player": 1, "name": "Foe", "models": 6, "quality": 4, "defense": 4, "tough": 1,
	"x_in": 8.0, "z_step_in": 1.3, "base_radius_in": 0.63, "game_system": "gf", "faction_folder": "alien_hives", "rules": []}
const STAFF := {"name": "Staff", "range_in": 0, "attacks": 1, "count": 1, "rules": []}
const BLOODTHIRST := {"name": "Infuse Bloodthirst", "threshold": 1, "range_in": 12,
	"target": {"side": "enemy", "count": 3, "kind": "unit"},
	"effect": {"kind": "debuff", "grants_rule": "Unpredictable Fighter", "duration": "once", "beneficiary": "attackers"}}
const SEEDS: Array[int] = [0, 1, 2, 3, 8, 11]

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _epoch_before: int
var _answer := 0


func before_test() -> void:
	_epoch_before = AiActRecorder.rules_epoch
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.solo_controller.ai_slot = 2
	_main.solo_controller.human_slot = 1
	_main.solo_controller.last_move_paths = []
	_main._solo_both_ai = false
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	_main._solo_batch = true   # seeded dice (the physics tray is not deterministic); the foe's dialog opens in batch mode too
	_main._solo_fast = true
	GraphicsSettings.combat_stage_hold_s = 0.0
	CoreActivation._env = 1
	CoreActivation._cast_env = 1
	CoreActivation._choice_on = {"interference": true}


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch_before
	AiActRecorder._stream = null
	AiActRecorder._checked = false
	AiActRecorder._header_written = false
	CoreActivation.reset_all(_main)
	CoreActivation._env = -1
	CoreActivation._cast_env = -1
	CoreActivation._choice_on = {}
	GraphicsSettings.combat_stage_hold_s = 2.5
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _card() -> PromptCard:
	for n in _main.get_children():
		if n is InterferenceDialog:
			for c in n.get_children():
				if c is PromptCard and (c as PromptCard).title == "Enemy spell!":
					return c
	return null


func _texts(n: Node) -> Array:
	var out: Array = []
	if n is Label:
		out.append((n as Label).text)
	elif n is Button:
		out.append((n as Button).text)
	for c in n.get_children():
		out.append_array(_texts(c))
	return out


## The foe's player answers the dialog with `_answer` tokens whenever it opens (the table's own prompt and the door's collect mode
## are the same card); `shown` gets the texts of every card that opened (title, info, the preview with the cast roll it shows).
func _answer_cards(shown: Array, stop: Array) -> void:
	while not stop[0]:
		var card := _card()
		if card != null:
			shown.append(_texts(card))
			card.resolve(_answer)
		await get_tree().process_frame


## One activation on fresh units; `door` = through the AI body's own seams with the switches ON (`takes_ai_activation`, the probe in
## `_solo_ai_casts`, the core's one call `_solo_ai_core_call`). Returns everything both paths must agree on.
func _run(seed: int, answer: int, door: bool, net := false) -> Dictionary:
	_answer = answer
	var caster := ParityTable._make_unit(_main, MYSTIC, STAFF)
	if net:   # a casting record on the caster: the dialog's base target is the net-adjusted 3+, not the book's 4+
		_main._solo_record_spell_mod(caster, "Hasten", {"modifier": {"casting_mod": 1}, "duration": "round", "quiet": true})
	var helper := ParityTable._make_unit(_main, HELPER, STAFF)
	var foe := ParityTable._make_unit(_main, FOE, {})
	caster.casts_current = 3
	helper.casts_current = 2
	var pool: Array = _main.solo_controller._aura_casters(1, caster, null)   # the planner's own pool for this cast
	var cast := {"caster": caster, "caster_unit": caster, "name": "Infuse Bloodthirst", "spell": BLOODTHIRST, "targets": [foe],
		"boost": 0, "interference": 0, "base_target": 4, "threshold": 1, "owner_label": "AI (Mystic)", "interference_open": true,
		"boost_sources": [], "interference_sources": [], "conduit": null, "conduit_shaken": [], "pools": [[1, pool]]}
	var report := {"action": AiDecision.Action.HOLD, "moved": false, "casts": [cast]}
	_main._solo_spell_tokens_active.clear()
	assert_int(pool.size()).override_failure_message("the planner's pool is empty").is_equal(1)
	var h := CoreActivation.capture(_main) if door else 0   # the tokens BEFORE the plan's spend: the core pays them itself
	caster.spend_caster_points(1)   # the planner pays the attempt at plan time
	_main._solo_act_flags = _main._solo_unit_flags()
	var lines: Array = []
	var tap := Harness._line_tap(lines)
	_main.battle_log.entry_added.connect(tap)
	CoreShadow.tap.clear()
	CoreShadow.tapping = true
	_main.seed_tray_rng(seed)
	var shown: Array = []
	var stop := [false]
	_answer_cards(shown, stop)
	if door:
		_main._solo_core_ai_h = h
		var takes: bool = CoreActivation.takes_ai_activation(_main, caster, report)
		assert_bool(takes).override_failure_message("the door does not take the casting activation").is_true()
		await _main._solo_ai_casts(caster, report, takes)
		assert_bool(report.has("cast_door")).override_failure_message("the probe refused the open cast: %s" % str(CoreActivation.cast_probe_reasons)).is_true()
		var runs := CoreActivation.ai_runs
		await _main._solo_ai_core_call(caster, report, null, [])
		assert_int(CoreActivation.ai_runs).override_failure_message("the core did not resolve the cast (the fallback did)").is_equal(runs + 1)
		assert_bool(report.has("cast_door")).override_failure_message("the mark outlived the core call").is_false()
		_main._solo_core_ai_h = 0
		_main.solo_controller._core_node_ready().release(h)
	else:
		await _main._solo_resolve_ai_casts(report)
	stop[0] = true
	await get_tree().process_frame
	CoreShadow.tapping = false
	_main.battle_log.entry_added.disconnect(tap)
	var rolls: Array = CoreShadow.tap.map(func(r: Dictionary) -> String: return "%s|%s|%dx%d+|%s|%s" % [
		str(r["leg"]), str(r["kind"]), int(r["count"]), int(r["target"]), str(r["owner"]),
		",".join((r["faces"] as Array).map(func(f: Variant) -> String: return str(int(f))))])
	CoreShadow.tap.clear()
	var out := {"lines": lines, "rolls": rolls, "final": Harness._final([caster, foe, helper]), "rng": Harness._rng_state(_main),
		"mods": Harness._spell_state(_main, [caster, foe, helper]), "tokens": [caster.casts_current, helper.casts_current], "cards": shown}
	for gu in [caster, foe, helper]:
		_main._solo_spell_mods.erase((gu as GameUnit).get_instance_id())
	_main._solo_spell_tokens_active.clear()
	Harness._free_units(_main, [caster, foe, helper])
	await _main.get_tree().process_frame
	return out


func _diff(table: Dictionary, door: Dictionary) -> String:
	for k in ["lines", "rolls", "final", "rng", "mods", "tokens", "cards"]:
		if table[k] != door[k]:
			var a: Array = table[k] if table[k] is Array else [table[k]]
			var b: Array = door[k] if door[k] is Array else [door[k]]
			return "%s\n table %s\n door  %s" % [k, "\n       ".join(PackedStringArray(a.map(func(v: Variant) -> String: return str(v)))),
				"\n       ".join(PackedStringArray(b.map(func(v: Variant) -> String: return str(v))))]
	return ""


## The foe spends 0, 1 or 2 tokens on the dialog: table and door leave the same lines, dice, units, records and token counts, and the
## dialog opened once each. The tokens that were spent are the answer, from the foe's only holder.
func test_a_foes_interference_through_the_door_is_the_tables(timeout := 600000) -> void:
	var bad: Array = []
	var spent_seen := {}
	for answer in [0, 1, 2]:
		for s in SEEDS:
			var table := await _run(s, answer, false)
			var door := await _run(s, answer, true)
			spent_seen[answer] = 2 - int((door["tokens"] as Array)[1])
			var d := _diff(table, door)
			if d != "":
				bad.append("answer %d seed %d: %s" % [answer, s, d])
			elif (door["cards"] as Array).size() != 1:
				bad.append("answer %d seed %d: the dialog opened %d times" % [answer, s, (door["cards"] as Array).size()])
	assert_array(bad).override_failure_message("\n".join(bad.slice(0, 2))).is_empty()
	assert_dict(spent_seen).override_failure_message("the tokens spent are not the answer").is_equal({0: 0, 1: 1, 2: 2})


## With a casting record on the caster the dialog shows the net-adjusted base (3+): the same card text from the table and the door
## (the door recomputes it from the planner's cast dict as `_solo_resolve_one_cast` does), and the die rolls at the net-adjusted target.
func test_the_dialog_shows_the_net_adjusted_base_on_both_paths(timeout := 600000) -> void:
	var bad: Array = []
	for s in SEEDS:
		var table := await _run(s, 1, false, true)
		var door := await _run(s, 1, true, true)
		var d := _diff(table, door)
		if d != "":
			bad.append("seed %d: %s" % [s, d])
		elif not "\n".join(PackedStringArray(((door["cards"] as Array)[0] as Array).map(func(t: Variant) -> String: return str(t)))).contains("3+ \u2192 4+"):
			bad.append("seed %d: the preview does not start from the net-adjusted 3+: %s" % [s, str(door["cards"])])
	assert_array(bad).override_failure_message("\n".join(bad.slice(0, 2))).is_empty()
