extends SceneTree
## Plan E (speed plan lever 3): committed single-boot melee matrix probe CLI.
## Boots main.tscn once, proves the instrument (rule-free control 100% equal + planted defender +1" fault unequal), then
## runs every (primitive, seat) cell in `--cells` door-vs-table with the door-test compare (positions 0.01", wounds, alive,
## Shaken, Fatigue, ledger, attached heroes, tray RNG, roll records, battle-log lines) and writes one JSON row per cell.
##
##   nml-godot-ds --headless --path . -s res://test/one_core/melee_matrix_cli.gd -- \
##     --cells res://test/one_core/melee_matrix_cells.json --seeds 16 --out <dir>
##
## Refuses to write the report (exit 2) if the control is not 100% equal or the planted fault is not unequal.

const ParityTable := preload("res://test/parity/parity_table.gd")
const RosterSweep := preload("res://test/one_core/roster_sweep.gd")
const INCH := 0.0254
const MAX_BOOT_FRAMES := 1800
const DEFAULT_CELLS := "res://test/one_core/melee_matrix_cells.json"
const BASE_SIDE := {"quality": 4, "defense": 4, "tough": 1, "z_step_in": 1.3, "game_system": "gf",
	"faction_folder": "robot_legions", "rules": []}
const BASE_BLADE := {"name": "Blade", "range_in": 0, "attacks": 2, "count": 10, "rules": []}
const CLASS_RANK := {"": 0, "line": 1, "roll": 2, "state": 3}
## Test hooks (the refusal tests break the instrument on purpose): the planted fault's defender nudge, and an extra gap that
## only the CORE half sees (a control that is no longer equal). Defaults = the real instrument.
static var fault_nudge_in := 1.0
static var core_half_nudge_in := 0.0


func _initialize() -> void:
	_run.call_deferred(OS.get_cmdline_user_args())


func _arg(args: Array, key: String, fallback := "") -> String:
	for i in args.size():
		if str(args[i]) == key and i + 1 < args.size():
			return str(args[i + 1])
	return fallback


func _boot() -> Node:
	for _i in MAX_BOOT_FRAMES:
		await process_frame
		if current_scene != null and current_scene.get("opr_army_manager") != null:
			return current_scene
	return null


func _run(args: Array) -> void:
	ProjectSettings.set_setting("niemandsland/harness_mode", true)
	change_scene_to_file("res://scenes/main.tscn")
	var main := await _boot()
	if main == null:
		printerr("MELEE-MATRIX-FAIL: main.tscn never finished booting")
		quit(1)
		return
	var cells_path := _arg(args, "--cells", DEFAULT_CELLS)
	var seeds := maxi(1, int(_arg(args, "--seeds", "16")))
	var out_arg := _arg(args, "--out", "user://melee_matrix_out")
	var flt := _arg(args, "--filter", "")
	var cells := load_cells(cells_path)
	if not flt.is_empty():
		cells = cells.filter(func(c: Dictionary) -> bool:
			return ("%s:%s" % [c["primitive"], c["seat"]]).to_lower().contains(flt.to_lower()))
	if cells.is_empty():
		printerr("MELEE-MATRIX-FAIL: no cells loaded from %s" % cells_path)
		quit(2)
		return
	var t0 := Time.get_ticks_msec()
	arm(main)
	var report := await run_matrix(main, cells, seeds, true)
	disarm(main)
	report["runtime_s"] = snappedf(float(Time.get_ticks_msec() - t0) / 1000.0, 0.01)
	if not bool(report["ok"]):
		printerr("MELEE-MATRIX-ABORT: %s" % str(report["error"]))
		quit(2)
		return
	var out_path := out_arg if out_arg.ends_with(".json") else out_arg.path_join("melee_matrix.json")
	DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  ", false, true) + "\n")
	f.close()
	var tot: Dictionary = report["totals"]
	printerr("MELEE-MATRIX-SUMMARY cells=%d seeds=%d runtime_s=%.2f EQUAL=%d UNEQUAL=%d (LINE=%d ROLL=%d STATE=%d) INERT=%d out=%s" % [
		cells.size(), seeds, float(report["runtime_s"]), int(tot["EQUAL"]), int(tot["UNEQUAL"]),
		int(tot["LINE"]), int(tot["ROLL"]), int(tot["STATE"]), int(tot["INERT"]), out_path])
	quit(0)


