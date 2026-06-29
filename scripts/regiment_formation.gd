class_name RegimentFormation
extends RefCounted
## Pure ranks-and-files layout for Age of Fantasy: Regiments. Given the per-model
## base footprints and a frontage (models per rank), returns the LOCAL positions of
## each model in a regiment block — tight base-to-base contact, front rank toward
## +Z (the unit's facing, matching the oval/square base "depth = north" convention).
##
## Static and side-effect-free so it is trivially testable; the RegimentTray applies
## these offsets to model nodes and owns the world transform. Re-ranking after a
## casualty is just calling local_offsets() again with the remaining models — the
## rear rank empties first because models fill front-to-back, left-to-right.

# === Constants ===

## Default models-per-rank by unit size, following the AoF:R convention (5-wide for
## 5/10-model units, 3-wide for 3/6, single models stand alone).
static func default_frontage(model_count: int) -> int:
	if model_count <= 1:
		return 1
	if model_count % 5 == 0:
		return 5
	if model_count % 3 == 0:
		return 3
	return min(5, model_count)


## The next frontage in the cycle used by the Regiments frontage-cycle hotkey.
## AoF:R v3.5.1 p.6 "Unit Formations" defines the default (5-wide for 5/10, 3-wide
## for 3/6), but a player may reform to any width 1..N. The cycle walks the common
## widths from widest to narrowest, then wraps: 5 -> 4 -> 3 -> 2 -> 1 -> 5.
## Widths wider than the live model count are skipped (a 3-model remnant can't form
## 5-wide). Returns `current` unchanged if no other option exists (single model).
static func next_frontage(current: int, live_model_count: int) -> int:
	# Candidate widths in cycle order, widest first; AoF:R p.6 sets 5 and 3 as the
	# canonical defaults, the others are valid player reforms (local_offsets clamps).
	const CYCLE := [5, 4, 3, 2, 1]
	var max_width := mini(5, maxi(live_model_count, 1))
	# Build the effective cycle (widths that fit the live model count).
	var effective: Array[int] = []
	for w in CYCLE:
		if w <= max_width and not effective.has(w):
			effective.append(w)
	if effective.size() <= 1:
		return current
	# Find the current width and advance; wrap from the last to the first.
	var idx := effective.find(current)
	if idx == -1:
		# Current width is outside the cycle (e.g. 6-wide custom) -> start at the widest.
		return effective[0]
	return effective[(idx + 1) % effective.size()]


## Number of ranks (rows) a regiment of `model_count` forms at `frontage`.
static func rank_count(model_count: int, frontage: int) -> int:
	var f := maxi(frontage, 1)
	return int(ceil(float(maxi(model_count, 0)) / float(f)))


## Local positions (Vector3, y = 0) for `footprints.size()` models arranged in ranks
## of `frontage`. `footprints` are per-model Vector2(width_x, depth_z) in metres.
## The block is centred on the origin; the front rank (index 0) sits toward +Z.
## A partial rear rank is centred on its own model count. `gap` adds spacing between
## base edges (0 = touching, the Regiments default).
static func local_offsets(footprints: Array, frontage: int, gap: float = 0.0) -> Array:
	var offsets: Array = []
	var n := footprints.size()
	if n == 0:
		return offsets
	var f := clampi(frontage, 1, n)

	# Uniform cell size from the largest base in the unit keeps files aligned even
	# if a model's footprint varies slightly.
	var cell_w := 0.0
	var cell_d := 0.0
	for fp in footprints:
		cell_w = maxf(cell_w, fp.x)
		cell_d = maxf(cell_d, fp.y)
	cell_w += gap
	cell_d += gap

	var rows := rank_count(n, f)
	for i in range(n):
		var row := i / f       # integer division: 0 = front rank
		var col := i % f
		var count_in_row := mini(f, n - row * f)
		var x := (col - (count_in_row - 1) / 2.0) * cell_w
		# Front rank toward +Z; rows march backwards (-Z); block centred in depth.
		var z := ((rows - 1) / 2.0 - row) * cell_d
		offsets.append(Vector3(x, 0.0, z))
	return offsets
