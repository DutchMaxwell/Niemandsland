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

## Sight lines shorter than this are always clear: nothing fits between two all-but-touching models.
const MIN_SPAN_M := 0.02

## Gaps narrower than this between two models of the SAME unit count as closed (tournament standard).
const CLOSED_GAP_INCHES := 1.0

## Height tolerance for slab tests. Vector3 carries 32-bit floats while the volume dicts hold 64-bit
## ones, so "the eye is exactly as high as this volume's top" — the everyday case of two equally tall
## models on flat ground — must not flip on rounding noise. 1e-6 m is 0.00004": invisible to the rules.
const Y_EPS_M := 1e-6

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


## Fallback base radius (16 mm = half a 32 mm round base) for models without unit data.
const DEFAULT_BASE_RADIUS_M := 0.016

## MEAN base radius (metres) of a model — the radius the sight CYLINDER is built from. Round bases use
## their real radius, ovals their mean semi-axis (a circle is close enough for a sight footprint, and it
## matches how oval_effective_mm feeds the height table). Falls back to half a 32 mm base without unit
## data. Moved here from the retired los_rules.gd in W5.23, semantics unchanged.
##
## NOTE the deliberate difference from SoloController.model_base_radius_m: that one CIRCUMSCRIBES the
## base (the movement/separation clearance radius, which must never under-report) — this one averages.
static func model_base_radius_m(model: ModelInstance) -> float:
	if model == null or model.unit == null:
		return DEFAULT_BASE_RADIUS_M
	var game_unit = model.unit
	if game_unit.unit_properties == null:
		return DEFAULT_BASE_RADIUS_M
	# Use the model's ACTUAL base (a per-model Tough upgrade enlarges it; mesh stays natural).
	var model_tough := int(model.properties.get("tough", 0)) if model.properties else 0
	var props: Dictionary = OPRArmyManager.effective_base_props(game_unit.unit_properties, model_tough)
	if props.get("base_is_oval", false):
		var width_mm: float = props.get("base_width_mm", 32)
		var depth_mm: float = props.get("base_depth_mm", 32)
		return (width_mm + depth_mm) / 4.0 * 0.001
	return float(props.get("base_size_round", 32)) / 2.0 * 0.001


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
	var lo := y0 - Y_EPS_M
	var hi := y1 + Y_EPS_M
	var dy := b.y - a.y
	if absf(dy) < 1e-9:
		return Vector2(0.0, 1.0) if (a.y >= lo and a.y <= hi) else Vector2(1.0, 0.0)
	var t_a := (lo - a.y) / dy
	var t_b := (hi - a.y) / dy
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


# === The sight query ===
# A model cylinder is {"c":Vector2,"r":float,"y0":float,"y1":float} — its base footprint extruded from
# where it stands to its own height. The eye sits at the TOP CENTRE and LOS is ONE segment eye->eye
# (G1): no multi-sample visibility, partial-visibility nuance is intentionally dropped.

## Eye point of a model cylinder: the centre of its top disc.
static func eye(cyl: Dictionary) -> Vector3:
	var c: Vector2 = cyl["c"]
	return Vector3(c.x, float(cyl["y1"]), c.y)


## True if the model `from_cyl` can see `to_cyl`. `volumes` are terrain volumes (see above), `blockers`
## are other models as cylinders, `exclude` holds the unit keys that never block their own sight line.
static func has_los(from_cyl: Dictionary, to_cyl: Dictionary, volumes: Array = [],
		blockers: Array = [], exclude: Array = []) -> bool:
	var a := eye(from_cyl)
	var b := eye(to_cyl)
	if a.distance_to(b) < MIN_SPAN_M:
		return true   # all but the same spot: nothing can stand between them
	if bool(to_cyl.get("is_aircraft", false)):
		return true   # P6: an aircraft is abstract — always visible, wherever it hovers
	if first_blocking_unit_key(a, b, blockers, exclude) != 0:
		return false
	for vol: Dictionary in volumes:
		if not segment_hits_volume(a, b, vol):
			continue
		if bool(vol.get("solid", true)):
			return false   # solid pieces hard-block, own zone or not
		# P4 area terrain: see INTO and OUT OF the zone you are in, just not through someone else's.
		if point_inside_volume(a, vol) or point_inside_volume(b, vol):
			continue
		return false
	return true