static func load_cells(path: String) -> Array:
	if path.is_empty() or not FileAccess.file_exists(path):
		return []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		return (parsed as Dictionary).get("cells", []) as Array
	return parsed as Array if parsed is Array else []


static func arm(main: Node) -> void:
	main.solo_ai_slots = {1: true, 2: true}
	main._ensure_solo_controller()
	main.solo_controller.ai_slot = 2
	main.solo_controller.human_slot = 1
	main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	main.opr_army_manager.current_round = 1
	main._solo_batch = true
	main._solo_auto_saves = true
	main._solo_fast = true
	main._autosave_controller.set_lesson_paused(true)
	CoreActivation._env = 1
	CoreActivation._charge_env = 1
	CoreActivation.ai_charges = 0


static func disarm(main: Node) -> void:
	CoreShadow.tapping = false
	CoreShadow.tap.clear()
	CoreActivation._charge_landing = false
	CoreActivation.reset_all(main)
	CoreActivation._env = -1
	CoreActivation._charge_env = -1


## Runs the mandatory control + planted-fault check, then every cell in `cells`. Returns the full report dict.
static func run_matrix(main: Node, cells: Array, seeds: int, verbose := false) -> Dictionary:
	var ctrl_cache := {}
	var base := {"primitive": "control", "seat": "-", "rule": "", "system": "gf", "faction": "robot_legions"}
	var ctrl := await _run_pair(main, base, seeds, ctrl_cache, true, false)
	var fault := await _run_pair(main, base, seeds, ctrl_cache, false, true)
	if int(ctrl["equal_seeds"]) != seeds:
		return {"ok": false, "error": "control was %d/%d equal (%s)" % [ctrl["equal_seeds"], seeds, ctrl["first_diff"]]}
	if int(fault["equal_seeds"]) >= seeds:
		return {"ok": false, "error": "planted fault was %d/%d equal (expected unequal)" % [fault["equal_seeds"], seeds]}
	var rows: Array = []
	var totals := {"EQUAL": 0, "UNEQUAL": 0, "INERT": 0, "LINE": 0, "ROLL": 0, "STATE": 0}
	for i in cells.size():
		var row := await run_cell(main, cells[i] as Dictionary, seeds, ctrl_cache)
		rows.append(row)
		var v := str(row["verdict"])
		totals[v] = int(totals[v]) + 1
		if v == "UNEQUAL":
			var cls := str(row["first_diff_class"]).to_upper()
			totals[cls] = int(totals.get(cls, 0)) + 1
		if verbose:
			printerr("MELEE-MATRIX [%d/%d] %s %s -> %s eq=%d/%d fired=%d cls=%s" % [
				i + 1, cells.size(), row["primitive"], row["seat"], v, row["equal_seeds"], seeds, row["fired_seeds"], row["first_diff_class"]])
	return {"ok": true, "schema": "nml-melee-matrix-run-v1", "seeds": seeds,
		"control": {"equal_seeds": ctrl["equal_seeds"], "seeds": seeds},
		"planted_fault": {"equal_seeds": fault["equal_seeds"], "seeds": seeds,
			"first_diff_class": fault["first_diff_class"], "first_diff": fault["first_diff"]},
		"totals": totals, "cells": rows}


