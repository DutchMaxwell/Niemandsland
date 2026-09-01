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
##
## NML-1140 step 6: the promise above is kept. A doctrine rung ("style"/"search",
## the optional `doctrine_mode`/`doctrine_armies` args) replaces the candidate CHOICE
## alone: count and roll-off still come off the pinned stream and the doctrine draws
## nothing more, the choice comes from the extension's `NmlCore.doctrine_place` (the
## SAME Rust `doctrine::place` the twin's pyo3 seam runs — design 0, one
## implementation), and every returned cell is re-verified with this file's own
## `is_legal` before it is accepted. The rung rides the stamp's "doctrine" key — the
## twin's key (the step-5 note, coordinator-approved) — beside "mode": "rulebook",
## never instead of it. Extension absent, seam refusal, or an answer the book
## rejects: the rulebook draw runs anyway (the stream state is untouched) and the
## stamp says "fallback" — design 0's no-silent-fallback law; the gate reads that RED.

const MARKER_GAP_IN := 9      # book: "over 9 inches away from other markers"
## OURS, NOT THE BOOK'S. The book names an edge distance only for King of the Hill /
## Mosh Pit (">9\" away from the deployment zones and the table edges"); for the generic
## alternate placement it names none. 3" keeps a marker reachable from every side
## without narrowing the legal band, and is stamped so a reader can see it was a choice.
const EDGE_MARGIN_IN := 3
const DRAW_CAP := 1000        # random attempts per marker before the deterministic sweep
const ROLL_OFF_CAP := 100     # SoloController.roll_off's own tie cap

const IMPASSABLE := 3         # TerrainRules.TerrainType.CONTAINER — terrain_rules.gd:72-73


## NML-1140 step 7: the harnesses' env seam, ONE definition for all three call
## sites (arena_match / core_selfplay / solo_selfplay). "" (unset/blank) is
## today's rulebook draw byte for byte, "style"/"search" arm the doctrine rung.
## Anything else prints one loud FATAL line and returns "?" — the harness quits
## on "?" (a static RefCounted cannot reach SceneTree.quit). A typo'd mode must
## never fall back to the rulebook silently and record a mislabeled corpus
## (the label-bug class; the same loud-FATAL law as NML_OBJECTIVES/NML_MISSION).
static func doctrine_mode_from_env() -> String:
	var m := OS.get_environment("NML_OBJECTIVE_DOCTRINE").strip_edges().to_lower()
	if m == "" or m == "style" or m == "search":
		return m
	printerr("[OBJECTIVES] FATAL: unknown NML_OBJECTIVE_DOCTRINE '%s' (style|search; unset = rulebook) — refusing a mislabeled run" % m)
	return "?"


## The doctrine's per-army input: {unit_id: profile} in the `_unit_profile`
## schema the act header stamps — the one roster schema both worlds share
## (design 2). The Rust summary sorts the keys itself, so insertion order
## cannot leak seat order.
static func army_profiles(units: Array) -> Dictionary:
	var out := {}
	for u in units:
		var gu := u as GameUnit
		out[str(gu.unit_id)] = BattleSim._unit_profile(gu)
	return out


