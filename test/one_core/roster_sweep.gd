extends RefCounted
## One core C-7 (shadow-run slice, lane S2): the ROSTER SWEEP harness. Real army lists, every unit of every list fires one AI
## volley at a unit of an opposing list and is the target of one, per seed, on BOTH paths:
##   table = the old table, the AI body's own shooting (`main._run_ai_shooting`) with no core handle, kill switch OFF;
##   core  = the one-core door minus the slice gate: the live capture (`CoreActivation.capture`) and the step driver
##           (`CoreActivation.drive`) with the same transcript the AI door sends, so units with rules (which the shipped slice
##           refuses) go through it too.
## Same seed (`main.seed_tray_rng`) for both halves. Per volley the harness records the dice stream (the table's own dice tap,
## NML_DICE_DUMP, as test/parity/parity_table.gd) and the end state of both units (alive, wounds, Shaken, Fatigued and the ledger
## `AiActRecorder._ledger_of`). Rolls are compared by `tools/parity/parity_compare.py` (the established gate reading); state and
## ledger here. Output: one JSONL per half (the parity files), the per-volley verdict, and the COVERAGE table (rule name x shooter /
## target volleys), which is a gate: an uncovered rule name is red.
##
## Both seats are AI (the soak's setting): a human target's wound-allocation prompt is out of scope here (it stays on the table).
## Lists: any gf / aof list JSON (the importer's own format), e.g. assets/arena_lists, test/fixtures, or a fleet directory of
## per-faction lists (<faction>_<points>.json): pairings are a ring over the lists of one system.
## Loaded by test/one_core/roster_sweep_test.gd and by the CLI test/one_core/roster_sweep_cli.gd, after main.tscn is up.

const ParityTable := preload("res://test/parity/parity_table.gd")
const INCH := 0.0254
const SEAT_SHOOTER := 2
const SEAT_TARGET := 1
## Centre-to-centre distance of the two unit blocks in inches: inside every weapon range a list carries, outside 9" (the rules
## that gate on it are exercised), before terrain exists.
const DISTANCE_IN := 14.0
const CHARGE_GAP_IN := 7.0
const CHARGE_STRUCTURAL := ["no_charge", "human_defender", "size", "no_statline", "dangerous", "cast"]
const ROW := 5


## The units of one list file: [{"unit": OPRUnit, "faction": "<registry key>", "system": "gf"|"aof"}] and the list's name.
static func load_list(path: String) -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		return {}
	var client := OPRApiClient.new()
	var army: OPRApiClient.OPRArmy = client.build_army_offline(data as Dictionary)
	client.free()
	if army == null:
		return {}
	var units: Array = []
	for u in army.units:
		units.append({"unit": u, "faction": army.faction_folder, "system": army.game_system_abbrev})
	return {"path": path, "name": str(data.get("name", path)), "system": army.game_system_abbrev, "units": units}


## The ring of pairings over `lists` (of one system each): list i against list i+1, so every list is in two pairings.
static func ring(lists: Array) -> Array:
	var out: Array = []
	if lists.size() < 2:
		return out
	for i in lists.size():
		var a: Dictionary = lists[i]
		var b: Dictionary = lists[(i + 1) % lists.size()]
		if str(a["system"]) == str(b["system"]) and (lists.size() > 2 or i == 0):
			out.append([a, b])
	return out


## Every rule name the registry map of `system` knows (the common rules and every faction's), sorted: what the coverage gate asks for.
static func rule_names(system: String) -> Array:
	var m := RulesRegistry.map_for(system)
	var seen := {}
	for n in (m.get("common", {}) as Dictionary):
		seen[n] = true
	for f in (m.get("factions", {}) as Dictionary):
		for n in (m["factions"][f] as Dictionary):
			seen[n] = true
	var out: Array = seen.keys()
	out.sort()
	return out


## The import's aura pass over every spawned unit (see `spawn`); a test may switch it off to prove what it fixes.
static var aura_pass := true