static func run_cell(main: Node, cell: Dictionary, seeds: int, ctrl_cache := {}) -> Dictionary:
	var res := await _run_pair(main, cell, seeds, ctrl_cache, false, false)
	var eq := int(res["equal_seeds"])
	var fired := int(res["fired_seeds"])
	var verdict := "UNEQUAL" if eq < seeds else ("INERT" if fired == 0 else "EQUAL")
	return {"primitive": str(cell["primitive"]), "seat": str(cell["seat"]), "verdict": verdict,
		"equal_seeds": eq, "fired_seeds": fired,
		"first_diff_class": str(res["first_diff_class"]) if verdict == "UNEQUAL" else "",
		"first_diff": str(res["first_diff"]) if verdict == "UNEQUAL" else ""}


static func _run_pair(main: Node, cell: Dictionary, seeds: int, ctrl_cache: Dictionary, cache_as_ctrl: bool, fault: bool) -> Dictionary:
	CoreActivation.reset_all(main)
	var eq := 0
	var fired := 0
	var best_cls := ""
	var best_diff := ""
	var cspec := _ctrl_spec(cell)
	var ckey := JSON.stringify(cspec, "", true, true)
	for s in seeds:
		var table := await _half(main, cell, s, false, false)
		if cache_as_ctrl:
			if not ctrl_cache.has(ckey):
				ctrl_cache[ckey] = {}
			(ctrl_cache[ckey] as Dictionary)[s] = table
		var core := await _half(main, cell, s, true, fault)
		if not cache_as_ctrl and not fault:
			if not ctrl_cache.has(ckey):
				ctrl_cache[ckey] = {}
			var bucket: Dictionary = ctrl_cache[ckey]
			if not bucket.has(s):
				bucket[s] = await _half(main, cspec, s, false, false)
			if _table_fired(table, bucket[s] as Dictionary):
				fired += 1
		var cmp := _compare_halves(table, core)
		if bool(cmp["equal"]):
			eq += 1
		elif int(CLASS_RANK[cmp["cls"]]) > int(CLASS_RANK[best_cls]):
			best_cls = str(cmp["cls"])
			best_diff = "seed %d: %s" % [s, cmp["diff"]]
	return {"equal_seeds": eq, "fired_seeds": fired, "first_diff_class": best_cls, "first_diff": best_diff}


## Strips ONLY the tested rule/feature from `cell` so the table baseline measures whether this cell's rule fired.
static func _ctrl_spec(cell: Dictionary) -> Dictionary:
	var c: Dictionary = cell.duplicate(true)
	var prim := str(c.get("primitive", ""))
	var seat := str(c.get("seat", ""))
	var rule := str(c.get("rule", ""))
	c["rule"] = ""
	var side_key := "att" if seat in ["CU", "CW"] else "def"
	if c.has(side_key):
		var sd: Dictionary = c[side_key]
		for pair in [["Tough", "tough"], ["Hero (joined", "attached_hero"], ["Limited", "limited_used"],
				["Growth Markers", "ledger"], ["Aura Channel", "expand_aura"]]:
			if prim.begins_with(str(pair[0])):
				sd.erase(str(pair[1]))
		for w in (sd.get("extra_weapons", []) as Array):
			((w as Dictionary).get("rules", []) as Array).erase(rule)
		if sd.is_empty():
			c.erase(side_key)
	c.erase("primitive")
	c.erase("seat")
	return c


