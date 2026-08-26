extends SceneTree
## NML-1073 M4-6a GATE B — the MOVE seam's Dictionary marshalling, proved lossless.
##
## The seam hands NmlCore a Godot Dictionary; the corpus gate hands nml-core a
## JSON line. Both must describe the SAME call, or a green corpus gate says
## nothing about the live game — M2-5 learned that the hard way: an Array[String]
## read as EMPTY across the Dictionary boundary while the JSONL gate stayed green,
## because JSON has only one kind of array.
##
## So: take recorded moves_calls.jsonl lines, rebuild each as a Dictionary, send
## it through NmlCore.move_call_roundtrip — the LIVE door, the same marshalling
## plan_unit_step uses — and compare the canonical JSON that comes back with the
## canonical JSON NmlCore.move_line_canonical reads out of the ORIGINAL line.
##
## TWO WAYS TO REBUILD, and the difference is the point:
##   live  — NmlCore.move_line_to_dict: the shape the controller actually sends
##           (Vector2 positions, a Vector2i-KEYED terrain grid, nested option
##           dictionaries). This is the gate: nothing but the Variant boundary
##           stands between the two canonical strings.
##   json  — JSON.parse_string: plain arrays, float-widened cells, no Vector2 and
##           no Vector2i key anywhere. Reported as a SECOND reading, not as the
##           gate, because Godot's own String::to_double is up to 1 ULP off on a
##           17-digit literal: a corpus line re-parsed in GDScript is not always
##           the number that was recorded, and that is the harness, not the seam.
##
## Usage: godot --headless --path . -s res://tools/move_seam_roundtrip.gd -- \
##          file=<moves_calls.jsonl> [n=10] [--corrupt]
##   --corrupt   RED proof: nudge board_in of the FIRST rebuilt dictionary by
##               1e-9 before the comparison, so a green run is earned and not two
##               empty strings agreeing with each other.

var _core: Object = null
var _corrupt := false


func _init() -> void:
	var file_path := ""
	var n := 10
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
	if not ClassDB.class_exists("NmlCore"):
		printerr("[MOVE-RT] the NmlCore extension is not loaded — nothing to check")
		quit(1)
		return
	var lines := _read_calls(file_path, n)
	if lines.is_empty():
		printerr("[MOVE-RT] no call lines read from ", file_path)
		quit(1)
		return
	_core = ClassDB.instantiate("NmlCore")
	print("[MOVE-RT] corpus=%s calls=%d corrupt=%s" % [file_path, lines.size(), str(_corrupt)])
	var live := _run(lines, true)
	var json := _run(lines, false)
	print("[MOVE-RT] live-shape (Vector2 / Vector2i keys): %d/%d identical" % [live, lines.size()])
	print("[MOVE-RT] JSON.parse_string shape:              %d/%d identical" % [json, lines.size()])
	quit(0 if live == lines.size() else 1)


## Every call line but the header, capped at n.
func _read_calls(path: String, n: int) -> Array:
	var out: Array = []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		printerr("[MOVE-RT] cannot open ", path)
		return out
	f.get_line()   # line 1 is the per-game header; the seam only ever sends CALLS
	while out.size() < n and not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line != "":
			out.append(line)
	return out


## How many of the lines survive the Dictionary round trip unchanged.
func _run(lines: Array, live: bool) -> int:
	var label := "live" if live else "json"
	var same := 0
	for i in lines.size():
		var line: String = lines[i]
		var call: Dictionary = {}
		if live:
			call = _core.move_line_to_dict(line)
		else:
			var parsed: Variant = JSON.parse_string(line)
			if parsed is Dictionary:
				call = parsed
		if call.is_empty():
			printerr("[MOVE-RT] %s call %d did not rebuild: %s" % [label, i + 1, str(_core.last_error())])
			continue
		if _corrupt and i == 0:
			call["board_in"] = float(call["board_in"]) + 1e-9   # the smallest lie the gate must catch
		var from_dict := str(_core.move_call_roundtrip(call))
		var from_line := str(_core.move_line_canonical(line))
		if from_dict == "" or from_line == "":
			printerr("[MOVE-RT] %s call %d did not parse: %s" % [label, i + 1, str(_core.last_error())])
			continue
		if from_dict == from_line:
			same += 1
		else:
			var at := _first_diff(from_dict, from_line)
			print("[MOVE-RT] %s call %d DIFFERS at char %d" % [label, i + 1, at])
			print("  dict: %s" % from_dict.substr(maxi(at - 40, 0), 160))
			print("  line: %s" % from_line.substr(maxi(at - 40, 0), 160))
	return same


## Index of the first differing character — names WHERE the two disagree, so a
## red run points at the field instead of at two 200 kB strings.
func _first_diff(a: String, b: String) -> int:
	var n := mini(a.length(), b.length())
	for i in n:
		if a[i] != b[i]:
			return i
	return n