## One real unit on the table: the importer's own `create_from_opr_unit` over fresh model nodes in `ROW`-wide ranks, centred on
## (`x_in`, 0), registered with the table. Rules, weapons and loadouts are the list's; only the position is the harness's.
static func spawn(main: Node, entry: Dictionary, seat: int, x_in: float) -> GameUnit:
	var ou: OPRApiClient.OPRUnit = entry["unit"]
	var nodes: Array[Node3D] = []
	var step := maxf(1.4, float(maxf(ou.base_size_round, ou.base_width_mm)) / 25.4 + 0.2)
	var n := maxi(ou.size, 1)
	for i in n:
		var nd := Node3D.new()
		main.add_child(nd)
		nd.global_position = Vector3((x_in + float(i / ROW) * step * (1.0 if seat == SEAT_TARGET else -1.0)) * INCH, 0.0,
			(float(i % ROW) - float(mini(n, ROW) - 1) / 2.0) * step * INCH)
		nodes.append(nd)
	var gu := EquipmentDistributor.create_from_opr_unit(ou, nodes, seat)
	if aura_pass:
		# The game's import runs this pass (`OPRArmyManager._expand_auras`, opr_army_manager.gd:403): a carried "X Aura" adds the base rule X to the
		# unit, which the table reads (it has no Aura Channel handling of its own) and the core reads through its registry. Without it a
		# sweep unit that carries "Relentless Aura" / "Fortified Aura" / "Unpredictable Shooter Aura" differs on the dice for a reason no
		# real game has (Plan H, H-10: the G3 / G5 / G14 groups). A joined hero is not attached here, so only the unit's own aura applies.
		OPRArmyManager.expand_auras_of([ou], {ou: gu})
	gu.unit_properties["faction_folder"] = str(entry["faction"])
	gu.unit_properties["network_id"] = gu.unit_id
	main.opr_army_manager.game_units[gu.unit_id] = gu
	return gu


static func free_units(main: Node, units: Array) -> void:
	for u in units:
		main.opr_army_manager.game_units.erase((u as GameUnit).unit_id)
		for m in (u as GameUnit).models:
			var nd: Node = (m as ModelInstance).node
			if nd != null and is_instance_valid(nd):
				nd.free()
	main.solo_controller._peeked_unit = null


## The rule names `gu` carries, parameters stripped: unit rules, then the weapon rules of its source (what the census labels are).
static func labels_of(gu: GameUnit) -> Array:
	var out: Array = []
	for r in gu.get_special_rules():
		out.append(_rule_name(r))
	var src := gu.source_data as OPRApiClient.OPRUnit
	for w in src.weapons if src != null else []:
		for r in w.special_rules:
			out.append(_rule_name(r))
	return out


static func _rule_name(r: Variant) -> String:
	return (str((r as Dictionary).get("name", "")) if r is Dictionary else str(r)).get_slice("(", 0).strip_edges()


## What the comparison reads off the two units after the volley.
static func state_of(att: GameUnit, tgt: GameUnit) -> Dictionary:
	var out := {}
	for pair in [["att", att], ["tgt", tgt]]:
		var gu: GameUnit = pair[1]
		var wounds: Array = gu.get_alive_models().map(func(m: ModelInstance) -> int: return m.wounds_current)
		wounds.sort()
		out[pair[0]] = {"alive": gu.get_alive_count(), "wounds": wounds, "shaken": gu.is_shaken, "fatigued": gu.is_fatigued,
			"ledger": JSON.parse_string(JSON.stringify(AiActRecorder._ledger_of(gu), "", true, true))}
	return out


## The first part in which two `state_of` readings differ ("" = equal); a ledger difference names its keys ("att.ledger:limited_used").
static func first_state_diff(t: Dictionary, c: Dictionary) -> String:
	for who in ["tgt", "att"]:
		for k in ["alive", "wounds", "shaken", "fatigued"]:
			if t[who][k] != c[who][k]:
				return "%s.%s" % [who, k]
		var keys: Array = (t[who]["ledger"] as Dictionary).keys().filter(func(x: String) -> bool: return t[who]["ledger"][x] != c[who]["ledger"].get(x))
		for x in (c[who]["ledger"] as Dictionary).keys():
			if not (t[who]["ledger"] as Dictionary).has(x) and not keys.has(x):
				keys.append(x)
		if not keys.is_empty():
			keys.sort()
			return "%s.ledger:%s" % [who, ",".join(keys)]
	return ""


