extends GdUnitTestSuite
## CC-12: the cast door's table side. The same planned cast runs twice on fresh units and the same tray seed: once through the
## table's `_solo_resolve_ai_casts` (the old path), once through `CoreActivation.run_ai` with the report marked `cast_door`
## (the core resolves the cast from one capture, the door shows and lands it). Both must leave the same lines, tray rolls with
## their legs (12c), unit state, spell records and tokens, caster tokens, `pre` block (12c) and the same combat-stage cards in
## the same order (12b); a hit buff / debuff is on the table before the volley starts (12a), the next capture carries it.
## Real: the main scene, NmlCore, the table's resolver, tray, stage and landing code. Constructed: alien_hives units with a
## real spell book (Terror Seeker, Infuse Bloodthirst, Psychic Blast). Nothing sets `cast_door` outside this suite yet (CC-13a).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const Harness := preload("res://test/one_core/golden_witness_harness.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")

const MYSTIC := {"key": "my", "player": 1, "name": "Mystic", "models": 1, "quality": 4, "defense": 4, "tough": 1,
	"x_in": 0.0, "z_step_in": 1.2, "base_radius_in": 0.63, "game_system": "gf", "faction_folder": "alien_hives",
	"rules": ["Caster"]}
const FOE := {"key": "foe", "player": 2, "name": "Foe", "models": 6, "quality": 4, "defense": 4, "tough": 1,
	"x_in": 8.0, "z_step_in": 1.3, "base_radius_in": 0.63, "game_system": "gf", "faction_folder": "alien_hives",
	"rules": []}
const STAFF := {"name": "Staff", "range_in": 0, "attacks": 1, "count": 1, "rules": []}
const RIFLE := {"name": "Rifle", "range_in": 24, "attacks": 1, "count": 1, "rules": []}
const TERROR_SEEKER := {"name": "Terror Seeker", "threshold": 1, "range_in": 12,
	"target": {"side": "friendly", "count": 1, "kind": "unit"},
	"effect": {"kind": "buff", "grants_rule": "Hit & Run Fighter", "duration": "once"}}
const BLOODTHIRST := {"name": "Infuse Bloodthirst", "threshold": 1, "range_in": 12,
	"target": {"side": "enemy", "count": 3, "kind": "unit"},
	"effect": {"kind": "debuff", "grants_rule": "Unpredictable Fighter", "duration": "once", "beneficiary": "attackers"}}
const PSYCHIC_BLAST := {"name": "Psychic Blast", "threshold": 1, "range_in": 18,
	"target": {"side": "enemy", "count": 1, "kind": "unit"},
	"effect": {"kind": "damage", "hits": 6, "weapon_rules": ["AP(2)"]}}
## A spell the core's spell book does not hold: its probe refuses it before any die (the table casts it from the planner's entry).
const UNKNOWN_BOLT := {"name": "Unknown Bolt", "threshold": 1, "range_in": 18,
	"target": {"side": "enemy", "count": 1, "kind": "unit"},
	"effect": {"kind": "damage", "hits": 3, "weapon_rules": []}}
const SEEDS: Array[int] = [0, 1, 2, 3, 8, 11]


## The recording stub (the presentation test's): the real stage, every call written down with what the table shows then.
class StageRec extends CombatStage:
	var main: Node
	var calls: Array = []

	func activation_begin(headline: String) -> void:
		calls.append("begin %s" % headline)
		super.activation_begin(headline)

	func phase(title: String) -> void:
		var toast: String = main._solo_toast.text if is_instance_valid(main._solo_toast) else ""
		if not _pending.is_empty():
			calls.append("phase %s | announce %d | toast %s | lines %s" % [title, (main._solo_live_announce as Array).size(), toast, " / ".join(_pending)])
		await super.phase(title)

	func activation_end() -> void:
		calls.append("end")
		super.activation_end()


static var _CONSUMED := RegEx.create_from_string(" / \"[^\"]+\" on [^ ]+ is consumed \\(applies once\\)")

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _rec: StageRec
var _epoch_before: int


