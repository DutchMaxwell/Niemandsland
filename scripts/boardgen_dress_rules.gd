class_name BoardgenDressRules
extends RefCounted
## The honesty rules of the ruin-town dressing (docs/adr/0003-generated-board-dressing.md, R1-R5 as
## plain arithmetic): the dressing never hides a walkable cell, never suggests a surface that is not
## there. The grid is the truth; a DressPlacement is checked against it with the numbers its
## DressModuleSpec declares (aabb_lo / aabb_hi, proud per height band, tags, family, role). Pure
## data, headless. Everything is in board inches, origin at the board centre. A model standing on a
## walkable cell needs the column above its top free: FLAT (0.08) of anything, then nothing up to
## CLEAR (2.0), except the edge strip of an edge that drops (R4); above CLEAR only an overhang (R2).
## R3 = the drawn face sits 0..0.2 inside the collider face. R5 = the ladder zones carry only
## ladders and plain faces. Layout of this file: the grid helpers and the constants first, then
## violations() for R1 / R2 / R4, then R3 (the face sits 0..0.2 in inside the collider face, lean <=
## 1.5 degrees) and R5 (the ladder zones).

# inches: what may lie on a walkable top (decals, flat litter) without counting as an obstacle
const FLAT := 0.08
const CLEAR := 2.0  # inches: the column above a walkable top that a standing model needs free
# inches: how far a piece above CLEAR may reach over a walkable cell from a taller footprint (R2)
const OVERHANG := 0.35
const REACH := 0.2  # inches: how far a drawn face may sit inside its collider face (R3)
const EDGE := 0.4  # inches: the edge strip of a dropping edge where a parapet may stand (R4)
# inches: the highest a piece in the edge strip may rise above the tier top (R4)
const PARAPET := 0.7
# soft vegetation (tag soft_veg) up to this high is no obstacle on the ground (R1 exception)
const SOFT_VEG := 0.4
const LADDER_GAP := 0.9  # inches kept free beyond a ladder's half width on each side (R5)
const LADDER_HALF_WIDTH_IN := 0.5
const LEAN_MAX := 1.5  # degrees a piece may lean (R3)
const LEAN_SLACK_DEG := 0.05  # float noise of the lean measurement, not a looser rule
const TOL := 0.02  # how far a piece may poke over a limit before it counts
# a ruin gable on a tier top: thin enough to read as a wall stub (R4 exception)
const GABLE_DEPTH_MAX_IN := 0.3
const GABLE_HEIGHT_MAX_IN := 2.6
const DEFAULT_TOWER_IN := 12.0  # the tall tower's top when the layout does not say
const MIN_UP_SCALE := 0.01  # guards the division by the up axis of a strongly tipped piece
const MIN_BAND_IN := 0.001  # a height band thinner than this has nothing in it
const FACES := ["house_panel", "ruin_face", "twall_face", "tower_face"]
# N, E, S, W
const DIRS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]


## The height of the surface a cell presents (a tall tower 12, a roofed house 2.5, else its level);
## off the board 0.
static func top_in(layout: Dictionary, x: int, z: int) -> float:
	if x < 0 or z < 0 or x >= int(layout["nx"]) or z >= int(layout["nz"]):
		return 0.0
	var cell: Dictionary = layout["cells"][z * int(layout["nx"]) + x]
	if cell["lot_kind"] == "Tower":
		return float(layout.get("tower_in", DEFAULT_TOWER_IN))
	if cell["lot_kind"] == "Roofed":
		return BoardgenGreybox.SOLID_IN
	return float(layout["level_in"][int(cell["level"])])


