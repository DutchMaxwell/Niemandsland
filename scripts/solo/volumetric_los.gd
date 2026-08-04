class_name VolumetricLos
extends RefCounted
## The ONE volumetric line-of-sight truth (elevation program, Phase A; GF Advanced Rules v3.5.1 p.56
## "alternative method"): every model occupies a CYLINDER standing on its base, every terrain piece is a
## 3D VOLUME in real dimensions, and a sight query is ONE 3D segment from eye to eye. Pure + static, no
## scene / mesh / physics dependency — the game (terrain_overlay, main.gd, sight fan, ruler) and the
## headless simulator both call THIS module, so sight math and sight visuals can never disagree again.
##
## UNITS: METRES everywhere inside this module (INCHES_TO_METERS). Callers that hold inch coordinates
## (solo_sim) convert at the boundary. Never mix the two inside a call.
##
## Model heights come from the BASE SIZE via the official table, NEVER from mesh bounds: meshes are
## optional per-client CDN content, so a mesh-derived height would desync multiplayer. Line of sight must
## stay a pure function of synced state (position + base size).

const INCHES_TO_METERS := 0.0254

## Official volumetric model heights as Vector2(base size in mm, model height in inches). Sizes between
## two rows interpolate LINEARLY; anything below the first / above the last row clamps to it.
const BASE_HEIGHT_TABLE := [
	Vector2(25.0, 1.0), Vector2(32.0, 1.25), Vector2(40.0, 1.5),
	Vector2(50.0, 2.0), Vector2(60.0, 3.0), Vector2(100.0, 4.0),
]


# === Model heights from the base (P1) ===

## Model height in INCHES for a round base of `base_mm`, off BASE_HEIGHT_TABLE (linear between rows,
## clamped outside). Oval bases feed their mean size in through oval_effective_mm().
static func height_in_for_base_mm(base_mm: float) -> float:
	var first: Vector2 = BASE_HEIGHT_TABLE[0]
	if base_mm <= first.x:
		return first.y
	for i in range(1, BASE_HEIGHT_TABLE.size()):
		var hi: Vector2 = BASE_HEIGHT_TABLE[i]
		if base_mm <= hi.x:
			var lo: Vector2 = BASE_HEIGHT_TABLE[i - 1]
			return lo.y + (hi.y - lo.y) * (base_mm - lo.x) / (hi.x - lo.x)
	return (BASE_HEIGHT_TABLE[BASE_HEIGHT_TABLE.size() - 1] as Vector2).y


## Effective (round-equivalent) base size in mm of an OVAL base: the mean of its two axes.
static func oval_effective_mm(width_mm: float, depth_mm: float) -> float:
	return (width_mm + depth_mm) * 0.5


# === Segment vs. volume (slab-clip first, then the flat 2D test) ===
# A volume is an upright prism: a 2D footprint extruded between y0 and y1 (metres). The exact test is
# therefore "clip the segment's t-range by the y-slab [y0,y1], then run the existing 2D footprint test on
# the CLIPPED XZ subsegment" — seeing OVER a piece is simply an empty clip, which is the whole elevation
# win. Volume dicts (registry entries) are:
#   box: {"kind":"box","c":Vector2,"he":Vector2,"yaw":float,"y0":float,"y1":float,"solid":bool}
#   cyl: {"kind":"cyl","c":Vector2,"r":float,"y0":float,"y1":float,"solid":bool}

## The part of the segment a->b that lies inside the y-slab [y0,y1], as Vector2(t_low, t_high) along the
## segment. t_low > t_high means the segment never enters the slab (it passes entirely over or under the
## volume). Boundaries count as inside: two equally tall models on flat ground look each other in the eye
## exactly at the top of an equally tall blocker, and that line IS blocked.
static func slab_t_range(a: Vector3, b: Vector3, y0: float, y1: float) -> Vector2:
	var dy := b.y - a.y
	if absf(dy) < 1e-9:
		return Vector2(0.0, 1.0) if (a.y >= y0 and a.y <= y1) else Vector2(1.0, 0.0)
	var t_a := (y0 - a.y) / dy
	var t_b := (y1 - a.y) / dy
	return Vector2(maxf(0.0, minf(t_a, t_b)), minf(1.0, maxf(t_a, t_b)))


## True if the 3D segment a->b touches the upright box volume `vol` (rotated footprint, yaw follows the
## node rotation.y convention of TerrainRules.point_in_obb).
static func segment_hits_box(a: Vector3, b: Vector3, vol: Dictionary) -> bool:
	var t := slab_t_range(a, b, float(vol["y0"]), float(vol["y1"]))
	if t.x > t.y:
		return false
	var p := a.lerp(b, t.x)
	var q := a.lerp(b, t.y)
	return TerrainRules.segment_intersects_obb(Vector2(p.x, p.z), Vector2(q.x, q.z),
		vol["c"], vol["he"], float(vol["yaw"]))


## True if the 3D segment a->b touches the upright cylinder volume `vol`.
static func segment_hits_cyl(a: Vector3, b: Vector3, vol: Dictionary) -> bool:
	var t := slab_t_range(a, b, float(vol["y0"]), float(vol["y1"]))
	if t.x > t.y:
		return false
	var p := a.lerp(b, t.x)
	var q := a.lerp(b, t.y)
	return segment_intersects_circle(Vector2(p.x, p.z), Vector2(q.x, q.z), vol["c"], float(vol["r"]))


## True if the flat segment from->to passes through (or touches) the circle. Own copy so the module keeps
## no dependency on the 2D ladder in los_rules.gd, which this program retires.
static func segment_intersects_circle(from_pt: Vector2, to_pt: Vector2, centre: Vector2, radius: float) -> bool:
	var seg := to_pt - from_pt
	var seg_len_sq := seg.length_squared()
	var t := 0.0
	if seg_len_sq > 0.0:
		t = clampf((centre - from_pt).dot(seg) / seg_len_sq, 0.0, 1.0)
	return (from_pt + seg * t).distance_to(centre) <= radius
