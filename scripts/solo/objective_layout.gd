class_name ObjectiveLayout
extends RefCounted
## D8a (NML-1073 M5) — the rulebook-LEGAL objective layout, seeded, identical on table
## and twin. Mirrored draw for draw by core/nml-core/src/objectives.rs.
##
## THE RULE (GF Advanced Rules v3.5.1, "PLACING OBJECTIVES" and the Advanced Missions
## "MISSION OBJECTIVES" block, which state it identically): set up D3+2 markers; the
## players roll-off and the winner picks who places the first; then they alternate
## placing one marker each OUTSIDE the deployment zones and over 9" away from other
## markers, never in an unreachable position (impassable terrain, spots too tight).
##
## WHAT THIS IS NOT: the book BOUNDS the placement, it never says WHERE the players
## place — that is a player decision. So this produces a layout LEGAL BY THE RULES, not
## one PLACED BY THE PLAYERS: candidates are drawn from a dedicated seeded stream and
## illegal ones rejected. The alternating placer is still rolled and recorded
## (`first_placer`, `placed_by`) so a real placement doctrine can later replace
## `_draw` alone, without touching the stream contract or the stamp.
##
## THE STREAM: ONE dedicated RandomNumberGenerator seeded with the LAYOUT seed, drawn in
## the pinned order below. Deliberately NOT the global RNG — the terrain layouter
## consumes that a data-dependent number of times (map_layout.gd:1902/1915), so the twin
## could not know where it stands without porting the layouter, which D2 refused when it
## banked the boards. Deliberately NOT SoloController._rng — adding draws there shifts
## every existing roll-off and section pick and invalidates every recorded corpus.
##
## ALL LEGALITY MATHS IS INTEGER. Candidates come off a 1" integer lattice and the
## standard zone polygons have integer vertices, so "inside a zone", "over 9" apart" and
## "off the edge" are exact on both sides — no float tie can make the two disagree.

const MARKER_GAP_IN := 9      # book: "over 9 inches away from other markers"
## OURS, NOT THE BOOK'S. The book names an edge distance only for King of the Hill /
## Mosh Pit (">9\" away from the deployment zones and the table edges"); for the generic
## alternate placement it names none. 3" keeps a marker reachable from every side
## without narrowing the legal band, and is stamped so a reader can see it was a choice.
const EDGE_MARGIN_IN := 3
const DRAW_CAP := 1000        # random attempts per marker before the deterministic sweep
const ROLL_OFF_CAP := 100     # SoloController.roll_off's own tie cap

const IMPASSABLE := 3         # TerrainRules.TerrainType.CONTAINER — terrain_rules.gd:72-73


## The layout for ONE game. `cells` is the board's {Vector2i: terrain type} (the very map
## the act header records and tools/terrain_bank_dump.gd banks), `n` its grid dimension.
## Returns the stamp the recorder writes and the twin re-derives:
##   {mode, count_roll, first_placer, layout_seed, edge_margin_in, positions:[[x,z]..],
##    placed_by:[player..], swept:int}
## `swept` counts markers the random draws could not place (the deterministic lattice
## sweep placed them instead) — 0 on every board measured; a non-zero value is a signal
## that the legal band got tight, not an error.
static func generate(layout_seed: int, mission: Dictionary, style: Dictionary,
		cells: Dictionary, n: int, table_w_in := 72.0, table_d_in := 48.0) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = layout_seed
	# Draw order, pinned: count, then the roll-off, then the placements.
	var count := _count(mission, rng)
	var first := _roll_off(rng)
	var hx := int(table_w_in / 2.0) - EDGE_MARGIN_IN
	var hz := int(table_d_in / 2.0) - EDGE_MARGIN_IN
	var pos: Array = []
	var swept := 0
	for i in range(count):
		var p := _draw(rng, hx, hz, pos, style, cells, n)
		if p.is_empty():
			p = _sweep(hx, hz, pos, style, cells, n)
			if p.is_empty():
				break        # no legal cell left at all: fewer markers, stamped honestly
			swept += 1
		pos.append(p)
	var placed_by: Array = []
	for i in range(pos.size()):
		placed_by.append(first if i % 2 == 0 else (3 - first))
	return {"mode": "rulebook", "count_roll": count, "first_placer": first,
		"layout_seed": layout_seed, "edge_margin_in": EDGE_MARGIN_IN,
		"positions": pos, "placed_by": placed_by, "swept": swept}


