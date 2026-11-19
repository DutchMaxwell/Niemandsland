extends SceneTree
## One core C-7: the roster sweep as a command (harness: test/one_core/roster_sweep.gd). Boots the real main.tscn with the one-core
## kill switch OFF (the table half is the OLD table), loads every list of the given directories (`<faction>_<points>.json` or any
## list JSON), pairs them in a ring per game system and runs every unit of every list as a shooter and as a target, `--seeds` times,
## on the table and on the core. Writes <out>/{sweep_table,sweep_core}.jsonl (the parity files), verdicts.jsonl, coverage.json, uncovered.txt.
##
##   godot --headless --path . -s res://test/one_core/roster_sweep_cli.gd -- --lists <dir> [--lists <dir2>] [--points 1000,2000]
##       [--door shoot|melee] [--seeds 20] [--out <dir>] [--deny <deny.json>] [--exempt <names.json>] [--min-volleys 20] [--max-pairs N]
##
## `--deny` is a JSON object {rule name: why}: a mismatching volley carrying one of them is explained, any other is red. `--min-volleys`
## turns the coverage into a gate: every registry rule name (minus the `--exempt` array, the "cannot occur in a volley" names) must
## appear on a firing unit or weapon AND on a target in that many volleys. Exit 0 = green, 1 = a mismatch outside the deny list or an
## uncovered rule name, 2 = nothing to sweep or another sweep holds `--out`. The same NOTE as golden_witness.gd: the harness loads only after main.tscn is up.

const HARNESS_PATH := "res://test/one_core/roster_sweep.gd"
const MAX_BOOT_FRAMES := 1800


func _initialize() -> void:
	_run.call_deferred(OS.get_cmdline_user_args())


func _arg(args: Array, name: String, fallback := "") -> String:
	for i in args.size():
		if str(args[i]) == name and i + 1 < args.size():
			return str(args[i + 1])
	return fallback


func _args(args: Array, name: String) -> Array:
	var out: Array = []
	for i in args.size():
		if str(args[i]) == name and i + 1 < args.size():
			out.append(str(args[i + 1]))
	return out


func _json(path: String, fallback: Variant) -> Variant:
	if path == "" or not FileAccess.file_exists(path):
		return fallback
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return v if v != null else fallback