## Whether a model can stand on cell `i`: not a roofed house, not a tall tower, not a solid
## landmark's footprint.
static func walkable(layout: Dictionary, i: int) -> bool:
	var nx := int(layout["nx"])
	var x := i % nx
	var z := floori(i / float(nx))
	for landmark: Dictionary in layout["landmarks"]:
		if not landmark["solid"]:
			continue
		var x0 := int(landmark["x"])
		var z0 := int(landmark["z"])
		if x >= x0 and x < x0 + int(landmark["w"]) and z >= z0 and z < z0 + int(landmark["h"]):
			return false
	return not ["Roofed", "Tower"].has(layout["cells"][i]["lot_kind"])


## The cells no clutter or prop may take: both cells of every ladder and every landmark footprint.
## {cell index: "ladder" | "landmark"}
static func kept_clear(layout: Dictionary) -> Dictionary:
	var out := {}
	for connector: Dictionary in layout["connectors"]:
		out[int(connector["low"])] = "ladder"
		out[int(connector["high"])] = "ladder"
	for landmark: Dictionary in layout["landmarks"]:
		for dz in int(landmark["h"]):
			for dx in int(landmark["w"]):
				out[(int(landmark["z"]) + dz) * int(layout["nx"]) + int(landmark["x"]) + dx] = "landmark"
	return out


## The transform of a face module: its origin on the face's start point moved `inset_in` INTO the
## mass (against `out`), x along the face, y up, z out; `lean_deg` tips the top outward (negative:
## inward).
static func face_xf(
	start_in: Vector3, along: Vector3, out: Vector3, inset_in: float, lean_deg: float
) -> Transform3D:
	var basis := Basis(along, Vector3.UP, out) * Basis(Vector3.RIGHT, deg_to_rad(lean_deg))
	return Transform3D(basis, (start_in - out * inset_in) * Units.INCHES_TO_METERS)


## The R1-R5 breaks of a set of placements on a layout, one line per rule and placement ("R1 <cls>
## <module> at (x, z): ..."); empty = honest.
static func violations(context: DressContext, placements: Array) -> PackedStringArray:
	var out := PackedStringArray()
	var nx := context.nx
	var nz := context.nz
	var cell := context.cell_in
	var origin := context.origin_in
	var zones := _ladder_zones(context.layout)
	var kept := context.kept_clear()
	for placement: DressPlacement in placements:
		var spec := context.spec(placement.module)
		var xf := placement.transform
		var at := (
			"%s %s at (%.1f, %.1f)"
			% [
				placement.cls,
				placement.module,
				xf.origin.x / Units.INCHES_TO_METERS,
				xf.origin.z / Units.INCHES_TO_METERS
			]
		)
		if spec == null:
			out.append("R0 unknown module " + at)
			continue
		var tags := spec.tags
		var lo := spec.aabb_lo
		var hi := spec.aabb_hi
		var footprint := _rect(xf, lo, hi, lo.y, hi.y, hi.z)
		var seen := {}
		var found: Array[String] = []
		var plain_face: bool = FACES.has(spec.family) and ["plain", "foot"].has(spec.role)
		if not tags.has("ladder") and not plain_face:
			for zone: Rect2 in zones:
				var overlap := zone.intersection(footprint)
				if overlap.size.x > TOL and overlap.size.y > TOL:
					found.append("R5 in a ladder's strip")
		var lean := rad_to_deg(xf.basis.y.normalized().angle_to(Vector3.UP))
		if lean > LEAN_MAX + LEAN_SLACK_DEG:
			found.append("R3 leans %.2f degrees" % lean)
		if FACES.has(spec.family):
			var outward := Vector2(xf.basis.z.x, xf.basis.z.z).normalized()
			var mid3 := (
				xf
				* (Vector3(spec.len_in * 0.5, 0.0, 0.0) * Units.INCHES_TO_METERS)
				/ Units.INCHES_TO_METERS
			)
			var mid := Vector2(mid3.x, mid3.z)
			var axis := 0 if absf(outward.x) > absf(outward.y) else 1
			# the cell the face belongs to, along its axis
			var inside := floori((mid[axis] - outward[axis] * 0.5 - origin[axis]) / cell)
			var collider_face := origin[axis] + (inside + (1 if outward[axis] > 0.0 else 0)) * cell
			var inset := (collider_face - mid[axis]) * signf(outward[axis])
			if inset < -TOL or inset > REACH + TOL:
				found.append("R3 sits %.2f in inside the collider face" % inset)
		var cz_first := maxi(floori((footprint.position.y - origin.y) / cell), 0)
		var cz_last := mini(floori((footprint.end.y - origin.y) / cell), nz - 1)
		var cx_first := maxi(floori((footprint.position.x - origin.x) / cell), 0)
		var cx_last := mini(floori((footprint.end.x - origin.x) / cell), nx - 1)
		for cz in range(cz_first, cz_last + 1):
			for cx in range(cx_first, cx_last + 1):
				if tags.has("soft_veg") and kept.has(cz * nx + cx):
					var cell_rect := Rect2(origin + Vector2(cx, cz) * cell, Vector2(cell, cell))
					if footprint.intersection(cell_rect).size.x > TOL:
						found.append("R1 soft vegetation in a kept-clear cell (ladder or landmark)")
				if context.walkable(cz * nx + cx):
					found.append(_air(context, spec, xf, cx, cz))
		for finding in found:
			var rule := finding.substr(0, 2)
			if finding != "" and not seen.has(rule):
				seen[rule] = true
				out.append("%s %s" % [rule, at + finding.substr(2)])
	return out