## One volley on one path. `core` false = the table's AI body, true = capture + step driver. Returns {"rolls", "state", ...}.
## `opts` plants a state or a fault: "ledger" {"att"|"tgt": {property: value}} is written on both halves (a fact the table keeps);
## the core half alone can drop properties before the capture ("core_drop": {"att"|"tgt": [property]}), edit one weapon rule of the
## shooter for the volley ("core_edit_rule": {"from", "to"}) or swap one face of the roll stream it recorded ("core_swap_face": roll
## index); "distance_in" puts the target that far (centre to centre, inches) from the shooter instead of `DISTANCE_IN` on both halves. Nothing is planted unless asked: the sweep itself never touches either half.
static func volley(main: Node, entry_a: Dictionary, entry_b: Dictionary, seed_n: int, core: bool, dump_dir: String, opts := {}) -> Dictionary:
	var att := spawn(main, entry_a, SEAT_SHOOTER, 0.0)
	var tgt := spawn(main, entry_b, SEAT_TARGET, float(opts.get("distance_in", DISTANCE_IN)))
	var by := {"att": att, "tgt": tgt}
	for who in opts.get("ledger", {}):
		for prop in opts["ledger"][who]:
			(by[who] as GameUnit).unit_properties[prop] = opts["ledger"][who][prop]
	var edited: Array = []
	if core:
		for who in opts.get("core_drop", {}):
			for prop in opts["core_drop"][who]:
				(by[who] as GameUnit).unit_properties.erase(prop)
		if opts.has("core_edit_rule"):
			for w in (att.source_data as OPRApiClient.OPRUnit).weapons:
				var i: int = (w.special_rules as Array).find(opts["core_edit_rule"]["from"])
				if i >= 0:
					w.special_rules[i] = opts["core_edit_rule"]["to"]
					edited.append([w, i])
	main.seed_tray_rng(seed_n)
	var lines: Array = []   # the battle-log lines the volley wrote, "<CATEGORY>|<text>", in log order
	var on_entry := func(e: Dictionary) -> void:
		lines.append("%s|%s" % [BattleLog.Category.keys()[int(e["category"])], str(e["text"])])
	main.battle_log.entry_added.connect(on_entry)
	if core:
		CoreActivation.reset_all(main)   # a new game per volley: the header carries the profiles of THESE two units
		var h := CoreActivation.capture(main)
		var at: Array = att.get_alive_models().map(func(m: ModelInstance) -> Vector3: return m.node.global_position)
		var trails: Array = att.get_alive_models().map(func(_m: ModelInstance) -> Array: return [])   # the AI door's own transcript (run_ai)
		var t: Array = [{"t": "begin"}, {"t": "placed", "positions": at, "trails": trails},
			{"t": "intent", "kind": AiDecision.Action.HOLD, "shoot": tgt.unit_id}]
		var r: Dictionary = await CoreActivation.drive(main, h, att, t, true)
		if str(r["step"]) != "done":
			push_warning("roster sweep: the core answered %s (%s) for %s" % [r["step"], r.get("reason", ""), att.get_name()])
			if h != 0:
				main.solo_controller._core_node_ready().release(h)
		for e in edited:
			(e[0].special_rules as Array)[e[1]] = opts["core_edit_rule"]["from"]
	else:
		main._solo_core_ai_h = 0
		await main._run_ai_shooting({"unit": att, "moved": false, "action": AiDecision.Action.HOLD})
		main.solo_controller.hit_and_run_move(att, true)   # DS-HR1: the body's post-shot tail (main.gd:1347-1349)
	main.battle_log.entry_added.disconnect(on_entry)
	AiDiceRecorder.close()
	var rolls: Array = ParityTable._read_dice(dump_dir)
	if core and opts.has("core_swap_face") and int(opts["core_swap_face"]) < rolls.size():
		var faces: Array = rolls[int(opts["core_swap_face"])]["faces"]
		if not faces.is_empty():
			faces[0] = int(faces[0]) % 6 + 1
	var out := {"rolls": rolls, "state": state_of(att, tgt), "lines": lines,
		"labels": {"att": labels_of(att), "tgt": labels_of(tgt)}, "names": [att.get_name(), tgt.get_name()],
		# What the deny-mode slice (NML_CORE_SLICE=deny) would refuse here, as the shadow record says it: [] = taken.
		"deny": CoreSlice.refusals_in(CoreSlice.DENY_PATH, att) \
			+ CoreSlice.refusals_in(CoreSlice.DENY_PATH, tgt, true).map(func(x: String) -> String: return "target_" + x) \
			+ CoreSlice.pair_refusals_in(CoreSlice.DENY_PATH, att, tgt)}
	free_units(main, [att, tgt])
	await main.get_tree().process_frame
	return out


