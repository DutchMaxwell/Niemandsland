class_name BoardgenDressRules
extends RefCounted
## The honesty rules of the ruin-town dressing (PLAN_RUINTOWN_DRESSING, R1-R5 as plain arithmetic): the dressing never hides a walkable cell, never suggests a surface that is not there. The grid is the truth;
## a placement {module, xf (Transform3D, metres, board space), cls} is checked against it with the numbers its manifest module declares (aabb_in, proud_in per height band, tags, family, role). Pure data, headless.
## Everything is in board inches, origin at the board centre. A model standing on a walkable cell needs the column above its top free: FLAT (0.08) of anything, then nothing up to CLEAR (2.0), except the
## edge strip of an edge that drops (R4); above CLEAR only an overhang (R2). R3 = the drawn face sits 0..0.2 inside the collider face. R5 = the ladder zones carry only ladders and plain faces.
## This file grew in three steps: 5a the grid helpers and the constants, 5b violations() for R1 / R2 / R4, 5c R3 (the face sits 0..0.2 in inside the collider face, lean <= 1.5 degrees) and R5 (the ladder zones).

const IN_M := 0.0254
const FLAT := 0.08
const CLEAR := 2.0
const OVERHANG := 0.35
const REACH := 0.2
const EDGE := 0.4
const PARAPET := 0.7
const SOFT_VEG := 0.4   # soft vegetation (tag soft_veg) up to this high is no obstacle on the ground (R1 exception)
const LADDER_GAP := 0.9
const LEAN_MAX := 1.5
const TOL := 0.02   # how far a piece may poke over a limit before it counts
const FACES := ["house_panel", "ruin_face", "twall_face", "tower_face"]
const DIRS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]   # N, E, S, W


## The height of the surface a cell presents (a tall tower 12, a roofed house 2.5, else its level); off the board 0.
static func top_in(layout: Dictionary, x: int, z: int) -> float:
	if x < 0 or z < 0 or x >= int(layout["nx"]) or z >= int(layout["nz"]):
		return 0.0
	var c: Dictionary = layout["cells"][z * int(layout["nx"]) + x]
	return float(layout.get("tower_in", 12.0)) if c["lot_kind"] == "Tower" else BoardgenGreybox.SOLID_IN if c["lot_kind"] == "Roofed" else float(layout["level_in"][int(c["level"])])


## Whether a model can stand on cell `i`: not a roofed house, not a tall tower, not a solid landmark's footprint.
static func walkable(layout: Dictionary, i: int) -> bool:
	var nx := int(layout["nx"])
	var x := i % nx
	var z := floori(i / float(nx))
	for lm: Dictionary in layout["landmarks"]:
		if lm["solid"] and x >= int(lm["x"]) and x < int(lm["x"]) + int(lm["w"]) and z >= int(lm["z"]) and z < int(lm["z"]) + int(lm["h"]):
			return false
	return not ["Roofed", "Tower"].has(layout["cells"][i]["lot_kind"])


## The cells no clutter or prop may take: both cells of every ladder and every landmark footprint. {cell index: "ladder" | "landmark"}
static func kept_clear(layout: Dictionary) -> Dictionary:
	var out := {}
	for c: Dictionary in layout["connectors"]:
		out[int(c["low"])] = "ladder"
		out[int(c["high"])] = "ladder"
	for lm: Dictionary in layout["landmarks"]:
		for dz in int(lm["h"]):
			for dx in int(lm["w"]):
				out[(int(lm["z"]) + dz) * int(layout["nx"]) + int(lm["x"]) + dx] = "landmark"
	return out


## The transform of a face module: its origin on the face's start point moved `inset_in` INTO the mass (against `out`), x along the face, y up, z out; `lean_deg` tips the top outward (negative: inward).
static func face_xf(start_in: Vector3, along: Vector3, out: Vector3, inset_in: float, lean_deg: float) -> Transform3D:
	return Transform3D(Basis(along, Vector3.UP, out) * Basis(Vector3.RIGHT, deg_to_rad(lean_deg)), (start_in - out * inset_in) * IN_M)


