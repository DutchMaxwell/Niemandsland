extends SceneTree
## NML-1073 M2-5 GATE A — the ACT corpus replayed through the RUST search.
##
## tools/act_recheck.gd asks the GDScript AiPlanner.plan_with_rollout; this tool
## asks NmlCore.plan_with_rollout (the M2-5 seam) with exactly the inputs the
## live SoloController hands it — the header (profiles + terrain + knobs) once,
## then per activation the recorded plain state, the class statics and the
## RECORDED playout signature. The diff is act_recheck's own: its four
## comparators are static and are called from here, so "identical" means the
## same thing on both tools.
##
## Nothing in here rebuilds a GDScript state: the corpus IS the plain form the
## seam sends, so this gate measures the search, not the marshalling (the
## marshalling has its own gate in tools/node_core_check.gd).
##
## Usage: godot --headless -s res://tools/act_core_check.gd -- \
##          file=<acts.jsonl> [n=100] [offset=0] [--corrupt]
##   --corrupt   RED proof: flip one recorded pick field before the diff, so a
##               green run can be shown to be earned rather than vacuous.

const ActRecheck := preload("res://tools/act_recheck.gd")

var _core: Object = null
var _corrupt := false
var _fields := {}   # mismatch field (array indices collapsed) -> count


func _init() -> void:
	var file_path := ""
	var n := 100
	var offset := 0
	for a in OS.get_cmdline_user_args():
		if a == "--corrupt":
			_corrupt = true
			continue
		var kv := a.split("=", true, 1)
		if kv.size() != 2:
			continue
		match kv[0]:
			"file": file_path = kv[1]
			"n": n = int(kv[1])
			"offset": offset = int(kv[1])
	print("[ACT-CORE] ClassDB.class_exists(\"NmlCore\") = %s" % str(ClassDB.class_exists("NmlCore")))
	print("[ACT-CORE] BattleSim.core_enabled() = %s (NML_CORE=%s)"
		% [str(BattleSim.core_enabled()), OS.get_environment("NML_CORE")])
	if not ClassDB.class_exists("NmlCore"):
		print("[ACT-CORE] the extension is not loaded — nothing to check")
		quit(1)
		return
	var f := FileAccess.open(file_path, FileAccess.READ)
	if f == null:
		printerr("[ACT-CORE] cannot open ", file_path)
		quit(1)
		return
	var header: Dictionary = JSON.parse_string(f.get_line())
	var knobs: Dictionary = header.get("knobs", {})
	_core = ClassDB.instantiate("NmlCore")
	_core.set_repo_root(ProjectSettings.globalize_path("res://"))
	_core.set_seams(bool(knobs.get("seam_spacing", false)), bool(knobs.get("seam_cast", false)))
	if not bool(_core.set_game_header(header)):
		printerr("[ACT-CORE] set_game_header failed: ", str(_core.last_error()))
		quit(1)
		return
	print("[ACT-CORE] corpus=%s knobs=%s" % [file_path, str(knobs)])

	var skipped := 0
	while skipped < offset and not f.eof_reached():
		if f.get_line().strip_edges() != "":
			skipped += 1

	var checked := 0
	var ok := 0
	var mismatch := 0
	var declined := 0
	var us_total := 0
	var us_max := 0
	while checked < n and not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line == "":
			continue
		var act: Dictionary = JSON.parse_string(line)
		checked += 1
		# The RECORDED signature — an input to the port, never recomputed (see
		# core/nml-core/src/arbitration.rs). Absent on an act the arbitration
		# never reached, where the core never reads it either.
		var arb: Variant = (act.get("trace", {}) as Dictionary).get("arbitration")
		var sig := int((arb as Dictionary)["sig"]) if arb != null else 0
		var t0 := Time.get_ticks_usec()
		var out: Dictionary = _core.plan_with_rollout(act["state"], int(act["player"]),
			act.get("statics", {}), sig)
		var dt := Time.get_ticks_usec() - t0
		us_total += dt
		us_max = maxi(us_max, dt)
		var tag := "ACT %d round=%d player=%d" % [offset + checked, int(act["round"]), int(act["player"])]
		if not bool(out.get("used", false)):
			declined += 1
			mismatch += 1
			_bump("core.unsupported")
			print("%s DECLINED (%s) (%dus)" % [tag, str(out.get("unsupported", "?")), dt])
			continue
		var mism := _diff(act, out)
		if mism.is_empty():
			ok += 1
			print("%s OK (%dus)" % [tag, dt])
		else:
			mismatch += 1
			print("%s MISMATCH (%dus)" % [tag, dt])
			for m in mism.slice(0, 3):
				print("  MISMATCH %s: recorded=%s got=%s"
					% [str(m["field"]), str(m["recorded"]), str(m["got"])])
	print("[ACT-CORE] per-field mismatch counts: %s" % str(_fields))
	print("[ACT-CORE] search us: n=%d mean=%d max=%d" % [checked,
		us_total / maxi(checked, 1), us_max])
	print("CORE-CHECK acts=%d ok=%d mismatch=%d declined=%d" % [checked, ok, mismatch, declined])
	quit(0 if mismatch == 0 else 1)


