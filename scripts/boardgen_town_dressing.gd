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
const PITCH_DEG := Vector2(50.0, 58.0)   # (L1, target C: steep roofs) the pitch range of a main roof over its ridge's half width
const SAG_DEG := 2.5   # (L2) a sagged roof: each half dips this much towards the middle of its ridge
const RIDGE_MAX_IN := 4.9   # (L1) no drawn ridge above this: the sight plan's look guard (S4) brackets the rule height 4.5 in with 4.3-4.9
const MAX_LIGHTS := 14   # 8 before the outer streets got their lamps (silhouette round 21.11.); only the SHADOWED_LANTERNS nearest the centre cast shadows
const LANTERN_COLOUR := Color(1.0, 0.74, 0.48)
## (train 3) the four square lamps (the shadowed, widest cones - the one beside the street camera among them): a paler flame, so their pools stay warm-in-grey
## like C's (pool 45 % warm) instead of an orange oval (83 %); the gate and edge lamps keep LANTERN_COLOUR.
const LANTERN_SQUARE_COLOUR := Color(1.0, 0.845, 0.67)   # (townC4: 0.86 / 0.7 left the pool at 37 % warm, C 45 %)
## A lantern is a down-cone (plan R7a): without a shadow the half-angle keeps the pool on the ground (height x tan) inside a 3 in cell's width - the light of a post against a wall must not reach the far side.
const LANTERN_CONE_DEG := 48.0
## The four lanterns that cast shadows (the square's corners) throw a wider pool - the walls stop it; the others stay narrow. 58 (was 75: a 9.5 in pool that flooded the
## whole square warm, 48 % of it; target C keeps warm light inside small pools, plan TARGET C train 2, C2).
const LANTERN_CONE_SHADOWED_DEG := 58.0
## A spot's energy is not an omni's: the cone, the cookie (mean ~0.4) and the 1 / d fall-off over 2.5 in of height set it; 3.5 keeps the plaster beside a post under the clip cap.
const LANTERN_ENERGY := 3.5
## The moons (the blue hour, D-R4, as two pale lights): the key and its half turn, equal in colour and nearly in energy, so the board looks the same from both players' sides.
const MOON_COLOUR := Color(0.93, 0.95, 1.0)
const MOON_AZIMUTH := -20.0
const MOON_ELEVATION := 52.0
const MOON_ENERGY := 2.0
const MOON2_ENERGY := 2.0
const MOON2_SHADOWS := true
## Maintainer 21.11. "too dark": the whole board one step brighter, evenly (exposure, a paler and stronger sky fill); was exposure 1.0, ambient 0.9 at (0.42, 0.47, 0.62).
const EXPOSURE := 1.6
const AMBIENT_ENERGY := 1.5
const AMBIENT_COLOUR := Color(0.48, 0.52, 0.64)
const MOON_SPECULAR := 0.0   # no specular from the moons: on the glossy pawns it is a white veil that washes their colours (gate, opposite player side: 0.63 -> 0.78 on seed 13)
const SSAO_RADIUS_M := 0.06   # 2.4 in: a wall's foot, a roof's eave, a joint between two tiers
const SSAO_INTENSITY := 1.4
## The Ultra preset's bounce light (SDFGI 1.1, SSIL 1.0) is tuned for daylight: under a strong moon it lifts the lit walls and decks round the models and cost their contrast (the Ultra rows of the readability
## gate: with both off the worst row went 0.62 -> 0.72). The blue hour turns them down, not off.
const SDFGI_ENERGY := 0.45
const SSIL_INTENSITY := 0.4
## A weak wide fill inside every lantern's pool (lead 21.11.): an omni with no shadow map, so the cone's pool has no hard black rim; weak enough that light leaking through a wall is a glow, not a pool.
const FILL_ENERGY := 0.05
const FILL_RANGE_M := 0.12   # (was 0.2, train 2: the warm fill stays near its post)
const EMBER_COLOUR := Color(1.0, 0.5, 0.2)
const EMBER_ENERGY := 0.7
const EMBER_RANGE_M := 0.18
const SHADOWED_LANTERNS := 4   # the nearest the centre cast shadows


