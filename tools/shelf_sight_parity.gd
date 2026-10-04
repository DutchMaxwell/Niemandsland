extends SceneTree
## Writes test/fixtures/shelf_sight_parity/cases.json: 1,000 seeded sight lines against ONE freely placed shelf
## piece each (a 6x3" 2.5" solid, a 9x6" 6" ruin hull or a 6x4" 3.4" forest hull) at 0/45/90 deg or a random yaw,
## with VolumetricLos.has_los as the verdict. Shooters/targets stand on the table, on a 3" floor or on a 2.5" roof,
## a fifth of them inside the footprint. Every value is stored as GDScript holds it (Vector2 = 32-bit floats), so the
## Rust core (sight::Zone::shelf_box) replays the very same numbers. Run from the repo root:
##   godot --headless --path . -s tools/shelf_sight_parity.gd

const OUT := "res://test/fixtures/shelf_sight_parity/cases.json"
const SEED := 20261003
const N := 1000
const IN := 0.0254
const PIECES := [[Vector2(6, 3), 2.5, true], [Vector2(9, 6), 6.0, false], [Vector2(6, 4), 3.4, false]]
const YAWS := [0.0, PI / 4.0, PI / 2.0]
const BASES := [25.0, 32.0, 40.0, 50.0]


func _initialize() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var cases: Array = []
	var seen := 0
	for i in N:
		var piece: Array = PIECES[0 if rng.randf() < 0.5 else rng.randi_range(1, 2)]   # half solids, half area hulls
		var yaw := float(YAWS[rng.randi_range(0, 2)]) if rng.randf() < 0.75 else rng.randf_range(0.0, TAU)
		var vol := {"kind": "box", "c": Vector2(rng.randf_range(-4, 4), rng.randf_range(-4, 4)) * IN,
			"he": (piece[0] as Vector2) * IN * 0.5, "yaw": yaw, "y0": 0.0, "y1": float(piece[1]) * IN,
			"solid": bool(piece[2])}
		var a := _cyl(rng, vol)
		var b := _cyl(rng, vol)
		var los := VolumetricLos.has_los(a, b, [vol])
		seen += 1 if los else 0
		cases.append({"c": [vol["c"].x, vol["c"].y], "he": [vol["he"].x, vol["he"].y], "yaw": yaw,
			"y1": vol["y1"], "solid": vol["solid"], "from": _out(a), "to": _out(b), "los": los})
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT.get_base_dir()))
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string("{\"seed\": %d, \"cases\": [\n%s\n]}\n" % [SEED, ",\n".join(cases.map(
		func(c: Dictionary) -> String: return JSON.stringify(c, "", false, true)))])
	f.close()
	print("SHELF_SIGHT_PARITY cases=%d los_true=%d los_false=%d" % [N, seen, N - seen])
	quit()


## A model cylinder: a base from BASES, standing on the table, a 3" floor or a 2.5" roof, a fifth inside the piece.
func _cyl(rng: RandomNumberGenerator, vol: Dictionary) -> Dictionary:
	var mm: float = BASES[rng.randi_range(0, BASES.size() - 1)]
	var y0: float = [0.0, 0.0, 0.0, 3.0 * IN, 2.5 * IN][rng.randi_range(0, 4)]
	var p := Vector2(rng.randf_range(-15, 15), rng.randf_range(-15, 15)) * IN
	if rng.randf() < 0.2:
		var he: Vector2 = vol["he"]
		var local := Vector2(rng.randf_range(-he.x, he.x), rng.randf_range(-he.y, he.y))
		var yaw: float = vol["yaw"]
		p = (vol["c"] as Vector2) + Vector2(cos(yaw), -sin(yaw)) * local.x + Vector2(sin(yaw), cos(yaw)) * local.y
	return {"c": p, "r": mm / 2000.0, "y0": y0, "y1": y0 + VolumetricLos.height_in_for_base_mm(mm) * IN}


func _out(cyl: Dictionary) -> Dictionary:
	return {"c": [cyl["c"].x, cyl["c"].y], "r": cyl["r"], "y0": cyl["y0"], "y1": cyl["y1"]}