## R1 / R2 / R4 for one placement over one walkable cell: the first break as "Rn: why", or "".
static func _air(
	context: DressContext, spec: DressModuleSpec, xf: Transform3D, cx: int, cz: int
) -> String:
	var tags := spec.tags
	var lo := spec.aabb_lo
	var hi := spec.aabb_hi
	var layout := context.layout
	var nx := context.nx
	var nz := context.nz
	var cell := context.cell_in
	var origin := context.origin_in
	var cell_rect := Rect2(origin + Vector2(cx, cz) * cell, Vector2(cell, cell))
	var top := context.top_in(cx, cz)
	var origin_y := xf.origin.y / Units.INCHES_TO_METERS
	var up_scale := maxf(xf.basis.y.y, MIN_UP_SCALE)
	# no collider, no cover: on the ground a tuft is no obstacle up to SOFT_VEG (a tier top keeps R4)
	if tags.has("soft_veg") and top <= 0.0:
		return (
			""
			if origin_y + hi.y * up_scale - top <= SOFT_VEG + TOL
			else "R1: soft vegetation higher than %.1f in" % SOFT_VEG
		)
	if tags.has("R1_exception"):
		return ""
	if (
		(tags.has("bulky_ok") or tags.has("terrain_or_solid_only"))
		and _terrain(layout, cz * nx + cx)
	):
		return ""
	if tags.has("R4_gable") and top > 0.0:
		var thin_enough := -lo.z * xf.basis.z.length() <= GABLE_DEPTH_MAX_IN + TOL
		var low_enough := hi.y * up_scale <= GABLE_HEIGHT_MAX_IN + TOL
		return (
			""
			if thin_enough and low_enough
			else (
				"R4: a ruin gable over %.1f in thick or %.1f in high"
				% [GABLE_DEPTH_MAX_IN, GABLE_HEIGHT_MAX_IN]
			)
		)
	for zone in 2:  # zone 0: from FLAT up to CLEAR above the top, zone 1: above CLEAR
		var y0 := maxf(lo.y, (top + (FLAT if zone == 0 else CLEAR) - origin_y) / up_scale)
		var y1 := minf(hi.y, (top + CLEAR - origin_y) / up_scale if zone == 0 else INF)
		if y1 - y0 < MIN_BAND_IN:
			continue
		var proud := spec.proud_low if zone == 0 else spec.proud_high
		var part := _rect(xf, lo, hi, y0, y1, proud).intersection(cell_rect)
		if part.size.x <= TOL or part.size.y <= TOL:
			continue
		# the part over this cell lies within OVERHANG of a taller footprint (above CLEAR) or within EDGE
		# of a lower neighbour (the edge strip)
		var ok := false
		for k in 9:
			var neighbour := Vector2i(cx + k % 3 - 1, cz + floori(k / 3.0) - 1)
			if neighbour == Vector2i(cx, cz):
				continue
			var neighbour_top := context.top_in(neighbour.x, neighbour.y)
			var on_board := (
				neighbour.x >= 0 and neighbour.y >= 0 and neighbour.x < nx and neighbour.y < nz
			)
			var rises := (
				on_board
				and (neighbour_top > top or not context.walkable(neighbour.y * nx + neighbour.x))
			)
			if not (rises if zone == 1 else neighbour_top < top):
				continue
			var reach := OVERHANG if zone == 1 else EDGE
			if (
				Rect2(origin + Vector2(neighbour) * cell, Vector2(cell, cell))
				. grow(reach + TOL)
				. encloses(part)
			):
				ok = true
				break
		if zone == 1 and not ok:
			return (
				"R2: reaches over walkable cell (%d, %d) further than %.2f in from a taller footprint"
				% [cx, cz, OVERHANG]
			)
		if zone == 0 and top <= 0.0:
			return (
				"R1: stands in walkable cell (%d, %d) between %.2f and %.0f in"
				% [cx, cz, FLAT, CLEAR]
			)
		if zone == 0 and (not ok or origin_y + hi.y * up_scale - top > PARAPET + TOL):
			return (
				"R4: over walkable tier cell (%d, %d) outside the %.1f in edge strip or above %.1f in"
				% [cx, cz, EDGE, PARAPET]
			)
	return ""