## The cone half-angle of lantern number `i` (nearest the centre first): wide where a shadow map stops it at the walls, narrow where none does.
static func lantern_cone_deg(i: int) -> float:
	return LANTERN_CONE_SHADOWED_DEG if i < SHADOWED_LANTERNS else LANTERN_CONE_DEG
const LANTERN_HEIGHT_IN := 2.55


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
## of at most 2 degrees. (L1) The pitch is 50-58 degrees over each ridge's half width, the ridge capped at RIDGE_MAX_IN (the core blocks sight to 4.5 in, sight plan S2 / S4: the mean
## ridge stays in 4.3-4.9 in), so a steep roof comes from a narrow strip, not a tall one; `ridges` = how many parallel gables the roof is drawn as (`ridge_strips`). VISUAL ONLY.
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
		var ridges := maxi(1, roundi(across / cell_in))   # (L1) a house two cells across its ridge gets TWIN parallel gables, one cell wide each: steep without growing
		var type := "gable" if ridges > 1 or pick < 0.45 or (pick >= 0.75 and not eaves_on) else ("hip" if pick < 0.75 else "catslide")   # (hips only on one-cell-wide roofs)
		var back := 1 if front in ["N", "W"] else -1   # the side of the ridge away from the street (+z / +x for a front on the north / west)
		var height := minf(tan(deg_to_rad(PITCH_DEG.x + (PITCH_DEG.y - PITCH_DEG.x) * _hash(id, half, 2))) * (across / ridges * 0.5 + OVERHANG_IN), RIDGE_MAX_IN - float(look["top"]))
		var yaw: float = look["yaw"] + (2.0 * _hash(id, half, 10) - 1.0) * deg_to_rad(2.0)
		var roof := {"lot": id, "centre": centre, "length": run + 2.0 * OVERHANG_IN, "width": across + 2.0 * OVERHANG_IN, "height": height, "along_x": along_x, "half": half,
			"yaw": yaw, "eaves": look["top"], "type": type, "back": back, "annex": false, "ridges": ridges, "rect": Rect2i(lot["x"], lot["z"], lot["w"], lot["h"])}
		if run >= 2.0 * cell_in and _hash(id, half, 11) < 0.4:
			var end := 1.0 if _hash(id, half, 12) < 0.5 else -1.0
			var shift := Vector2(end, 0.0) if along_x else Vector2(0.0, end)
			var annex := roof.duplicate()
			annex.merge({"centre": centre + shift * (run * 0.5 - cell_in * 0.5), "length": cell_in + 2.0 * OVERHANG_IN, "height": height * 0.55, "type": "gable", "annex": true}, true)
			roof.merge({"centre": centre - shift * cell_in * 0.5, "length": run - cell_in + 2.0 * OVERHANG_IN}, true)
			out.append(annex)
		out.append(roof)
	_damage(out)
	return out


