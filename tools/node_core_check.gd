extends SceneTree
## NML-1073 M1-5 — the GDExtension gate: the SAME recorded nodes, replayed
## through the Rust core from GDScript, compared against the RECORDING.
##
## Per node: capture_plain(plain) -> resolve(action) -> score(player, rich),
## then plain_of() against the recorded state_after (positions/wounds/radii/mods
## within 1e-9, ints and bools exact) and the score against the recorded score.
## The numbers must match what the pure-Rust binary reports on the same corpus
## (`cargo run --release --bin parity -- <nodes.jsonl>`); if they do not, the
## Dictionary marshalling lost something the JSONL loader kept.
##
## The two Callable answers a plain state cannot carry are fed in exactly as the
## recorder wrote them — `cover_dest` (terrain at the destination) and, on a
## cast corpus, `cast_los` (the post-move sight row). The Rust parity binary
## reads the same two off the corpus; neither side re-derives them.
##
## MODES
##   mode=plain    (default) the recorded plain state goes straight into the
##                 core, with the header's static profile spliced back into each
##                 unit — the shape state_to_plain(state, true) writes.
##   mode=rebuild  the plain state is first rebuilt into a GDScript BattleSim
##                 state (tools/node_recheck.gd's stand-in GameUnits) and pushed
##                 back out through BattleSim.state_to_plain() — the call the
##                 LIVE seam would make. The recorded `los_pairs` is stamped
##                 back on, because a rebuilt state has no los_blocked Callable
##                 to regenerate it with.
##   mode=both     runs both and reports the difference.
##
## Usage: godot --headless -s res://tools/node_core_check.gd -- \
##          dir=<corpus dir> [n=2000] [mode=plain] [passes=3] [bench=1] [out=<file>]
## NML_SIM_SPACING / NML_SIM_CAST need not be set: the seams are taken from the
## corpus header and pushed into the core with set_seams().

const EPS := 1e-9
const NodeRecheck := preload("res://tools/node_recheck.gd")

var _core: Object = null
var _lines: Array[String] = []


func _init() -> void:
	var dir := ""
	var n := 2000
	var passes := 3
	var mode := "plain"
	var bench := true
	var redgreen := false
	var out_path := ""
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() != 2:
			continue
		match kv[0]:
			"dir": dir = kv[1]
			"n": n = int(kv[1])
			"passes": passes = int(kv[1])
			"mode": mode = kv[1]
			"bench": bench = kv[1] == "1"
			"redgreen": redgreen = kv[1] == "1"
			"out": out_path = kv[1]
	_say("[CORE-CHECK] ClassDB.class_exists(\"NmlCore\") = %s" % str(ClassDB.class_exists("NmlCore")))
	_say("[CORE-CHECK] BattleSim.core_enabled() = %s (NML_CORE=%s)"
		% [str(BattleSim.core_enabled()), OS.get_environment("NML_CORE")])
	if not ClassDB.class_exists("NmlCore"):
		_say("[CORE-CHECK] the extension is not loaded — nothing to check")
		quit(1)
		return
	_core = ClassDB.instantiate("NmlCore")
	_core.set_repo_root(ProjectSettings.globalize_path("res://"))

	var f := FileAccess.open(dir.path_join("nodes.jsonl"), FileAccess.READ)
	if f == null:
		_say("[CORE-CHECK] cannot open " + dir.path_join("nodes.jsonl"))
		quit(1)
		return
	var header: Dictionary = JSON.parse_string(f.get_line())
	var profiles: Dictionary = header["profiles"]
	var seams: Dictionary = header.get("seams", {})
	# redgreen=1 flips the spacing seam the corpus was played with. The clamped
	# movers MUST then redden — a green run with the wrong seam would mean the
	# comparison is not looking at anything.
	var spacing := bool(seams.get("spacing", false))
	if redgreen:
		spacing = not spacing
	_core.set_seams(spacing, bool(seams.get("cast", false)))
	_say("[CORE-CHECK] corpus=%s seams=%s core.seams=%s redgreen=%s"
		% [dir, str(seams), str(_core.seams()), str(redgreen)])

	var recs: Array = []
	while recs.size() < n and not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line == "":
			continue
		var rec: Variant = JSON.parse_string(line)
		if rec is Dictionary:
			recs.append(rec)
	f.close()
	_say("[CORE-CHECK] nodes read %d" % recs.size())

	# The header keeps ONE profile table for the whole game (the recorder writes
	# it once, ai_planner.gd:483-485); state_to_plain writes it per unit. Splice
	# it back so the core sees the shape it is contracted to.
	for rec in recs:
		for side in ["state_before", "state_after"]:
			var units: Dictionary = (rec[side] as Dictionary)["units"]
			for uid in units:
				(units[uid] as Dictionary)["profile"] = profiles[uid]
		rec["_action"] = _action_of(rec, seams)

	if mode == "plain" or mode == "both":
		_parity(recs, "plain")
	if mode == "rebuild" or mode == "both":
		_parity(_rebuilt(recs, profiles), "rebuild")
	if bench:
		_bench(recs, passes)
	var dropped: PackedStringArray = _core.dropped_keys()
	_say("[CORE-CHECK] plain-form keys the port does not model: %s" % str(dropped))
	if out_path != "":
		var of := FileAccess.open(out_path, FileAccess.WRITE)
		if of != null:
			for l in _lines:
				of.store_line(l)
			of.close()
	quit(0)


