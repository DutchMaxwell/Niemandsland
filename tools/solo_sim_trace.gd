extends SceneTree
## Emits a full step-by-step JSON trace of ONE sample game (Vanguard vs Horde) for the HTML replay
## viewer. Run: godot --headless -s res://tools/solo_sim_trace.gd -- [seed]
## The JSON is printed between TRACE_JSON_START / TRACE_JSON_END markers.


func _ap(x: int) -> Array:
	return ["AP(%d)" % x]


func _vanguard() -> Array:
	return [
		SoloSim.make_unit("Rifles A", 0, 4, 4, 5, [{"name": "Rifle", "range_value": 24, "attacks": 1, "count": 5, "special_rules": []}]),
		SoloSim.make_unit("Rifles B", 0, 4, 4, 5, [{"name": "Rifle", "range_value": 24, "attacks": 1, "count": 5, "special_rules": []}]),
		SoloSim.make_unit("Heavy Gun", 0, 4, 4, 1, [{"name": "Autocannon", "range_value": 30, "attacks": 3, "count": 1, "special_rules": _ap(1)}]),
		SoloSim.make_unit("Guard Squad", 0, 4, 3, 10, [{"name": "CCW", "range_value": 0, "attacks": 1, "count": 10, "special_rules": []}]),
	]


func _horde() -> Array:
	return [
		SoloSim.make_unit("Assault A", 1, 4, 4, 10, [{"name": "CCW", "range_value": 0, "attacks": 2, "count": 10, "special_rules": []}]),
		SoloSim.make_unit("Assault B", 1, 4, 4, 10, [{"name": "CCW", "range_value": 0, "attacks": 2, "count": 10, "special_rules": []}]),
		SoloSim.make_unit("Skirmishers", 1, 5, 4, 5, [{"name": "Pistol", "range_value": 12, "attacks": 1, "count": 5, "special_rules": []}]),
		SoloSim.make_unit("Bruiser", 1, 3, 3, 1, [{"name": "Great Axe", "range_value": 0, "attacks": 4, "count": 1, "special_rules": _ap(2)}], 3),
	]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var seed_value := 1000
	if args.size() > 0 and str(args[0]).is_valid_int():
		seed_value = int(args[0])

	var a := _vanguard()
	var b := _horde()
	var trace: Array = []
	var res: Dictionary = SoloSim.simulate_game(a, b, seed_value, 4, [], [], trace)

	var objs: Array = []
	for o in SoloSim.default_objectives():
		objs.append([(o as Vector2).x, (o as Vector2).y])

	var out := {
		"board": SoloSim.BOARD_IN,
		"objectives": objs,
		"armies": {"0": "Steel Vanguard", "1": "Blood Horde"},
		"roster": SoloSim.roster(a, b),
		"steps": trace,
		"result": res,
		"seed": seed_value,
	}
	print("TRACE_JSON_START")
	print(JSON.stringify(out))
	print("TRACE_JSON_END")
	quit()