## (L2) Which main roofs are BROKEN, one list the kit and the procedural path both read: by the lot's hash a quarter holed and an eighth sagged; the first roof of each board half
## (lowest hash) at least holed, the board's lowest COLLAPSED to its rafters on one slope; a roof never shows the damage of a roof whose lot touches its own (holed <-> sagged, else
## whole), and never more than half of them (bar those two). A broken roof is a gable. `end` / `side` = the end of the ridge and the slope the hole takes, `frac` = how much of the ridge. Annexes stay whole.
static func _damage(out: Array[Dictionary]) -> void:
	var mains := out.filter(func(r: Dictionary) -> bool: return not r["annex"])
	mains.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _hash(a["lot"], a["half"], 7) < _hash(b["lot"], b["half"], 7))
	var first := {}
	var broken := 0
	var done: Array[Dictionary] = []
	for i in mains.size():
		var r: Dictionary = mains[i]
		var h := _hash(r["lot"], r["half"], 7)
		var forced := i == 0 or not first.has(r["half"])
		var state := "collapsed" if i == 0 else ("holed" if forced or h < 0.25 else ("sagged" if h < 0.375 else "whole"))
		if not forced and broken >= mains.size() * 0.5:
			state = "whole"   # never more than half of a board's roofs (bar the two every board has)
		first[r["half"]] = true
		var near := done.filter(func(d: Dictionary) -> bool: return (d["rect"] as Rect2i).grow(1).intersects(r["rect"])).map(func(d: Dictionary) -> String: return d["damage"])
		if state != "whole" and near.has(state):
			state = "sagged" if state != "sagged" and not near.has("sagged") else ("holed" if not near.has("holed") else "whole")
		r.merge({"damage": state, "end": signf(_hash(r["lot"], r["half"], 17) - 0.5), "side": signf(_hash(r["lot"], r["half"], 18) - 0.5),
			"frac": 0.9 if state == "collapsed" else 0.3 + 0.2 * _hash(r["lot"], r["half"], 19), "type": "gable" if state != "whole" else r["type"]}, true)
		broken += int(state != "whole")
		done.append(r)


## (L2) What one ridge strip is drawn as: [prism pieces (roof dicts; `tilt` = a roll about the cross axis), boxes {centre (Vector3, board inches), size, yaw, pitch, kind}]. Whole: itself.
## HOLED (COLLAPSED: over 90 % of the ridge): the prism stays over the rest; over the hole one slope keeps its tiles, the other shows three tile courses stepping back raggedly from the
## prism, the ridge beam, a rafter every ~0.6 in at the pitch and two battens. SAGGED: two prism halves dipping SAG_DEG to the middle and two slipped tile patches. Every timber box
## stays 0.45 in inside the lot's own (solid) cells, tile pieces inside the roof's overhang: nothing over standing room. Only a roof's first strip breaks. Pure data.
static func roof_parts(r: Dictionary) -> Array:
	var state: String = r.get("damage", "whole") if int(r.get("strip", 0)) == 0 else "whole"
	var pieces: Array[Dictionary] = [r]
	var boxes: Array[Dictionary] = []
	if state == "whole":
		return [pieces, boxes]
	var a := float(r["yaw"]) + (0.0 if r["along_x"] else PI * 0.5)
	var l := float(r["length"])
	var w := float(r["width"]) * 0.5
	var h := float(r["height"])
	var e := float(r["eaves"])
	var th := atan2(h, w)
	var side := float(r["side"])
	var o := Vector3(r["centre"].x, 0.0, r["centre"].y)
	var box := func(u: float, y: float, v: float, size: Vector3, pitch: float, kind: String) -> Dictionary:
		return {"centre": o + Vector3(u, y, v).rotated(Vector3.UP, a), "size": size, "yaw": a, "pitch": pitch, "kind": kind}
	if state == "sagged":
		var sag := deg_to_rad(SAG_DEG)
		pieces = []
		for s: float in [-1.0, 1.0]:
			pieces.append(r.merged({"centre": r["centre"] + Vector2(s * l * 0.25, 0.0).rotated(-a), "length": l * 0.5, "tilt": s * sag, "eaves": e - sin(sag) * l * 0.25}, true))
			boxes.append(box.call((0.5 - _hash(r["lot"], r["half"], 20 + int(s))) * l * 0.6, e + h * 0.5 - 0.03, s * w * 0.5, Vector3(0.6, 0.05, 0.45), -s * th, "roof"))   # a slipped patch
		return [pieces, boxes]
	var end := float(r["end"])
	var lh := l * float(r["frac"])
	var ub := end * (l * 0.5 - lh)   # where the prism stops and the hole begins
	pieces = [r.merged({"centre": r["centre"] - Vector2(end * lh * 0.5, 0.0).rotated(-a), "length": l - lh}, true)]
	var slope := sqrt(h * h + w * w)
	boxes.append(box.call(ub + end * lh * 0.5, e + h * 0.5, -side * w * 0.5, Vector3(lh, 0.06, slope), side * th, "roof"))   # the slope that kept its tiles
	for k in 3:   # the ragged edge: three courses, the lowest reaching furthest into the hole
		var p: float = lh * [0.5, 0.3, 0.12][k] * (0.6 + 0.8 * _hash(r["lot"], r["half"], 21 + k)) * (0.4 if state == "collapsed" else 1.0)
		var t := (k + 0.5) / 3.0
		boxes.append(box.call(ub + end * p * 0.5, e + h * t, side * w * (1.0 - t), Vector3(p, 0.06, slope / 3.0), -side * th, "roof"))
	var u0 := end * maxf(l * 0.5 - lh + 0.15, OVERHANG_IN + 0.45 - l * 0.5)   # the timber starts just past the prism, never nearer the far end than its inset
	var u1 := end * (l * 0.5 - OVERHANG_IN - 0.45)
	var span := absf(u1 - u0)
	var reach := w - OVERHANG_IN - 0.45   # how far a rafter runs down from the ridge: inside the house's cells
	var n := clampi(int(span / 0.6) + 1, 3, 9)
	for i in n:
		boxes.append(box.call(lerpf(u0, u1, float(i) / (n - 1)), e + h * (1.0 - reach * 0.5 / w) - 0.08, side * reach * 0.5, Vector3(0.13, 0.13, reach / cos(th)), -side * th, "wood"))
	boxes.append(box.call((u0 + u1) * 0.5, e + h - 0.08, 0.0, Vector3(span, 0.12, 0.12), 0.0, "wood"))   # the bare ridge beam
	for t: float in [0.45, 0.75]:
		var bl := span * (0.55 + 0.45 * _hash(r["lot"], r["half"], int(t * 100.0)))
		boxes.append(box.call(u0 + end * bl * 0.5, e + h * t, side * w * (1.0 - t), Vector3(bl, 0.05, 0.09), 0.0, "wood"))   # battens across the hole
	return [pieces, boxes]


