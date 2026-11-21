class_name BoardgenDecals
extends Node3D
## Painted-on detail of a generated board from the T2 decal atlas (TiefwerkLibrary): a leak under every pipe that ends in the air, a
## louvre with soot above and a leak below on the tall walls, the tier's height as a stencil numeral on its wall, lane arrows down the
## streets and soot in the corners of the open floor. VISUAL ONLY. plan() is a pure function of the layout (its seed feeds one
## RandomNumberGenerator); build() turns the plan into at most MAX_DECALS Decal nodes once the atlas is cached. The Compatibility
## renderer has no decals: the board is simply bare there.

const INCHES_TO_METERS := 0.0254
const MAX_DECALS := 48
## Candidates kept per kind (a vent is three decals: 14 + 12 + 10 + 6 + 6 = 48).
const CAPS := {"num": 14, "vent": 4, "leak": 10, "corner": 6, "arrow": 6}
const DEPTH_IN := 0.3   # how far in front of and behind the surface the projection reaches
const RENDER_LAYER := 1 << 19   # the board's own surfaces sit on this layer too; models and props never receive these decals
const FADE_BEGIN_M := 1.8
const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]


## Every decal of the board: {cell: atlas cell, pos: Vector3 inches off the board centre ON the surface, n: the surface's outward
## normal, up: where the image's top points, size: Vector2 inches}. Pure data. Each kind has its own cap (a random pick of its candidates),
## so one kind never crowds out another and the whole stays within MAX_DECALS.
static func plan(layout: Dictionary) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(layout["seed"]) * 40503 + 29
	var nx: int = layout["nx"]
	var nz: int = layout["nz"]
	var cell_in := float(layout["cell_in"])
	var cells: Array = layout["cells"]
	var origin := Vector2(nx, nz) * cell_in * -0.5
	var bare := {}   # ladder feet, landmark footprints and sumps carry nothing
	for c: Dictionary in layout["connectors"]:
		bare[Vector2i(c["low_xz"][0], c["low_xz"][1])] = true
	for lm: Dictionary in layout.get("landmarks", []):
		for dz in int(lm["h"]):
			for dx in int(lm["w"]):
				bare[Vector2i(int(lm["x"]) + dx, int(lm["z"]) + dz)] = true
	var found := {"num": [], "vent": [], "corner": [], "arrow": []}   # kind -> candidates (each an Array of decals)
	for z in nz:
		for x in nx:
			var me: Dictionary = cells[z * nx + x]
			var at := Vector2i(x, z)
			if me["level"] > 0 or me["lot_kind"] == "Hazard" or bare.has(at):
				continue
			var centre := origin + (Vector2(at) + Vector2(0.5, 0.5)) * cell_in
			var walls: Array[Vector2i] = []   # the neighbours that are tier walls
			for d in DIRS:
				var o := at + d
				if o.x >= 0 and o.y >= 0 and o.x < nx and o.y < nz and cells[o.y * nx + o.x]["level"] > 0:
					walls.append(d)
			for d in walls:
				var h := float(layout["level_in"][cells[(z + d.y) * nx + x + d.x]["level"]])
				var face := Vector3(-d.x, 0, -d.y)   # out of the wall, onto the floor cell
				var on_wall := Vector3(centre.x + d.x * cell_in * 0.5, 0.0, centre.y + d.y * cell_in * 0.5)
				found["num"].append([_d("num_%d" % int(h), on_wall + Vector3.UP * minf(h * 0.5, 3.0), face, Vector2(0.94, 1.5))])   # the tier's height, stencilled
				if h >= 6.0:   # a louvre, soot above it, a leak under it
					found["vent"].append([_d("louvre_slats6", on_wall + Vector3.UP * 2.0, face, Vector2(1.0, 0.62)),
						_d("scorch", on_wall + Vector3.UP * 3.4, face, Vector2(1.0, 1.5)), _d("leak_oil", on_wall + Vector3.UP * 0.9, face, Vector2(0.5, 2.0))])
			if walls.size() >= 2 and walls[0] != -walls[1]:   # a corner of the open floor: soot (the artwork's dark corner is its bottom left)
				var c := Vector2(walls[0] + walls[1])
				found["corner"].append([_d("grime_corner", Vector3(centre.x + c.x * cell_in * 0.25, 0.0, centre.y + c.y * cell_in * 0.25), Vector3.UP, Vector2(1.5, 1.5),
						Vector3(-(c.x + c.y) * 0.5, 0, (c.x - c.y) * 0.5))])
			elif me["street"] and walls.is_empty():   # a lane arrow along a straight street
				var street := func(o: Vector2i) -> bool: return o.x >= 0 and o.y >= 0 and o.x < nx and o.y < nz and cells[o.y * nx + o.x]["street"]
				var along := Vector3(1, 0, 0) if street.call(at + Vector2i(1, 0)) and street.call(at - Vector2i(1, 0)) else Vector3(0, 0, 1)
				found["arrow"].append([_d("floor_arrow", Vector3(centre.x, 0.0, centre.y), Vector3.UP, Vector2(0.75, 1.5), along)])
	found["leak"] = _pipe_ends(layout).map(func(p: Dictionary) -> Array: return [_d("leak_rust", p["pos"] + Vector3.DOWN * 1.1, p["n"], Vector2(0.5, 2.0))])
	var out: Array[Dictionary] = []
	for kind: String in CAPS:
		var group: Array = found[kind]
		while group.size() > CAPS[kind]:
			group.remove_at(rng.randi() % group.size())
		for entry: Array in group:
			out.append_array(entry)
	return out


