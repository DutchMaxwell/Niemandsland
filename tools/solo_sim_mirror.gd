extends SceneTree
## Mirror-match self-play (goal 003 stage 1). Loads an OPR TTS-API list from a JSON file and plays the
## SAME army against itself N times. A mirror match is a FAIRNESS test: identical forces must win ~50/50
## — any strong skew reveals an engine bias (e.g. a first-activation advantage). Run:
##   godot --headless -s res://tools/solo_sim_mirror.gd -- /abs/path/list.json 1000


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		print("usage: -- <abs_path_to_opr_json> [num_games]")
		quit()
		return
	var path := str(args[0])
	var n := 1000
	if args.size() > 1 and str(args[1]).is_valid_int():
		n = maxi(int(args[1]), 1)

	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		print("Cannot open: ", path)
		quit()
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (data is Dictionary):
		print("Bad JSON")
		quit()
		return

	var list_name := str((data as Dictionary).get("name", "List"))
	var army_a := SoloSim.units_from_opr_json(data, 0)
	var army_b := SoloSim.units_from_opr_json(data, 1)
	print("Mirror: %s vs %s — %d unit(s)/side, %d games" % [list_name, list_name, army_a.size(), n])

	# One verbose game to eyeball the play, then the aggregate. Each game runs on its own seeded terrain
	# layout — reflection-symmetric, so a fair mirror stays fair (both sides get equivalent cover).
	var log_lines: Array = []
	SoloSim.simulate_game(army_a, army_b, 1000, 4, log_lines, [], [], SoloSim.default_terrain(1000))
	print("=== FIRST GAME (seed 1000) — full log ===")
	for line in log_lines:
		print("  ", line)

	var p0 := 0
	var p1 := 0
	var draws := 0
	var round_sum := 0
	var obj_decided := 0
	for i in range(n):
		var res: Dictionary = SoloSim.simulate_game(army_a, army_b, 1000 + i, 4, [], [], [], SoloSim.default_terrain(1000 + i))
		match int(res["winner"]):
			0: p0 += 1
			1: p1 += 1
			_: draws += 1
		round_sum += int(res["rounds"])
		if int(res["a_objectives"]) != int(res["b_objectives"]):
			obj_decided += 1

	print("")
	print("=== %d mirror game(s): %s ===" % [n, list_name])
	print("  Player 0 (first) wins : %d (%.1f%%)" % [p0, 100.0 * p0 / n])
	print("  Player 1 wins         : %d (%.1f%%)" % [p1, 100.0 * p1 / n])
	print("  Draws                 : %d (%.1f%%)" % [draws, 100.0 * draws / n])
	print("  Avg rounds            : %.2f" % (float(round_sum) / n))
	print("  Decided by objectives : %d (%.1f%%)  [rest by model-count tiebreak]" % [obj_decided, 100.0 * obj_decided / n])
	print("  → FAIR if ~50/50; a skew toward Player 0 = first-activation advantage.")
	quit()