## The game's table-fidelity setting before `arm()` stamped it, so `disarm()` leaves the process as it found it.
static var _fidelity_was := false


## The AI seats, the batch tray and the dice tap, exactly as the parity gate and the soak set them.
static func arm(main: Node, dump_dir: String) -> void:
	main.solo_ai_slots = {1: true, 2: true}
	main._ensure_solo_controller()
	# DS-RG: the shipped presets (planner_v0/V0S/V0_pool1) all carry `table_fidelity`, and _apply_aifix —
	# which _ensure_solo_controller runs — stamps AiPlanner.table_fidelity from it, so the header carries
	# `range_by_base_edge` and the six sibling fidelity knobs the LIVE core reads. The sweep arms no preset,
	# so without this line the core measured range centre to centre while the table measures base edge to
	# base edge: every 12 in weapon at the fixed 14 in distance was a false G1. AFTER the controller, because
	# the difficulty application overwrites the static.
	_fidelity_was = AiPlanner.table_fidelity
	AiPlanner.table_fidelity = true
	main.solo_controller.ai_slot = SEAT_SHOOTER
	main.solo_controller.human_slot = SEAT_TARGET
	main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	main.opr_army_manager.current_round = 1
	main._solo_batch = true
	main._solo_auto_saves = true
	main._solo_fast = true
	main._autosave_controller.set_lesson_paused(true)
	DirAccess.make_dir_recursive_absolute(dump_dir)
	OS.set_environment("NML_DICE_DUMP", dump_dir)
	AiDiceRecorder._checked = false
	AiDiceRecorder._stream = null
	AiDiceRecorder._count = 0
	CoreActivation._env = 0   # the table half: kill switch OFF; the core half calls the driver directly


## The lock directory one sweep process holds on its dice directory (`claim`).
const LOCK_DIR := "sweep.lock"


## One sweep process per dice directory. Two processes with the same `--out` (the gate script started twice on 18.11.) share
## `dice.jsonl`: each truncates, appends to and deletes the other's file, so a volley reads another row's dice, a torn line or
## none at all, and the sweep reports misaligned "rolls" differences the rules never made. `mkdir` is atomic, so the first
## process wins; a lock whose holder is gone (a killed run) is taken over. Returns "" when this process holds it, else why not.
static func claim(dump_dir: String) -> String:
	DirAccess.make_dir_recursive_absolute(dump_dir)
	var lock := dump_dir.path_join(LOCK_DIR)
	for _attempt in 2:
		if DirAccess.make_dir_absolute(lock) == OK:
			var f := FileAccess.open(lock.path_join("pid"), FileAccess.WRITE)
			f.store_string(str(OS.get_process_id()))
			f.close()
			return ""
		var holder := int(FileAccess.get_file_as_string(lock.path_join("pid")))
		if holder == OS.get_process_id():
			return ""
		if holder <= 0 or _alive(holder):   # no pid yet = another process is between mkdir and write
			return "%s is held by sweep process %d (remove %s if no sweep runs)" % [dump_dir, holder, lock]
		release(dump_dir, holder)
	return "%s: the lock %s could not be taken" % [dump_dir, lock]


## Whether process `pid` runs. `OS.is_process_running` knows only this process's own children (a waitpid), so another sweep
## would always read as gone; Linux answers for any process through /proc.
static func _alive(pid: int) -> bool:
	if DirAccess.dir_exists_absolute("/proc/self"):
		return DirAccess.dir_exists_absolute("/proc/%d" % pid)
	return OS.is_process_running(pid)


## Drops the lock `claim` took, if `holder` (default: this process) holds it.
static func release(dump_dir: String, holder := -1) -> void:
	var pid_path := dump_dir.path_join(LOCK_DIR).path_join("pid")
	if int(FileAccess.get_file_as_string(pid_path)) != (OS.get_process_id() if holder < 0 else holder):
		return
	DirAccess.remove_absolute(pid_path)
	DirAccess.remove_absolute(dump_dir.path_join(LOCK_DIR))