## The layout for ONE game. `cells` is the board's {Vector2i: terrain type} (the very map
## the act header records and tools/terrain_bank_dump.gd banks), `n` its grid dimension.
## Returns the stamp the recorder writes and the twin re-derives:
##   {mode, count_roll, first_placer, layout_seed, edge_margin_in, positions:[[x,z]..],
##    placed_by:[player..], swept:int}
## `swept` counts markers the random draws could not place (the deterministic lattice
## sweep placed them instead) — 0 on every board measured; a non-zero value is a signal
## that the legal band got tight, not an error.
## `doctrine_mode` is "" or "rulebook" for today's rulebook draw (byte-identical
## default), or a doctrine rung "style"/"search" with `doctrine_armies` the PAIR
## [army_a, army_b] of profile dictionaries (the `_unit_profile` schema the act
## header stamps) — the candidate choice then comes from the extension.
static func generate(layout_seed: int, mission: Dictionary, style: Dictionary,
		cells: Dictionary, n: int, table_w_in := 72.0, table_d_in := 48.0,
		doctrine_mode := "", doctrine_armies: Array = []) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = layout_seed
	# Draw order, pinned: count, then the roll-off, then the placements. The
	# doctrine draws NOTHING more — design 1's stream contract, so a doctrine game
	# and a rulebook game of the same seed share count, roll-off and every later
	# draw, and the A/B pairing is exact.
	var count := _count(mission, rng)
	var first := _roll_off(rng)
	var hx := int(table_w_in / 2.0) - EDGE_MARGIN_IN
	var hz := int(table_d_in / 2.0) - EDGE_MARGIN_IN
	var pos: Array = []
	var swept := 0
	var doct: Dictionary = {}
	if doctrine_mode != "" and doctrine_mode != "rulebook":
		doct = _doctrine_choice(doctrine_mode, doctrine_armies, count, style,
			cells, n, table_w_in, table_d_in)
	if doct.is_empty():
		# The rulebook candidates — and, unchanged, the doctrine's LOUD fallback:
		# the stream state is exactly where a rulebook draw of this seed stands.
		for i in range(count):
			var p := _draw(rng, hx, hz, pos, style, cells, n)
			if p.is_empty():
				p = _sweep(hx, hz, pos, style, cells, n)
				if p.is_empty():
					break        # no legal cell left at all: fewer markers, stamped honestly
				swept += 1
			pos.append(p)
	else:
		# The doctrine's choice, swept count included — the stream's count and
		# roll-off already bookkeep `placed_by` below, exactly as the rulebook's.
		pos = doct["positions"]
		swept = int(doct["swept"])
	var placed_by: Array = []
	for i in range(pos.size()):
		placed_by.append(first if i % 2 == 0 else (3 - first))
	var stamp := {"mode": "rulebook", "count_roll": count, "first_placer": first,
		"layout_seed": layout_seed, "edge_margin_in": EDGE_MARGIN_IN,
		"positions": pos, "placed_by": placed_by, "swept": swept}
	if doctrine_mode != "" and doctrine_mode != "rulebook":
		stamp["doctrine"] = doctrine_mode if not doct.is_empty() else "fallback"
	return stamp


## The doctrine's candidate choice, through the extension's `NmlCore.doctrine_place`.
## The board travels as the act header's terrain line (the `AiActRecorder`
## school-terrain shape, act_recorder.gd:283-292 — 0-based cell triples over the
## SAME 3" grid `is_legal` reads), so the Rust search sees what the table sees.
## Every failure prints one loud line and returns {} — `generate` then runs the
## rulebook draw with the stamp saying "fallback" (never a silent one).
static func _doctrine_choice(mode: String, armies: Array, count: int,
		style: Dictionary, cells: Dictionary, n: int,
		table_w_in: float, table_d_in: float) -> Dictionary:
	if not ClassDB.class_exists("NmlCore"):
		printerr("[OBJECTIVES] doctrine rung '%s' requested but the NmlCore extension is absent — the rulebook draw runs instead and the stamp says \"fallback\" (gate RED)" % mode)
		return {}
	var core: Object = ClassDB.instantiate("NmlCore")   # the solo_controller.gd:3182 pattern
	if core == null:
		printerr("[OBJECTIVES] NmlCore present but not instantiable — the rulebook draw runs instead and the stamp says \"fallback\" (gate RED)")
		return {}
	var terrain := {"cells": [], "sandbox": [], "walls": [],
		"cell_params": {"table_size_feet": [table_w_in / 12.0, table_d_in / 12.0],
			"grid_rotation_degrees": 0.0, "grid_size_inches": SchoolTerrain.CELL_IN,
			"inches_to_meters": SchoolTerrain.IN2M}}
	for k in cells:
		var c := k as Vector2i
		(terrain["cells"] as Array).append([c.x, c.y, int(cells[k])])
	var placed: Dictionary = core.doctrine_place(terrain, mode, armies, count,
		style, table_w_in, table_d_in)
	if placed.is_empty():
		printerr("[OBJECTIVES] doctrine_place refused rung '%s' (%s) — the rulebook draw runs instead and the stamp says \"fallback\" (gate RED)" % [mode, core.last_error()])
		return {}
	var pos: Array = placed.get("positions", [])
	if pos.size() > count:
		printerr("[OBJECTIVES] the doctrine answered %d markers for a draw of %d — the rulebook draw runs instead and the stamp says \"fallback\" (gate RED)" % [pos.size(), count])
		return {}
	# The design's table-side re-verification: each cell against every OTHER
	# returned cell, the zones and the board — a Rust cell that violates the book
	# goes RED here, not in a report.
	for i in range(pos.size()):
		var others: Array = []
		for j in range(pos.size()):
			if j != i:
				others.append(pos[j])
		if not is_legal(int(pos[i][0]), int(pos[i][1]), others, style, cells, n):
			printerr("[OBJECTIVES] the doctrine's cell %s is illegal by the book — the rulebook draw runs instead and the stamp says \"fallback\" (gate RED)" % str(pos[i]))
			return {}
	return {"positions": pos, "swept": int(placed.get("swept", 0))}


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
