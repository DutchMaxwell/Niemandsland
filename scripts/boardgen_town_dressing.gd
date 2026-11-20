class_name BoardgenTownDressing
extends Node3D
## The look pieces of a ruin-town board that are not a flat box of the greybox plan: the tiled GABLE roofs of the intact (Roofed) houses
## (a prism mesh each, one MultiMesh), their brick chimneys (boxes in the greybox plan) and, later, the battlements of the wall. VISUAL ONLY: an
## intact house is the core's 2.5 in solid (CONTAINER) whatever the roof above it is, and nobody stands on a roof (no collider). The two
## halves of the board vary the pitch and the chimney end by a hash of the lot and its half, so a half turn does not look like its twin.

const INCHES_TO_METERS := 0.0254
const BODY_IN := 2.5   # the intact house's body: the core's solid height
const OVERHANG_IN := 0.3
const CHIMNEY_IN := 0.62
const MAX_LIGHTS := 8
const LANTERN_COLOUR := Color(1.0, 0.62, 0.30)


## A 0..1 hash of a lot id and the half of the board it stands in (0 = north, 1 = south), stable per layout.
static func _hash(lot_id: int, half: int, salt: int) -> float:
	return float(posmod((lot_id * 73856093) ^ (half * 19349663) ^ (salt * 83492791), 1000)) / 1000.0


## How an intact house is DRAWN differently from its collider (plan O3), per lot and half of the board: the drawn body is inset 0.06-0.14 in on every side (inward only), yawed so
## that no corner swings out of the lot's cells (the yaw is at most 3 degrees, and at most what the inset allows, so the drawn wall is never more than 0.2 in off the collider's face),
## its top (= its eaves) is 2.5 in +- 0.3, its stone plinth 0.3-0.6 in high. The collider and the class stay the core's 2.5 in solid; nothing here is a rule.
static func house_look(lot_id: int, half: int, size: Vector2) -> Dictionary:
	var inset := 0.06 + 0.08 * _hash(lot_id, half, 4)
	var room := minf(inset, 0.2 - inset)   # how far a corner may swing out of the inset body and still stay in its cells with a gap <= 0.2 in
	var yaw_max := minf(deg_to_rad(3.0), asin(room / (maxf(size.x, size.y) * 0.5)))
	return {"inset": inset, "yaw": (2.0 * _hash(lot_id, half, 5) - 1.0) * yaw_max, "top": BODY_IN + (_hash(lot_id, half, 6) - 0.5) * 0.6, "plinth": 0.3 + 0.3 * _hash(lot_id, half, 7)}