## The R1-R5 breaks of a set of placements on a layout, one line per rule and placement ("R1 <cls> <module> at (x, z): ..."); empty = honest.
static func violations(layout: Dictionary, placements: Array, meta: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var nx := int(layout["nx"])
	var cell := float(layout["cell_in"])
	var org := Vector2(nx, int(layout["nz"])) * cell * -0.5
	var zones := _ladder_zones(layout)
	var kept := kept_clear(layout)
	for p: Dictionary in placements:
		var m: Dictionary = meta["modules"].get(p["module"], {})
		var xf: Transform3D = p["xf"]
		var at := "%s %s at (%.1f, %.1f)" % [p.get("cls", ""), p["module"], xf.origin.x / IN_M, xf.origin.z / IN_M]
		if m.is_empty():
			out.append("R0 unknown module " + at)
			continue
		var lo := _v(m["aabb_in"], 0)
		var hi := _v(m["aabb_in"], 1)
		var all := _rect(xf, lo, hi, lo.y, hi.y, hi.z)
		var seen := {}
		var found: Array[String] = []
		if not (m["tags"] as Array).has("ladder") and not (FACES.has(m["family"]) and ["plain", "foot"].has(m["role"])):
			for zr: Rect2 in zones:
				var ov := zr.intersection(all)
				if ov.size.x > TOL and ov.size.y > TOL:
					found.append("R5 in a ladder's strip")
		var lean := rad_to_deg(xf.basis.y.normalized().angle_to(Vector3.UP))
		if lean > LEAN_MAX + 0.05:
			found.append("R3 leans %.2f degrees" % lean)
		if FACES.has(m["family"]):
			var o := Vector2(xf.basis.z.x, xf.basis.z.z).normalized()
			var mid3 := xf * (Vector3(float(m["len_in"]) * 0.5, 0.0, 0.0) * IN_M) / IN_M
			var mid := Vector2(mid3.x, mid3.z)
			var axis := 0 if absf(o.x) > absf(o.y) else 1
			var inside := floori((mid[axis] - o[axis] * 0.5 - org[axis]) / cell)   # the cell the face belongs to, along its axis
			var inset := (org[axis] + (inside + (1 if o[axis] > 0.0 else 0)) * cell - mid[axis]) * signf(o[axis])
			if inset < -TOL or inset > REACH + TOL:
				found.append("R3 sits %.2f in inside the collider face" % inset)
		for cz in range(maxi(floori((all.position.y - org.y) / cell), 0), mini(floori((all.end.y - org.y) / cell), int(layout["nz"]) - 1) + 1):
			for cx in range(maxi(floori((all.position.x - org.x) / cell), 0), mini(floori((all.end.x - org.x) / cell), nx - 1) + 1):
				if (m["tags"] as Array).has("soft_veg") and kept.has(cz * nx + cx) and all.intersection(Rect2(org + Vector2(cx, cz) * cell, Vector2(cell, cell))).size.x > TOL:
					found.append("R1 soft vegetation in a kept-clear cell (ladder or landmark)")
				if walkable(layout, cz * nx + cx):
					found.append(_air(layout, m, xf, cx, cz))
		for f in found:
			if f != "" and not seen.has(f.substr(0, 2)):
				seen[f.substr(0, 2)] = true
				out.append("%s %s" % [f.substr(0, 2), at + f.substr(2)])
	return out


## R1 / R2 / R4 for one placement over one walkable cell: the first break as "Rn: why", or "".
static func _air(layout: Dictionary, m: Dictionary, xf: Transform3D, cx: int, cz: int) -> String:
	var tags: Array = m["tags"]
	var lo := _v(m["aabb_in"], 0)
	var hi := _v(m["aabb_in"], 1)
	var cell := float(layout["cell_in"])
	var org := Vector2(layout["nx"], layout["nz"]) * cell * -0.5
	var cr := Rect2(org + Vector2(cx, cz) * cell, Vector2(cell, cell))
	var top := top_in(layout, cx, cz)
	var oy := xf.origin.y / IN_M
	var sy := maxf(xf.basis.y.y, 0.01)
	if tags.has("soft_veg") and top <= 0.0:   # no collider, no cover: on the ground a tuft is no obstacle up to SOFT_VEG (a tier top keeps R4)
		return "" if oy + hi.y * sy - top <= SOFT_VEG + TOL else "R1: soft vegetation higher than %.1f in" % SOFT_VEG
	if tags.has("R1_exception") or ((tags.has("bulky_ok") or tags.has("terrain_or_solid_only")) and _terrain(layout, cz * int(layout["nx"]) + cx)):
		return ""
	if tags.has("R4_gable") and top > 0.0:
		return "" if -lo.z * xf.basis.z.length() <= 0.3 + TOL and hi.y * sy <= 2.6 + TOL else "R4: a ruin gable over 0.3 in thick or 2.6 in high"
	for zone in 2:
		var y0 := maxf(lo.y, (top + (FLAT if zone == 0 else CLEAR) - oy) / sy)
		var y1 := minf(hi.y, (top + CLEAR - oy) / sy if zone == 0 else INF)
		if y1 - y0 < 0.001:
			continue
		var r := _rect(xf, lo, hi, y0, y1, float(m["proud_in"]["low" if zone == 0 else "high"])).intersection(cr)
		if r.size.x <= TOL or r.size.y <= TOL:
			continue
		var ok := false   # the part over this cell lies within OVERHANG of a taller footprint (above CLEAR) or within EDGE of a lower neighbour (the edge strip)
		for k in 9:
			var nb := Vector2i(cx + k % 3 - 1, cz + floori(k / 3.0) - 1)
			var nt := top_in(layout, nb.x, nb.y)
			var inside := nb.x >= 0 and nb.y >= 0 and nb.x < int(layout["nx"]) and nb.y < int(layout["nz"])
			var rises := inside and (nt > top or not walkable(layout, nb.y * int(layout["nx"]) + nb.x))
			if nb != Vector2i(cx, cz) and (rises if zone == 1 else nt < top) and Rect2(org + Vector2(nb) * cell, Vector2(cell, cell)).grow((OVERHANG if zone == 1 else EDGE) + TOL).encloses(r):
				ok = true
				break
		if zone == 1 and not ok:
			return "R2: reaches over walkable cell (%d, %d) further than %.2f in from a taller footprint" % [cx, cz, OVERHANG]
		if zone == 0 and top <= 0.0:
			return "R1: stands in walkable cell (%d, %d) between %.2f and %.0f in" % [cx, cz, FLAT, CLEAR]
		if zone == 0 and (not ok or oy + hi.y * sy - top > PARAPET + TOL):
			return "R4: over walkable tier cell (%d, %d) outside the %.1f in edge strip or above %.1f in" % [cx, cz, EDGE, PARAPET]
	return ""


## Cells that are terrain in the rules (garden plots, ruin yards) - bulky pieces may stand there.
static func _terrain(layout: Dictionary, i: int) -> bool:
	var c: Dictionary = layout["cells"][i]
	return c["lot_kind"] == "Rough" or (c["lot_kind"] == "Terrace" and int(c["level"]) == 0 and not c["street"])


## The strip every ladder keeps: LADDER_GAP beyond the ladder's half width to each side, from the top edge's EDGE strip over the wall face to the foot. [Rect2], board inches.
static func _ladder_zones(layout: Dictionary) -> Array[Rect2]:
	var out: Array[Rect2] = []
	var org := Vector2(layout["nx"], layout["nz"]) * float(layout["cell_in"]) * -0.5
	for c: Dictionary in layout["connectors"]:
		var e := Vector2(c["edge_in"][0], c["edge_in"][1]) + org
		var away := Vector2(Vector2i(c["low_xz"][0], c["low_xz"][1]) - Vector2i(c["high_xz"][0], c["high_xz"][1]))
		var side := Vector2(away.y, away.x)
		out.append(Rect2(e - away * EDGE - side * (0.5 + LADDER_GAP), Vector2.ZERO).expand(e + away * (0.5 + LADDER_GAP) + side * (0.5 + LADDER_GAP)))
	return out


static func _v(a: Array, k: int) -> Vector3:
	return Vector3(float(a[k][0]), float(a[k][1]), float(a[k][2]))


## The XZ rect (board inches) of a module's part between local heights y0 and y1, cut at `reach` along its local +z.
static func _rect(xf: Transform3D, lo: Vector3, hi: Vector3, y0: float, y1: float, reach: float) -> Rect2:
	var r := Rect2()
	for k in 8:
		var q := xf * (Vector3(hi.x if k & 1 else lo.x, y1 if k & 2 else y0, reach if k & 4 else lo.z) * IN_M) / IN_M
		r = Rect2(q.x, q.z, 0.0, 0.0) if k == 0 else r.expand(Vector2(q.x, q.z))
	return r