## Cells that are terrain in the rules (garden plots, ruin yards) - bulky pieces may stand there.
static func _terrain(layout: Dictionary, i: int) -> bool:
	var cell: Dictionary = layout["cells"][i]
	return (
		cell["lot_kind"] == "Rough"
		or (cell["lot_kind"] == "Terrace" and int(cell["level"]) == 0 and not cell["street"])
	)


## The strip every ladder keeps: LADDER_GAP beyond the ladder's half width to each side, from the
## top edge's EDGE strip over the wall face to the foot. [Rect2], board inches.
static func _ladder_zones(layout: Dictionary) -> Array[Rect2]:
	var out: Array[Rect2] = []
	var origin := Vector2(layout["nx"], layout["nz"]) * float(layout["cell_in"]) * -0.5
	var reach := LADDER_HALF_WIDTH_IN + LADDER_GAP
	for connector: Dictionary in layout["connectors"]:
		var edge := Vector2(connector["edge_in"][0], connector["edge_in"][1]) + origin
		var low := Vector2i(connector["low_xz"][0], connector["low_xz"][1])
		var high := Vector2i(connector["high_xz"][0], connector["high_xz"][1])
		var away := Vector2(low - high)
		var side := Vector2(away.y, away.x)
		var near_corner := edge - away * EDGE - side * reach
		var far_corner := edge + away * reach + side * reach
		out.append(Rect2(near_corner, Vector2.ZERO).expand(far_corner))
	return out


## The XZ rect (board inches) of a module's part between local heights y0 and y1, cut at `reach`
## along its local +z.
static func _rect(
	xf: Transform3D, lo: Vector3, hi: Vector3, y0: float, y1: float, reach: float
) -> Rect2:
	var out := Rect2()
	for corner in 8:  # bit 0 = x, bit 1 = y, bit 2 = z of the box corner
		var local := Vector3(
			hi.x if corner & 1 else lo.x, y1 if corner & 2 else y0, reach if corner & 4 else lo.z
		)
		var point := xf * (local * Units.INCHES_TO_METERS) / Units.INCHES_TO_METERS
		out = (
			Rect2(point.x, point.z, 0.0, 0.0)
			if corner == 0
			else out.expand(Vector2(point.x, point.z))
		)
	return out
