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
	if str(layout.get("theme", "")) == "RuinTown":
		return town_plan(layout)
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


## THE RUIN TOWN'S DECALS (plan PLAN_RUINTOWN_GRIT D1, the T-R2 atlas): each kind where its cause is - cart ruts at the ends of the arteries along the run, a drain on a lane's kennel,
## a puddle rim on every grit puddle, leaves and straw in the lee corners of the open ground, droppings at the foot of the city wall, cracks on the tower tops, plaster loss and a repair patch
## on the street faces of the ruined rows, soot / scorch on the fire side's faces. Capped per kind (TOWN_CAPS, <= MAX_DECALS together). Nothing on a ladder foot, a dangerous cell or a
## landmark; ground decals are flat (they never stand on open ground), the board shader's surfaces receive them, the models never.
const TOWN_CAPS := {"cart_ruts": 4, "drain": 4, "puddle_rim": 6, "leaf_drift": 6, "straw_scatter": 6, "bird_droppings": 4, "crack": 6, "plaster_loss": 0, "repair_patch": 0, "soot": 4}   # (no plaster loss / repair decals: they projected white blots onto the towers next to the faces; the shader draws the losses, W2)


static func town_plan(layout: Dictionary) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(layout["seed"]) * 40503 + 31
	var nx: int = layout["nx"]
	var nz: int = layout["nz"]
	var cell_in := float(layout["cell_in"])
	var cells: Array = layout["cells"]
	var origin := Vector2(nx, nz) * cell_in * -0.5
	var bare := {}
	for c: Dictionary in layout["connectors"]:
		bare[Vector2i(c["low_xz"][0], c["low_xz"][1])] = true
	for lm: Dictionary in layout.get("landmarks", []):
		for dz in int(lm["h"]):
			for dx in int(lm["w"]):
				bare[Vector2i(int(lm["x"]) + dx, int(lm["z"]) + dz)] = true
	var open := func(at: Vector2i) -> bool:
		if at.x < 0 or at.y < 0 or at.x >= nx or at.y >= nz or bare.has(at):
			return false
		var cd: Dictionary = cells[at.y * nx + at.x]
		return int(cd["level"]) == 0 and cd["lot_kind"] != "Hazard"
	var found := {}
	for kind: String in TOWN_CAPS:
		found[kind] = []
	var cls := BoardgenTownGrit.classes(layout)
	var section := BoardgenTownGrit.runs(layout, cls)
	for i: int in section:
		var r: Dictionary = section[i]
		var at := Vector2i(i % nx, i / nx)
		if not open.call(at):
			continue
		var centre := origin + (Vector2(at) + Vector2(0.5, 0.5)) * cell_in
		var along := Vector3(1, 0, 0) if r["axis"] == 0 else Vector3(0, 0, 1)
		var on_line := Vector3(centre.x, 0.0, float(r["centre"])) if r["axis"] == 0 else Vector3(float(r["centre"]), 0.0, centre.y)
		var step := Vector2i(1, 0) if r["axis"] == 0 else Vector2i(0, 1)
		var run_end: bool = not open.call(at + step) or not open.call(at - step) or not section.has((at + step).y * nx + (at + step).x) or not section.has((at - step).y * nx + (at - step).x)
		var on_cell := Vector2i(floori(on_line.x / cell_in + nx * 0.5), floori(on_line.z / cell_in + nz * 0.5))
		if not open.call(on_cell):
			continue   # a two-cell street's centre line is a cell edge: the decal's own cell must be open too
		if r["artery"] and run_end:
			found["cart_ruts"].append([_d("cart_ruts", on_line, Vector3.UP, Vector2(3.0, 1.6), along)])
		elif not r["artery"]:
			found["drain"].append([_d("drain", on_line, Vector3.UP, Vector2(0.75, 0.75), along)])
	for pd: Dictionary in BoardgenTownGrit.puddles(layout, cls):
		var p: Vector2 = pd["at"]
		var dia := float(pd["r"]) * 2.0 * 1.5
		found["puddle_rim"].append([_d("puddle_rim", Vector3(p.x, 0.0, p.y), Vector3.UP, Vector2(dia, dia * 0.67))])
	for z in nz:
		for x in nx:
			var at := Vector2i(x, z)
			if not open.call(at):
				continue
			var centre := origin + (Vector2(at) + Vector2(0.5, 0.5)) * cell_in
			var walls: Array[Vector2i] = []
			for d in DIRS:
				var o := at + d
				if o.x >= 0 and o.y >= 0 and o.x < nx and o.y < nz and int(cells[o.y * nx + o.x]["level"]) > 0:
					walls.append(d)
			if walls.size() >= 2 and walls[0] != -walls[1]:   # a lee corner: leaves or straw blown into it
				var c := Vector2(walls[0] + walls[1])
				var kind := "leaf_drift" if (x + z) % 2 == 0 else "straw_scatter"
				found[kind].append([_d(kind, Vector3(centre.x + c.x * cell_in * 0.3, 0.0, centre.y + c.y * cell_in * 0.3), Vector3.UP, Vector2(1.5, 1.0) if kind == "leaf_drift" else Vector2(1.0, 1.0),
						Vector3(-(c.x + c.y) * 0.5, 0, (c.x - c.y) * 0.5).normalized())])
			for d in walls:
				var nb: Dictionary = cells[(z + d.y) * nx + x + d.x]
				var face := Vector3(-d.x, 0, -d.y)
				var foot := Vector3(centre.x + d.x * cell_in * 0.38, 0.0, centre.y + d.y * cell_in * 0.38)
				var on_wall := Vector3(centre.x + d.x * cell_in * 0.5, 0.0, centre.y + d.y * cell_in * 0.5)
				if nb["lot_kind"] == "Wall" and int(nb["level"]) >= 2:
					found["bird_droppings"].append([_d("bird_droppings", foot, Vector3.UP, Vector2(0.5, 0.5))])
				elif ["Block", "Terrace", "Deck"].has(String(nb["lot_kind"])) and cells[z * nx + x]["street"]:
					var h := float(layout["level_in"][int(nb["level"])])
					found["plaster_loss"].append([_d("plaster_loss_%d" % (rng.randi() % 3), on_wall + Vector3.UP * minf(h - 0.8, 4.2), face, Vector2(1.0, 1.0), Vector3.UP, 0.9)])
					found["repair_patch"].append([_d("repair_patch", on_wall + Vector3.UP * 1.2, face, Vector2(1.0, 1.0), Vector3.UP, 0.9)])
					found["soot"].append([_d("soot_%d" % (rng.randi() % 3), on_wall + Vector3.UP * minf(h - 1.0, 3.5), face, Vector2(0.62, 1.5), Vector3.UP, 0.9), int(nb["lot_id"])])
	for cd: Dictionary in cells:   # cracks across the flagstones of the tower and wall tops
		if int(cd["level"]) >= 3 or (cd["lot_kind"] == "Wall" and int(cd["level"]) >= 2):
			var centre := origin + (Vector2(cd["x"], cd["z"]) + Vector2(0.5, 0.5)) * cell_in
			found["crack"].append([_d("crack_%d" % (rng.randi() % 3), Vector3(centre.x, float(layout["level_in"][int(cd["level"])]), centre.y), Vector3.UP, Vector2(1.0, 0.62),
					Vector3(1, 0, 0) if rng.randf() < 0.5 else Vector3(0, 0, 1))])
	var tale := BoardgenTownDressing.story(int(layout["seed"]))   # soot on the fire side: the faces whose cell lies furthest along the fire's way (folded per half like the shader)
	var fire := func(e: Array) -> float:
		var p: Vector3 = e[0]["pos"]
		var q := Vector2(-p.x, -p.z) if p.z >= 0.0 else Vector2(p.x, p.z)
		return (q + Vector2(0.0, 12.0)).dot(Vector2(tale.r, tale.g))
	found["soot"].sort_custom(func(a: Array, b: Array) -> bool: return fire.call(a) > fire.call(b))
	found["soot"] = found["soot"].slice(0, TOWN_CAPS["soot"]).map(func(e: Array) -> Array: return [e[0]])
	var out: Array[Dictionary] = []
	for kind: String in TOWN_CAPS:
		var group: Array = found[kind]
		while group.size() > TOWN_CAPS[kind]:
			group.remove_at(rng.randi() % group.size())
		for entry: Array in group:
			out.append(entry[0])
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