## (L1) The parallel gable strips a roof is drawn as: a copy of it per ridge (`strip` 0, 1, ...), each one cell wide plus the overhang, side by side across the ridge. Pure data.
static func ridge_strips(r: Dictionary) -> Array[Dictionary]:
	var n: int = r["ridges"]
	var w := (float(r["width"]) - 2.0 * OVERHANG_IN) / n
	var across := (Vector2(0, 1) if r["along_x"] else Vector2(1, 0)).rotated(-float(r["yaw"]))
	var out: Array[Dictionary] = []
	for k in n:
		out.append(r.merged({"centre": r["centre"] + across * w * (k - (n - 1) * 0.5), "width": w + 2.0 * OVERHANG_IN, "ridges": 1, "strip": k}, true))
	return out


## A brick chimney on the ridge of every roof, at the end the lot's hash picks: boxes for the greybox plan ({lo, hi, kind, solid}).
static func chimneys(layout: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for r: Dictionary in roofs(layout).filter(func(r: Dictionary) -> bool: return not r["annex"]):
		var end_sign := 1.0 if _hash(r["lot"], r["half"], 3) < 0.5 else -1.0
		var offset: float = end_sign * (float(r["length"]) * 0.5 - 0.9)
		var centre: Vector2 = ridge_strips(r)[0]["centre"] + (Vector2(offset, 0.0) if r["along_x"] else Vector2(0.0, offset))   # (on the first ridge of a twin roof, not in its valley)
		out.append({"lo": Vector3(centre.x - CHIMNEY_IN * 0.5, BODY_IN, centre.y - CHIMNEY_IN * 0.5),
			"hi": Vector3(centre.x + CHIMNEY_IN * 0.5, BODY_IN + float(r["height"]) + 0.9, centre.y + CHIMNEY_IN * 0.5), "kind": "brick", "solid": false})
	return out


## The battlements: merlons (0.7 x 0.7 x 0.4 in, three to a 3 in edge) along the open FIELD edge of every wall ridge (6 in) and round the open edges of every tower crown (any 9 in
## cell), inside the 0.4 in edge strip so the walkway keeps its width. Some are missing, more in the south half than in the north
## one (a broken battlement is a look; no merlon is cover the core knows). Boxes for the greybox plan ({lo, hi, kind, solid}).
static func merlons(layout: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var nx: int = layout["nx"]
	var nz: int = layout["nz"]
	var cell_in := float(layout["cell_in"])
	var origin := Vector2(nx, nz) * cell_in * -0.5
	for cd: Dictionary in layout["cells"]:
		var level: int = cd["level"]
		var tall: bool = cd["lot_kind"] == "Tower"   # a tall scenery tower (towers plan L1): merlons on every open edge of its crown at `tower_in`
		if not tall and (level < 2 or (level == 2 and cd["lot_kind"] != "Wall")):
			continue
		var top: float = float(layout.get("tower_in", 12.0)) if tall else float(layout["level_in"][level])
		var half := 1 if cd["z"] >= nz / 2 else 0
		for side in 4:
			var d := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)][side] as Vector2i
			var at := Vector2i(cd["x"], cd["z"]) + d
			var inside := at.x >= 0 and at.y >= 0 and at.x < nx and at.y < nz
			if inside and (layout["cells"][at.y * nx + at.x]["lot_kind"] == "Tower" if tall else int(layout["cells"][at.y * nx + at.x]["level"]) >= level):
				continue   # a neighbour as high: this edge is no open edge
			if level == 2 and side != (3 if int(cd["x"]) * 2 < nx else 1):
				continue   # a wall ridge has its parapet on the FIELD side only: the town side of the walk is open (a thin wall with a walk, not a crenellated block)
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
	out.append_array(outer_lanterns(layout))
	return out


