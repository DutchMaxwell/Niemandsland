class_name BoardgenDressProps
extends DressPlanner
## The props planner of the ruin-town dressing (SPEC_RUINTOWN_DRESSING step 30): one lamp visual at
## every lantern point of BoardgenTownDressing (a bracket on the nearest raised or solid face within
## LAMP_REACH_IN of the point, else a post at the point, the R1 exception), the fountain on the
## solid TankCluster and the statue plinth on the solid Crane. Placements only: the lantern lights,
## the landmark boxes and their colliders stay where they are. A PumpHouse has no module: its rim
## boxes belong to this class and are not drawn while the class is dressed.

const MODULES: Array[String] = [
	"dr_lamp_bracket", "dr_lamp_post", "dr_fountain", "dr_statue_plinth"
]
const LAMP_REACH_IN := 0.75
# the bracket's origin height; its glass sits at the 2.55 in light, nothing below CLEAR
const BRACKET_Y_IN := 2.6

# a lamp keeps off a door (R12): the opening widened by this much either side, this far out
const DOOR_SIDE_IN := 0.5
const DOOR_OUT_IN := 1.0
const LAMP_RADIUS_IN := 0.1  # the post's / lantern's half width (the 0.2 in envelope)
const MAX_SHIFT_IN := 2.0  # a lamp moves at most this far along the face, else it is dropped
const BRACKET_GLASS_OUT_IN := 0.205  # the bracket lantern's glass centre out from the wall face


func plan(context: DressContext) -> Array[DressPlacement]:
	var out: Array[DressPlacement] = []
	var doors := door_zones(context, BoardgenDressHouses.new().plan(context))
	for l: Dictionary in BoardgenTownDressing.lanterns(context.layout):
		var lamp := place_lamp(context, l["at"], doors)
		if lamp != null:
			out.append(lamp)
	for lm: Dictionary in context.layout["landmarks"]:
		match str(lm["kind"]):
			"TankCluster":
				out.append(
					DressPlacement.new("dr_fountain", _at_landmark(context, lm, 0.0), "props")
				)
			"Crane":
				var yaw := float(lm["turn"]) * PI * 0.5
				out.append(
					DressPlacement.new("dr_statue_plinth", _at_landmark(context, lm, yaw), "props")
				)
	return out


## Where each lantern point's lamp carries its glass (board inches, xz): {at: Vector2, or null when
## the lamp is dropped}. BoardgenTownDressing puts the lantern's lights there.
func glass(context: DressContext) -> Dictionary:
	var out := {}
	var doors := door_zones(context, BoardgenDressHouses.new().plan(context))
	for l: Dictionary in BoardgenTownDressing.lanterns(context.layout):
		var lamp := place_lamp(context, l["at"], doors)
		out[l["at"]] = null if lamp == null else glass_of(lamp)
	return out


## The xz glass centre of a lamp placement, board inches.
static func glass_of(lamp: DressPlacement) -> Vector2:
	var at := Vector2(lamp.transform.origin.x, lamp.transform.origin.z) / Units.INCHES_TO_METERS
	if lamp.module == "dr_lamp_bracket":
		var o := lamp.transform.basis.z
		at += Vector2(o.x, o.z).normalized() * BRACKET_GLASS_OUT_IN
	return at


## The lamp for lantern point `at` clear of every door zone: as placed when it is clear, else moved
## along the blocking door's face past its zone (the nearer end first), else null (dropped).
func place_lamp(context: DressContext, at: Vector2, doors: Array[Dictionary]) -> DressPlacement:
	var tries: Array[Vector2] = [at]
	for z: Dictionary in doors:
		if _in_door(z, at, LAMP_RADIUS_IN + 0.3):
			var s: float = (at - z["p"]).dot(z["a"])
			var ends: Array[float] = [
				z["s0"] - 0.3 - 2.0 * LAMP_RADIUS_IN, z["s1"] + 0.3 + 2.0 * LAMP_RADIUS_IN
			]
			ends.sort_custom(func(e0: float, e1: float) -> bool: return absf(e0 - s) < absf(e1 - s))
			for e in ends:
				if absf(e - s) > MAX_SHIFT_IN:
					continue
				tries.append(at + z["a"] * (e - s))
	for p in tries:
		var lamp := _lamp_at(context, p)
		var spots: Array[Vector2] = [p]
		if lamp.module == "dr_lamp_bracket":
			var o3 := lamp.transform.basis.z
			var face := (
				Vector2(lamp.transform.origin.x, lamp.transform.origin.z) / Units.INCHES_TO_METERS
			)
			spots = [face, face + Vector2(o3.x, o3.z).normalized() * 0.205]
		elif p != at and (context.top_in(_cx(context, p.x), _cx(context, p.y, true)) > 0.0):
			continue  # a moved post must still stand on the ground
		if doors.all(
			func(z: Dictionary) -> bool:
				return spots.all(
					func(q: Vector2) -> bool: return not _in_door(z, q, LAMP_RADIUS_IN)
				)
		):
			return lamp
	return null


