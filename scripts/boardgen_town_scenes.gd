class_name BoardgenTownScenes
extends RefCounted
## STORY SCENES of the ruin town (plan PLAN_RUINTOWN_GRIT S1, maintainer: "where is the life?"): 5-7 scenes per board, each answering "what happened here on the last day?", built from
## the EXISTING kit modules as a readable CLUSTER of 6-12 pieces round one hero piece, sized to read at the play camera (a 6 in run of wall strip where two cells allow, else 3 in): a toppled
## cart with its wheel, sacks and barrels spilled along the street edge; an abandoned market stall with its crates; the remains of a barricade (a cart, crates and barrels pushed into the
## strip); a cooper's store; and per half one yard scene - a midden or a burnt house's yard with its beams. Pure data: plan(layout) = {items: {module: [{xf, colour}]}, reserved: {cell index:
## true}, scenes: [{kind, cell, half, at, into, span}]} in the format of BoardgenTownClutter.
## THE LOOK MUST NOT LIE: every solid piece stands in the 0.75 in strip of a wall face (its origin on the face, +z away from it) or in a yard; on open ground only FLAT pieces (<= 0.08 in)
## fan out, at most 3 in; never on a ladder end, a landmark, a pool or a garden plot; never the same kind twice in a half; 6 in apart. The halves draw their own scenes (seed, half).