func before_test() -> void:
	_epoch_before = AiActRecorder.rules_epoch
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {1: true, 2: true}
	_main._ensure_solo_controller()
	_main.solo_controller.ai_slot = 2
	_main.solo_controller.human_slot = 1
	_main.solo_controller.last_move_paths = []
	_main._solo_both_ai = true
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	_main._solo_batch = true
	GraphicsSettings.combat_stage_hold_s = 0.0
	_rec = StageRec.new()
	_rec.main = _main
	_rec.force_for_tests = true
	_main.add_child(_rec)
	_main.combat_stage = _rec
	CoreActivation._env = 1
	CoreActivation._cast_env = -1
	CoreActivation.cast_probe_refusals = 0
	CoreActivation.cast_probe_reasons.clear()


func after_test() -> void:
	CoreActivation._cast_env = -1
	AiActRecorder.rules_epoch = _epoch_before
	AiActRecorder._stream = null
	AiActRecorder._checked = false
	AiActRecorder._header_written = false
	CoreActivation.reset_all(_main)
	CoreActivation._env = -1
	GraphicsSettings.combat_stage_hold_s = 2.5
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## One activation on fresh units: the caster (a rifle when `shoot`), the foe (six models, or gone for `fizzle`). `mode`: "table" =
## the table's resolvers; "run_ai" = `CoreActivation.run_ai` with the report marked `cast_door` (CC-12); "body" = the AI body's own
## seams behind the switch (CC-13a): `takes_ai_activation`, `_solo_ai_casts` (the probe), `_solo_ai_core_call`. `opts.dangerous`
## = a Dangerous block under the caster (the test the body owes) (the core's when it takes the activation, else the table pays it before the casts).
## Returns everything both paths must agree on.
func _run(spell: Dictionary, seed: int, mode: String, opts := {}) -> Dictionary:
	var door := mode != "table"
	var shoot: bool = bool(opts.get("shoot", false))
	var caster := ParityTable._make_unit(_main, MYSTIC, RIFLE if shoot else STAFF)
	var foe := ParityTable._make_unit(_main, FOE.merged({"models": int(opts.get("foe_models", 6))}, true), {})
	if bool(opts.get("fizzle", false)):
		Harness._kill_models(foe, foe.models.size())
	var painted := {}   # a Dangerous block under the caster: the core rolls the test from the captured board, the table's forced dice match
	var dangerous := 0
	if bool(opts.get("dangerous", false)):
		painted = Harness._paint_cover(_main, caster, _main.terrain_overlay.TerrainType.DANGEROUS)
		dangerous = OPRArmyManager.dangerous_dice_for(caster)
	var on_self: bool = str((spell["target"] as Dictionary)["side"]) == "friendly"
	var cast := {"caster": caster, "caster_unit": caster, "name": str(spell["name"]), "spell": spell,
		"targets": [caster] if on_self else [foe], "boost": 0, "interference": 0, "base_target": 4, "threshold": 1,
		"owner_label": "AI (Mystic)", "interference_open": false, "boost_sources": [], "interference_sources": [],
		"conduit": null, "conduit_shaken": [], "pools": []}
	var report := {"action": AiDecision.Action.HOLD, "moved": false, "casts": [cast]}
	var out_takes := false
	var out_marked := false
	var runs_before := CoreActivation.ai_runs
	var shots: Array = []
	if shoot:
		for pr in AiShooting.profiles_in_range([(caster.source_data as OPRApiClient.OPRUnit).weapons[0]], float(FOE["x_in"])):
			shots.append({"member": caster, "quality": caster.get_quality(), "alive": caster.get_alive_count(),
				"max": caster.models.size(), "reach": float(RIFLE["range_in"]), "profile": pr})
	_main._solo_spell_tokens_active.clear()
	caster.casts_current = 1 if shoot else 3   # a spare token would feed the core's modelled spell rider on the volley (#3110, pending epoch 93)
	var h := CoreActivation.capture(_main) if door else 0   # the tokens BEFORE the plan's spend: the core pays them itself
	caster.spend_caster_points(1)   # the planner pays the attempt at plan time
	_main._solo_act_flags = _main._solo_unit_flags()   # the AI body's own, taken before the Dangerous test
	var pre_path := "user://cast_door_pre_%s.jsonl" % ("door" if door else "table")
	AiActRecorder._stream = FileAccess.open(pre_path, FileAccess.WRITE)
	AiActRecorder._checked = true
	AiActRecorder._header_written = true
	var lines: Array = []
	var tap := Harness._line_tap(lines)
	_main.battle_log.entry_added.connect(tap)
	CoreShadow.tap.clear()
	CoreShadow.tapping = true
	_rec.calls.clear()
	_main.seed_tray_rng(seed)
	if mode == "run_ai":
		report["cast_door"] = true
		var ran: bool = await CoreActivation.run_ai(_main, caster, report, foe if shoot else null, h, shots, not shoot)
		assert_bool(ran).override_failure_message("the door refused the cast activation").is_true()
		_main.solo_controller._core_node_ready().release(h)
	elif mode == "body":
		_main._solo_core_ai_h = h
		if dangerous > 0:
			report["dangerous_dice"] = dangerous
		var takes: bool = CoreActivation.takes_ai_activation(_main, caster, report)
		out_takes = takes
		if dangerous > 0 and takes:
			report["core_dangerous"] = dangerous   # the body's deferral: the core's one call pays it
		elif dangerous > 0:
			await _main._run_ai_dangerous(caster, dangerous)
		await _main._solo_ai_casts(caster, report, takes)
		if opts.get("no_core_call", false):
			_main._solo_core_ai_h = 0   # the call cannot run (no board): the fallback owes the casts
		await _main._solo_ai_core_call(caster, report, foe if shoot else null, shots)
		out_marked = report.has("cast_door")
		_main._solo_core_ai_h = 0
		_main.solo_controller._core_node_ready().release(h)
	else:
		if dangerous > 0:
			await _main._run_ai_dangerous(caster, dangerous)
		await _main._solo_resolve_ai_casts(report)
		if shoot:
			await _main._solo_resolve_ai_volley(caster, foe, shots)
	CoreShadow.tapping = false
	_main.battle_log.entry_added.disconnect(tap)
	(AiActRecorder._stream as FileAccess).close()
	AiActRecorder._stream = null
	var pre: Array = []
	for l in FileAccess.get_file_as_string(pre_path).split("\n", false):
		pre.append(l)
	var rolls: Array = CoreShadow.tap.map(func(r: Dictionary) -> String: return "%s|%s|%dx%d+|%s|%s" % [
		str(r["leg"]), str(r["kind"]), int(r["count"]), int(r["target"]), str(r["owner"]),
		",".join((r["faces"] as Array).map(func(f: Variant) -> String: return str(int(f))))])
	CoreShadow.tap.clear()
	# The consume line of a once record the volley spent is the volley door's own (`_land_buffs` at the delta, inside the stage's
	# last card; the table writes it outside the cards): not a cast difference, the lines list above still compares it.
	var cards: Array = _rec.calls.map(func(c: String) -> String:
		return _CONSUMED.sub(c, "", true))
	var out := {"lines": lines, "rolls": rolls, "final": Harness._final([caster, foe]), "rng": Harness._rng_state(_main),
		"mods": Harness._spell_state(_main, [caster, foe]), "tokens": caster.casts_current, "pre": pre,
		"takes": out_takes, "marked": out_marked, "core_ran": CoreActivation.ai_runs - runs_before, "cards": cards, "ledger": AiActRecorder._ledger_of(caster).get("buffs", []).size()
			+ AiActRecorder._ledger_of(foe).get("buffs", []).size()}
	for gu in [caster, foe]:
		_main._solo_spell_mods.erase((gu as GameUnit).get_instance_id())
	_main._solo_spell_tokens_active.clear()
	Harness._unpaint_cover(_main, painted)
	Harness._free_units(_main, [caster, foe])
	await _main.get_tree().process_frame
	return out


