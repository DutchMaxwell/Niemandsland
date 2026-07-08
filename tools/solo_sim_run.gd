extends SceneTree
## Headless self-play runner (goal 003 stage 0). Plays N AI-vs-AI games between two sample armies and
## prints an aggregate table + a full log of the first game. Run:
##   godot --headless -s res://tools/solo_sim_run.gd            (1 game, verbose)
##   godot --headless -s res://tools/solo_sim_run.gd -- 100     (100 games, aggregate only)


func _ap(x: int) -> Array:
	return ["AP(%d)" % x]


## Sample armies — deliberately different archetypes so the game actually plays out.
func _vanguard() -> Array:
	# Shooting-leaning defenders (player 0). OPR: weapon `count` = models carrying it (attacks scale with
	# the unit's size) — every model shoots/fights, so count matches the model count.
	return [
		SoloSim.make_unit("Rifles A", 0, 4, 4, 5, [{"name": "Rifle", "range_value": 24, "attacks": 1, "count": 5, "special_rules": []}]),
		SoloSim.make_unit("Rifles B", 0, 4, 4, 5, [{"name": "Rifle", "range_value": 24, "attacks": 1, "count": 5, "special_rules": []}]),
		SoloSim.make_unit("Heavy Gun", 0, 4, 4, 1, [{"name": "Autocannon", "range_value": 30, "attacks": 3, "count": 1, "special_rules": _ap(1)}]),
		SoloSim.make_unit("Guard Squad", 0, 4, 3, 10, [{"name": "CCW", "range_value": 0, "attacks": 1, "count": 10, "special_rules": []}]),
	]


func _horde() -> Array:
	# Melee-leaning attackers (player 1).
	return [
		SoloSim.make_unit("Assault A", 1, 4, 4, 10, [{"name": "CCW", "range_value": 0, "attacks": 2, "count": 10, "special_rules": []}]),
		SoloSim.make_unit("Assault B", 1, 4, 4, 10, [{"name": "CCW", "range_value": 0, "attacks": 2, "count": 10, "special_rules": []}]),
		SoloSim.make_unit("Skirmishers", 1, 5, 4, 5, [{"name": "Pistol", "range_value": 12, "attacks": 1, "count": 5, "special_rules": []}]),
		SoloSim.make_unit("Bruiser", 1, 3, 3, 1, [{"name": "Great Axe", "range_value": 0, "attacks": 4, "count": 1, "special_rules": _ap(2)}], 3),
	]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var n := 1
	if args.size() > 0 and str(args[0]).is_valid_int():
		n = maxi(int(args[0]), 1)

	var a_wins := 0
	var b_wins := 0
	var draws := 0
	var round_sum := 0
	var a_loss_sum := 0
	var b_loss_sum := 0

	for i in range(n):
		var log_lines: Array = []
		var verbose := (i == 0 and n == 1)
		var res: Dictionary = SoloSim.simulate_game(_vanguard(), _horde(), 1000 + i, 4, log_lines)
		match int(res["winner"]):
			0: a_wins += 1
			1: b_wins += 1
			_: draws += 1
		round_sum += int(res["rounds"])
		a_loss_sum += int(res["a_losses"])
		b_loss_sum += int(res["b_losses"])
		if verbose:
			print("=== FIRST GAME (seed 1000) — full log ===")
			for line in log_lines:
				print("  ", line)
			print("--- result: winner=%s rounds=%d end=%s | objectives %d-%d | Vanguard %d/%d alive, Horde %d/%d alive ---" % [
				("Vanguard" if int(res["winner"]) == 0 else ("Horde" if int(res["winner"]) == 1 else "draw")),
				int(res["rounds"]), res["end_reason"], int(res["a_objectives"]), int(res["b_objectives"]),
				int(res["a_alive"]), int(res["a_start"]), int(res["b_alive"]), int(res["b_start"])])

	print("")
	print("=== %d game(s): Vanguard vs Horde ===" % n)
	print("  Vanguard wins : %d (%.1f%%)" % [a_wins, 100.0 * a_wins / n])
	print("  Horde wins    : %d (%.1f%%)" % [b_wins, 100.0 * b_wins / n])
	print("  Draws         : %d (%.1f%%)" % [draws, 100.0 * draws / n])
	print("  Avg rounds    : %.2f" % (float(round_sum) / n))
	print("  Avg losses    : Vanguard %.1f models, Horde %.1f models" % [float(a_loss_sum) / n, float(b_loss_sum) / n])
	quit()