## The recorded pick/trace against the core's answer, through act_recheck's own
## comparators. The only shaping done here is the one the LIVE seam does too:
## the core writes a destination as [x, y, z] and the game wants a Vector3.
func _diff(act: Dictionary, out: Dictionary) -> Array:
	var got_pick := {"used": true, "unit_key": str(out["unit_key"]),
		"action": _action_of(out.get("action", {})),
		"expectation": out.get("expectation", {}), "waits": int(out.get("waits", 0)),
		"rolled_units": out.get("rolled_units", [])}
	var ru: Dictionary = out.get("runner_up", {})
	if not ru.is_empty():
		got_pick["runner_up"] = {"unit_key": str(ru["unit_key"]),
			"action": _action_of(ru.get("action", {})), "score": float(ru["score"])}
	var got_trace := {"scored": out.get("scored", []), "pool_idx": out.get("pool_idx", []),
		"rs": out.get("rs", []), "best_idx": int(out.get("best_idx", -1)),
		"runner_idx": int(out.get("runner_idx", -1)),
		"arbitration": out.get("arbitration")}
	var rec_pick: Dictionary = (act.get("pick", {}) as Dictionary).duplicate(true)
	if _corrupt and rec_pick.has("waits"):
		rec_pick["waits"] = int(rec_pick["waits"]) + 1   # RED proof
	var mism: Array = []
	ActRecheck._compare_pick(rec_pick, got_pick, mism)
	# act_recheck stops at the pick's own fields; the RUNNER-UP is part of the
	# answer too (it reaches the battle log through _intent and the teacher rows
	# through core_selfplay), so it is diffed here as well.
	_compare_runner(rec_pick.get("runner_up", {}), got_pick.get("runner_up", {}), mism)
	ActRecheck._compare_trace(act.get("trace", {}), got_trace, mism)
	for m in mism:
		_bump(str(m["field"]))
	return mism


func _action_of(a: Dictionary) -> Dictionary:
	var out := {}
	for k in a:
		out[k] = a[k]
	if a.has("dest"):
		out["dest"] = BattleSim._vec3_of(a["dest"])
	return out


## "trace.scored[17].score" and "trace.scored[3].score" are ONE finding, not two.
func _bump(field: String) -> void:
	var norm := ""
	var skip := false
	for c in field:
		if c == "[":
			skip = true
			norm += "["
		elif c == "]":
			skip = false
			norm += "]"
		elif not skip:
			norm += c
	_fields[norm] = int(_fields.get(norm, 0)) + 1


## The pick's runner_up — {} on both sides when the pool held one candidate.
static func _compare_runner(rec: Dictionary, got: Dictionary, mism: Array) -> void:
	if rec.is_empty() and got.is_empty():
		return
	if rec.is_empty() != got.is_empty():
		mism.append({"field": "pick.runner_up.present", "recorded": not rec.is_empty(),
			"got": not got.is_empty()})
		return
	ActRecheck._eq(mism, "pick.runner_up.unit_key", rec.get("unit_key", ""),
		got.get("unit_key", ""), "s")
	ActRecheck._eq(mism, "pick.runner_up.score", rec.get("score", 0.0),
		got.get("score", 0.0), "f")
	ActRecheck._compare_action(rec.get("action", {}), got.get("action", {}), mism,
		"pick.runner_up.action")
