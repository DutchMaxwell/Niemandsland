extends SceneTree
## Emits a full step-by-step JSON trace of ONE game for the HTML replay viewer.
## Run:  godot --headless -s res://tools/solo_sim_trace.gd -- <opr_list.json> [seed]
## With a list path it plays a MIRROR match (the same army on both sides); without one it falls back to
## the built-in Vanguard-vs-Horde sample. The JSON prints between TRACE_JSON_START / TRACE_JSON_END.


func _ap(x: int) -> Array:
	return ["AP(%d)" % x]


func _sample() -> Array:
	var a := [
		SoloSim.make_unit("Rifles A", 0, 4, 4, 5, [{"name": "Rifle", "range_value": 24, "attacks": 1, "count": 5, "special_rules": []}]),
		SoloSim.make_unit("Rifles B", 0, 4, 4, 5, [{"name": "Rifle", "range_value": 24, "attacks": 1, "count": 5, "special_rules": []}]),
		SoloSim.make_unit("Heavy Gun", 0, 4, 4, 1, [{"name": "Autocannon", "range_value": 30, "attacks": 3, "count": 1, "special_rules": _ap(1)}]),
		SoloSim.make_unit("Guard Squad", 0, 4, 3, 10, [{"name": "CCW", "range_value": 0, "attacks": 1, "count": 10, "special_rules": []}]),
	]
	var b := [
		SoloSim.make_unit("Assault A", 1, 4, 4, 10, [{"name": "CCW", "range_value": 0, "attacks": 2, "count": 10, "special_rules": []}]),
		SoloSim.make_unit("Assault B", 1, 4, 4, 10, [{"name": "CCW", "range_value": 0, "attacks": 2, "count": 10, "special_rules": []}]),
		SoloSim.make_unit("Skirmishers", 1, 5, 4, 5, [{"name": "Pistol", "range_value": 12, "attacks": 1, "count": 5, "special_rules": []}]),
		SoloSim.make_unit("Bruiser", 1, 3, 3, 1, [{"name": "Great Axe", "range_value": 0, "attacks": 4, "count": 1, "special_rules": _ap(2)}], 3),
	]
	return [a, b, "Steel Vanguard", "Blood Horde"]


## Give every unit a unique, readable label (mirror lists repeat unit names). Cyan side = C, amber = A.
func _label(units: Array, tag: String) -> void:
	for i in range(units.size()):
		units[i]["name"] = "%s %s%d" % [str(units[i]["name"]), tag, i + 1]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var list_path := ""
	var seed_value := 1000
	for a in args:
		var s := str(a)
		if s.is_valid_int():
			seed_value = int(s)
		elif s.ends_with(".json") or s.begins_with("res://"):
			list_path = s

	var army_a: Array
	var army_b: Array
	var name_a: String
	var name_b: String
	if list_path != "":
		var f := FileAccess.open(list_path, FileAccess.READ)
		var data: Variant = JSON.parse_string(f.get_as_text()) if f != null else null
		if not (data is Dictionary):
			print("Bad or missing list: ", list_path)
			quit()
			return
		var list_name := str((data as Dictionary).get("name", "List"))
		army_a = SoloSim.units_from_opr_json(data, 0)
		army_b = SoloSim.units_from_opr_json(data, 1)
		_label(army_a, "C")
		_label(army_b, "A")
		name_a = "%s · Cyan" % list_name
		name_b = "%s · Amber" % list_name
	else:
		var sample := _sample()
		army_a = sample[0]
		army_b = sample[1]
		name_a = str(sample[2])
		name_b = str(sample[3])

	var trace: Array = []
	# Play on a seeded, reflection-symmetric terrain layout (grid of typed 3" cells — the game's model), plus a
	# symmetric layer of thin IMPASSABLE walls the AI must steer its individual models around (MovementPlanner).
	var terrain: Dictionary = SoloSim.default_terrain(seed_value)
	var walls: Array = SoloSim.default_walls(seed_value)
	var res: Dictionary = SoloSim.simulate_game(army_a, army_b, seed_value, 4, [], [], trace, terrain, walls)
	var objs: Array = []
	for o in SoloSim.default_objectives():
		objs.append([(o as Vector2).x, (o as Vector2).y])

	var out := {
		"board": SoloSim.BOARD_IN,
		"objectives": objs,
		"terrain": res.get("terrain", []),
		"walls": res.get("walls", []),
		"cell_in": TerrainRules.CELL_IN,
		"armies": {"0": name_a, "1": name_b},
		"roster": SoloSim.roster(army_a, army_b),
		"steps": trace,
		"result": res,
		"seed": seed_value,
	}
	print("TRACE_JSON_START")
	print(JSON.stringify(out))
	print("TRACE_JSON_END")
	quit()