static func disarm(main: Node) -> void:
	AiDiceRecorder.close()
	OS.set_environment("NML_DICE_DUMP", "")
	AiPlanner.table_fidelity = _fidelity_was
	CoreActivation._charge_landing = false
	CoreActivation.reset_all(main)
	CoreActivation._env = -1
	CoreActivation._charge_env = -1


## One pairing (`a` shoots at `b` and `b` at `a`, unit i of one against unit i of the other, round robin over the longer list), each
## `seeds` times. Rows: {"id", "pair", "dir", "seed", "att", "tgt", "table", "core"}; the ids are unique ints (the parity files' seed).
static func sweep_pair(main: Node, a: Dictionary, b: Dictionary, seeds: int, dump_dir: String, first_id := 0, opts := {}) -> Array:
	var rows: Array = []
	var id := first_id
	var n: int = maxi((a["units"] as Array).size(), (b["units"] as Array).size())
	for dir in 2:
		var shooters: Array = a["units"] if dir == 0 else b["units"]
		var targets: Array = b["units"] if dir == 0 else a["units"]
		for i in n:
			for s in seeds:
				var sh: Dictionary = shooters[i % shooters.size()]
				var tg: Dictionary = targets[i % targets.size()]
				var table := await volley(main, sh, tg, s, false, dump_dir, opts)
				var core := await volley(main, sh, tg, s, true, dump_dir, opts)
				rows.append({"id": id, "pair": "%s | %s" % [a["name"], b["name"]], "dir": dir, "seed": s,
					"att": (table["names"] as Array)[0], "tgt": (table["names"] as Array)[1], "table": table, "core": core})
				id += 1
	return rows


## The two parity files of `rows` (the format of test/parity: {"seed","epoch","def_alive","rolls"}), owner names normalised on both
## halves ("AI (x)" -> "x") so the comparison reads kind, count, target and faces.
static func write_parity(rows: Array, table_path: String, core_path: String) -> void:
	for half in ["table", "core"]:
		var f := FileAccess.open(table_path if half == "table" else core_path, FileAccess.WRITE)
		for r in rows:
			var v: Dictionary = r[half]
			var rolls: Array = (v["rolls"] as Array).map(func(x: Dictionary) -> Dictionary:
				var o := str(x["owner"])
				return x.merged({"owner": o.substr(4, o.length() - 5) if o.begins_with("AI (") and o.ends_with(")") else o}, true))
			var def_alive: int = int((v["alive"] as Array)[1]) if v.has("alive") else int((v["state"]["tgt"] as Dictionary)["alive"])
			f.store_line(JSON.stringify({"seed": r["id"], "epoch": AiActRecorder.rules_epoch,
				"def_alive": def_alive, "rolls": rolls}, "", true, true))
		f.close()


## The per-volley (or per-charge, Plan E step 4b) verdict: roll mismatches (ids from parity_compare.py) and the first state / charge diff.
static func verdicts(rows: Array, mismatching_ids: Array) -> Array:
	var out: Array = []
	for r in rows:
		var melee: bool = r.has("charge_first_diff")
		var first := "rolls" if mismatching_ids.has(r["id"]) else (str(r["charge_first_diff"]) if melee else first_state_diff(r["table"]["state"], r["core"]["state"]))
		var deny: Array = r.get("deny", r["table"].get("deny", []))
		var row := {"id": r["id"], "pair": r["pair"], "att": r["att"], "tgt": r["tgt"], "seed": r["seed"], "first_diff": first,
			"fired": not (r["table"]["rolls"] as Array).is_empty() or not (r["core"]["rolls"] as Array).is_empty(),
			"labels": r["table"]["labels"], "deny": deny}
		if melee:
			row["taken"] = deny.is_empty()
			row["equal"] = first == ""
		out.append(row)
	return out