## The first field two runs differ in, as text; "" = equal.
func _diff(table: Dictionary, door: Dictionary) -> String:
	for k in ["lines", "rolls", "final", "rng", "mods", "tokens", "pre", "ledger", "cards"]:   # `takes` / `marked` are the switch's own
		if table[k] != door[k]:
			var a: Array = table[k] if table[k] is Array else [table[k]]
			var b: Array = door[k] if door[k] is Array else [door[k]]
			return "%s\n table %s\n door  %s" % [k, "\n       ".join(PackedStringArray(a.map(func(v: Variant) -> String: return str(v)))),
				"\n       ".join(PackedStringArray(b.map(func(v: Variant) -> String: return str(v))))]
	return ""


func _grid(spell: Dictionary, opts := {}, mode := "run_ai") -> Array:
	var bad: Array = []
	var landed := 0
	for s in (opts.get("seeds", SEEDS) as Array):
		var table := await _run(spell, s, "table", opts)
		var door := await _run(spell, s, mode, opts)
		landed += 1 if (door["rolls"] as Array).size() > 0 else 0
		var d := _diff(table, door)
		if d != "":
			bad.append("%s seed %d: %s" % [spell["name"], s, d])
		if mode == "body" and (not bool(door["takes"]) or bool(door["marked"]) or int(door["core_ran"]) != 1):
			bad.append("%s seed %d: takes %s, mark left %s, core ran %d (must be 1: the core resolved the casts, not the table's fallback)" % [
				spell["name"], s, door["takes"], door["marked"], door["core_ran"]])
	if not bool(opts.get("fizzle", false)):
		assert_int(landed).override_failure_message("no activation rolled a die").is_greater(0)
	return bad


