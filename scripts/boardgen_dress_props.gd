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


func plan(context: DressContext) -> Array[DressPlacement]:
	var out: Array[DressPlacement] = []
	for l: Dictionary in BoardgenTownDressing.lanterns(context.layout):
		var at: Vector2 = l["at"]
		var b := _bracket(context, at)
		if b.is_empty():
			var xf := Transform3D(Basis(), Vector3(at.x, 0.0, at.y) * Units.INCHES_TO_METERS)
			out.append(DressPlacement.new("dr_lamp_post", xf, "props"))
		else:
			out.append(DressPlacement.new("dr_lamp_bracket", b["xf"], "props"))
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