## Action + the two recorded Callable answers `resolve` needs.
func _action_of(rec: Dictionary, seams: Dictionary) -> Dictionary:
	var act: Dictionary = (rec["action"] as Dictionary).duplicate()
	if rec.has("cover_dest") and rec["cover_dest"] != null:
		act["cover_dest"] = bool(rec["cover_dest"])
	if bool(seams.get("cast", false)):
		var after: Dictionary = rec["state_after"]
		var rows: Array = after.get("los_pairs", [])
		var keys: Array = (after["units"] as Dictionary).keys()
		var i := keys.find(str(act.get("unit", "")))
		if i >= 0 and i < rows.size():
			act["cast_los"] = str(rows[i])
	return act


func _parity(recs: Array, label: String) -> void:
	var kind_names := ["HOLD", "ADVANCE", "RUSH", "CHARGE"]
	var per_kind := {}
	var fields := {}
	var soft := {}
	var unresolved := {}
	var checked := 0
	var exact := 0
	var score_ok := 0
	var max_score_diff := 0.0
	var rec_score_ok := 0
	var max_rec_diff := 0.0
	var first_bad: Array = []
	for rec in recs:
		var plain: Dictionary = rec["state_before"]
		var h: int = _core.capture_plain(plain)
		if h == 0:
			_bump(unresolved, "capture: " + str(_core.last_error()))
			continue
		var act: Dictionary = rec["_action"]
		var h2: int = _core.resolve(h, act)
		if h2 == 0:
			_bump(unresolved, "resolve: " + str(_core.last_error()))
			_core.release(h)
			continue
		checked += 1
		var kind := int(act.get("kind", -1))
		var slot: Array = per_kind.get(kind, [0, 0])
		slot[0] += 1
		var player := int(rec["player"])
		var rich := bool(rec.get("rich", false))
		var s: float = _core.score(h2, player, rich)
		var d := absf(s - float(rec["score"]))
		max_score_diff = maxf(max_score_diff, d)
		if d <= EPS:
			score_ok += 1
		# The pure-Rust parity binary prices the RECORDED state_after (its GATE A).
		# Same call here — the marshalling test proper. Scoring the state the port
		# RESOLVED is a different question (see the note under the numbers).
		var h3: int = _core.capture_plain(rec["state_after"])
		var d3 := absf(_core.score(h3, player, rich) - float(rec["score"]))
		max_rec_diff = maxf(max_rec_diff, d3)
		if d3 <= EPS:
			rec_score_ok += 1
		_core.release(h3)
		var got: Dictionary = _core.plain_of(h2)
		var want: Dictionary = (rec["state_after"] as Dictionary).duplicate()
		# los_pairs is a recorded Callable answer, not a resolve OUTPUT: the port
		# carries the capture-time matrix forward unchanged (the same staleness
		# the GDScript clone has), so it is excluded on both sides — exactly the
		# field set the pure-Rust parity binary compares.
		want.erase("los_pairs")
		got.erase("los_pairs")
		var diff: Array = []
		_diff(got, want, "", diff)
		var hard: Array = []
		for x in diff:
			if str(x).begins_with("~"):
				_bump(soft, str(x).substr(1))
			else:
				hard.append(x)
		if hard.is_empty():
			exact += 1
			slot[1] += 1
		else:
			for x in hard:
				_bump(fields, str(x))
			if first_bad.size() < 5:
				first_bad.append({"node": checked, "kind": kind, "fields": hard.slice(0, 6)})
		per_kind[kind] = slot
		_core.release(h)
		_core.release(h2)
	_say("")
	_say("=== PARITY (%s) — resolve + score through NmlCore ===" % label)
	for k in [0, 1, 2, 3]:
		if per_kind.has(k):
			_say("%-8s %d/%d exact" % [kind_names[k], per_kind[k][1], per_kind[k][0]])
	_say("TOTAL    %d/%d exact, %d mismatched" % [exact, checked, checked - exact])
	_say("score on the RECORDED state_after   %d/%d within 1e-9, max abs diff %s"
		% [rec_score_ok, checked, str(max_rec_diff)])
	_say("score on the RESOLVED state         %d/%d within 1e-9, max abs diff %s"
		% [score_ok, checked, str(max_score_diff)])
	_say("  (the second is LOWER by design: resolve carries the capture-time los_pairs")
	_say("   forward, the recorder rewrote the matrix from the POST-move centres —")
	_say("   the stale-parent-LOS caveat of record, unchanged by this step.)")
	if not soft.is_empty():
		_say("key-presence-only differences (value matches the default on the missing side —")
		_say("the pure-Rust parity binary compares typed arrays and never sees these):")
		for k in soft:
			_say("  %-40s %d" % [k, soft[k]])
	if not fields.is_empty():
		_say("mismatching fields (node counts):")
		for k in fields:
			_say("  %-28s %d" % [k, fields[k]])
	for b in first_bad:
		_say("  MISS #%d %s %s" % [b["node"], kind_names[b["kind"]], str(b["fields"])])
	if not unresolved.is_empty():
		_say("not resolved by the port:")
		for k in unresolved:
			_say("  %5d  %s" % [unresolved[k], k])
	_say("live handles after the pass: %d" % int(_core.live_handles()))