func _run(args: Array) -> void:
	var door := _arg(args, "--door", "shoot")
	if door != "shoot" and door != "melee":
		printerr("ROSTER-SWEEP-FAIL: unknown --door %s (expected shoot or melee)" % door)
		quit(2)
		return
	ProjectSettings.set_setting("niemandsland/harness_mode", true)
	OS.set_environment("NML_ONE_CORE_ACTIVATION", "0")
	OS.set_environment("NML_ONE_CORE_CHARGE", "0")
	change_scene_to_file("res://scenes/main.tscn")
	var main := await _boot()
	if main == null:
		printerr("ROSTER-SWEEP-FAIL: main.tscn never finished booting")
		quit(1)
		return
	var h: Script = load(HARNESS_PATH)
	var points: PackedStringArray = _arg(args, "--points").split(",", false)
	var lists: Array = []
	for dir in _args(args, "--lists"):
		for f in DirAccess.get_files_at(dir):
			if not f.ends_with(".json") or f.begins_with("_") or (not points.is_empty() and not points.has(f.get_basename().get_slice("_", f.get_basename().count("_")))):
				continue
			var l: Dictionary = h.load_list(dir.path_join(f))
			if not l.is_empty():
				lists.append(l)
	var pairs: Array = []
	for system in ["gf", "aof"]:
		pairs.append_array(h.ring(lists.filter(func(l: Dictionary) -> bool: return str(l["system"]) == system)))
	if int(_arg(args, "--max-pairs", "0")) > 0:
		pairs = pairs.slice(0, int(_arg(args, "--max-pairs")))
	if pairs.is_empty():
		printerr("ROSTER-SWEEP-FAIL: no pairing (need two lists of one system; %d loaded)" % lists.size())
		quit(2)
		return
	var out := _arg(args, "--out", "user://roster_sweep_cli")
	var dice := ProjectSettings.globalize_path(out.path_join("dice"))
	var seeds := int(_arg(args, "--seeds", "20"))
	var held: String = h.claim(dice)   # one process per --out: two share dice.jsonl and read each other's dice
	if held != "":
		printerr("ROSTER-SWEEP-FAIL: %s" % held)
		quit(2)
		return
	h.arm(main, dice)
	var rows: Array = []
	for p in pairs:
		if door == "melee":
			rows.append_array(await h.sweep_melee_pair(main, p[0], p[1], seeds, dice, rows.size()))
			printerr("ROSTER-SWEEP: %d charges (%s)" % [rows.size(), p[0]["name"]])
		else:
			rows.append_array(await h.sweep_pair(main, p[0], p[1], seeds, dice, rows.size()))
			printerr("ROSTER-SWEEP: %d volleys (%s)" % [rows.size(), p[0]["name"]])
	h.disarm(main)
	h.release(dice)
	var cmp: Dictionary = h.compare(rows, out)
	var gate: Dictionary = h.gate(cmp["verdicts"], _json(_arg(args, "--deny"), {}))
	var cov: Dictionary = h.coverage(cmp["verdicts"])
	var required: Array = []
	for system in ["gf", "aof"]:
		if lists.any(func(l: Dictionary) -> bool: return str(l["system"]) == system):
			required.append_array(h.rule_names(system))
	var exempt: Array = _json(_arg(args, "--exempt"), [])
	required = required.filter(func(n: String) -> bool: return not exempt.has(n))
	var min_volleys := int(_arg(args, "--min-volleys", "0"))
	var missing: Array = h.uncovered(cov, required, min_volleys) if min_volleys > 0 else []
	_write(out.path_join("verdicts.jsonl"), (cmp["verdicts"] as Array).map(func(v: Dictionary) -> String: return JSON.stringify(v, "", true, true)))
	_write(out.path_join("coverage.json"), [JSON.stringify(cov, " ", true, true)])
	var fired := (cmp["verdicts"] as Array).filter(func(v: Dictionary) -> bool: return bool(v["fired"])).size()
	var share: Dictionary = h.deny_share(cmp["verdicts"])
	printerr("ROSTER-SWEEP-DENY-MODE fired=%d taken=%d equal=%d" % [share["fired"], share["taken"], share["equal"]])
	for v in share["unequal"]:
		printerr("ROSTER-SWEEP-DENY-UNEQUAL: %s | %s -> %s seed %d: %s" % [v["pair"], v["att"], v["tgt"], v["seed"], v["first_diff"]])
	printerr("ROSTER-SWEEP-SUMMARY lists=%d pairs=%d volleys=%d fired=%d roll_mismatches=%d mismatches=%d explained=%d unexplained=%d uncovered=%d (min %d)" % [
		lists.size(), pairs.size(), rows.size(), fired, cmp["roll_mismatches"], gate["mismatches"], gate["explained"], (gate["unexplained"] as Array).size(), missing.size(), min_volleys])
	for p in cmp["problems"]:
		printerr("ROSTER-SWEEP-PROBLEM: %s" % p)
	for v in (gate["unexplained"] as Array).slice(0, 25):
		printerr("ROSTER-SWEEP-DIFF: %s | %s -> %s seed %d: %s | att %s | tgt %s" % [v["pair"], v["att"], v["tgt"], v["seed"], v["first_diff"], v["labels"]["att"], v["labels"]["tgt"]])
	_write(out.path_join("uncovered.txt"), missing.map(func(n: String) -> String: return "%s %s" % [n, cov.get(n, {"att": 0, "tgt": 0})]))
	for n in missing.slice(0, 40):
		printerr("ROSTER-SWEEP-UNCOVERED: %s %s" % [n, cov.get(n, {"att": 0, "tgt": 0})])
	if missing.size() > 40:
		printerr("ROSTER-SWEEP-UNCOVERED: ... %d more in uncovered.txt" % (missing.size() - 40))
	quit(1 if not (gate["unexplained"] as Array).is_empty() or not missing.is_empty() else 0)


func _write(path: String, lines: Array) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	for l in lines:
		f.store_line(str(l))
	f.close()


func _boot() -> Node:
	for _i in MAX_BOOT_FRAMES:
		await process_frame
		if current_scene != null and current_scene.get("opr_army_manager") != null:
			return current_scene
	return null