## The drawn bodies of the intact houses (ruined, walkable tiers are never touched): {lot, centre (Vector2, board inches), size (inset), yaw, top, plinth, half, front, jetty, storey}. A house
## with a street at its door ("front", from the frontage table) may carry a JETTY (plan O5): its upper storey (above `storey`, 1.5-1.9 in) overhangs the ground storey on the front face by `jetty`
## 0.15-0.2 in - a recess inside the house's own cells, never over ground a model could stand on. Pure data.
static func house_bodies(layout: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var cell_in := float(layout["cell_in"])
	var board := Vector2(layout["nx"], layout["nz"]) * cell_in
	var fronts := {}
	for f: Dictionary in frontage(layout):
		fronts[f["lot"]] = f["front"]
	for lot: Dictionary in layout["lots"]:
		if lot["kind"] != "Roofed":
			continue
		var size := Vector2(lot["w"], lot["h"]) * cell_in
		var centre := Vector2(lot["x"], lot["z"]) * cell_in + size * 0.5 - board * 0.5
		var half := 1 if centre.y > 0.0 else 0
		var look := house_look(lot["id"], half, size)
		var front: String = fronts.get(lot["id"], "")
		var jetty := (0.15 + 0.05 * _hash(lot["id"], half, 13)) if front != "" and _hash(lot["id"], half, 14) < 0.6 else 0.0
		out.append({"lot": lot["id"], "centre": centre, "size": size - Vector2.ONE * 2.0 * float(look["inset"]), "yaw": look["yaw"], "top": look["top"], "plinth": look["plinth"], "half": half,
			"front": front, "jetty": jetty, "storey": 1.5 + 0.4 * _hash(lot["id"], half, 15)})
	return out


## The boxes a drawn body is made of: one, or - with a jetty - the ground storey (below `storey`, its front face pulled back by `jetty`) and the upper storey (the whole body above it).
## {centre (Vector2, board inches, before the yaw is applied), size (Vector2), y0, y1}. Pure data.
static func house_parts(body: Dictionary) -> Array[Dictionary]:
	var upper := {"centre": body["centre"], "size": body["size"], "y0": 0.0, "y1": body["top"]}
	if body["jetty"] <= 0.0:
		return [upper]
	var pull: Vector2 = {"N": Vector2(0, 1), "S": Vector2(0, -1), "E": Vector2(-1, 0), "W": Vector2(1, 0)}[body["front"]]   # which way the ground storey's front face moves in
	var lower := {"centre": body["centre"] + (pull * float(body["jetty"]) * 0.5).rotated(-float(body["yaw"])), "size": body["size"] - pull.abs() * float(body["jetty"]), "y0": 0.0, "y1": body["storey"]}
	upper["y0"] = body["storey"]
	return [lower, upper]


## The roofs of the intact lots (plan O4), pure data: {lot, centre (Vector2, board inches), length, width (along / across the ridge), height, along_x, half, yaw, eaves, type, back, annex}.
## The ridge runs ALONG the street (eaves-on) or ACROSS it (gable-on) by the lot's hash, from the frontage (a lot with no street beside it keeps the long axis). The type is a gable, a
## hip (the ends slope too) or, for an eaves-on roof only, a catslide (the back slope runs down past the eaves; `back` = which side of the ridge is the back, -1 / +1). A lot of two or
## more cells may carry an ANNEX: its last cell at one end of the ridge gets its own, lower gable roof (`annex` true; the main roof is shorter by that cell). The yaw is the body's plus a skew
## of at most 2 degrees. VISUAL ONLY: the body below stays the core's 2.5 in solid.
static func roofs(layout: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var cell_in := float(layout["cell_in"])
	var board := Vector2(layout["nx"], layout["nz"]) * cell_in
	var fronts := {}
	for f: Dictionary in frontage(layout):
		fronts[f["lot"]] = f["front"]
	for lot: Dictionary in layout["lots"]:
		if lot["kind"] != "Roofed":
			continue
		var id: int = lot["id"]
		var size := Vector2(lot["w"], lot["h"]) * cell_in
		var centre := Vector2(lot["x"], lot["z"]) * cell_in + size * 0.5 - board * 0.5
		var half := 1 if centre.y > 0.0 else 0
		var front: String = fronts.get(id, "")
		var along_x := size.x > size.y or (size.x == size.y and _hash(id, half, 1) < 0.5)
		if front != "" and _hash(id, half, 8) < 0.7:
			along_x = front in ["N", "S"]   # eaves-on: the ridge parallels the street
		elif front != "":
			along_x = front in ["E", "W"]   # gable-on: the ridge points at it
		var run := size.x if along_x else size.y
		var across := size.y if along_x else size.x
		var look := house_look(id, half, size)
		var pick := _hash(id, half, 9)
		var eaves_on := front != "" and along_x == (front in ["N", "S"])
		var type := "gable" if pick < 0.45 or (pick >= 0.75 and not eaves_on) else ("hip" if pick < 0.75 else "catslide")
		var back := 1 if front in ["N", "W"] else -1   # the side of the ridge away from the street (+z / +x for a front on the north / west)
		var height := 1.5 + 1.2 * _hash(id, half, 2)
		var yaw: float = look["yaw"] + (2.0 * _hash(id, half, 10) - 1.0) * deg_to_rad(2.0)
		var roof := {"lot": id, "centre": centre, "length": run + 2.0 * OVERHANG_IN, "width": across + 2.0 * OVERHANG_IN, "height": height, "along_x": along_x, "half": half,
			"yaw": yaw, "eaves": look["top"], "type": type, "back": back, "annex": false}
		if run >= 2.0 * cell_in and _hash(id, half, 11) < 0.4:
			var end := 1.0 if _hash(id, half, 12) < 0.5 else -1.0
			var shift := Vector2(end, 0.0) if along_x else Vector2(0.0, end)
			var annex := roof.duplicate()
			annex.merge({"centre": centre + shift * (run * 0.5 - cell_in * 0.5), "length": cell_in + 2.0 * OVERHANG_IN, "height": height * 0.55, "type": "gable", "annex": true}, true)
			roof.merge({"centre": centre - shift * cell_in * 0.5, "length": run - cell_in + 2.0 * OVERHANG_IN}, true)
			out.append(annex)
		out.append(roof)
	return out


## A brick chimney on the ridge of every roof, at the end the lot's hash picks: boxes for the greybox plan ({lo, hi, kind, solid}).
static func chimneys(layout: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for r: Dictionary in roofs(layout).filter(func(r: Dictionary) -> bool: return not r["annex"]):
		var end_sign := 1.0 if _hash(r["lot"], r["half"], 3) < 0.5 else -1.0
		var offset: float = end_sign * (float(r["length"]) * 0.5 - 0.9)
		var centre: Vector2 = r["centre"] + (Vector2(offset, 0.0) if r["along_x"] else Vector2(0.0, offset))
		out.append({"lo": Vector3(centre.x - CHIMNEY_IN * 0.5, BODY_IN, centre.y - CHIMNEY_IN * 0.5),
			"hi": Vector3(centre.x + CHIMNEY_IN * 0.5, BODY_IN + float(r["height"]) + 0.9, centre.y + CHIMNEY_IN * 0.5), "kind": "brick", "solid": false})
	return out


## The battlements: merlons (0.7 x 0.7 x 0.4 in, three to a 3 in edge) round the open edges of every wall ridge and tower crown (a cell of the wall at
## 6 in or more, or any 9 in cell), inside the 0.4 in edge strip so the walkway keeps its width. Some are missing, more in the south half than in the north
## one (a broken battlement is a look; no merlon is cover the core knows). Boxes for the greybox plan ({lo, hi, kind, solid}).
static func merlons(layout: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var nx: int = layout["nx"]
	var nz: int = layout["nz"]
	var cell_in := float(layout["cell_in"])
	var origin := Vector2(nx, nz) * cell_in * -0.5
	for cd: Dictionary in layout["cells"]:
		var level: int = cd["level"]
		if level < 2 or (level == 2 and cd["lot_kind"] != "Wall"):
			continue
		var top: float = layout["level_in"][level]
		var half := 1 if cd["z"] >= nz / 2 else 0
		for side in 4:
			var d := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)][side] as Vector2i
			var at := Vector2i(cd["x"], cd["z"]) + d
			if at.x >= 0 and at.y >= 0 and at.x < nx and at.y < nz and int(layout["cells"][at.y * nx + at.x]["level"]) >= level:
				continue   # a neighbour as high: this edge is no open edge
			for i in 3:
				if _hash(cd["x"] * 16 + cd["z"], half, 10 + side * 3 + i) < (0.28 if half == 1 else 0.10):
					continue
				var lo := origin + Vector2(cd["x"], cd["z"]) * cell_in
				var t := 0.5 + float(i)
				var box_lo := Vector2(lo.x + t - 0.35, lo.y) if d.x == 0 else Vector2(lo.x, lo.y + t - 0.35)
				var box_hi := box_lo + (Vector2(0.7, 0.4) if d.x == 0 else Vector2(0.4, 0.7))
				if d.y == 1:
					box_lo.y += cell_in - 0.4
					box_hi.y += cell_in - 0.4
				if d.x == 1:
					box_lo.x += cell_in - 0.4
					box_hi.x += cell_in - 0.4
				out.append({"lo": Vector3(box_lo.x, top, box_lo.y), "hi": Vector3(box_hi.x, top + 0.7, box_hi.y), "kind": "wall", "solid": false, "merlon": true})
	return out


## Where the lanterns stand (board inches, {at, half}): a post at each corner of the market square and one at every gate of the wall, against the wall
## face (north side of the gate in the north half, south side in the south half), so nothing stands in the middle of a passage and nothing takes more than the 0.75 in strip.
static func lanterns(layout: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var nx: int = layout["nx"]
	var nz: int = layout["nz"]
	var cell_in := float(layout["cell_in"])
	var origin := Vector2(nx, nz) * cell_in * -0.5
	for corner in [Vector2(-5.5, -5.5), Vector2(5.5, -5.5), Vector2(-5.5, 5.5), Vector2(5.5, 5.5)]:
		out.append({"at": corner, "half": 1 if corner.y > 0.0 else 0})
	var per_column := {}   # a wall column is a column with a run of wall cells (a stray buttress beside it does not count)
	for cd: Dictionary in layout["cells"]:
		if cd["lot_kind"] == "Wall" and cd["level"] >= 1:
			per_column[cd["x"]] = int(per_column.get(cd["x"], 0)) + 1
	var wall_cols := {}
	for x in per_column:
		if per_column[x] >= 5:
			wall_cols[x] = true
	for cd: Dictionary in layout["cells"]:
		if cd["street"] and wall_cols.has(cd["x"]) and cd["level"] == 0:
			var half := 1 if cd["z"] >= nz / 2 else 0
			var at := origin + Vector2(cd["x"] + 0.5, cd["z"] + (0.12 if half == 0 else 0.88)) * cell_in
			out.append({"at": at, "half": half})
	return out


## Post and lantern boxes for the greybox plan ({lo, hi, kind, solid}): a 0.14 in timber post 2.3 in high, a 0.4 in lantern on top (the kind "lantern" glows).
static func lantern_boxes(layout: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for l: Dictionary in lanterns(layout):
		var at: Vector2 = l["at"]
		out.append({"lo": Vector3(at.x - 0.07, 0.0, at.y - 0.07), "hi": Vector3(at.x + 0.07, 2.3, at.y + 0.07), "kind": "ladder", "solid": false, "lantern": true})
		out.append({"lo": Vector3(at.x - 0.2, 2.3, at.y - 0.2), "hi": Vector3(at.x + 0.2, 2.85, at.y + 0.2), "kind": "lantern", "solid": false, "lantern": true})
	return out


## The warm lights of the first MAX_LIGHTS lanterns (the square's four first, then the gates nearest the centre); the four nearest the centre cast shadows.
func _add_lights(layout: Dictionary) -> void:
	var list := lanterns(layout)
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (a["at"] as Vector2).length() < (b["at"] as Vector2).length())
	for i in mini(list.size(), MAX_LIGHTS):
		var at: Vector2 = list[i]["at"]
		var light := OmniLight3D.new()
		light.name = "Lantern%d" % i
		light.position = Vector3(at.x, 2.55, at.y) * INCHES_TO_METERS
		light.light_color = LANTERN_COLOUR
		light.light_energy = 0.5
		light.omni_range = 0.24
		light.omni_attenuation = 1.3
		light.shadow_enabled = i < 4
		add_child(light)


## The dusk of the town: a low warm sun, a cool violet sky fill, a touch less exposure; applied to the scene's lighting controller (a dev view, so it is not restored).
static func dusk(lighting: Object) -> void:
	if lighting == null:
		return
	lighting.set_sun_color(Color(1.0, 0.66, 0.42))
	lighting.set_sun_energy(1.0)
	lighting.set_sun_angles(-50.0, 14.0)
	lighting.set_ambient_color(Color(0.36, 0.40, 0.66))
	lighting.set_ambient_energy(0.8)
	lighting.set_exposure(0.95)


## Props against the house walls: crates, barrels, wood piles and sacks on bare ground, only in the 0.75 in strip beside a wall face of a raised house, an intact
## house or the wall, never on a street, a plot, a pool, a ladder foot or a landmark (a prop never takes standing room). The north half stacks more barrels and
## fewer crates than the south half. Boxes ({lo, hi, kind, solid}).
static func props(layout: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var nx: int = layout["nx"]
	var nz: int = layout["nz"]
	var cell_in := float(layout["cell_in"])
	var origin := Vector2(nx, nz) * cell_in * -0.5
	var cells: Array = layout["cells"]
	var feet := {}
	for c: Dictionary in layout["connectors"]:
		feet[int(c["low"])] = true
		feet[int(c["high"])] = true
	var taken := {}
	for lm: Dictionary in layout["landmarks"]:
		for dz in int(lm["h"]):
			for dx in int(lm["w"]):
				taken[(int(lm["z"]) + dz) * nx + int(lm["x"]) + dx] = true
	for cd: Dictionary in cells:
		var i: int = cd["z"] * nx + cd["x"]
		if cd["level"] != 0 or cd["street"] or feet.has(i) or taken.has(i) or ["Hazard", "Rough", "Wall", "Roofed"].has(cd["lot_kind"]):
			continue
		var half := 1 if cd["z"] >= nz / 2 else 0
		for side in 4:
			var d := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)][side] as Vector2i
			var at := Vector2i(cd["x"], cd["z"]) + d
			if at.x < 0 or at.y < 0 or at.x >= nx or at.y >= nz:
				continue
			var n: Dictionary = cells[at.y * nx + at.x]
			if n["level"] == 0 and n["lot_kind"] != "Roofed":
				continue   # no wall face on that side
			if _hash(i, half, 40 + side) > (0.42 if half == 0 else 0.3):
				continue
			var kind := int(_hash(i, half, 50 + side) * (4.0 if half == 0 else 3.99))   # 0 barrel .. 3 crate; the north half draws from a longer list
			var size := [Vector3(0.5, 0.75, 0.5), Vector3(0.9, 0.4, 0.4), Vector3(0.7, 0.3, 0.45), Vector3(0.6, 0.55, 0.6)][kind % 4] as Vector3
			var along := 0.8 + 1.4 * _hash(i, half, 60 + side)   # position along the 3 in edge
			var lo := origin + Vector2(cd["x"], cd["z"]) * cell_in
			var depth := minf(size.z, 0.7)
			var box_lo := Vector2.ZERO
			var box_size := Vector2(size.x, depth) if d.x == 0 else Vector2(depth, size.x)
			if d.x == 0:
				box_lo = Vector2(lo.x + along, lo.y + 0.05 if d.y < 0 else lo.y + cell_in - depth - 0.05)
			else:
				box_lo = Vector2(lo.x + 0.05 if d.x < 0 else lo.x + cell_in - depth - 0.05, lo.y + along)
			out.append({"lo": Vector3(box_lo.x, 0.0, box_lo.y), "hi": Vector3(box_lo.x + box_size.x, size.y, box_lo.y + box_size.y), "kind": "wood", "solid": false, "prop": true})
	return out


## The parts a ruined, walkable tier (Block, Deck) is drawn as (plan O7): a lot two or more cells long is a row that lost its roofs - two or three houses side by side, cut at cell
## boundaries along its long axis. {cells: {cell index: part number}, parts: {lot: number of parts}, axis_x: {lot: bool}, shade: {"lot/part": 0..1}}. Pure data; the tier's boxes and tops are
## not touched, only the paint (stone / timber tone and the storey band) and the short party-wall stubs differ per part.
static func tier_parts(layout: Dictionary) -> Dictionary:
	var out := {"cells": {}, "parts": {}, "axis_x": {}, "shade": {}}
	var nx: int = layout["nx"]
	for lot: Dictionary in layout.get("lots", []):   # a bare layout (no lots) has no tiers
		if not ["Block", "Deck"].has(lot["kind"]):
			continue
		var axis_x: bool = lot["w"] >= lot["h"]
		var n: int = lot["w"] if axis_x else lot["h"]
		var half := 1 if lot["z"] * 2 >= int(layout["nz"]) else 0
		var cut_at: Array[int] = []   # the cell indices (along the axis) where a new part starts
		if n == 2 or (n == 3 and _hash(lot["id"], half, 100) < 0.5):
			cut_at.append(1 + int(n == 3 and _hash(lot["id"], half, 101) < 0.5))   # 2: 1 + 1; 3: 1 + 2 or 2 + 1
		elif n == 3:
			cut_at.append_array([1, 2])   # 1 + 1 + 1
		out["parts"][lot["id"]] = cut_at.size() + 1
		out["axis_x"][lot["id"]] = axis_x
		for dz in lot["h"]:
			for dx in lot["w"]:
				var part := 0
				for c in cut_at:
					part += int((dx if axis_x else dz) >= c)
				out["cells"][(int(lot["z"]) + dz) * nx + int(lot["x"]) + dx] = part
				out["shade"]["%d/%d" % [lot["id"], part]] = _hash(lot["id"], half, 110 + part)
	return out


## The party-wall stubs: where two parts of a tier meet, a stub 0.3 in thick and 0.4 in high stands at EACH end of the boundary, 0.6 in long, inside the 0.75 in edge strip, on the tier top
## (boxes for the greybox plan). The middle of the top stays flat; none at a ladder's top cell.
static func party_stubs(layout: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var nx: int = layout["nx"]
	var nz: int = layout["nz"]
	var cell_in := float(layout["cell_in"])
	var origin := Vector2(nx, nz) * cell_in * -0.5
	var tiers := tier_parts(layout)
	var feet := {}
	for c: Dictionary in layout["connectors"]:
		feet[int(c["high"])] = true
	var level_in: Array = layout["level_in"]
	for lot: Dictionary in layout["lots"]:
		if not tiers["parts"].has(lot["id"]) or tiers["parts"][lot["id"]] < 2:
			continue
		var axis_x: bool = tiers["axis_x"][lot["id"]]
		for dz in lot["h"]:
			for dx in lot["w"]:
				var i: int = (int(lot["z"]) + dz) * nx + int(lot["x"]) + dx
				var nb: int = i + (1 if axis_x else nx)   # the next cell along the axis
				if (dx + 1 >= lot["w"] if axis_x else dz + 1 >= lot["h"]) or tiers["cells"][nb] == tiers["cells"][i]:
					continue
				var edge_end: bool = (dz == 0 or dz == int(lot["h"]) - 1) if axis_x else (dx == 0 or dx == int(lot["w"]) - 1)   # the boundary's end cells
				if not edge_end or feet.has(i) or feet.has(nb):
					continue
				var cell := origin + Vector2(i % nx, i / nx) * cell_in
				var top: float = level_in[layout["cells"][i]["level"]]
				var outer_first: bool = (dz == 0) if axis_x else (dx == 0)   # the end on the lot's low-coordinate side
				var lo := Vector2.ZERO
				var size := Vector2.ZERO
				if axis_x:
					size = Vector2(0.3, 0.6)
					lo = Vector2(cell.x + cell_in - 0.15, cell.y + (0.05 if outer_first else cell_in - 0.65))
				else:
					size = Vector2(0.6, 0.3)
					lo = Vector2(cell.x + (0.05 if outer_first else cell_in - 0.65), cell.y + cell_in - 0.15)
				out.append({"lo": Vector3(lo.x, top, lo.y), "hi": Vector3(lo.x + size.x, top + 0.4, lo.y + size.y), "kind": "stone", "solid": false, "prop": true, "party_stub": true, "lot": lot["id"]})
	return out


## Lean-tos and sheds at the BACK and SIDE of the houses (plan O6): boxes for the greybox plan ({lo, hi, kind, solid, prop, lean_to, lot, face}) on bare ground outside a house face, flush with the
## collider's face, at most 0.75 in deep and 1.6 in high, never on the front (the door side), a party wall, a street cell, a ladder foot, a landmark or a pool / garden / hazard cell. A shed is a wooden
## box with a tiled lid, a woodpile a low wooden box, a privy a narrow tall box with a lid. Only whole raised or intact houses (Block, Deck, Roofed) carry them. Pure data.
static func lean_tos(layout: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var nx: int = layout["nx"]
	var nz: int = layout["nz"]
	var cell_in := float(layout["cell_in"])
	var origin := Vector2(nx, nz) * cell_in * -0.5
	var cells: Array = layout["cells"]
	var feet := {}
	for c: Dictionary in layout["connectors"]:
		feet[int(c["low"])] = true
		feet[int(c["high"])] = true
	var taken := {}
	for lm: Dictionary in layout["landmarks"]:
		for dz in int(lm["h"]):
			for dx in int(lm["w"]):
				taken[(int(lm["z"]) + dz) * nx + int(lm["x"]) + dx] = true
	var dirs := {"N": Vector2i(0, -1), "E": Vector2i(1, 0), "S": Vector2i(0, 1), "W": Vector2i(-1, 0)}
	var lots := {}
	for lot: Dictionary in layout["lots"]:
		lots[lot["id"]] = lot
	for f: Dictionary in frontage(layout):
		var lot: Dictionary = lots[f["lot"]]
		if f["front"] == "" or not ["Block", "Deck", "Roofed"].has(lot["kind"]):
			continue
		var half := 1 if lot["z"] * 2 >= nz else 0
		for face: String in [f["back"]] + f["sides"]:
			if f["party"][face] or _hash(f["lot"], half, 20 + "NESW".find(face)) > (0.55 if face == f["back"] else 0.3):
				continue
			var d: Vector2i = dirs[face]
			var along_x := d.x == 0   # the face runs along x (a north or south face)
			var run: int = lot["w"] if along_x else lot["h"]
			var idx := int(_hash(f["lot"], half, 30 + "NESW".find(face)) * run)
			var out_cell := Vector2i(lot["x"], lot["z"]) + (Vector2i(idx, 0) if along_x else Vector2i(0, idx)) + (Vector2i(0, lot["h"]) if face == "S" else Vector2i(lot["w"], 0) if face == "E" else Vector2i.ZERO) + (d if face in ["N", "W"] else Vector2i.ZERO)
			if out_cell.x < 0 or out_cell.y < 0 or out_cell.x >= nx or out_cell.y >= nz:
				continue
			var cd: Dictionary = cells[out_cell.y * nx + out_cell.x]
			var i := out_cell.y * nx + out_cell.x
			if cd["level"] != 0 or cd["street"] or cd["lot_id"] != 0 or cd["lot_kind"] != "Street" or feet.has(i) or taken.has(i):
				continue
			var pick := int(_hash(f["lot"], half, 70 + "NESW".find(face)) * 3.0)
			var length: float = [2.0, 1.6, 0.7][pick]
			var height: float = [1.3, 0.7, 1.6][pick]
			var depth := 0.5 + 0.25 * _hash(f["lot"], half, 80 + "NESW".find(face))
			var cell_lo := origin + Vector2(out_cell) * cell_in
			var along := 0.3 + (cell_in - 0.6 - length) * _hash(f["lot"], half, 90 + "NESW".find(face))
			var lo := Vector2.ZERO
			var size := Vector2(length, depth) if along_x else Vector2(depth, length)
			if along_x:
				lo = Vector2(cell_lo.x + along, cell_lo.y + cell_in - depth if face == "N" else cell_lo.y)   # flush with the house face
			else:
				lo = Vector2(cell_lo.x + cell_in - depth if face == "W" else cell_lo.x, cell_lo.y + along)
			var box := {"lo": Vector3(lo.x, 0.0, lo.y), "hi": Vector3(lo.x + size.x, height, lo.y + size.y), "kind": "wood", "solid": false, "prop": true, "lean_to": true, "lot": f["lot"], "face": face}
			out.append(box)
			if pick != 1:   # a shed and a privy get a tiled lid, a little proud of the box
				out.append({"lo": Vector3(lo.x - 0.05, height, lo.y - 0.05), "hi": Vector3(lo.x + size.x + 0.05, height + 0.12, lo.y + size.y + 0.05), "kind": "roof", "solid": false, "prop": true, "lean_to": true, "lot": f["lot"], "face": face})
	return out


## The rubble of a wall breach: eight low stones (0.08-0.25 in) scattered over the gap, flat enough to stand on (the breach is Difficult ground).
static func breach_rubble(layout: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var nx: int = layout["nx"]
	var cell_in := float(layout["cell_in"])
	var origin := Vector2(nx, layout["nz"]) * cell_in * -0.5
	for cd: Dictionary in layout["cells"]:
		if cd["lot_kind"] != "Wall" or cd["level"] != 0:
			continue
		var id: int = cd["z"] * nx + cd["x"]
		for k in 8:
			var w := 0.3 + 0.4 * _hash(id, 0, 70 + k)
			var at := origin + Vector2(cd["x"], cd["z"]) * cell_in + Vector2(0.2 + (cell_in - 0.4 - w) * _hash(id, 1, 80 + k), 0.2 + (cell_in - 0.4 - w) * _hash(id, 0, 90 + k))
			out.append({"lo": Vector3(at.x, 0.0, at.y), "hi": Vector3(at.x + w, 0.08 + 0.17 * _hash(id, 1, 100 + k), at.y + w * 0.8), "kind": "rubble", "solid": false, "prop": true})
	return out


## Battlements round the hall: merlons along the outer edges of every hall footprint (a pumphouse landmark) on its block, like the wall's, inside the rim.
static func hall_merlons(layout: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var nx: int = layout["nx"]
	var cell_in := float(layout["cell_in"])
	var origin := Vector2(nx, layout["nz"]) * cell_in * -0.5
	var n := 0
	for lm: Dictionary in layout["landmarks"]:
		n += 1
		if lm["kind"] != "PumpHouse":
			continue
		var top := 0.0
		for dz in int(lm["h"]):
			for dx in int(lm["w"]):
				top = maxf(top, float(layout["level_in"][layout["cells"][(int(lm["z"]) + dz) * nx + int(lm["x"]) + dx]["level"]]))
		var lo := origin + Vector2(lm["x"], lm["z"]) * cell_in
		var size := Vector2(lm["w"], lm["h"]) * cell_in
		var half := 1 if lo.y + size.y * 0.5 > 0.0 else 0
		for edge in 4:   # north, east, south, west: 3 merlons per 3 in of edge
			var length := size.x if edge % 2 == 0 else size.y
			for i in int(length / cell_in) * 3:
				if _hash(n * 31 + edge, half, 110 + i) < (0.28 if half == 1 else 0.10):
					continue
				var t := 0.5 + float(i)
				var box_lo := Vector2(lo.x + t - 0.35, lo.y if edge == 0 else lo.y + size.y - 0.4) if edge % 2 == 0 else Vector2(lo.x if edge == 3 else lo.x + size.x - 0.4, lo.y + t - 0.35)
				var box_size := Vector2(0.7, 0.4) if edge % 2 == 0 else Vector2(0.4, 0.7)
				out.append({"lo": Vector3(box_lo.x, top, box_lo.y), "hi": Vector3(box_lo.x + box_size.x, top + 0.7, box_lo.y + box_size.y), "kind": "wall", "solid": false, "merlon": true})
	return out


## The frontage table of the building lots (plan O1, no visual change yet): for every house lot (Block, Terrace, Deck, Roofed) its FRONT face - the face with the most
## street cells beside it, ties toward the square - its back (opposite), its sides, the faces that are party walls (a building lot of its own right beside them) and
## whether it is a corner lot (street beside two adjacent faces). A lot with no street beside any face has front "" (a backyard house). Faces are "N" (z - 1), "E", "S", "W".
## Pure data: [{lot, front, back, sides, party {face: bool}, corner, streets {face: count}}].
static func frontage(layout: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var nx: int = layout["nx"]
	var nz: int = layout["nz"]
	var cells: Array = layout["cells"]
	var dirs := {"N": Vector2i(0, -1), "E": Vector2i(1, 0), "S": Vector2i(0, 1), "W": Vector2i(-1, 0)}
	var opposite := {"N": "S", "E": "W", "S": "N", "W": "E"}
	var houses := ["Block", "Terrace", "Deck", "Roofed"]
	for lot: Dictionary in layout["lots"]:
		if not houses.has(lot["kind"]):
			continue
		var streets := {"N": 0, "E": 0, "S": 0, "W": 0}
		var party := {"N": false, "E": false, "S": false, "W": false}
		for dz in int(lot["h"]):
			for dx in int(lot["w"]):
				var x: int = int(lot["x"]) + dx
				var z: int = int(lot["z"]) + dz
				for face: String in dirs:
					var at: Vector2i = Vector2i(x, z) + (dirs[face] as Vector2i)
					if at.x < 0 or at.y < 0 or at.x >= nx or at.y >= nz or (at.x >= int(lot["x"]) and at.x < int(lot["x"]) + int(lot["w"]) and at.y >= int(lot["z"]) and at.y < int(lot["z"]) + int(lot["h"])):
						continue
					var nb: Dictionary = cells[at.y * nx + at.x]
					if nb["street"]:
						streets[face] += 1
					elif nb["lot_id"] != 0 and nb["lot_id"] != lot["id"] and houses.has(String(nb["lot_kind"])):
						party[face] = true
		var centre := Vector2(float(lot["x"]) + float(lot["w"]) * 0.5 - float(nx) * 0.5, float(lot["z"]) + float(lot["h"]) * 0.5 - float(nz) * 0.5)
		var front := ""
		var best_key := Vector2(0.0, -INF)   # (street cells, how much the face points at the board centre)
		for face: String in dirs:
			if streets[face] == 0:
				continue
			var key := Vector2(float(streets[face]), -(Vector2(dirs[face] as Vector2i)).dot(centre))
			if key.x > best_key.x or (key.x == best_key.x and key.y > best_key.y):
				best_key = key
				front = face
		var sides: Array = []
		for face: String in dirs:
			if front != "" and face != front and face != opposite[front]:
				sides.append(face)
		out.append({"lot": lot["id"], "front": front, "back": opposite[front] if front != "" else "", "sides": sides, "party": party, "streets": streets,
			"corner": (streets["N"] > 0 or streets["S"] > 0) and (streets["E"] > 0 or streets["W"] > 0)})
	return out


## The unit gable prism: ridge along x at height 1 over z = 0, eaves at y = 0 on z = -0.5 / +0.5, x from -0.5 to 0.5.
static func prism_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var quads := [
		[Vector3(-0.5, 0, 0.5), Vector3(0.5, 0, 0.5), Vector3(0.5, 1, 0), Vector3(-0.5, 1, 0), Vector3(0, 0.5, 1).normalized()],
		[Vector3(0.5, 0, -0.5), Vector3(-0.5, 0, -0.5), Vector3(-0.5, 1, 0), Vector3(0.5, 1, 0), Vector3(0, 0.5, -1).normalized()]]
	for q: Array in quads:
		for i in [0, 2, 1, 0, 3, 2]:   # clockwise seen from outside
			st.set_normal(q[4])
			st.add_vertex(q[i])
	for end in [-1.0, 1.0]:   # the gable triangles, wound to face outward
		var a := Vector3(end * 0.5, 0, 0.5)
		var b := Vector3(end * 0.5, 0, -0.5)
		var c := Vector3(end * 0.5, 1, 0)
		for v: Vector3 in ([a, c, b] if end > 0.0 else [b, c, a]):
			st.set_normal(Vector3(end, 0, 0))
			st.add_vertex(v)
	return st.commit()


## A triangle added wound clockwise seen from outside (`ref` = a point inside the shape), with its flat normal.
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, ref: Vector3) -> void:
	var n := (b - a).cross(c - a)
	var out := n.dot((a + b + c) / 3.0 - ref) > 0.0   # counter-clockwise from outside: swap to clockwise
	for v: Vector3 in ([a, c, b] if out else [a, b, c]):
		st.set_normal(n.normalized() if out else -n.normalized())
		st.add_vertex(v)


## The unit HIP roof: ridge at height 1 from x = -0.2 to 0.2 over z = 0, eaves at y = 0 on the whole rectangle (x, z in -0.5..0.5): four slopes, no gable end.
static func hip_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ref := Vector3(0, 0.3, 0)
	var a := Vector3(-0.2, 1, 0)
	var b := Vector3(0.2, 1, 0)
	for z in [-0.5, 0.5]:
		_tri(st, Vector3(-0.5, 0, z), Vector3(0.5, 0, z), b, ref)
		_tri(st, Vector3(-0.5, 0, z), b, a, ref)
	_tri(st, Vector3(0.5, 0, -0.5), Vector3(0.5, 0, 0.5), b, ref)
	_tri(st, Vector3(-0.5, 0, 0.5), Vector3(-0.5, 0, -0.5), a, ref)
	return st.commit()


## The unit CATSLIDE roof: like the gable prism, but the ridge is at z = +0.15 and the slope on the -z side runs on down to y = -0.45 at the edge (the back, which the caller flips).
static func catslide_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ref := Vector3(0, 0.3, 0)
	var a := Vector3(-0.5, 1, 0.15)
	var b := Vector3(0.5, 1, 0.15)
	_tri(st, Vector3(-0.5, 0, 0.5), Vector3(0.5, 0, 0.5), b, ref)
	_tri(st, Vector3(-0.5, 0, 0.5), b, a, ref)
	_tri(st, Vector3(0.5, -0.45, -0.5), Vector3(-0.5, -0.45, -0.5), a, ref)
	_tri(st, Vector3(0.5, -0.45, -0.5), a, b, ref)
	_tri(st, Vector3(0.5, 0, 0.5), Vector3(0.5, -0.45, -0.5), b, ref)
	_tri(st, Vector3(-0.5, -0.45, -0.5), Vector3(-0.5, 0, 0.5), a, ref)
	return st.commit()


## The roofs in one MultiMesh PER TYPE (gable, hip, catslide: "Roofs", "RoofsHip", "RoofsCatslide") with the board's material (the kind "roof" in its instance data).
func build(layout: Dictionary, material: Material) -> void:
	var list := roofs(layout)
	var meshes := {"gable": [prism_mesh(), "Roofs"], "hip": [hip_mesh(), "RoofsHip"], "catslide": [catslide_mesh(), "RoofsCatslide"]}
	var kind := float(BoardgenTheme.TOWN_KINDS.find("roof"))
	for type: String in meshes:
		var of := list.filter(func(r: Dictionary) -> bool: return r["type"] == type)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = meshes[type][0]
		mm.instance_count = of.size()
		for i in of.size():
			var r: Dictionary = of[i]
			var basis := Basis.from_scale(Vector3(r["length"], r["height"], r["width"]) * INCHES_TO_METERS)
			if type == "catslide" and r["back"] > 0:
				basis = Basis(Vector3.UP, PI) * basis   # the mesh's long slope is on -z: half a turn puts it on the back (a mirror would flip the faces)
			if not r["along_x"]:
				basis = Basis(Vector3.UP, PI * 0.5) * basis
			basis = Basis(Vector3.UP, r["yaw"]) * basis   # the roof follows its body's yaw
			var at: Vector2 = r["centre"]
			mm.set_instance_transform(i, Transform3D(basis, Vector3(at.x, r["eaves"], at.y) * INCHES_TO_METERS))
			mm.set_instance_custom_data(i, Color(kind, r["length"], r["height"], r["width"]))
		var mmi := MultiMeshInstance3D.new()
		mmi.name = meshes[type][1]
		mmi.multimesh = mm
		mmi.material_override = material
		add_child(mmi)
	_add_bodies(layout, material)
	_add_lights(layout)


## The drawn bodies of the intact houses in ONE MultiMesh with the board's material (kind "roofed"; the fraction of the kind carries the plinth height for the shader).
## The greybox's own boxes for these cells draw nothing (zero scale) and only keep the collider.
func _add_bodies(layout: Dictionary, material: Material) -> void:
	var parts: Array[Dictionary] = []
	for b: Dictionary in house_bodies(layout):
		for part in house_parts(b):
			parts.append(part.merged({"yaw": b["yaw"], "plinth": b["plinth"]}))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = BoxMesh.new()
	mm.instance_count = parts.size()
	var kind := float(BoardgenTheme.TOWN_KINDS.find("roofed"))
	for i in parts.size():
		var b: Dictionary = parts[i]
		var size := Vector3(b["size"].x, float(b["y1"]) - float(b["y0"]), b["size"].y)
		var at: Vector2 = b["centre"]
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, b["yaw"]) * Basis.from_scale(size * INCHES_TO_METERS), Vector3(at.x, (float(b["y0"]) + float(b["y1"])) * 0.5, at.y) * INCHES_TO_METERS))
		mm.set_instance_custom_data(i, Color(kind + (float(b["plinth"]) - 0.3) / 0.75, size.x, size.y, size.z))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Houses"
	mmi.multimesh = mm
	mmi.material_override = material
	add_child(mmi)