## Lamps out to the edges (maintainer 21.11.: "too dark" outside the square): on the street cells of the second row from each board edge (inside the deployment bands) where a street runs
## to the edge, a post at the cell's corner beside a non-street neighbour (0.12 in off the edge, the 0.75 in strip), every street that reaches the edge once. Half-turn twins by construction.
static func outer_lanterns(layout: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var nx: int = layout["nx"]
	var nz: int = layout["nz"]
	var cell_in := float(layout["cell_in"])
	var origin := Vector2(nx, nz) * cell_in * -0.5
	var cells: Array = layout["cells"]
	for z: int in [1, nz - 2]:
		var half := 1 if z >= nz / 2 else 0
		for x in nx:
			var cd: Dictionary = cells[z * nx + x]
			if not cd["street"] or int(cd["level"]) != 0:
				continue
			var left: bool = x > 0 and not cells[z * nx + x - 1]["street"]
			var right: bool = x + 1 < nx and not cells[z * nx + x + 1]["street"]
			if not (left if half == 0 else right):
				continue   # one post per street: on its west side in the north band, its east side in the south (the half turn)
			out.append({"at": origin + Vector2(x + (0.12 if half == 0 else 0.88), z + 0.5) * cell_in, "half": half})
	return out


## Embers of the burnt-out town (maintainer 21.11.: "too dark"): a low warm glow over every wall breach and over the level-0 rest of a ruined house (a RUINS yard), the
## yards nearest the board edges first, at most `limit` (a half-turn pair each). Light only: nothing here takes standing room. [{at (Vector2, inches), half}]
static func ember_glows(layout: Dictionary, limit := 6) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var nx: int = layout["nx"]
	var nz: int = layout["nz"]
	var cell_in := float(layout["cell_in"])
	var origin := Vector2(nx, nz) * cell_in * -0.5
	var spots: Array = []
	for cd: Dictionary in layout["cells"]:
		var breach: bool = cd["lot_kind"] == "Wall" and int(cd["level"]) == 0
		var yard: bool = cd["lot_kind"] == "Terrace" and int(cd["level"]) == 0 and not cd["street"]
		if (breach or yard) and int(cd["z"]) * 2 < nz:
			spots.append([0 if breach else 1, absf(float(cd["z"]) - 7.5) * -1.0, cd])
	spots.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	for sp: Array in spots.slice(0, limit / 2):
		var cd: Dictionary = sp[2]
		var at := origin + Vector2(float(cd["x"]) + 0.5, float(cd["z"]) + 0.5) * cell_in
		out.append({"at": at, "half": 0})
		out.append({"at": -at, "half": 1})
	return out


## Post and lantern boxes for the greybox plan ({lo, hi, kind, solid}): a 0.14 in timber post 2.3 in high, a 0.4 in lantern on top (the kind "lantern" glows).
static func lantern_boxes(layout: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for l: Dictionary in lanterns(layout):
		var at: Vector2 = l["at"]
		out.append({"lo": Vector3(at.x - 0.07, 0.0, at.y - 0.07), "hi": Vector3(at.x + 0.07, 2.3, at.y + 0.07), "kind": "ladder", "solid": false, "lantern": true})
		out.append({"lo": Vector3(at.x - 0.2, 2.3, at.y - 0.2), "hi": Vector3(at.x + 0.2, 2.85, at.y + 0.2), "kind": "lantern", "solid": false, "lantern": true})
	return out


## The lantern's projector cookie, 128 px (plan R7a, the "IES read"): a hot core, a smooth fall-off to the pool's rim and the four bars of the lantern frame as thin dark lines through the pool.
static func lantern_projector() -> Texture2D:
	var size := 128
	var img := Image.create(size, size, false, Image.FORMAT_L8)
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5 - size * 0.5, y + 0.5 - size * 0.5) / (size * 0.5)
			var r := d.length()
			var v := 1.0 - smoothstep(0.7, 1.0, r)   # the pool fades at the cone's rim
			v *= 0.55 + 0.45 * (1.0 - smoothstep(0.0, 0.35, r))   # the hot core
			var bar := minf(absf(d.x), absf(d.y))   # the frame bars: a cross of thin shadow lines
			v *= 1.0 - 0.7 * (1.0 - smoothstep(0.02, 0.06, bar)) * smoothstep(0.1, 0.25, r)
			img.set_pixel(x, y, Color(v, v, v))
	return ImageTexture.create_from_image(img)


## The warm lights of the first MAX_LIGHTS lanterns (the square's four first, then the gates nearest the centre): SpotLight3D down-cones with the projector cookie, colour (1.0, 0.74, 0.48),
## the four nearest the centre cast shadows.
func _add_lights(layout: Dictionary) -> void:
	var list := lanterns(layout)
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (a["at"] as Vector2).length() < (b["at"] as Vector2).length())
	var cookie := lantern_projector()
	for i in mini(list.size(), MAX_LIGHTS):
		var at: Vector2 = list[i]["at"]
		var light := SpotLight3D.new()
		light.name = "Lantern%d" % i
		light.position = Vector3(at.x, LANTERN_HEIGHT_IN, at.y) * INCHES_TO_METERS
		light.rotation_degrees = Vector3(-90.0, 0.0, 0.0)   # straight down
		light.light_color = LANTERN_SQUARE_COLOUR if i < SHADOWED_LANTERNS else LANTERN_COLOUR
		light.light_energy = LANTERN_ENERGY   # measured: <= 0.2 % of pixels above 0.95 luminance in street, wall and fountain
		light.spot_range = 0.2   # (was 0.34; 8 in still reaches the ground 2.55 in below at the widest cone)
		light.spot_angle = lantern_cone_deg(i)
		light.spot_attenuation = 1.0
		light.light_projector = cookie
		light.light_specular = 0.4
		light.light_cull_mask &= ~BoardgenMood.LAMP_IRON_LAYER   # the lamp's own iron is lit by the moon and the other lamps, not from inside its cage
		light.shadow_enabled = i < SHADOWED_LANTERNS
		add_child(light)
		var fill := OmniLight3D.new()
		fill.name = "LanternFill%d" % i
		fill.position = light.position
		fill.light_color = LANTERN_COLOUR
		fill.light_energy = FILL_ENERGY
		fill.omni_range = FILL_RANGE_M
		fill.omni_attenuation = 2.0
		fill.light_specular = 0.0
		fill.light_cull_mask &= ~BoardgenMood.LAMP_IRON_LAYER
		fill.shadow_enabled = false
		add_child(fill)