## One half (table or core) of a charge comparison: returns state, positions, RNG, roll records and battle-log lines.
static func _half(main: Node, cell: Dictionary, seed_n: int, core_run: bool, fault: bool) -> Dictionary:
	var spawned := _spawn_fixture(main, cell, core_run and fault, core_half_nudge_in if core_run else 0.0)
	var att: GameUnit = spawned[0]
	var foe: GameUnit = spawned[1]
	var terrain_saved := _paint_forest(main) if str(cell.get("terrain", "")) == "forest" else {}
	var lines: Array = []
	var tap := func(e: Dictionary) -> void:
		lines.append("%s|%s" % [BattleLog.Category.keys()[int(e["category"])], str(e["text"])])
	main.battle_log.entry_added.connect(tap)
	main.seed_tray_rng(seed_n)
	var charges := CoreActivation.ai_charges
	var sc: SoloController = main.solo_controller
	var h := 0
	if core_run:
		CoreActivation._announced.clear()
		CoreActivation._ended_round = -1
		CoreActivation._ended_rows.clear()
		h = CoreActivation.capture(main)
	CoreShadow.tap.clear()
	CoreShadow.tapping = true
	main._solo_core_ai_h = h
	var band := float(MovementRangeController.move_bands_for_props(att.unit_properties).get("charge", 12.0))
	if RulesRegistry.unit_rule_active(att, "Versatile Reach"):
		var vr_add := float(RulesRegistry.unit_param(att, "Versatile Reach", "charge_bonus_in", 2.0))
		var vr_gap := sc.nearest_melee_gap_in(att, foe)
		if vr_gap > band and vr_gap <= band + vr_add:
			band += vr_add
	var from_in: float = sc.charge_from_in(att, foe, MoveIntent.distance_inches(sc.unit_centre(att), sc.unit_centre(foe)))
	sc._charge_move(att, foe, sc.melee_shroud_charge_in(band, foe))
	att.unit_properties["moved_round"] = 1
	var report := {"unit": att, "target": foe, "action": AiDecision.Action.CHARGE, "charge_from_in": from_in, "moved": true}
	if core_run:
		if h != 0:
			await CoreActivation.run_ai_charge(main, att, report)
	else:
		await main._run_ai_melee(report)
		if not att.is_destroyed() and sc.hit_and_run_move(att, false):
			main.battle_log.log_event(BattleLog.Category.MOVEMENT, "%s: %s steps up to 3\" after its attack" % [
				sc._hit_and_run_pick(att, false), att.get_name()], true)
	CoreShadow.tapping = false
	main._solo_core_ai_h = 0
	if h != 0:
		sc._core_node_ready().release(h)
	main.battle_log.entry_added.disconnect(tap)
	var rolls: Array = CoreShadow.tap.map(func(r: Dictionary) -> String:
		return "%s|%d|%d|%s" % [r["kind"], int(r["count"]), int(r["target"]), JSON.stringify(r["faces"])])
	var out := {"att": RosterSweep._pos(att), "foe": RosterSweep._pos(foe),
		"wounds": [main._solo_unit_wounds_now(att), main._solo_unit_wounds_now(foe)],
		"alive": [att.get_alive_count(), foe.get_alive_count()],
		"shaken": [att.is_shaken, foe.is_shaken], "fatigued": [att.is_fatigued, foe.is_fatigued],
		"ledger": [_ledger_json(att), _ledger_json(foe)], "heroes": _hero_snap(main, att) + _hero_snap(main, foe),
		"rng": main._tray_rng.state, "rolls": rolls, "lines": lines, "core": CoreActivation.ai_charges - charges}
	_unpaint_forest(main, terrain_saved)
	RosterSweep.free_units(main, spawned)
	await main.get_tree().process_frame
	return out