## The free ends of the pipe runs of BoardgenProps (a run whose end meets no other run's end): {pos: inches, on the wall just below the pipe, n}.
static func _pipe_ends(layout: Dictionary) -> Array[Dictionary]:
	var ends: Array[Dictionary] = []
	var seen := {}
	for p: Dictionary in BoardgenProps.plan(layout):
		var s: Vector3 = p["xf"].basis.get_scale() / INCHES_TO_METERS
		if p["shape"] != "cyl" or absf(s.y - (float(layout["cell_in"]) - 0.12)) > 0.01:
			continue
		var c: Vector3 = p["xf"].origin / INCHES_TO_METERS
		var axis: Vector3 = p["xf"].basis.y.normalized()
		var wall: Vector3 = p["xf"].basis.z.normalized()   # towards the wall
		for e: float in [-1.0, 1.0]:
			var end := c + axis * s.y * 0.5 * e
			var key := Vector3i((end * 4.0).round())
			seen[key] = seen.get(key, 0) + 1
			ends.append({"pos": end + wall * (0.05 + s.x * 0.65) + Vector3.DOWN * s.x * 0.6, "n": -wall, "key": key})
	return ends.filter(func(e: Dictionary) -> bool: return seen[e["key"]] == 1)


static func _d(cell: String, pos: Vector3, n: Vector3, size: Vector2, up := Vector3.UP) -> Dictionary:
	return {"cell": cell, "pos": pos, "n": n, "up": up, "size": size}


## Nodes of the plan, textured from the library. Nothing is built while the atlas is not cached (the board is bare, never broken).
func build(layout: Dictionary, lib: TiefwerkLibrary) -> void:
	if not lib.decals_cached():
		return
	for e in plan(layout):
		var tex := lib.decal_textures(e["cell"])
		if tex.is_empty():
			continue
		var decal := Decal.new()
		decal.size = Vector3(e["size"].x, DEPTH_IN, e["size"].y) * INCHES_TO_METERS
		decal.texture_albedo = tex["albedo"]
		decal.texture_normal = tex["normal"]
		decal.texture_orm = tex["orm"]
		decal.cull_mask = RENDER_LAYER
		decal.distance_fade_enabled = true
		decal.distance_fade_begin = FADE_BEGIN_M
		decal.distance_fade_length = 0.5
		var y: Vector3 = e["n"]
		var z: Vector3 = -e["up"]   # the image's top is local -Z
		decal.transform = Transform3D(Basis(y.cross(z), y, z), (e["pos"] + y * DEPTH_IN * 0.25) * INCHES_TO_METERS)
		add_child(decal)
