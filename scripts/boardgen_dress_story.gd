class_name BoardgenDressStory
extends RefCounted
## The decay story of one ruin-town board (PLAN_RUINTOWN_DRESSING): the seed picks the way the fire came from and the shade side (BoardgenTownDressing.story), the wall breaches are where the
## town fell first. Together they give a damage field D(p) in 0..1 and a shade field S, which the planners read through the KNOBS to decide where the grid breaks (roof variant, lean, missing
## merlons, litter, moss) - bounded and with a cause, never jitter. Pure data: nothing here touches a collider, a cell or a node. Positions are board inches, origin at the board centre.

const KNOBS := {
	"fire_weight": 0.5, "breach_weight": 0.35, "noise_weight": 0.15,   # D = their sum (1.0), so D stays in 0..1
	"breach_reach_in": 18.0, "noise_cell_in": 9.0,
	"roof_holed_from": 0.45, "roof_rafters_from": 0.7, "roof_whole_share": 0.6,   # a roof is rafters above D 0.7, holed above 0.45, else whole; >= 60 % whole per half
	"lean_base_deg": 0.3, "lean_gain_deg": 1.2,   # lean = base + gain x D (at most LEAN_MAX 1.5 degrees)
	"merlon_loss_base": 0.2, "merlon_loss_gain": 0.5,   # the share of merlons missing = base + gain x D
	"litter_gain": 1.5,   # litter density factor = 1 + gain x D
	"accent_cuts": [0.2, 0.4, 0.6, 0.75],   # cumulative shares of jetty / lean / sag / ragged; the rest has no accent
}
const ACCENTS := ["jetty", "lean", "sag", "ragged", ""]


## The story of a layout: {seed, fire (unit Vector2, the way the fire came from), shade (unit Vector2, a quarter turn off), breaches: Array[Vector2] (centres of the level 0 wall cells)}.
static func of(layout: Dictionary) -> Dictionary:
	var seed := int(layout.get("seed", 0))
	var st := BoardgenTownDressing.story(seed)
	var cell := float(layout["cell_in"])
	var half := Vector2(layout["nx"], layout["nz"]) * 0.5
	var breaches: Array[Vector2] = []
	for c: Dictionary in layout["cells"]:
		if c["lot_kind"] == "Wall" and int(c["level"]) == 0:
			breaches.append((Vector2(c["x"], c["z"]) + Vector2(0.5, 0.5) - half) * cell)
	return {"seed": seed, "fire": Vector2(st.r, st.g), "shade": Vector2(st.b, st.a), "breaches": breaches}


## The damage at a point (board inches), 0..1: how far the fire burnt it (half the weight), how near a breach it lies (a third), and a slow seeded value noise (the rest).
static func damage(story: Dictionary, p_in: Vector2) -> float:
	var k := KNOBS
	return clampf(float(k["fire_weight"]) * _fire(story, p_in) + float(k["breach_weight"]) * _breach(story, p_in) + float(k["noise_weight"]) * _noise(int(story["seed"]), p_in), 0.0, 1.0)


## How much a face that looks along `out` sits on the shade side, 0..1 (1 = looks straight at the shade side, where moss grows).
static func shade(story: Dictionary, out: Vector2) -> float:
	return clampf(0.5 + 0.5 * out.normalized().dot(story["shade"]), 0.0, 1.0)


## A well-mixed pick in 0..n-1 for a lot or a cell id and a salt (the old _hash repeats along a run of ids).
static func pick(lot_or_cell: int, salt: int, n: int) -> int:
	return _mix(lot_or_cell, salt, 0x51) % maxi(n, 1)


## The one strong break a lot may carry: "jetty", "lean", "sag", "ragged" or "" (none); the planners put it on the lot's street face first.
static func accent(lot: int) -> String:
	var u := _unit(lot, 0xAC, 7)
	var cuts: Array = KNOBS["accent_cuts"]
	for i in cuts.size():
		if u < float(cuts[i]):
			return ACCENTS[i]
	return ""


## The fire term, 0..1: today's fold (BoardgenTownFrames.fire_at, re-implemented here so that file can go) - the south half is mirrored through the centre, both halves see the same story.
static func _fire(story: Dictionary, p: Vector2) -> float:
	var f: Vector2 = story["fire"]
	var q := (-p if p.y >= 0.0 else p) + Vector2(0.0, 12.0)
	return clampf(0.5 + 0.65 * clampf(q.dot(f) / (absf(f.x) * 24.0 + absf(f.y) * 12.0), -1.0, 1.0), 0.0, 1.0)


## The breach term, 0..1: 1 at a breach, 0 from `breach_reach_in` away (and on a board without breaches).
static func _breach(story: Dictionary, p: Vector2) -> float:
	var best := INF
	for b: Vector2 in story["breaches"]:
		best = minf(best, p.distance_to(b))
	return clampf(1.0 - best / float(KNOBS["breach_reach_in"]), 0.0, 1.0)


## Smooth seeded value noise, 0..1, on a `noise_cell_in` lattice (not folded: the two halves differ in detail, not in mean).
static func _noise(seed: int, p: Vector2) -> float:
	var g: Vector2 = p / float(KNOBS["noise_cell_in"])
	var i := Vector2i(floori(g.x), floori(g.y))
	var f := g - Vector2(i)
	var u := f * f * (Vector2(3.0, 3.0) - 2.0 * f)
	var top := lerpf(_unit(i.x, i.y, seed), _unit(i.x + 1, i.y, seed), u.x)
	var bottom := lerpf(_unit(i.x, i.y + 1, seed), _unit(i.x + 1, i.y + 1, seed), u.x)
	return lerpf(top, bottom, u.y)


static func _unit(a: int, b: int, c: int) -> float:
	return float(_mix(a, b, c)) / 4294967296.0


## A 32-bit integer hash of three ints (multiplies stay below 2^63 so nothing overflows).
static func _mix(a: int, b: int, c: int) -> int:
	var h := (a * 0x1B873593 + b * 0x2545F491 + c * 0x6C8E9CF5) & 0xFFFFFFFF
	h = ((h ^ (h >> 16)) * 0x7FEB352D) & 0xFFFFFFFF
	h = ((h ^ (h >> 15)) * 0x2C1B3C6D) & 0xFFFFFFFF
	return h ^ (h >> 16)