## The deny-mode share (C-19's gate): the fired volleys the deny-mode slice would take (`deny` empty), how many of those are equal,
## and every taken volley that is not.
static func deny_share(verdict_rows: Array) -> Dictionary:
	var fired := verdict_rows.filter(func(v: Dictionary) -> bool: return bool(v["fired"]))
	var taken := fired.filter(func(v: Dictionary) -> bool: return (v.get("deny", ["?"]) as Array).is_empty())
	var unequal := taken.filter(func(v: Dictionary) -> bool: return str(v["first_diff"]) != "")
	return {"fired": fired.size(), "taken": taken.size(), "equal": taken.size() - unequal.size(), "unequal": unequal}


## The coverage table: per rule name, the volleys that FIRED with it on the shooter and the volleys that had it on the target.
static func coverage(verdict_rows: Array) -> Dictionary:
	var out := {}
	for v in verdict_rows:
		if not bool(v["fired"]):
			continue
		for side in ["att", "tgt"]:
			var seen := {}
			for l in (v["labels"][side] as Array):
				seen[l] = true
			for l in seen:
				var e: Dictionary = out.get(l, {"att": 0, "tgt": 0})
				e[side] = int(e[side]) + 1
				out[l] = e
	return out


## The rule names `required` (the registry's, minus the "cannot occur in a volley" list) a coverage table leaves under `min_volleys`
## on either side. Empty = covered.
static func uncovered(cov: Dictionary, required: Array, min_volleys: int) -> Array:
	return required.filter(func(n: String) -> bool:
		var e: Dictionary = cov.get(n, {"att": 0, "tgt": 0})
		return int(e["att"]) < min_volleys or int(e["tgt"]) < min_volleys)


## The python of the parity gate (`NML_PARITY_PYTHON` / `NML_DOCTRINE_PYO3_PYTHON`), else `python3`: parity_compare.py needs only the
## standard library.
static func python() -> String:
	for k in ["NML_PARITY_PYTHON", "NML_DOCTRINE_PYO3_PYTHON"]:
		if OS.get_environment(k) != "":
			return OS.get_environment(k)
	return "python3"


## Rolls and survivors through tools/parity/parity_compare.py (gate reading), then the state / ledger reading here. Returns
## {"verdicts": [...], "roll_mismatches": n, "rc": int, "problems": [...]}; the files are left in `out_dir`.
static func compare(rows: Array, out_dir: String) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(out_dir)
	var table := ProjectSettings.globalize_path(out_dir.path_join("sweep_table.jsonl"))
	var core := ProjectSettings.globalize_path(out_dir.path_join("sweep_core.jsonl"))
	var exc := ProjectSettings.globalize_path(out_dir.path_join("sweep_exceptions.json"))
	var res := ProjectSettings.globalize_path(out_dir.path_join("sweep_result.json"))
	write_parity(rows, table, core)
	var f := FileAccess.open(exc, FileAccess.WRITE)
	f.store_string("[]")
	f.close()
	var rc := OS.execute(python(), [ProjectSettings.globalize_path("res://tools/parity/parity_compare.py"), "--table", table, "--core", core,
		"--scenario", "roster_sweep", "--exceptions", exc, "--out", res], [])
	var result: Variant = JSON.parse_string(FileAccess.get_file_as_string(res)) if FileAccess.file_exists(res) else null
	if not result is Dictionary:
		return {"verdicts": [], "roll_mismatches": -1, "rc": rc, "problems": ["parity_compare.py wrote no result (exit %d)" % rc]}
	var bad: Array = (result["mismatching_seeds"] as Array).map(func(x: Variant) -> int: return int(x))
	return {"verdicts": verdicts(rows, bad), "roll_mismatches": bad.size(), "rc": rc, "problems": result["problems"]}


## The gate on a compare result: every mismatching volley must carry a rule name of the deny list (`deny`: rule name -> why). Returns
## {"mismatches", "explained", "unexplained": [verdicts]}. The deny list only shrinks (a ceiling test of its own belongs with it).
static func gate(verdict_rows: Array, deny: Dictionary) -> Dictionary:
	var explained := 0
	var unexplained: Array = []
	for v in verdict_rows:
		if str(v["first_diff"]) == "":
			continue
		var names: Array = (v["labels"]["att"] as Array) + (v["labels"]["tgt"] as Array)
		if names.any(func(n: String) -> bool: return deny.has(n)):
			explained += 1
		else:
			unexplained.append(v)
	return {"mismatches": explained + unexplained.size(), "explained": explained, "unexplained": unexplained}