## 12a + 12b + 12c: a buff on the caster itself, a debuff on the foe, a damage spell, a fizzle, a cast then a volley (the
## once-debuff on the volley's own target is spent by it, lead ruling O7), each over seeds that pass and fail the 4+ die.
func test_a_cast_through_the_door_is_the_table_cast(timeout := 600000) -> void:
	var bad: Array = []
	bad.append_array(await _grid(TERROR_SEEKER))
	bad.append_array(await _grid(BLOODTHIRST))
	bad.append_array(await _grid(PSYCHIC_BLAST, {"foe_models": 10}))
	bad.append_array(await _grid(BLOODTHIRST, {"fizzle": true}))
	bad.append_array(await _grid(BLOODTHIRST, {"shoot": true}))
	assert_array(bad).override_failure_message("\n".join(bad.slice(0, 2))).is_empty()


## 12a: a hit buff is on the table when the activation is done and the NEXT capture of the board carries it; a miss lands
## nothing. RED without the landing (neither the stage's nor the delta's): no record, no token, the ledger of the capture empty.
func test_a_hit_buff_is_on_the_table_and_in_the_next_capture() -> void:
	var hit := 0
	for s in SEEDS:
		var door := await _run(TERROR_SEEKER, s, "run_ai")
		var passed: bool = int(str((door["rolls"] as Array)[0]).get_slice("|", 4)) >= 4   # the cast die's face against its 4+
		hit += 1 if passed else 0
		assert_int(int(door["ledger"])).override_failure_message("seed %d: rolls %s ledger %s" % [s, door["rolls"], door["ledger"]]) \
			.is_equal(1 if passed else 0)
	assert_int(hit).override_failure_message("no seed passed the 4+ die: the test proved nothing").is_greater(0)


## 12a: the delta's `buffs_gained` lands what the stage did not (a drive with no presentation of its own), once; a name no
## planned cast explains is reported (push_error) and writes nothing; a cast the stage landed already is no news.
func test_the_delta_lands_a_gained_buff_once() -> void:
	var caster := ParityTable._make_unit(_main, MYSTIC, STAFF)
	_main._solo_spell_tokens_active.clear()
	var cast := {"caster": caster, "caster_unit": caster, "name": "Terror Seeker", "spell": TERROR_SEEKER, "targets": [caster]}
	var cx := CoreActivation.cast_context(_main, {"casts": [cast]})
	var done := {"cx": cx}
	CoreActivation._land_spell_buffs(_main, caster, {"buffs_gained": ["Terror Seeker"]}, done)
	CoreActivation._land_spell_buffs(_main, caster, {"buffs_gained": ["Terror Seeker"]}, done)   # no news the second time
	assert_int((_main._solo_spell_mods.get(caster.get_instance_id(), []) as Array).size()).override_failure_message("one record").is_equal(1)
	assert_int(_main._solo_spell_tokens_active.size()).override_failure_message("one token").is_equal(1)
	_main._solo_spell_mods.erase(caster.get_instance_id())
	_main._solo_spell_tokens_active.clear()
	Harness._free_units(_main, [caster])