## The ember glows: warm omni lights 0.6 in over the ground, no shadow (a cheap light), range 7 in.
func _add_embers(layout: Dictionary) -> void:
	var i := 0
	for e: Dictionary in ember_glows(layout):
		var at: Vector2 = e["at"]
		var light := OmniLight3D.new()
		light.name = "Ember%d" % i
		light.position = Vector3(at.x, 0.6, at.y) * INCHES_TO_METERS
		light.light_color = EMBER_COLOUR
		light.light_energy = EMBER_ENERGY
		light.omni_range = EMBER_RANGE_M
		light.omni_attenuation = 1.6
		light.light_specular = 0.0
		light.shadow_enabled = false
		add_child(light)
		i += 1


## One ReflectionProbe over the board, rendered ONCE after the build (plan R7b): the water and the wet stone mirror the sky instead of black. The box is the board plus a margin, low (the pieces stand
## up to 9 in = 0.23 m).
func _add_probe(layout: Dictionary) -> void:
	var probe := ReflectionProbe.new()
	probe.name = "BoardProbe"
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.size = Vector3(float(layout["nx"]) * float(layout["cell_in"]) * INCHES_TO_METERS * 1.1, 0.5, float(layout["nz"]) * float(layout["cell_in"]) * INCHES_TO_METERS * 1.1)
	probe.position = Vector3(0.0, 0.2, 0.0)
	probe.intensity = 0.8
	add_child(probe)