static func _pos(u: GameUnit) -> Array:
	var a: Array = u.get_alive_models().map(func(m: ModelInstance) -> Vector2: return Vector2(m.node.global_position.x, m.node.global_position.z) / INCH)
	a.sort()
	return a


## Whether two position lists agree within 0.01" per model, in whatever order the models are listed: each model of `a` takes the nearest model of
## `b` not taken yet. (`_pos` sorts by x, so two mirror models of a formation, equal in x up to float noise, swapped places between the halves and a
## sorted compare paired the wrong two: a false 2.5" difference for models 0.00004" apart.)
static func positions_near(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	var free: Array = b.duplicate()
	for p in a:
		var best := -1
		var best_d := INF
		for j in free.size():
			var d: float = (p as Vector2).distance_to(free[j])
			if d < best_d:
				best_d = d
				best = j
		if best < 0 or best_d > 0.01:
			return false
		free.remove_at(best)
	return true


static func _spawn_side(main: Node, spec: Variant, seat: int, x_in: float) -> GameUnit:
	return (spec as Callable).call() if spec is Callable else spawn(main, spec as Dictionary, seat, x_in)


## One half of a charge comparison (`core_run` false = table's `_run_ai_melee`, true = board capture before the move + AI charge
## door). `att_spec` and `foe_spec` are either `load_list` entries (spawned at 0" and `gap_in`) or `Callable` factories.
static func _charge_half(main: Node, att_spec: Variant, foe_spec: Variant, seed_n: int, core_run: bool, opts := {}) -> Dictionary:
	var att := _spawn_side(main, att_spec, SEAT_SHOOTER, 0.0)
	var foe := _spawn_side(main, foe_spec, SEAT_TARGET, float(opts.get("gap_in", CHARGE_GAP_IN)))
	var labels := {"att": labels_of(att), "tgt": labels_of(foe)}
	var names := [att.get_name(), foe.get_name()]
	var lines: Array = []
	var tap := func(e: Dictionary) -> void:
		lines.append("%s|%s" % [BattleLog.Category.keys()[int(e["category"])], str(e["text"])])
	main.battle_log.entry_added.connect(tap)
	main.seed_tray_rng(seed_n)
	var charges := CoreActivation.ai_charges
	var sc: SoloController = main.solo_controller
	var h := 0
	if core_run:
		CoreActivation.reset_all(main)
		h = CoreActivation.capture(main)
	main._solo_core_ai_h = h
	var from_in: float = sc.charge_from_in(att, foe, MoveIntent.distance_inches(sc.unit_centre(att), sc.unit_centre(foe)))
	sc._charge_move(att, foe, float(opts.get("band_in", 12.0)))
	att.unit_properties["moved_round"] = 1
	var report := {"unit": att, "target": foe, "action": AiDecision.Action.CHARGE, "charge_from_in": from_in, "moved": true}
	var refusals: Array = CoreActivation.charge_refusals(main, att, report)
	var deny: Array = melee_deny_refusals(att, foe, refusals)
	# The body's hand-over (`_solo_activate_one_ai_body`): the door when it takes the charge (or forced by `bypass_slice`), else table.
	if core_run and bool(opts.get("bypass_slice", false)):
		if h != 0:
			await CoreActivation.run_ai_charge(main, att, report)
	elif not (CoreActivation.takes_ai_charge(main, att, report) and await CoreActivation.run_ai_charge(main, att, report)):
		await main._run_ai_melee(report)
	if core_run and opts.has("core_fault"):
		(opts["core_fault"] as Callable).call(att, foe)
	main._solo_core_ai_h = 0
	if h != 0:
		sc._core_node_ready().release(h)
	main.battle_log.entry_added.disconnect(tap)
	var rolls: Array = []
	var dump_dir := str(opts.get("dump_dir", ""))
	if dump_dir != "":
		AiDiceRecorder.close()
		rolls = ParityTable._read_dice(dump_dir)
		if core_run and opts.has("core_swap_face") and int(opts["core_swap_face"]) < rolls.size():
			var faces: Array = rolls[int(opts["core_swap_face"])]["faces"]
			if not faces.is_empty():
				faces[0] = int(faces[0]) % 6 + 1
	var out := {"att": _pos(att), "foe": _pos(foe), "wounds": [main._solo_unit_wounds_now(att), main._solo_unit_wounds_now(foe)],
		"alive": [att.get_alive_count(), foe.get_alive_count()], "shaken": [att.is_shaken, foe.is_shaken],
		"fatigued": [att.is_fatigued, foe.is_fatigued], "rng": main._tray_rng.state, "lines": lines, "rolls": rolls,
		"core": CoreActivation.ai_charges - charges, "refusals": refusals, "deny": deny, "labels": labels, "names": names}
	free_units(main, [att, foe])
	await main.get_tree().process_frame
	return out


## Compares a `table` and a `core` half from `_charge_half`: positions (0.01"), wounds, alive, Shaken, Fatigue, RNG, lines.
static func compare_charge(table: Dictionary, core: Dictionary) -> Dictionary:
	var diffs: Array = []
	var first := ""
	for k in ["att", "foe"]:
		if not positions_near(table[k], core[k]):
			first = k if first == "" else first
			diffs.append("%s positions: table %s, core %s" % [k, table[k], core[k]])
	for k in ["wounds", "alive", "shaken", "fatigued", "rng", "lines"]:
		if table[k] != core[k]:
			first = k if first == "" else first
			diffs.append("%s: table %s, core %s" % [k, table[k], core[k]])
	return {"first_diff": first, "diffs": diffs}


## Plan E (step 4a): one AI charge compared door-vs-table (`table` = `_run_ai_melee`, `core` = capture before the move + door).
static func charge(main: Node, att: Variant, foe: Variant, seed_n: int, opts := {}) -> Dictionary:
	var table := await _charge_half(main, att, foe, seed_n, false, opts)
	var core := await _charge_half(main, att, foe, seed_n, true, opts)
	var cmp := compare_charge(table, core)
	return {"table": table, "core": core, "taken": int(core["core"]) == 1 and int(table["core"]) == 0,
		"refusals": table["refusals"], "deny": table["deny"], "labels": table["labels"], "names": table["names"],
		"equal": (cmp["diffs"] as Array).is_empty(), "first_diff": cmp["first_diff"], "diffs": cmp["diffs"]}


## Plan E (step 4b): whether a `load_list` entry carries at least one melee weapon (`range_value <= 0`, `attacks > 0`).
static func has_melee(entry: Dictionary) -> bool:
	var ou: OPRApiClient.OPRUnit = entry["unit"]
	return ou.weapons.any(func(w: OPRApiClient.OPRWeapon) -> bool: return w.range_value <= 0 and w.attacks > 0 and w.count > 0)


## Plan E (step 4b): what `MELEE_DENY_PATH` plus `charge_refusals`'s structural gates would refuse for this charge.
static func melee_deny_refusals(att: GameUnit, foe: GameUnit, refusals: Array) -> Array:
	var out: Array = CoreSlice.melee_refusals(att, false, true) + CoreSlice.melee_refusals(foe, true, true).map(func(r: String) -> String: return "target_" + r)
	return out + refusals.filter(func(r: String) -> bool: return CHARGE_STRUCTURAL.has(r) and not out.has(r))


## Plan E (step 4b): melee sweep over one ring pairing: every melee unit of one list charges every enemy unit of the other, `seeds` times.
static func sweep_melee_pair(main: Node, a: Dictionary, b: Dictionary, seeds: int, dump_dir: String, first_id := 0, opts := {}) -> Array:
	var rows: Array = []
	var id := first_id
	var call_opts: Dictionary = opts.merged({"bypass_slice": true, "dump_dir": dump_dir})
	for dir in 2:
		var chargers: Array = ((a["units"] if dir == 0 else b["units"]) as Array).filter(has_melee)
		var foes: Array = b["units"] if dir == 0 else a["units"]
		for att in chargers:
			for foe in foes:
				for s in seeds:
					var r: Dictionary = await charge(main, att, foe, s, call_opts)
					rows.append({"id": id, "pair": "%s | %s" % [a["name"], b["name"]], "dir": dir, "seed": s,
						"att": (r["names"] as Array)[0], "tgt": (r["names"] as Array)[1], "table": r["table"], "core": r["core"],
						"deny": r["deny"], "charge_first_diff": r["first_diff"], "diffs": r["diffs"]})
					id += 1
	return rows