## CC-13a: with the switch ON the AI body's own seams take the cast: `takes_ai_activation`, the probe, the core's one call. The same
## cases as the door grid above, through `_solo_ai_casts` + `_solo_ai_core_call` instead of a hand-marked `run_ai`; the Dangerous
## test the body owes rides the core's call and is thrown BEFORE the cast die, as the table pays it. Equal to the table path.
func test_the_body_takes_a_cast_through_the_switch(timeout := 600000) -> void:
	CoreActivation._cast_env = 1
	var bad: Array = []
	bad.append_array(await _grid(TERROR_SEEKER, {}, "body"))
	bad.append_array(await _grid(BLOODTHIRST, {}, "body"))
	bad.append_array(await _grid(PSYCHIC_BLAST, {"foe_models": 10}, "body"))
	bad.append_array(await _grid(BLOODTHIRST, {"fizzle": true}, "body"))
	bad.append_array(await _grid(BLOODTHIRST, {"shoot": true}, "body"))
	# seed 3's Dangerous die is a 1 that destroys the one-model caster: the door's destroyed-unit lines differ from the table's there
	# (the volley door's own, `e2e_one_core_ai_dangerous_test`), not a cast matter
	bad.append_array(await _grid(TERROR_SEEKER, {"dangerous": true, "seeds": [0, 1, 2, 8, 11]}, "body"))
	assert_array(bad).override_failure_message("\n".join(bad.slice(0, 2))).is_empty()
	assert_int(CoreActivation.cast_probe_refusals).override_failure_message("a probe refused: %s" % str(CoreActivation.cast_probe_reasons)).is_equal(0)


## CC-13a: a spell the core cannot take is refused by the probe BEFORE any die, and the table then does what it always did: it
## pays the Dangerous test the body had left to the core, then resolves the cast (never cast -> Dangerous, c19_cast_dangerous_order).
func test_a_refused_probe_leaves_the_table_its_old_order() -> void:
	CoreActivation._cast_env = 1
	for s in [0, 1, 2]:
		var table := await _run(UNKNOWN_BOLT, s, "table", {"dangerous": true})
		var body := await _run(UNKNOWN_BOLT, s, "body", {"dangerous": true})
		assert_str(_diff(table, body)).override_failure_message("seed %d: %s" % [s, _diff(table, body)]).is_empty()
		assert_bool(bool(body["takes"]) and not bool(body["marked"])).override_failure_message("taken by the predicate, not by the probe").is_true()
		assert_bool(str((body["rolls"] as Array)[0]).begins_with("dangerous|")).override_failure_message("the Dangerous test comes first: %s" % str(body["rolls"])).is_true()
	assert_int(CoreActivation.cast_probe_refusals).override_failure_message(str(CoreActivation.cast_probe_reasons)).is_equal(3)


## CC-13a: with the switch OFF nothing changes: the activation is not taken (CC-2c's line), no mark, the table casts.
func test_the_switch_off_keeps_the_old_path() -> void:
	CoreActivation._cast_env = 0
	var table := await _run(TERROR_SEEKER, 0, "table")
	var body := await _run(TERROR_SEEKER, 0, "body")
	assert_str(_diff(table, body)).is_empty()
	assert_bool(bool(body["takes"]) or bool(body["marked"])).is_false()
	assert_int(CoreActivation.cast_probe_refusals).is_equal(0)


## CC-13a: a marked activation whose core call cannot run (no board) owes the casts: the fallback pays the test and casts on the
## table, the activation's old order.
func test_a_core_call_that_cannot_run_leaves_the_casts_to_the_table() -> void:
	CoreActivation._cast_env = 1
	for s in [0, 1]:
		var table := await _run(TERROR_SEEKER, s, "table", {"dangerous": true})
		var body := await _run(TERROR_SEEKER, s, "body", {"dangerous": true, "no_core_call": true})
		assert_str(_diff(table, body)).override_failure_message("seed %d: %s" % [s, _diff(table, body)]).is_empty()
		assert_bool(bool(body["takes"]) and not bool(body["marked"])).is_true()


