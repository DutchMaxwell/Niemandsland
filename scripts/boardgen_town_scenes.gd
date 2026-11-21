class_name BoardgenTownScenes
extends RefCounted
## STORY SCENES of the ruin town (plan PLAN_RUINTOWN_GRIT S1, maintainer: "where is the life?"): 5-7 scenes per board, each answering "what happened here on the last day?", built from
## the EXISTING kit modules as a readable CLUSTER of 6-12 pieces round one hero piece, sized to read at the play camera (a 6 in run of wall strip where two cells allow, else 3 in): a toppled
## cart with its wheel, sacks and barrels spilled along the street edge; an abandoned market stall with its crates; the remains of a barricade (a cart, crates and barrels pushed into the
## strip); a cooper's store; and per half one yard scene - a midden or a burnt house's yard with its beams. Pure data: plan(layout) = {items: {module: [{xf, colour}]}, reserved: {cell index:
## true}, scenes: [{kind, cell, half, at, into, span}]} in the format of BoardgenTownClutter.
## THE LOOK MUST NOT LIE: every solid piece stands in the 0.75 in strip of a wall face (its origin on the face, +z away from it) or in a yard; on open ground only FLAT pieces (<= 0.08 in)
## fan out, at most 3 in; never on a ladder end, a landmark, a pool or a garden plot; never the same kind twice in a half; 6 in apart. The halves draw their own scenes (seed, half).

const STRIP_KINDS := ["cart", "stall", "barricade", "back"]
const YARD_KINDS := ["midden", "burnt", "table"]
## The solid pieces of each strip scene along a 6 in run of wall strip: [module, along (inches from the run's start), load] - the HERO first (kit batch A7, 2.2-2.9 in long: it reads at the
## play camera), its load / cloth a second module at the same origin. A 3 in run keeps the hero (moved along to fit its cell edge) and drops what does not fit. `back` (behind the houses:
## woodpile, hay, a trough) draws one of BACK_PAIRS.
const STRIP_SCENES := {
	"cart": [["cart_toppled", 1.55, "cart_toppled_load"], ["sack_pile", 3.7], ["barrel_broken", 4.6], ["crate", 5.5]],
	"stall": [["stall_collapsed", 1.5, "stall_collapsed_cloth"], ["crate", 3.35], ["crate_broken", 4.1], ["bucket", 4.85], ["crate", 5.5]],
	"barricade": [["barricade", 1.55], ["barrel", 3.4], ["crate_broken", 4.2], ["barrel_broken", 5.0]],
}
const BACK_PAIRS := [[["woodpile_block", 1.55], ["hay_heap", 4.45]], [["hay_heap", 1.4], ["trough_used", 4.3]], [["woodpile_block", 1.55], ["trough_used", 4.3]]]
## The extent along the wall (min, max inches off the origin) of the pieces that have none in BoardgenTownClutter.STRIP: the A7 heroes (from their build bounds).
const EXTRA_SPAN := {"cart_toppled": Vector2(-1.45, 1.38), "handcart": Vector2(-1.41, 0.80), "stall_collapsed": Vector2(-1.30, 1.37), "barricade": Vector2(-1.41, 1.42),
	"woodpile_block": Vector2(-1.38, 1.22), "hay_heap": Vector2(-1.12, 1.15), "trough_used": Vector2(-0.81, 0.81), "table_overturned": Vector2(-1.43, 1.43)}