## The decay story of a board (plan R5): the board's seed picks the way the fire came from (a unit vector) and, a quarter turn off it, the shade side where moss grows. Returned as a Color
## (r, g = fire x, z; b, a = shade x, z) for the shader's `story` uniform. Pure: the same seed, the same story.
static func story(seed: int) -> Color:
	var fire := _hash(seed, 0, 210) * TAU
	var turn := 1.0 if _hash(seed, 0, 211) < 0.5 else -1.0
	var shade := fire + turn * PI * 0.5
	return Color(cos(fire), sin(fire), cos(shade), sin(shade))


## The BLUE HOUR of the town (decision D-R4): a cool pale moon as the key, high on one side; the last warm light low on the opposite horizon (the scene's fill light, turned round) as a rim; a
## cool sky; the lanterns are the only strong warm source. Applied to the scene's lighting controller (a dev view, so it is not restored).
## Readability tuning (tools: gate3.sh, the median of three repeats per row against the plain-table baseline; lead 21.11.): a strongly blue moon washed the figures' colours, so the key is pale (nearly
## neutral) and strong (5.5), comes from the side of the play camera (azimuth -20 deg; at -55 deg the far models stood against lit walls) and the ambient is lower (0.9); the shader's ground values (cobbles,
## packed earth, garden plots, the decks of yards and tiers) sit below the models' own values, and the Ultra preset's bounce light is turned down (SDFGI_ENERGY, SSIL_INTENSITY). The blue stays in the sky,
## the ambient and the shadows. The measured moves are in PLAN_RUINTOWN_AAA.md.
static func dusk(lighting: Object) -> void:
	if lighting == null:
		return
	lighting.set_sun_color(MOON_COLOUR)
	lighting.set_sun_energy(MOON_ENERGY)
	lighting.set_sun_angles(MOON_AZIMUTH, MOON_ELEVATION)
	lighting.set_ambient_color(AMBIENT_COLOUR)
	lighting.set_ambient_energy(AMBIENT_ENERGY)
	lighting.set_exposure(EXPOSURE)
	if lighting.has_method("set_ssao_radius"):   # board-scale occlusion (plan R7b): the presets' 0.8 - 1.2 m radius is wider than the whole 1.2 m board
		lighting.set_ssao_radius(SSAO_RADIUS_M)
		lighting.set_ssao_intensity(SSAO_INTENSITY)
	if lighting.has_method("set_sdfgi_energy"):
		lighting.set_sdfgi_energy(SDFGI_ENERGY)
		lighting.set_ssil_intensity(SSIL_INTENSITY)
	lighting.set_fill_light_color(MOON_COLOUR)   # the SECOND moon, the half turn of the first: the board is a half-turn mirror, so a fair light is too (the gate at the opposite player's side)
	lighting.set_fill_light_energy(MOON2_ENERGY)
	var key: Variant = lighting.get("_directional_light")   # the moons' specular is turned down: a strong pale light on the glossy pawns adds a white veil that washes their colours (the gate)
	if key is DirectionalLight3D:
		(key as DirectionalLight3D).light_specular = MOON_SPECULAR
	var fill: Variant = lighting.get("_fill_light")   # no setter for its direction: turn it to the opposite azimuth by hand
	if fill is DirectionalLight3D:
		var light := fill as DirectionalLight3D
		light.shadow_enabled = MOON2_SHADOWS
		light.light_specular = MOON_SPECULAR
		var h := deg_to_rad(MOON_AZIMUTH + 180.0)
		var v := deg_to_rad(MOON_ELEVATION)
		light.position = Vector3(cos(v) * sin(h), sin(v), cos(v) * cos(h)) * 10.0
		light.look_at(Vector3.ZERO, Vector3.UP)


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
			out.append({"lo": Vector3(box_lo.x, 0.0, box_lo.y), "hi": Vector3(box_lo.x + box_size.x, size.y, box_lo.y + box_size.y), "kind": "wood", "solid": false, "prop": true,
				"face": d, "at": Vector2(cd["x"], cd["z"]), "along": along})   # the wall side and the cell: where an authored module of the strip stands instead of the box
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
func build(layout: Dictionary, material: Material, prism_roofs := true, timber: Dictionary = {}) -> void:   # prism_roofs false: BoardgenTownKit draws the gable roofs (hip and catslide have no module: they stay procedural)
	var list: Array[Dictionary] = []
	var damage: Array = []
	for r: Dictionary in roofs(layout):
		for st: Dictionary in ridge_strips(r):   # (L1) a twin roof is two prisms; (L2) a broken one its pieces and its timber
			if prism_roofs or st["type"] != "gable":
				var parts := roof_parts(st)
				list.append_array(parts[0])
				for b: Dictionary in parts[1]:
					damage.append([Basis(Vector3.UP, b["yaw"]) * Basis(Vector3.RIGHT, -float(b["pitch"])) * Basis.from_scale(b["size"] * INCHES_TO_METERS), b["centre"] * INCHES_TO_METERS,
						Color(BoardgenTheme.TOWN_KINDS.find(b["kind"]), b["size"].x, b["size"].y, b["size"].z)])
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
			var basis := Basis(Vector3.BACK, float(r.get("tilt", 0.0))) * Basis.from_scale(Vector3(r["length"], r["height"], r["width"]) * INCHES_TO_METERS)
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
	BoardgenTownSilhouette._multimesh(self, "RoofDamage", BoxMesh.new(), damage, material)   # (L2) one more draw: tile courses and timber of the broken roofs
	_add_bodies(layout, material)
	BoardgenTownSilhouette.build(self, layout, material, timber)   # (timber: the ruined lots whose gables the kit draws in timber, BoardgenTownFrames)
	_add_lights(layout)
	_add_embers(layout)
	_add_probe(layout)


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