## CC-15 prep: the door's census for the soak. Casting activations seen at the body's cast slot, the probe's takes, its refusals (with
## the core's reason) and the marked activations whose core call could not run, all in the census file the soak reads.
func test_the_door_counts_what_it_takes_refuses_and_falls_back_for_the_soak() -> void:
	CoreActivation._cast_env = 1
	CoreActivation.cast_seen = 0
	CoreActivation.cast_taken = 0
	CoreActivation.cast_fallbacks = 0
	CoreActivation.cast_probe_refusals = 0
	CoreActivation.cast_probe_reasons = []
	CoreActivation.cast_not_asked = {}
	await _run(TERROR_SEEKER, 0, "body")   # taken
	await _run(UNKNOWN_BOLT, 0, "body")   # refused by the probe before any die
	await _run(TERROR_SEEKER, 0, "body", {"no_core_call": true})   # taken, the core call cannot run: the table casts after all
	CoreActivation._cast_env = 0
	await _run(TERROR_SEEKER, 0, "body")   # the switch is off: seen, not asked
	var path := ProjectSettings.globalize_path("user://cc15_census.json")
	var saved := OS.get_environment("NML_TABLE_CENSUS")
	OS.set_environment("NML_TABLE_CENSUS", path)
	CoreActivation.dump_legacy()
	OS.set_environment("NML_TABLE_CENSUS", saved)
	var door: Dictionary = (JSON.parse_string(FileAccess.get_file_as_string(path)) as Dictionary).get("cast_door", {})
	assert_int(int(door.get("seen", -1))).is_equal(4)
	assert_int(int(door.get("taken", -1))).is_equal(2)
	assert_int(int(door.get("fallbacks", -1))).is_equal(1)
	assert_int(int(door.get("probe_refusals", -1))).is_equal(1)
	assert_int((door.get("reasons", []) as Array).size()).is_equal(1)
	assert_str(str((door["reasons"] as Array)[0])).contains("has no spell named")
	assert_int(int((door.get("not_asked", {}) as Dictionary).get("switch_off", -1))).is_equal(1)
	# why a casting activation is not asked: no board, a unit the slice refuses (Mend is on the deny list), an action the door does not take
	CoreActivation._cast_env = 1
	CoreActivation.cast_not_asked = {}
	var plain := ParityTable._make_unit(_main, MYSTIC, STAFF)
	var mender := ParityTable._make_unit(_main, MYSTIC.merged({"key": "mn", "name": "Mender", "faction_folder": "robot_legions", "rules": ["Caster", "Mend"]}, true), STAFF)
	var report := {"action": AiDecision.Action.HOLD, "casts": [{}]}
	CoreActivation.note_cast_not_asked(_main, plain, report)   # no handle
	_main._solo_core_ai_h = CoreActivation.capture(_main)
	CoreActivation.note_cast_not_asked(_main, mender, report)   # a Mend carrier: the slice refuses it first
	CoreActivation.note_cast_not_asked(_main, plain, {"action": AiDecision.Action.CHARGE, "casts": [{}]})
	_main.solo_controller._core_node_ready().release(_main._solo_core_ai_h)
	_main._solo_core_ai_h = 0
	assert_dict(CoreActivation.cast_not_asked).is_equal({"no_handle": 1, "unit:unit_rule:Mend": 1, "action:%d" % AiDecision.Action.CHARGE: 1})


## CC-13a: the cast predicate: a unit (or a joined hero) that carries a table-only pre-attack beat (Mend here) stays on the table
## even with the switch ON; a plain caster is taken.
func test_a_unit_with_a_pre_attack_beat_stays_on_the_table() -> void:
	CoreActivation._cast_env = 1
	var plain := ParityTable._make_unit(_main, MYSTIC, STAFF)
	var mender := ParityTable._make_unit(_main, MYSTIC.merged({"key": "mn", "name": "Mender", "faction_folder": "robot_legions", "rules": ["Caster", "Mend"]}, true), STAFF)
	var cast := {"caster": mender, "caster_unit": mender, "name": "Terror Seeker", "spell": TERROR_SEEKER, "targets": [mender]}
	var report := {"action": AiDecision.Action.HOLD, "moved": false, "casts": [cast]}
	assert_bool(CoreActivation.cast_chain_clear(plain)).is_true()
	assert_bool(CoreActivation.cast_chain_clear(mender)).override_failure_message("Mend is a table-only beat").is_false()
	_main._solo_core_ai_h = CoreActivation.capture(_main)
	assert_bool(CoreActivation.takes_ai_activation(_main, mender, report)).is_false()
	_main.solo_controller._core_node_ready().release(_main._solo_core_ai_h)
	_main._solo_core_ai_h = 0
	Harness._free_units(_main, [plain, mender])