## D3+2, or the mission's fixed int. Same spec MissionCatalog.marker_count reads.
static func _count(mission: Dictionary, rng: RandomNumberGenerator) -> int:
	var spec: Variant = (mission.get("markers", {}) as Dictionary).get("count", "d3+2")
	if spec is float or spec is int:
		return maxi(1, int(spec))
	var s := str(spec).strip_edges().to_lower()
	if s.begins_with("d3+") and s.substr(3).is_valid_int():
		return rng.randi_range(1, 3) + int(s.substr(3))
	return rng.randi_range(1, 3) + 2


## "The players roll-off and the winner picks who places the first objective marker."
## With no placement doctrine to model the CHOICE, the winner places first.
static func _roll_off(rng: RandomNumberGenerator) -> int:
	for _a in range(ROLL_OFF_CAP):
		var d1 := rng.randi_range(1, 6)
		var d2 := rng.randi_range(1, 6)
		if d1 != d2:
			return 1 if d1 > d2 else 2
	return 1


## One accepted candidate, or [] when DRAW_CAP attempts all came back illegal.
static func _draw(rng: RandomNumberGenerator, hx: int, hz: int, pos: Array,
		style: Dictionary, cells: Dictionary, n: int) -> Array:
	for _a in range(DRAW_CAP):
		var x := rng.randi_range(-hx, hx)
		var z := rng.randi_range(-hz, hz)
		if is_legal(x, z, pos, style, cells, n):
			return [x, z]
	return []


## The deterministic fall-back the twin runs identically: the first legal lattice cell in
## a fixed sweep (x ascending outermost, z ascending inner).
static func _sweep(hx: int, hz: int, pos: Array, style: Dictionary,
		cells: Dictionary, n: int) -> Array:
	for x in range(-hx, hx + 1):
		for z in range(-hz, hz + 1):
			if is_legal(x, z, pos, style, cells, n):
				return [x, z]
	return []


## The book's three constraints, exact in integers. Public: the gate's legality self-test
## and the tests call it directly, so one definition answers for the rule and the check.
static func is_legal(x: int, z: int, pos: Array, style: Dictionary,
		cells: Dictionary, n: int) -> bool:
	for q in pos:
		var dx: int = x - int(q[0])
		var dz: int = z - int(q[1])
		if dx * dx + dz * dz <= MARKER_GAP_IN * MARKER_GAP_IN:
			return false              # "over 9 inches" — 9.0 exactly is NOT over
	for pk in ["1", "2"]:
		var polys: Variant = (style.get("zones", {}) as Dictionary).get(pk)
		if polys is Array:
			for poly in (polys as Array):
				if _in_poly(x, z, poly as Array):
					return false
	return int(cells.get(SchoolTerrain.cell_of(float(x), float(z), n),
		0)) != IMPASSABLE


## Even-odd crossing test in pure integers; a point ON the boundary counts as INSIDE, so
## a marker on the deployment line is rejected and "outside the zones" is strict.
static func _in_poly(px: int, pz: int, poly: Array) -> bool:
	var m := poly.size()
	var inside := false
	for i in range(m):
		var a: Array = poly[i]
		var b: Array = poly[(i + m - 1) % m]
		var ax := int(a[0])
		var az := int(a[1])
		var bx := int(b[0])
		var bz := int(b[1])
		if (bx - ax) * (pz - az) - (bz - az) * (px - ax) == 0 \
				and mini(ax, bx) <= px and px <= maxi(ax, bx) \
				and mini(az, bz) <= pz and pz <= maxi(az, bz):
			return true
		if (az > pz) != (bz > pz):
			var d := bz - az
			var lhs := (px - ax) * d
			var rhs := (pz - az) * (bx - ax)
			if (d > 0 and lhs < rhs) or (d < 0 and lhs > rhs):
				inside = not inside
	return inside
