class_name BoardgenTownScenes
extends RefCounted
## STORY SCENES of the ruin town (plan PLAN_RUINTOWN_GRIT S1, maintainer: "where is the life?"): 5-7 small scenes per board, each answering "what happened here on the last day?", built
## from the EXISTING kit modules: a toppled cart with its load spilled, an abandoned market stall, the remains of a barricade, a cooper's store, a midden behind a row, a burnt house's yard
## with its beams. Pure data: plan(layout) = {items: {module: [{xf, colour}]}, reserved: {cell index: true}, scenes: [{kind, cell, half, at}]} in the format of BoardgenTownClutter.
## THE LOOK MUST NOT LIE: every solid piece stands in the 0.75 in strip of a wall face (its origin on the face, +z away from it, kept inside the cell's edge) or in a yard; on open ground only
## FLAT pieces (<= 0.08 in) fan out, at most 3 in; never on a ladder end, a landmark, a pool or a garden plot; 2-3 scenes per half (+1 on the market square), never the same kind twice in a
## half, 6 in or more apart. The halves draw their own scenes (seed, half): the look need not mirror.

const STRIP_KINDS := ["cart", "stall", "barricade", "store"]
const YARD_KINDS := ["midden", "burnt"]
## The solid pieces of each strip scene: [module, along offset (inches, from the anchor along the wall)]
const STRIP_SCENES := {
	"cart": [["cart_wreck", 0.0], ["loose_wheel", 1.15]],
	"stall": [["stall_frame_ruined", 0.0], ["stall_awning_ruined", 0.0], ["crate_broken", 1.05], ["bucket", -1.0]],
	"barricade": [["crate_broken", -0.9], ["barrel_broken", 0.0], ["crate", 1.1]],
	"store": [["barrel", -0.75], ["barrel", -0.1], ["barrel", 0.55], ["bucket", 1.2]],
}
## The flat spill fanning onto the ground in front of each strip scene (<= 0.08 in high): [module, along, out] inches
const FLAT_SPILL := {
	"cart": [["cloth_flat", 0.4, 1.0], ["debris_flat_a", -0.6, 1.6], ["splinters_flat", 0.9, 2.2], ["debris_flat_b", 0.1, 2.8]],
	"stall": [["cloth_flat", -0.3, 1.1], ["splinters_flat", 0.6, 1.7], ["debris_flat_a", -0.8, 2.3]],
	"barricade": [["splinters_flat", -0.5, 1.0], ["splinters_flat", 0.6, 1.8], ["debris_flat_b", 0.0, 2.6]],
	"store": [["debris_flat_b", 0.5, 1.2]],
}
const YARD_SCENES := {
	"midden": [["rubble_heap_a", 0.0, 0.0], ["weeds_flat", 0.7, 0.5], ["debris_flat_b", -0.6, 0.6], ["cloth_flat", 0.3, -0.7]],
	"burnt": [["rubble_heap_b", 0.0, 0.0], ["beam_end", 0.8, -0.3], ["splinters_flat", -0.7, 0.4], ["debris_flat_a", 0.2, 0.9]],
}
const FLAT_MODULES := ["cloth_flat", "debris_flat_a", "debris_flat_b", "splinters_flat", "weeds_flat"]
const STRIP_ALONG := 1.5   # the anchor sits in the middle of the 3 in cell edge
const MIN_APART_IN := 6.0
const DIRS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]