static func _spawn_fixture(main: Node, cell: Dictionary, fault_nudge: bool, extra_gap_in := 0.0) -> Array:
	var sys := str(cell.get("system", "gf"))
	var fac := str(cell.get("faction", "robot_legions"))
	var seat := str(cell.get("seat", ""))
	var rule := str(cell.get("rule", ""))
	var gap := float(cell.get("gap_in", 7.0)) + (fault_nudge_in if fault_nudge else 0.0) + extra_gap_in
	var att_o: Dictionary = cell.get("att", {})
	var def_o: Dictionary = cell.get("def", {})
	var att := _build_unit(main, 2, "Att", 5, 0.0, 1.3, 2, sys, fac, att_o, rule if seat == "CU" else "", rule if seat == "CW" else "")
	var foe := _build_unit(main, 1, "Def", 8, gap, 1.4, 2, sys, fac, def_o, rule if seat == "TU" else "", rule if seat == "TW" else "")
	for i in foe.models.size():
		(foe.models[i] as ModelInstance).node.global_position.z += float((i * 7) % 5) * 0.0001
	var spawned: Array = [att, foe]
	for pair in [[att, att_o, 2, 0.0], [foe, def_o, 1, gap]]:
		if bool((pair[1] as Dictionary).get("attached_hero", false)):
			var h := _build_unit(main, int(pair[2]), "Hero", 1, float(pair[3]), 1.3, 3, sys, fac, {"quality": 3, "tough": 3}, rule, "")
			(h.models[0] as ModelInstance).node.global_position.z = -1.3 * INCH
			EquipmentDistributor.attach_hero_to_unit(h, pair[0] as GameUnit)
			spawned.append(h)
	if bool(cell.get("mid_blocker", false)):
		var mid := _build_unit(main, 1, "Mid", 1, 3.5, 1.3, 1, sys, fac, {}, "", "")
		(mid.models[0] as ModelInstance).node.global_position.z = 2.6 * INCH
		spawned.append(mid)
	return spawned


static func _build_unit(main: Node, player: int, uname: String, def_models: int, x_in: float, def_z: float,
		def_atk: int, sys: String, fac: String, ov: Dictionary, unit_rule: String, weap_rule: String) -> GameUnit:
	var models := int(ov.get("models", def_models))
	var tough := int(ov.get("tough", 1))
	var urules: Array = (ov.get("rules", []) as Array).duplicate()
	if not unit_rule.is_empty() and not (tough > 1 and unit_rule.begins_with("Tough(")) and not urules.has(unit_rule):
		urules.append(unit_rule)
	var extra_w: Array = ov.get("extra_weapons", [])
	var wrules: Array = (ov.get("weapon_rules", []) as Array).duplicate()
	if not weap_rule.is_empty() and not extra_w.any(func(ew: Dictionary) -> bool: return (ew.get("rules", []) as Array).has(weap_rule)) and not wrules.has(weap_rule):
		wrules.append(weap_rule)
	var spec := BASE_SIDE.merged({"player": player, "name": uname, "models": models, "x_in": x_in,
		"quality": int(ov.get("quality", 4)), "defense": int(ov.get("defense", 4)), "tough": tough,
		"z_step_in": float(ov.get("z_step_in", def_z)), "game_system": sys, "faction_folder": fac,
		"rules": urules, "ledger": ov.get("ledger", {})}, true)
	var gu := ParityTable._make_unit(main, spec, BASE_BLADE.merged({"count": int(ov.get("weapon_count", 10)), "attacks": int(ov.get("weapon_attacks", def_atk)), "rules": wrules}, true))
	for ew in extra_w:
		var d: Dictionary = ew
		var w := OPRApiClient.OPRWeapon.new()
		w.name = str(d["name"]); w.range_value = int(d["range_in"]); w.attacks = int(d["attacks"]); w.count = int(d["count"])
		w.special_rules.assign(d.get("rules", []))
		(gu.source_data as OPRApiClient.OPRUnit).weapons.append(w)
	if ov.has("wounds_cur") and not gu.models.is_empty():
		(gu.models[0] as ModelInstance).wounds_current = int(ov["wounds_cur"])
	if bool(ov.get("pin_kits", false)):
		for m in gu.models:
			(m as ModelInstance).properties["weapons"] = [{"name": "Blade", "count": 1}]
	if bool(ov.get("limited_used", false)):
		main.solo_controller.mark_limited_used(gu, {"name": "Blade"})
	if bool(ov.get("expand_aura", false)):
		OPRArmyManager.expand_auras_of([gu.source_data], {gu.source_data: gu})
	return gu


static func _ledger_json(u: GameUnit) -> String:
	var d: Dictionary = AiActRecorder._ledger_of(u)
	d.erase("moved_round")
	return JSON.stringify(d, "", true, true)