## mode=rebuild — the call the LIVE seam would make: plain -> GDScript state
## (stand-in GameUnits, tools/node_recheck.gd) -> BattleSim.state_to_plain() ->
## the core. Also reports whether the profile a stand-in DERIVES matches the one
## the recorder read off the live GameUnit; a drift there is a rebuild artefact,
## not a marshalling bug, and it is named rather than absorbed.
func _rebuilt(recs: Array, profiles: Dictionary) -> Array:
	var drift := {}
	var drifted_units := 0
	var out: Array = []
	var first := true
	var t_plainify := 0
	for rec in recs:
		var st: Dictionary = NodeRecheck._rebuild_state(rec["state_before"], profiles)
		var t0 := Time.get_ticks_usec()
		var plain: Dictionary = BattleSim.state_to_plain(st, true)
		t_plainify += Time.get_ticks_usec() - t0
		# A rebuilt state has no los_blocked Callable, so state_to_plain cannot
		# write the sight matrix — stamp the recorded answers back on.
		if (rec["state_before"] as Dictionary).has("los_pairs"):
			plain["los_pairs"] = (rec["state_before"] as Dictionary)["los_pairs"]
		if first:
			first = false
			for uid in (plain["units"] as Dictionary):
				var got: Dictionary = (plain["units"][uid] as Dictionary)["profile"]
				var want: Dictionary = profiles[uid]
				var d: Array = []
				_diff(got, want, "", d)
				if not d.is_empty():
					drifted_units += 1
					for x in d:
						_bump(drift, str(x))
		out.append({"state_before": plain, "state_after": rec["state_after"],
			"score": rec["score"], "player": rec["player"], "rich": rec.get("rich", false),
			"_action": rec["_action"]})
	_say("")
	_say("[CORE-CHECK] rebuild: BattleSim.state_to_plain(state, true) costs %.1f us/node —"
		% (float(t_plainify) / maxf(1.0, float(recs.size()))))
	_say("[CORE-CHECK] rebuild: the GDScript half of any live seam, paid BEFORE capture_plain")
	_say("[CORE-CHECK] rebuild: stand-in profiles that differ from the recorded ones: %d units" % drifted_units)
	for k in drift:
		_say("  %-28s %d" % [k, drift[k]])
	return out