## The unit key of the first model standing in the sight line (0 = the lane is clear), so a rules-correct
## refusal can name the blocker. Blockers are model cylinders plus "unit_key" and "is_aircraft"; a unit
## never blocks its own sight line (`exclude` carries the shooter's and the target's key). Geometry alone
## decides — a taller eye simply passes over a shorter cylinder, there is no height ladder any more.
static func first_blocking_unit_key(a: Vector3, b: Vector3, blockers: Array, exclude: Array) -> int:
	var by_unit: Dictionary = {}   # Dictionary[int, Array] for the closed-gap pass below
	for bl: Dictionary in blockers:
		var key := int(bl.get("unit_key", 0))
		if exclude.has(key) or bool(bl.get("is_aircraft", false)):
			continue   # own/target unit, and aircraft bases are transparent (P6)
		if segment_hits_cyl(a, b, bl):
			return key
		if not by_unit.has(key):
			by_unit[key] = []
		by_unit[key].append(bl)

	# Closed-gap pass: a gap of less than 1" between two models of the SAME unit counts as closed, so the
	# line cannot thread between them. In 3D the wall is only as tall as the shorter of the pair.
	var closed_gap_m := CLOSED_GAP_INCHES * INCHES_TO_METERS
	var a2 := Vector2(a.x, a.z)
	var b2 := Vector2(b.x, b.z)
	for key: int in by_unit:
		var models: Array = by_unit[key]
		for i: int in models.size():
			for j: int in range(i + 1, models.size()):
				var m: Dictionary = models[i]
				var n: Dictionary = models[j]
				var mc: Vector2 = m["c"]
				var nc: Vector2 = n["c"]
				if mc.distance_to(nc) - float(m["r"]) - float(n["r"]) >= closed_gap_m:
					continue
				var hit = Geometry2D.segment_intersects_segment(a2, b2, mc, nc)
				if hit == null:
					continue
				var seg := b2 - a2
				var t := 0.0
				if seg.length_squared() > 0.0:
					t = clampf(((hit as Vector2) - a2).dot(seg) / seg.length_squared(), 0.0, 1.0)
				if lerpf(a.y, b.y, t) < minf(float(m["y1"]), float(n["y1"])):
					return key
	return 0


## Height (metres) of the walkable surface at the flat point `p`: the top of the tallest SOLID volume
## whose footprint contains it (container roof, floor slab), else the table at 0. The AI checker and the
## ruler place hypothetical models with this, so their eyes match a real model's drop-probe placement.
static func surface_y_at(p: Vector2, volumes: Array) -> float:
	var y := 0.0
	for vol: Dictionary in volumes:
		if not bool(vol.get("solid", true)):
			continue   # area terrain is ground you walk in, not a surface you stand on top of
		var top := float(vol["y1"])
		if top <= y:
			continue
		if point_in_footprint(p, vol):
			y = top
	return y


## Dispatch: does the segment a->b touch this volume, whatever kind it is?
static func segment_hits_volume(a: Vector3, b: Vector3, vol: Dictionary) -> bool:
	match String(vol.get("kind", "box")):
		"cyl":
			return segment_hits_cyl(a, b, vol)
		"cells":
			return segment_hits_cells(a, b, vol)
		_:
			return segment_hits_box(a, b, vol)


## Grid-painted zone: the quarter-cell walk (min 4 steps, exact endpoints skipped) of the flat model,
## with the segment's interpolated height tested against the zone's slab at every sample.
static func segment_hits_cells(a: Vector3, b: Vector3, vol: Dictionary) -> bool:
	var cells: Dictionary = vol["cells"]
	var cell_size := float(vol["cell_size"])
	var y0 := float(vol["y0"])
	var y1 := float(vol["y1"])
	var a2 := Vector2(a.x, a.z)
	var b2 := Vector2(b.x, b.z)
	var span := a2.distance_to(b2)
	if span < MIN_SPAN_M:
		return false
	var steps := maxi(int(ceil(span / (cell_size * 0.25))), 4)
	for i in range(1, steps):
		var t := float(i) / float(steps)
		var y := lerpf(a.y, b.y, t)
		if y < y0 - Y_EPS_M or y > y1 + Y_EPS_M:
			continue   # the line passes over (or under) the zone at this sample
		if cells.has(cells_key(a2.lerp(b2, t), vol)):
			return true
	return false


## The cell a flat world point falls into, in the zone's OWN grid frame. A table's painted grid can be
## ROTATED against the world (the map layout's rotation slider), so the point is rotated back by the
## volume's `yaw` first; yaw 0 — the default, and what the headless simulator's grid uses — is the
## world-aligned case and skips the rotation entirely.
static func cells_key(p: Vector2, vol: Dictionary) -> Vector2i:
	var yaw := float(vol.get("yaw", 0.0))
	var q := p if is_zero_approx(yaw) else p.rotated(-yaw)
	return TerrainRules.cell_of(q, float(vol["cell_size"]))


## True if `p` stands inside `vol`'s footprint AND at or below its top — the endpoint-in-zone test the
## area rule keys on (a model on a 6" roof is NOT "in" the 3.4" forest below it).
static func point_inside_volume(p: Vector3, vol: Dictionary) -> bool:
	if p.y > float(vol["y1"]) + Y_EPS_M:
		return false
	return point_in_footprint(Vector2(p.x, p.z), vol)


## True if the flat point `p` lies in the volume's footprint, height ignored.
static func point_in_footprint(p: Vector2, vol: Dictionary) -> bool:
	match String(vol.get("kind", "box")):
		"cyl":
			return p.distance_to(vol["c"]) <= float(vol["r"])
		"cells":
			return (vol["cells"] as Dictionary).has(cells_key(p, vol))
		_:
			return TerrainRules.point_in_obb(p, vol["c"], vol["he"], float(vol["yaw"]))


## True if the flat segment from->to passes through (or touches) the circle. Own copy so the module keeps
## no dependency on the 2D ladder in los_rules.gd, which this program retires.
static func segment_intersects_circle(from_pt: Vector2, to_pt: Vector2, centre: Vector2, radius: float) -> bool:
	var seg := to_pt - from_pt
	var seg_len_sq := seg.length_squared()
	var t := 0.0
	if seg_len_sq > 0.0:
		t = clampf((centre - from_pt).dot(seg) / seg_len_sq, 0.0, 1.0)
	return (from_pt + seg * t).distance_to(centre) <= radius