const STRIP_KINDS := ["cart", "stall", "barricade", "store"]
const YARD_KINDS := ["midden", "burnt"]
## The solid pieces of each strip scene along a 6 in run of wall strip: [module, along (inches from the run's start)]. A 3 in run keeps the pieces that fit (STRIP extents).
const STRIP_SCENES := {
	"cart": [["cart_wreck", 1.6], ["loose_wheel", 2.75], ["sack_pile", 3.7], ["barrel_broken", 4.75], ["crate", 5.65]],
	"stall": [["stall_frame_ruined", 1.5], ["stall_awning_ruined", 1.5], ["crate", 3.3], ["crate", 3.85], ["crate_broken", 4.6], ["bucket", 5.4]],
	"barricade": [["cart_wreck", 1.6], ["crate_broken", 2.75], ["barrel", 3.55], ["barrel_broken", 4.3], ["woodpile", 5.3]],
	"store": [["barrel", 0.5], ["barrel", 1.1], ["barrel", 1.7], ["trough", 2.75], ["barrel", 3.8], ["barrel", 4.4], ["bucket", 5.0], ["crate", 5.5]],
}
## The extent along the wall of the pieces that have none in BoardgenTownClutter.STRIP (the stall frame and its awning).
const EXTRA_SPAN := {"stall_frame_ruined": Vector2(-1.2, 1.2), "stall_awning_ruined": Vector2(-1.2, 1.2)}
## The flat spill in front: [module, along, out] inches (<= 0.08 in high, out <= 2.9).
const FLAT_SPILL := {
	"cart": [["cloth_flat", 1.0, 1.0], ["debris_flat_a", 2.2, 1.6], ["splinters_flat", 3.3, 1.1], ["debris_flat_b", 4.4, 2.0], ["cloth_flat", 5.2, 1.4]],
	"stall": [["cloth_flat", 1.2, 1.0], ["splinters_flat", 2.0, 1.6], ["debris_flat_a", 3.6, 1.2], ["cloth_flat", 4.5, 1.8]],
	"barricade": [["splinters_flat", 1.0, 1.2], ["splinters_flat", 2.6, 1.8], ["debris_flat_b", 3.9, 1.3], ["splinters_flat", 4.8, 2.2]],
	"store": [["debris_flat_b", 2.5, 1.2]],
}
## Yard scenes round the yard cell's middle: [module, x, z] inches.
const YARD_SCENES := {
	"midden": [["rubble_heap_a", 0.0, 0.0], ["sack_pile", 0.9, -0.5], ["barrel_broken", -0.9, 0.4], ["crate_broken", 0.6, 0.8], ["weeds_flat", -0.5, -0.8], ["debris_flat_b", 0.9, 0.3],
		["cloth_flat", -0.2, 0.9], ["debris_flat_a", -1.0, -0.3]],
	"burnt": [["rubble_heap_b", 0.0, 0.0], ["beam_end", 0.8, -0.3], ["beam_end", -0.7, 0.6], ["woodpile", 0.4, 0.9], ["splinters_flat", -0.7, 0.4], ["splinters_flat", 1.0, 0.6],
		["debris_flat_a", 0.2, -0.9]],
}
const FLAT_MODULES := ["cloth_flat", "debris_flat_a", "debris_flat_b", "splinters_flat", "weeds_flat"]
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
	var spot_set := {}   # "i/d" -> true: an open cell with a free wall face in direction d and open ground in front
	var strip_spots: Array = [[], []]
	var yard_spots: Array = [[], []]
	for cd: Dictionary in cells:
		var i: int = cd["z"] * nx + cd["x"]
		if int(cd["level"]) != 0 or clear.has(i) or ["Hazard", "Rough", "Roofed"].has(cd["lot_kind"]):
			continue
		var half := 1 if int(cd["z"]) >= nz / 2 else 0
		if cd["lot_kind"] == "Terrace" and not cd["street"]:
			yard_spots[half].append(i)
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
				continue
			spot_set["%d/%s" % [i, d]] = true
			strip_spots[half].append([i, d])
	var out := {"items": {}, "reserved": {}, "scenes": []}
	var tale := BoardgenTownDressing.story(int(layout.get("seed", 0)))
	var flight := -Vector2(tale.r, tale.g)   # the spill leans away from the fire
	var anchors: Array[Vector2] = []
	for half in 2:
		var rng := RandomNumberGenerator.new()
		rng.seed = int(layout.get("seed", 0)) * 7177 + 1009 * half + 3
		var kinds: Array = STRIP_KINDS.duplicate()
		_shuffle(kinds, rng)
		var want := 3 + (rng.randi_range(0, 1) if half == 0 else 0)   # 6-7 scenes a board
		var spots: Array = strip_spots[half].duplicate()
		_shuffle(spots, rng)
		var paired: Array = spots.filter(func(a: Array) -> bool: return _pair(a, spot_set, nx))   # two-cell runs first: they read at the play camera
		paired.append_array(spots.filter(func(a: Array) -> bool: return not _pair(a, spot_set, nx)))
		spots = paired
		var yards: Array = yard_spots[half].duplicate()
		_shuffle(yards, rng)
		var placed := 0
		var used := {}
		if not yards.is_empty():
			var y: int = yards[0]
			var kind: String = YARD_KINDS[rng.randi_range(0, 1)]
			var at := origin + (Vector2(y % nx, y / nx) + Vector2(0.5, 0.5)) * cell_in
			_yard_scene(out, kind, at, rng, layout)
			out["reserved"][y] = true
			out["scenes"].append({"kind": kind, "cell": y, "half": half, "at": at, "into": Vector2.ZERO, "span": 3.0})
			anchors.append(at)
			placed += 1
		for s: Array in spots:
			if placed >= want or kinds.is_empty():
				break
			var i: int = s[0]
			var d: Vector2i = s[1]
			var along_v := Vector2i(1, 0) if d.x == 0 else Vector2i(0, 1)
			var j := i + along_v.y * nx + along_v.x
			var two := _pair(s, spot_set, nx) and not used.has(j)
			var span := 6.0 if two else 3.0
			var lo := origin + Vector2(i % nx, i / nx) * cell_in
			var start := Vector2(lo.x, lo.y if d.y < 0 else lo.y + cell_in) if d.x == 0 else Vector2(lo.x if d.x < 0 else lo.x + cell_in, lo.y)
			var mid := start + Vector2(along_v) * span * 0.5
			if used.has(i) or not anchors.all(func(a: Vector2) -> bool: return a.distance_to(mid) >= MIN_APART_IN):
				continue
			var front: Dictionary = cells[(i / nx - d.y) * nx + i % nx - d.x]
			var pick := kinds.size() - 1
			while pick >= 0 and kinds[pick] == "stall" and not front["street"]:
				pick -= 1   # a stall trades onto a street (fronts carry trade)
			if pick < 0:
				continue
			var kind: String = kinds[pick]
			kinds.remove_at(pick)
			_strip_scene(out, kind, start, Vector2(along_v), d, span, flight, layout, clear)
			for c: int in ([i, j] if two else [i]):
				out["reserved"][c] = true
				used[c] = true
			out["scenes"].append({"kind": kind, "cell": i, "half": half, "at": mid, "into": Vector2(-d.x, -d.y), "span": span})
			anchors.append(mid)
			placed += 1
	return out


