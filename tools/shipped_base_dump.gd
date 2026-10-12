extends SceneTree
## Shipped-base generator (konrad ORDER 476c3390, step 1): the base knob bundle a
## promotion A/B must run against, read from the game's OWN header path so the
## harness never again runs on a hand copy that can go stale.
##
## The hand copy it replaces (BB.cand.json + leaf_opener_only) predated #1724
## (table_fidelity) and #1728 (breadth 128), so every "shipped-base" table since
## 08.10. afternoon ran without top_k 128 / horizon 3 and without the eight
## table-fidelity keys — a base that is NOT the shipped header.
##
## The knobs block of AiActRecorder._header_line IS the shipped contract (the live
## core's header and every recorded act row read it). It is built here from the
## shipped preset exactly as a real pick builds it: SoloDifficulty planner_v0 with
## the shipped brain wired, SoloController._apply_aifix stamping the per-pick
## statics, and eval_variant ridden through _eval_variant_for (3 composes to 4).
##
## Prints canonical JSON (sorted keys, compact) of that block on stdout; with
## out=<path> it also writes it, newline-terminated.
##
## Usage: godot --headless -s res://tools/shipped_base_dump.gd [-- out=<path>]
## The GDExtension is NOT needed: shipped_brain_ready() only checks core-wanted +
## a node + a non-empty sha, so a bare Node stands in (the header tests do the same).

func _init() -> void:
	var out := ""
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2 and kv[0] == "out":
			out = kv[1]
	var line := JSON.stringify(_sorted(shipped_knobs()), "", false)
	print(line)
	if not out.is_empty():
		var f := FileAccess.open(out, FileAccess.WRITE)
		if f == null:
			printerr("[SHIPPED-BASE] cannot write ", out)
			quit(1)
			return
		f.store_string(line + "\n")
		f.close()
	quit(0)


## The shipped planner_v0 header knobs. Shared with test/shipped_base_header_test.gd
## so the drift guard compares against the SAME reading the generator emits.
static func shipped_knobs() -> Dictionary:
	BattleSim._core_env = 1
	var solo := SoloController.new()
	var node := Node.new()
	solo._core_node = node
	solo.shipped_brain_sha = "shipped-base-dump"
	var diff := SoloDifficulty.for_grade("planner_v0")
	solo._apply_aifix(diff)
	AiMissionEval.eval_variant = solo._eval_variant_for(diff)
	# The knobs block is state-INDEPENDENT (only profiles/terrain read the state),
	# so an empty unit table is the exact reading a real game writes.
	var head: Dictionary = AiActRecorder._header_line({"units": {}}, Callable())
	node.free()
	solo.free()
	return head.get("knobs", {})


## JSON.stringify emits keys in insertion order; a canonical dump sorts them, so
## the file digest is stable across GDScript dictionary ordering.
static func _sorted(d: Dictionary) -> Dictionary:
	var out := {}
	var keys := d.keys()
	keys.sort()
	for k in keys:
		out[k] = d[k]
	return out