static func _hero_snap(main: Node, host: GameUnit) -> Array:
	return host.get_attached_heroes().map(func(h: GameUnit) -> Dictionary:
		return {"pos": RosterSweep._pos(h), "alive": h.get_alive_count(),
			"wounds": main._solo_unit_wounds_now(h), "shaken": h.is_shaken, "fatigued": h.is_fatigued})


static func _heroes_equal(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if not RosterSweep.positions_near(a[i]["pos"], b[i]["pos"]):
			return false
		for k in ["alive", "wounds", "shaken", "fatigued"]:
			if a[i][k] != b[i][k]:
				return false
	return true


static func _table_fired(t: Dictionary, ctrl: Dictionary) -> bool:
	for k in ["att", "foe"]:
		if not RosterSweep.positions_near(t[k], ctrl[k]):
			return true
	for k in ["wounds", "alive", "shaken", "fatigued", "ledger", "rng", "rolls", "lines"]:
		if t[k] != ctrl[k]:
			return true
	return not _heroes_equal(t["heroes"], ctrl["heroes"])


## Compares table vs core for one seed; classifies the first difference as state > roll > line.
static func _compare_halves(t: Dictionary, c: Dictionary) -> Dictionary:
	if int(c["core"]) != 1 or int(t["core"]) != 0:
		return {"equal": false, "cls": "state", "diff": "door_refused (core=%d table=%d)" % [c["core"], t["core"]]}
	for k in ["att", "foe"]:
		if not RosterSweep.positions_near(t[k], c[k]):
			return {"equal": false, "cls": "state", "diff": "%s positions: table %s / core %s" % [k, t[k], c[k]]}
	for k in ["alive", "wounds", "shaken", "fatigued", "ledger", "rng"]:
		if t[k] != c[k]:
			return {"equal": false, "cls": "state", "diff": "%s: table %s / core %s" % [k, t[k], c[k]]}
	if not _heroes_equal(t["heroes"], c["heroes"]):
		return {"equal": false, "cls": "state", "diff": "heroes: table %s / core %s" % [t["heroes"], c["heroes"]]}
	if t["rolls"] != c["rolls"]:
		return {"equal": false, "cls": "roll", "diff": "roll %s" % _first_list_diff(t["rolls"], c["rolls"])}
	if t["lines"] != c["lines"]:
		return {"equal": false, "cls": "line", "diff": "line %s" % _first_list_diff(t["lines"], c["lines"])}
	return {"equal": true, "cls": "", "diff": ""}


static func _first_list_diff(a: Array, b: Array) -> String:
	for i in maxi(a.size(), b.size()):
		var va: Variant = a[i] if i < a.size() else "<none>"
		var vb: Variant = b[i] if i < b.size() else "<none>"
		if va != vb:
			return "#%d table %s / core %s" % [i, va, vb]
	return ""


static func _paint_forest(main: Node) -> Dictionary:
	var saved := {}
	if main.terrain_overlay == null:
		return saved
	var o: Node3D = main.terrain_overlay
	var x := 2.5
	while x <= 5.51:
		var z := -4.0
		while z <= 12.01:
			var key: Vector2i = o.world_to_cell(Vector3(x * INCH, 0.0, z * INCH))
			if not saved.has(key):
				saved[key] = {"had": o.grid_cells.has(key), "value": int(o.grid_cells.get(key, 0))}
			o.grid_cells[key] = o.TerrainType.FOREST
			z += 0.5
		x += 0.5
	return saved


static func _unpaint_forest(main: Node, saved: Dictionary) -> void:
	if saved.is_empty() or main.terrain_overlay == null:
		return
	var o: Node3D = main.terrain_overlay
	for key in saved:
		if bool(saved[key]["had"]):
			o.grid_cells[key] = int(saved[key]["value"])
		else:
			o.grid_cells.erase(key)