static func _d(cell: String, pos: Vector3, n: Vector3, size: Vector2, up := Vector3.UP, depth := DEPTH_IN) -> Dictionary:
	return {"cell": cell, "pos": pos, "n": n, "up": up, "size": size, "depth": depth}


## Nodes of the plan, textured from the library. Nothing is built while the atlas is not cached (the board is bare, never broken).
func build(layout: Dictionary, lib: TiefwerkLibrary) -> void:
	if not lib.decals_cached():
		return
	for e in plan(layout):
		var tex := lib.decal_textures(e["cell"])
		if tex.is_empty():
			continue
		var decal := Decal.new()
		var depth: float = e.get("depth", DEPTH_IN)
		decal.size = Vector3(e["size"].x, depth, e["size"].y) * INCHES_TO_METERS
		decal.texture_albedo = tex["albedo"]
		decal.texture_normal = tex["normal"]
		decal.texture_orm = tex["orm"]
		decal.cull_mask = RENDER_LAYER | (BoardgenMood.BOARD_LAYER if str(layout.get("theme", "")) == "RuinTown" else 0)   # (the town's walls are drawn by several meshes on the board layer)
		decal.distance_fade_enabled = true
		decal.distance_fade_begin = FADE_BEGIN_M
		decal.distance_fade_length = 0.5
		var y: Vector3 = e["n"]
		var z: Vector3 = -e["up"]   # the image's top is local -Z
		decal.transform = Transform3D(Basis(y.cross(z), y, z), (e["pos"] + y * minf(depth, DEPTH_IN) * 0.25) * INCHES_TO_METERS)
		add_child(decal)