## GATE 3 — what one node costs THROUGH the extension: capture + resolve + score,
## the same unit the M1-4 benchmark timed on both sides (ai_planner.gd:462-467).
func _bench(recs: Array, passes: int) -> void:
	var m := recs.size()
	if m == 0:
		return
	var sink := 0.0
	var best_mean := INF
	var best: PackedFloat64Array = PackedFloat64Array()
	var pass_means: Array = []
	for p in range(passes):
		var per := PackedFloat64Array()
		per.resize(m)
		var t_pass := Time.get_ticks_usec()
		for i in range(m):
			var rec: Dictionary = recs[i]
			var t0 := Time.get_ticks_usec()
			var h: int = _core.capture_plain(rec["state_before"])
			var h2: int = _core.resolve(h, rec["_action"])
			sink += _core.score(h2, int(rec["player"]), bool(rec.get("rich", false)))
			var dt := Time.get_ticks_usec() - t0
			_core.release(h)
			_core.release(h2)
			per[i] = float(dt)
		var wall := float(Time.get_ticks_usec() - t_pass)
		pass_means.append(wall / float(m))
		var inst := 0.0
		for v in per:
			inst += v
		inst /= float(m)
		if inst < best_mean:
			best_mean = inst
			best = per
	var sorted: Array = Array(best)
	sorted.sort()

	# ---- parts, each best of `passes` (same recipe as tools/node_bench.gd) ----
	var handles: PackedInt64Array = PackedInt64Array()
	for rec in recs:
		handles.append(_core.capture_plain(rec["state_before"]))
	var nexts: PackedInt64Array = PackedInt64Array()
	for i in range(m):
		nexts.append(_core.resolve(handles[i], (recs[i] as Dictionary)["_action"]))
	var t_capture := INF
	var t_resolve := INF
	var t_score := INF
	var t_clone := INF
	var t_plain := INF
	for p in range(passes):
		var t0 := Time.get_ticks_usec()
		for i in range(m):
			_core.release(_core.capture_plain((recs[i] as Dictionary)["state_before"]))
		t_capture = minf(t_capture, float(Time.get_ticks_usec() - t0) / float(m))
		t0 = Time.get_ticks_usec()
		for i in range(m):
			_core.release(_core.resolve(handles[i], (recs[i] as Dictionary)["_action"]))
		t_resolve = minf(t_resolve, float(Time.get_ticks_usec() - t0) / float(m))
		t0 = Time.get_ticks_usec()
		for i in range(m):
			sink += _core.score(nexts[i], int((recs[i] as Dictionary)["player"]),
				bool((recs[i] as Dictionary).get("rich", false)))
		t_score = minf(t_score, float(Time.get_ticks_usec() - t0) / float(m))
		t0 = Time.get_ticks_usec()
		for i in range(m):
			_core.release(_core.clone(handles[i]))
		t_clone = minf(t_clone, float(Time.get_ticks_usec() - t0) / float(m))
		t0 = Time.get_ticks_usec()
		for i in range(m):
			sink += float((_core.plain_of(nexts[i]) as Dictionary).size())
		t_plain = minf(t_plain, float(Time.get_ticks_usec() - t0) / float(m))
	_core.release_all()
	_say("")
	_say("=== GATE 3 — us per node THROUGH the extension (best of %d passes) ===" % passes)
	for i in range(pass_means.size()):
		_say("  pass %d mean %.2f us/node (wall/n)" % [i + 1, pass_means[i]])
	_say("BEST PASS mean   %.2f us/node" % best_mean)
	_say("BEST PASS MEDIAN %.2f us/node" % _median(sorted))
	_say("BEST PASS p90    %.2f us/node" % _pct(sorted, 0.90))
	_say("BEST PASS max    %.2f us/node" % float(sorted[sorted.size() - 1]))
	_say("parts us/node: capture=%.2f resolve=%.2f score=%.2f clone=%.2f plain_of=%.2f (plain_of is a parity artefact, not part of a node)"
		% [t_capture, t_resolve, t_score, t_clone, t_plain])
	if sink == INF:
		_say("unreachable")