## The flat spill in front: [module, along, out] inches (<= 0.08 in high, out <= 2.9).
const FLAT_SPILL := {
	"cart": [["cloth_flat", 1.0, 1.0], ["debris_flat_a", 2.2, 1.6], ["splinters_flat", 3.3, 1.1], ["debris_flat_b", 4.4, 2.0], ["cloth_flat", 5.2, 1.4]],
	"stall": [["cloth_flat", 1.2, 1.1], ["splinters_flat", 2.0, 1.6], ["debris_flat_a", 3.6, 1.2], ["cloth_flat", 4.5, 1.8]],
	"barricade": [["splinters_flat", 1.0, 1.2], ["splinters_flat", 2.6, 1.8], ["debris_flat_b", 3.9, 1.3], ["splinters_flat", 4.8, 2.2]],
	"back": [["debris_flat_b", 2.9, 1.1], ["weeds_flat", 5.0, 1.3]],
}
## Yard scenes round the yard cell's middle: [module, x, z, load] inches.
const YARD_SCENES := {
	"midden": [["rubble_heap_a", 0.0, 0.0], ["sack_pile", 0.9, -0.5], ["barrel_broken", -0.9, 0.4], ["crate_broken", 0.6, 0.8], ["weeds_flat", -0.5, -0.8], ["debris_flat_b", 0.9, 0.3],
		["cloth_flat", -0.2, 0.9], ["debris_flat_a", -1.0, -0.3]],
	"burnt": [["rubble_heap_b", 0.0, 0.0], ["beam_end", 0.8, -0.3], ["beam_end", -0.7, 0.6], ["woodpile", 0.4, 0.9], ["splinters_flat", -0.7, 0.4], ["splinters_flat", 1.0, 0.6],
		["debris_flat_a", 0.2, -0.9]],
	"table": [["table_overturned", 0.0, -0.4, "table_overturned_load"], ["crate_broken", 0.9, 0.85], ["cloth_flat", -0.7, 0.8], ["debris_flat_a", 0.3, 1.0]],
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
	var occupied := _occupied(layout)
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
		if not yards.is_empty():
			var y: int = yards[0]
			var kind: String = YARD_KINDS[rng.randi_range(0, YARD_KINDS.size() - 1)]
			var at := origin + (Vector2(y % nx, y / nx) + Vector2(0.5, 0.5)) * cell_in
			_yard_scene(out, kind, at, rng, layout)
			out["reserved"][y] = true
			out["scenes"].append({"kind": kind, "cell": y, "half": half, "at": at, "into": Vector2.ZERO, "span": 3.0})
			anchors.append(at)
			placed += 1
		for kind: String in kinds:
			if placed >= want:
				break
			var best: Array = []
			var best_rank := -1
			for s: Array in spots:   # the best spot for this kind: its preferred place (a lane mouth, a gate, the square, behind a house), then a two-cell run, then the shuffle
				var rank := _rank(kind, s, layout) * 2 + (1 if _pair(s, spot_set, nx) and not used.has(int(s[0]) + (1 if Vector2i(s[1]).x == 0 else nx)) else 0)
				if rank <= best_rank or used.has(int(s[0])):
					continue
				var fit := _run(s, spot_set, used, layout, origin)
				if not anchors.all(func(p: Vector2) -> bool: return p.distance_to(fit["mid"]) >= MIN_APART_IN) or _blocked(fit, occupied):
					continue
				best = s
				best_rank = rank
			if best.is_empty() or _rank(kind, best, layout) < 0:
				continue
			var run := _run(best, spot_set, used, layout, origin)
			_strip_scene(out, kind, run["start"], run["along"], best[1], run["span"], flight, layout, clear, rng)
			for c: int in run["cells"]:
				out["reserved"][c] = true
				used[c] = true
			out["scenes"].append({"kind": kind, "cell": best[0], "half": half, "at": run["mid"], "into": Vector2(-best[1].x, -best[1].y), "span": run["span"]})
			anchors.append(run["mid"])
			placed += 1
	return out


## How well a strip spot suits a scene kind (-1 = never): a cart or a barricade at a lane mouth or a gate of the wall (the barricade in the wall strip there, pushed aside, the lane open),
## a stall on a street - best on the square's edge -, the woodpile / hay / trough BEHIND a house (fronts carry trade, backs carry waste).
static func _rank(kind: String, s: Array, layout: Dictionary) -> int:
	var nx: int = layout["nx"]
	var i: int = s[0]
	var cd: Dictionary = layout["cells"][i]
	var street: bool = cd["street"]
	match kind:
		"cart":
			return 2 if _mouth(layout, i) else (1 if street else 0)
		"barricade":
			return 3 if _gate(layout, i) else (2 if _mouth(layout, i) else (1 if street else 0))
		"stall":
			if not street:
				return -1
			return 2 if absf(i % nx - 7.5) <= 2.5 and absf(i / nx - 7.5) <= 3.5 else 1
		"back":
			return 0 if street else 2
	return 0


## A gate of the city wall: a street cell in a column of wall cells (as BoardgenTownDressing.lanterns finds them).
static func _gate(layout: Dictionary, i: int) -> bool:
	var nx: int = layout["nx"]
	var cd: Dictionary = layout["cells"][i]
	if not cd["street"]:
		return false
	var n := 0
	for c: Dictionary in layout["cells"]:
		if c["x"] == cd["x"] and c["lot_kind"] == "Wall" and int(c["level"]) >= 1:
			n += 1
	return n >= 5 and i % nx == int(cd["x"])


## A lane mouth: a street cell where three or more streets meet (a lane runs into a wider street or the square).
static func _mouth(layout: Dictionary, i: int) -> bool:
	var nx: int = layout["nx"]
	var nz: int = layout["nz"]
	if not layout["cells"][i]["street"]:
		return false
	var n := 0
	for d: Vector2i in DIRS:
		var c := Vector2i(i % nx, i / nx) + d
		if c.x >= 0 and c.y >= 0 and c.x < nx and c.y < nz and layout["cells"][c.y * nx + c.x]["street"] and int(layout["cells"][c.y * nx + c.x]["level"]) == 0:
			n += 1
	return n >= 3


## The run of wall strip a spot gives: {start, along, span (6 or 3 in), mid, cells}.
static func _run(s: Array, spot_set: Dictionary, used: Dictionary, layout: Dictionary, origin: Vector2) -> Dictionary:
	var nx: int = layout["nx"]
	var cell_in := float(layout["cell_in"])
	var i: int = s[0]
	var d: Vector2i = s[1]
	var along_v := Vector2i(1, 0) if d.x == 0 else Vector2i(0, 1)
	var j := i + along_v.y * nx + along_v.x
	var two := _pair(s, spot_set, nx) and not used.has(j)
	var span := 6.0 if two else 3.0
	var lo := origin + Vector2(i % nx, i / nx) * cell_in
	var start := Vector2(lo.x, lo.y if d.y < 0 else lo.y + cell_in) if d.x == 0 else Vector2(lo.x if d.x < 0 else lo.x + cell_in, lo.y)
	return {"start": start, "along": Vector2(along_v), "span": span, "mid": start + Vector2(along_v) * span * 0.5, "cells": [i, j] if two else [i], "into": Vector2(-d.x, -d.y)}


## The points (board inches) a scene's run must keep clear: every ladder's foot on its wall face, every lamp post, the stalls / braziers / spouts of the square and the walls, the
## buttresses and rubble spills of the city wall.
static func _occupied(layout: Dictionary) -> Array[Vector2]:
	var pts: Array[Vector2] = []
	for l: Dictionary in BoardgenTownDressing.lanterns(layout):
		pts.append(l["at"])
	var origin := Vector2(layout["nx"], layout["nz"]) * float(layout["cell_in"]) * -0.5
	for c: Dictionary in layout["connectors"]:
		if c.has("edge_in"):   # the ladder's foot on its wall face (as BoardgenGreybox.ladder_kit_plan puts it)
			pts.append(Vector2(c["edge_in"][0], c["edge_in"][1]) + origin)
	var square := BoardgenTownClutter.wall_feet(layout)   # (the wall's buttresses and rubble spills too)
	BoardgenTownClutter._square_and_walls(layout, square)
	for m in ["stall_frame", "stall_frame_ruined", "brazier", "pool_spout", "wall_rubble_spill", "wall_buttress_a", "wall_buttress_b"]:
		for it: Dictionary in square.get(m, []):
			var o: Vector3 = (it["xf"] as Transform3D).origin / BoardgenTownClutter.INCHES_TO_METERS
			pts.append(Vector2(o.x, o.z))
	return pts


## True when a point of `occupied` lies in the run's strip (its span plus 0.9 in at each end - a lamp post right at a hero's end crowded it -, 1.2 in out from the face).
static func _blocked(run: Dictionary, occupied: Array[Vector2]) -> bool:
	for p: Vector2 in occupied:
		var rel: Vector2 = p - run["start"]
		var a: float = rel.dot(run["along"])
		var o: float = rel.dot(run["into"])
		if a > -0.9 and a < float(run["span"]) + 0.9 and o > -0.3 and o < 1.2:
			return true
	return false


## Is the next cell along the wall (+x for a north / south face, +z for an east / west one) a free spot on the same face too?
static func _pair(s: Array, spot_set: Dictionary, nx: int) -> bool:
	var i: int = s[0]
	var d: Vector2i = s[1]
	if d.x == 0 and i % nx == nx - 1:
		return false
	return spot_set.has("%d/%s" % [i + (1 if d.x == 0 else nx), d])


## A strip scene on the wall face from `start` along `along` for `span` inches (the wall lies in direction `d` of its cells): the solid pieces on the face (+z away from it) where their
## extent fits the run; the flat spill in front, leaning the way of the story's flight, only on open ground.
static func _strip_scene(out: Dictionary, kind: String, start: Vector2, along: Vector2, d: Vector2i, span: float, flight: Vector2, layout: Dictionary, clear: Dictionary,
		rng: RandomNumberGenerator) -> void:
	var into := Vector2(-d.x, -d.y)
	var yaw := atan2(-float(d.x), -float(d.y))
	var local_x := Vector2(cos(yaw), -sin(yaw))   # a piece's local +x on the board (Basis(UP, yaw) turns +x to (cos, -sin))
	var flip := 1.0 if local_x.dot(along) > 0.0 else -1.0
	var pieces: Array = BACK_PAIRS[rng.randi_range(0, BACK_PAIRS.size() - 1)] if kind == "back" else STRIP_SCENES[kind]
	var hand := kind == "cart" and rng.randf() < 0.4   # a handcart instead of the farm cart
	for k in pieces.size():
		var piece: Array = pieces[k]
		var m: String = "handcart" if hand and piece[0] == "cart_toppled" else piece[0]
		var a: float = piece[1]
		var ext: Vector2 = BoardgenTownClutter.STRIP.get(m, EXTRA_SPAN.get(m, Vector2(-0.3, 0.3)))
		var lo_rel := ext.x if flip > 0.0 else -ext.y
		var hi_rel := ext.y if flip > 0.0 else -ext.x
		if k == 0:
			a = clampf(a, 0.06 - lo_rel, minf(span, 3.0) - 0.06 - hi_rel)   # the hero always fits its first cell edge
		if a + lo_rel < 0.059 or a + hi_rel > span - 0.059:
			continue
		var p: Vector2 = start + along * a
		BoardgenTownClutter._add(out["items"], m, BoardgenTownClutter._item(yaw, Vector3(p.x, 0.0, p.y)))
		if piece.size() > 2:
			BoardgenTownClutter._add(out["items"], ("handcart_load" if m == "handcart" else String(piece[2])), BoardgenTownClutter._item(yaw, Vector3(p.x, 0.0, p.y)))
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
	if kind == "table":
		turn = PI * 0.5 * rng.randi_range(0, 3) + rng.randf_range(-0.06, 0.06)   # the 2.9 in table lies square in its 3 in yard cell
	var c_in := float(layout["cell_in"])
	var cell := (at / c_in).floor()
	for piece: Array in YARD_SCENES[kind]:
		var o := Vector2(float(piece[1]), float(piece[2])).rotated(turn)
		var p := at + o
		if (p / c_in).floor() != cell:
			continue
		var yaw: float = -turn if piece.size() > 3 else turn + o.x   # (a hero's local frame turns with the scene: Vector2.rotated(t) is Basis(UP, -t) on the board)
		BoardgenTownClutter._add(out["items"], piece[0], BoardgenTownClutter._item(yaw, Vector3(p.x, 0.0, p.y)))
		if piece.size() > 3:
			BoardgenTownClutter._add(out["items"], piece[3], BoardgenTownClutter._item(yaw, Vector3(p.x, 0.0, p.y)))


static func _shuffle(a: Array, rng: RandomNumberGenerator) -> void:
	for k in a.size():
		var j := rng.randi_range(k, a.size() - 1)
		var t: Variant = a[k]
		a[k] = a[j]
		a[j] = t