## Is the next cell along the wall (+x for a north / south face, +z for an east / west one) a free spot on the same face too?
static func _pair(s: Array, spot_set: Dictionary, nx: int) -> bool:
	var i: int = s[0]
	var d: Vector2i = s[1]
	if d.x == 0 and i % nx == nx - 1:
		return false
	return spot_set.has("%d/%s" % [i + (1 if d.x == 0 else nx), d])


## A strip scene on the wall face from `start` along `along` for `span` inches (the wall lies in direction `d` of its cells): the solid pieces on the face (+z away from it) where their
## extent fits the run; the flat spill in front, leaning the way of the story's flight, only on open ground.
static func _strip_scene(out: Dictionary, kind: String, start: Vector2, along: Vector2, d: Vector2i, span: float, flight: Vector2, layout: Dictionary, clear: Dictionary) -> void:
	var into := Vector2(-d.x, -d.y)
	var yaw := atan2(-float(d.x), -float(d.y))
	var local_x := Vector2(cos(yaw), -sin(yaw))   # a piece's local +x on the board (Basis(UP, yaw) turns +x to (cos, -sin))
	var flip := 1.0 if local_x.dot(along) > 0.0 else -1.0
	for piece: Array in STRIP_SCENES[kind]:
		var a: float = piece[1]
		var ext: Vector2 = BoardgenTownClutter.STRIP.get(piece[0], EXTRA_SPAN.get(piece[0], Vector2(-0.3, 0.3)))
		var lo := a + (ext.x if flip > 0.0 else -ext.y)
		var hi := a + (ext.y if flip > 0.0 else -ext.x)
		if lo < 0.06 or hi > span - 0.06:
			continue
		var p: Vector2 = start + along * a
		BoardgenTownClutter._add(out["items"], piece[0], BoardgenTownClutter._item(yaw, Vector3(p.x, 0.0, p.y)))
	var lean := 0.25 * signf(flight.dot(along))
	for k in FLAT_SPILL[kind].size():
		var f: Array = FLAT_SPILL[kind][k]
		if float(f[1]) > span - 0.3:
			continue
		var out_in: float = minf(float(f[2]), 2.9)
		var p: Vector2 = start + along * (float(f[1]) + lean * out_in) + into * out_in
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


## A yard scene round the yard cell's middle; a piece that would leave the yard cell is dropped.
static func _yard_scene(out: Dictionary, kind: String, at: Vector2, rng: RandomNumberGenerator, layout: Dictionary) -> void:
	var turn := rng.randf() * TAU
	var c_in := float(layout["cell_in"])
	var cell := (at / c_in).floor()
	for piece: Array in YARD_SCENES[kind]:
		var o := Vector2(float(piece[1]), float(piece[2])).rotated(turn)
		var p := at + o
		if (p / c_in).floor() != cell:
			continue
		BoardgenTownClutter._add(out["items"], piece[0], BoardgenTownClutter._item(turn + o.x, Vector3(p.x, 0.0, p.y)))


static func _shuffle(a: Array, rng: RandomNumberGenerator) -> void:
	for k in a.size():
		var j := rng.randi_range(k, a.size() - 1)
		var t: Variant = a[k]
		a[k] = a[j]
		a[j] = t