# ------------------------------------------------------------------ helpers --

func _say(s: String) -> void:
	print(s)
	_lines.append(s)


static func _bump(d: Dictionary, k: String) -> void:
	d[k] = int(d.get(k, 0)) + 1


## Recursive compare against the recording. Numbers: two ints must be EQUAL, any
## float pair within 1e-9. Bools and strings exact. Missing/extra keys are named.
## The path collapses dictionary keys under `units` and array indices, so the
## report aggregates by FIELD instead of by node.
static func _diff(a: Variant, b: Variant, path: String, out: Array) -> void:
	if a is Dictionary and b is Dictionary:
		var child := path + "/*" if path == "/units" else path
		for k in b:
			if str(k) == "profile":
				continue   # static input spliced in for capture, never a resolve output
			if not (a as Dictionary).has(k):
				out.append(_absent(child + "/" + str(k), (b as Dictionary)[k], "MISSING"))
			else:
				_diff((a as Dictionary)[k], (b as Dictionary)[k], child + "/" + str(k), out)
		for k in a:
			if str(k) == "profile":
				continue
			if not (b as Dictionary).has(k):
				out.append(_absent(child + "/" + str(k), (a as Dictionary)[k], "EXTRA"))
		return
	if a is Array and b is Array:
		if (a as Array).size() != (b as Array).size():
			out.append(path + " SIZE %d!=%d" % [(a as Array).size(), (b as Array).size()])
			return
		for i in (a as Array).size():
			_diff((a as Array)[i], (b as Array)[i], path + "[]", out)
		return
	if a is bool or b is bool:
		if typeof(a) != typeof(b) or bool(a) != bool(b):
			out.append(path + " BOOL")
		return
	if (a is int or a is float) and (b is int or b is float):
		if a is int and b is int:
			if int(a) != int(b):
				out.append(path + " INT")
		elif absf(float(a) - float(b)) > EPS:
			out.append(path + " NUM")
		return
	if a != b:
		out.append(path + " VALUE")


## A key one side does not carry. When the value on the present side IS the
## default the absent side would be read as (0 / 0.0 — every numeric field of the
## plain form defaults that way, io.rs #[serde(default)] included), the two states
## are numerically equal and only the KEY SET differs: marked "~" and counted
## apart, because the pure-Rust parity binary compares typed arrays and cannot
## see it. Anything else is a real mismatch.
static func _absent(path: String, present: Variant, side: String) -> String:
	if (present is int or present is float) and absf(float(present)) <= EPS:
		return "~" + path + " " + side + " (both read 0)"
	return path + " " + side


static func _median(sorted: Array) -> float:
	var n := sorted.size()
	if n == 0:
		return 0.0
	if n % 2 == 1:
		return float(sorted[n / 2])
	return 0.5 * (float(sorted[n / 2 - 1]) + float(sorted[n / 2]))


static func _pct(sorted: Array, p: float) -> float:
	if sorted.is_empty():
		return 0.0
	return float(sorted[int(round((sorted.size() - 1) * p))])