static func plan(layout: Dictionary) -> Dictionary:
	var nx: int = layout["nx"]
	var nz: int = layout["nz"]
	var cell_in := float(layout["cell_in"])
	var origin := Vector2(nx, nz) * cell_in * -0.5
	var cells: Array = layout["cells"]
	var clear := BoardgenTownClutter._kept_clear(layout)
	var taken_faces := {}   # the wall faces the procedural strip props already use
	for b: Dictionary in BoardgenTownDressing.props(layout):
		if typeof(b.get("face")) == TYPE_VECTOR2I:
			var c: Vector2 = b["at"]
			taken_faces["%d/%d/%s" % [int(c.x), int(c.y), b["face"]]] = true
	var strip_spots: Array = [[], []]   # per half: [cell index, face dir]
	var yard_spots: Array = [[], []]
	for cd: Dictionary in cells:
		var i: int = cd["z"] * nx + cd["x"]
		if int(cd["level"]) != 0 or clear.has(i) or ["Hazard", "Rough", "Roofed"].has(cd["lot_kind"]):
			continue
		var half := 1 if int(cd["z"]) >= nz / 2 else 0
		if cd["lot_kind"] == "Terrace" and not cd["street"]:
			yard_spots[half].append([i, Vector2i.ZERO])
			continue
		if cd["lot_kind"] == "Wall":
			continue   # a breach is a passage
		for d: Vector2i in DIRS:
			var n := Vector2i(cd["x"], cd["z"]) + d
			var back := Vector2i(cd["x"], cd["z"]) - d
			if n.x < 0 or n.y < 0 or n.x >= nx or n.y >= nz or back.x < 0 or back.y < 0 or back.x >= nx or back.y >= nz:
				continue
			if int(cells[n.y * nx + n.x]["level"]) == 0 or taken_faces.has("%d/%d/%s" % [int(cd["x"]), int(cd["z"]), d]):
				continue
			var front: Dictionary = cells[back.y * nx + back.x]
			if int(front["level"]) != 0 or front["lot_kind"] == "Hazard":
				continue   # open ground in front of the scene, for its spill
			strip_spots[half].append([i, d])
	var out := {"items": {}, "reserved": {}, "scenes": []}
	var tale := BoardgenTownDressing.story(int(layout.get("seed", 0)))
	var flight := -Vector2(tale.r, tale.g)   # the spill runs away from the fire
	var anchors: Array[Vector2] = []
	for half in 2:
		var rng := RandomNumberGenerator.new()
		rng.seed = int(layout.get("seed", 0)) * 7177 + 1009 * half + 3
		var kinds: Array = STRIP_KINDS.duplicate()
		_shuffle(kinds, rng)
		var want := 3 + (rng.randi_range(0, 1) if half == 0 else 0)   # 6-7 scenes a board
		var spots: Array = strip_spots[half].duplicate()
		_shuffle(spots, rng)
		var yards: Array = yard_spots[half].duplicate()
		_shuffle(yards, rng)
		var placed := 0
		var used := {}
		if not yards.is_empty():   # one yard scene per half when the half has a yard: the waste goes to the back
			var y: Array = yards[0]
			var kind: String = YARD_KINDS[rng.randi_range(0, 1)]
			var at := origin + (Vector2(int(y[0]) % nx, int(y[0]) / nx) + Vector2(0.5, 0.5)) * cell_in
			if anchors.all(func(a: Vector2) -> bool: return a.distance_to(at) >= MIN_APART_IN):
				_yard_scene(out, kind, at, rng)
				out["reserved"][int(y[0])] = true
				out["scenes"].append({"kind": kind, "cell": int(y[0]), "half": half, "at": at})
				anchors.append(at)
				placed += 1
		for s: Array in spots:
			if placed >= want or kinds.is_empty():
				break
			var i: int = s[0]
			var d: Vector2i = s[1]
			var lo := origin + Vector2(i % nx, i / nx) * cell_in
			var wall_pt := Vector2(lo.x + STRIP_ALONG, lo.y if d.y < 0 else lo.y + cell_in) if d.x == 0 else Vector2(lo.x if d.x < 0 else lo.x + cell_in, lo.y + STRIP_ALONG)
			if used.has(i) or not anchors.all(func(a: Vector2) -> bool: return a.distance_to(wall_pt) >= MIN_APART_IN):
				continue
			var front: Dictionary = cells[(i / nx - d.y) * nx + i % nx - d.x]
			var pick := kinds.size() - 1
			while pick >= 0 and kinds[pick] == "stall" and not front["street"]:
				pick -= 1   # a stall trades onto a street (fronts carry trade)
			if pick < 0:
				continue
			var kind: String = kinds[pick]
			kinds.remove_at(pick)
			_strip_scene(out, kind, wall_pt, d, flight, layout, clear)
			out["reserved"][i] = true
			used[i] = true
			out["scenes"].append({"kind": kind, "cell": i, "half": half, "at": wall_pt})
			anchors.append(wall_pt)
			placed += 1
	return out


## A strip scene against the wall face at `wall_pt` (the wall lies in direction `d` of the cell): solid pieces on the face, +z away from it; the flat spill fans out in front, leaning the way
## of the story's flight.
static func _strip_scene(out: Dictionary, kind: String, wall_pt: Vector2, d: Vector2i, flight: Vector2, layout: Dictionary, clear: Dictionary) -> void:
	var into := Vector2(-d.x, -d.y)   # from the wall onto the open ground
	var along := Vector2(-into.y, into.x)
	var yaw := atan2(-float(d.x), -float(d.y))
	for piece: Array in STRIP_SCENES[kind]:
		var p: Vector2 = wall_pt + along * float(piece[1])
		BoardgenTownClutter._add(out["items"], piece[0], BoardgenTownClutter._item(yaw, Vector3(p.x, 0.0, p.y)))
	var lean := 0.35 * signf(flight.dot(along))
	for k in FLAT_SPILL[kind].size():
		var f: Array = FLAT_SPILL[kind][k]
		var out_in: float = minf(float(f[2]), 2.9)
		var p: Vector2 = wall_pt + along * (float(f[1]) + lean * out_in) + into * out_in
		if not _open_ground(layout, clear, p):
			continue   # a flat piece only on open level-0 ground: never on a raised cell, a pool, a plot, a ladder end or a landmark
		BoardgenTownClutter._add(out["items"], f[0], BoardgenTownClutter._item(yaw + 0.7 * k, Vector3(p.x, 0.0, p.y)))


static func _open_ground(layout: Dictionary, clear: Dictionary, p: Vector2) -> bool:
	var nx: int = layout["nx"]
	var nz: int = layout["nz"]
	var at := Vector2i(floori(p.x / float(layout["cell_in"]) + nx * 0.5), floori(p.y / float(layout["cell_in"]) + nz * 0.5))
	if at.x < 0 or at.y < 0 or at.x >= nx or at.y >= nz or clear.has(at.y * nx + at.x):
		return false
	var cd: Dictionary = layout["cells"][at.y * nx + at.x]
	return int(cd["level"]) == 0 and not ["Hazard", "Rough", "Roofed", "Wall"].has(cd["lot_kind"])


static func _yard_scene(out: Dictionary, kind: String, at: Vector2, rng: RandomNumberGenerator) -> void:
	var turn := rng.randf() * TAU
	for piece: Array in YARD_SCENES[kind]:
		var o := Vector2(float(piece[1]), float(piece[2])).rotated(turn)
		BoardgenTownClutter._add(out["items"], piece[0], BoardgenTownClutter._item(turn + o.x, Vector3(at.x + o.x, 0.0, at.y + o.y)))


static func _shuffle(a: Array, rng: RandomNumberGenerator) -> void:
	for k in a.size():
		var j := rng.randi_range(k, a.size() - 1)
		var t: Variant = a[k]
		a[k] = a[j]
		a[j] = t
