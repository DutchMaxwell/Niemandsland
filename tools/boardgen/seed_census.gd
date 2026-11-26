extends SceneTree
## SEED CENSUS of the generated boards (headless, seconds): per seed what the generator made and which named FAIL rules it breaks.
##   godot --headless --path . -s res://tools/boardgen/seed_census.gd -- [n=20] [master=<int>] [seeds=a,b,c] [theme=ruintown] [out=<dir>]
## `master` draws the n seeds (printed); `seeds=` names them. Writes <out>/census.json LAST, prints `CENSUS_DONE seeds=<n> fails=<k>`, exit 1 when k > 0.
## FAIL codes: PROBLEMS (the core reported problems), NONDETERMINISTIC (two generations differ), ASYMMETRIC (level / lot kind not half-turn equal),
## ISLAND_NO_STUB (a raised non-wall island with no gable stub), NINE_IN_PAIRS (more than one pair of 9 in non-wall patches), FILLER (over 8 filler slab cells).

const FILLER_MAX := 8   # filler slab cells (raised, no lot, not wall: the core test `a_town_grows_few_filler_slabs`)
const TRUTH := preload("res://tools/boardgen/truth_census.gd")


func _initialize() -> void:
	var a := {"n": "20", "master": str(int(Time.get_unix_time_from_system())), "seeds": "", "theme": "ruintown", "out": "user://seed_census"}
	for arg: String in OS.get_cmdline_user_args():
		a[arg.get_slice("=", 0)] = arg.get_slice("=", 1)
	var seeds: Array = Array(str(a["seeds"]).split(",", false)).map(func(s: String) -> int: return int(s))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(a["master"])
	if seeds.is_empty():
		for i in int(a["n"]):
			seeds.append(rng.randi_range(1, 999999))
		print("CENSUS master=%s seeds=%s" % [a["master"], ",".join(seeds.map(func(s: int) -> String: return str(s)))])
	var theme: String = a["theme"]
	var out: String = a["out"]
	var rows: Array = []
	var fails := 0
	for s: int in seeds:
		var r := row(TRUTH.layout_of(s, theme), TRUTH.layout_of(s, theme))
		r["seed"] = s
		fails += int(not (r["fail"] as Array).is_empty())
		print("CENSUS %d %s" % [s, JSON.stringify(r)])
		rows.append(r)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	FileAccess.open(out.path_join("census.json"), FileAccess.WRITE).store_string(JSON.stringify({"theme": theme, "master": int(a["master"]), "rows": rows}, " "))
	print("CENSUS_DONE seeds=%d fails=%d" % [seeds.size(), fails])
	quit(1 if fails > 0 else 0)


## One seed's row: cells per class, islands, roofs, ladders, determinism, symmetry and the FAIL codes. `again` = the same seed generated a second time.
static func row(layout: Dictionary, again: Dictionary) -> Dictionary:
	var nx: int = layout["nx"]
	var nz: int = layout["nz"]
	var c := {"wall_3": 0, "wall_6": 0, "wall_9": 0, "tower": 0, "roofed": 0, "hall": BoardgenTownSilhouette._hall_cells(layout).size(), "nine_in": 0, "filler": 0}
	var island := {}   # cell index -> island number: 4-connected raised cells that are not city wall
	var asym := 0
	for cd: Dictionary in layout["cells"]:
		var lv: int = cd["level"]
		var kind: String = cd["lot_kind"]
		var o: Dictionary = layout["cells"][(nz - 1 - int(cd["z"])) * nx + nx - 1 - int(cd["x"])]
		asym += int(int(o["level"]) != lv or o["lot_kind"] != kind)
		if kind == "Wall" and lv >= 1:
			c["wall_%d" % (lv * 3)] += 1
			continue
		c["tower"] += int(kind == "Tower")
		c["roofed"] += int(kind == "Roofed")
		c["nine_in"] += int(lv >= 3)
		c["filler"] += int(lv >= 1 and int(cd["lot_id"]) == 0)
	var nine_patches := _islands(layout, func(cd: Dictionary) -> bool: return int(cd["level"]) >= 3 and cd["lot_kind"] != "Wall", {})
	var n_islands := _islands(layout, func(cd: Dictionary) -> bool: return int(cd["level"]) >= 1 and cd["lot_kind"] != "Wall", island)
	var stubbed := {}
	var origin := Vector2(nx, nz) * float(layout["cell_in"]) * -0.5
	for b: Dictionary in BoardgenTownSilhouette.ruin_gables(layout):
		var q := ((Vector2(b["lo"].x + b["hi"].x, b["lo"].z + b["hi"].z) * 0.5 - origin) / float(layout["cell_in"])).floor()
		stubbed[island.get(int(q.y) * nx + int(q.x), -1)] = true
	var roofs := {"gable": 0, "hip": 0, "catslide": 0, "low": 0}
	var all_roofs := BoardgenTownDressing.roofs(layout)
	for rf: Dictionary in all_roofs:
		roofs[rf["type"]] = int(roofs.get(rf["type"], 0)) + 1
		roofs["low"] += int(float(rf["height"]) / float(rf["width"]) < 0.35)
	var r := {"attempt": layout["attempt"], "problems": layout["problems"], "cells": c, "islands": n_islands, "islands_stub": stubbed.size() - int(stubbed.has(-1)),
		"nine_in_patches": nine_patches, "roofs": roofs, "low_roof_share": float(roofs["low"]) / maxf(1.0, all_roofs.size()),
		"ladders": (layout["connectors"] as Array).filter(func(k: Dictionary) -> bool: return k["kind"] == "Ladder").size(),
		"digest": TRUTH.layout_digest(layout), "asymmetric_cells": asym}
	var checks := {"PROBLEMS": not (layout["problems"] as Array).is_empty(), "NONDETERMINISTIC": r["digest"] != TRUTH.layout_digest(again), "ASYMMETRIC": asym > 0,
		"ISLAND_NO_STUB": r["islands_stub"] < n_islands, "NINE_IN_PAIRS": nine_patches > 2, "FILLER": c["filler"] > FILLER_MAX}
	var fail: Array = checks.keys().filter(func(k: String) -> bool: return checks[k])
	r["fail"] = fail
	return r


## Labels the 4-connected patches of cells `keep` accepts into `into` (cell index -> patch number); returns the number of patches.
static func _islands(layout: Dictionary, keep: Callable, into: Dictionary) -> int:
	var nx: int = layout["nx"]
	var n := 0
	for i in (layout["cells"] as Array).size():
		if into.has(i) or not keep.call(layout["cells"][i]):
			continue
		var todo: Array[int] = [i]
		into[i] = n
		while not todo.is_empty():
			var j: int = todo.pop_back()
			for d: Vector2i in BoardgenTownSilhouette.DIRS:
				var k := j + d.y * nx + d.x
				if BoardgenTownSilhouette._level(layout, j % nx + d.x, j / nx + d.y) >= 0 and not into.has(k) and keep.call(layout["cells"][k]):
					into[k] = n
					todo.append(k)
		n += 1
	return n