## A post at `at`, or a bracket on the nearest raised face within reach.
func _lamp_at(context: DressContext, at: Vector2) -> DressPlacement:
	var b := _bracket(context, at)
	if b.is_empty():
		var xf := Transform3D(Basis(), Vector3(at.x, 0.0, at.y) * Units.INCHES_TO_METERS)
		return DressPlacement.new("dr_lamp_post", xf, "props")
	return DressPlacement.new("dr_lamp_bracket", b["xf"], "props")


func _cx(context: DressContext, v: float, z_axis := false) -> int:
	return floori((v - context.origin_in[1 if z_axis else 0]) / context.cell_in)


## The keep-out zone of every door opening (an opening from the ground up) of `placements`, board
## inches: {p (face origin), a (along), o (out), s0, s1 (along, widened by DOOR_SIDE_IN)}.
static func door_zones(
	context: DressContext, placements: Array[DressPlacement]
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for pl in placements:
		var spec := context.spec(pl.module)
		if spec == null:
			continue
		for op: Array in spec.openings:
			if float(op[2]) > 0.05:
				continue  # a window, not a door
			var b := pl.transform.basis
			(
				out
				. append(
					{
						"p":
						(
							Vector2(pl.transform.origin.x, pl.transform.origin.z)
							/ Units.INCHES_TO_METERS
						),
						"a": Vector2(b.x.x, b.x.z).normalized(),
						"o": Vector2(b.z.x, b.z.z).normalized(),
						"s0": float(op[0]) - DOOR_SIDE_IN,
						"s1": float(op[1]) + DOOR_SIDE_IN,
					}
				)
			)
	return out


## Whether a disc of radius `r` at `q` touches door zone `z` (out 0..DOOR_OUT_IN from the face).
static func _in_door(z: Dictionary, q: Vector2, r: float) -> bool:
	var s: float = (q - z["p"]).dot(z["a"])
	var o: float = (q - z["p"]).dot(z["o"])
	return s > z["s0"] - r and s < z["s1"] + r and o > -0.3 - r and o < DOOR_OUT_IN + r


## The bracket transform on the nearest raised (top > 0) cell face within LAMP_REACH_IN of `at`, or
## {} when there is none: origin on the face at BRACKET_Y_IN, +z out of the face toward the point.
func _bracket(context: DressContext, at: Vector2) -> Dictionary:
	var cell := context.cell_in
	var org := context.origin_in
	var cx := floori((at.x - org.x) / cell)
	var cz := floori((at.y - org.y) / cell)
	var best := LAMP_REACH_IN
	var found := {}
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var x := cx + dx
			var z := cz + dz
			if x < 0 or z < 0 or x >= context.nx or z >= context.nz or context.top_in(x, z) <= 0.0:
				continue
			var lo := org + Vector2(x, z) * cell
			var hi := lo + Vector2(cell, cell)
			var in_z: bool = at.y >= lo.y - 0.15 and at.y <= hi.y + 0.15
			var in_x: bool = at.x >= lo.x - 0.15 and at.x <= hi.x + 0.15
			var edges := [
				[
					hi.x - at.x,
					Vector3(hi.x, BRACKET_Y_IN, at.y),
					Vector3(0, 0, -1),
					Vector3.RIGHT,
					in_z
				],
				[
					at.x - lo.x,
					Vector3(lo.x, BRACKET_Y_IN, at.y),
					Vector3(0, 0, 1),
					Vector3.LEFT,
					in_z
				],
				[
					lo.y - at.y,
					Vector3(at.x, BRACKET_Y_IN, lo.y),
					Vector3.LEFT,
					Vector3(0, 0, -1),
					in_x
				],
				[
					at.y - hi.y,
					Vector3(at.x, BRACKET_Y_IN, hi.y),
					Vector3.RIGHT,
					Vector3(0, 0, 1),
					in_x
				],
			]
			for e: Array in edges:
				var d: float = e[0]
				if d >= 0.0 and d < best and bool(e[4]):
					best = d
					found = {"xf": BoardgenDressRules.face_xf(e[1], e[2], e[3], 0.0, 0.0)}
	return found


## A landmark module centred in its footprint, yawed by `yaw` about the footprint centre.
func _at_landmark(context: DressContext, lm: Dictionary, yaw: float) -> Transform3D:
	var c: Vector2 = (
		context.origin_in
		+ (Vector2(lm["x"], lm["z"]) + Vector2(lm["w"], lm["h"]) * 0.5) * context.cell_in
	)
	return Transform3D(Basis(Vector3.UP, yaw), Vector3(c.x, 0.0, c.y) * Units.INCHES_TO_METERS)
