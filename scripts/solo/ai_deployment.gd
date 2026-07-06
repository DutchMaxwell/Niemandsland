class_name AiDeployment
extends RefCounted
## Solo-AI M2 — OPR Solo & Co-Op v3.5.0 "AI Deployment" (goal 001 P2), the pure, seeded-RNG core:
## the AI's units are randomly split into 3 groups of equal size (as far as possible); the table is
## divided into 3 sections along the AI's deployment-zone edge; each group rolls a D3 for its section
## (re-rolling while ALL groups would share one); then one random unit at a time deploys in its section,
## as close as possible to the nearest objective and outside difficult/dangerous terrain (unless the
## unit has Strider or Flying). Scout units deploy after all others; Ambush units stay in reserve
## (arriving at the start of round 2). The caller supplies zone geometry, objectives and a terrain
## callback — no scene access here (headless-testable per the solo conventions).


## Randomly split `count` unit indices into 3 groups of equal size as far as possible.
## Deterministic under a fixed rng seed (Fisher-Yates with the provided rng).
static func split_into_groups(count: int, rng: RandomNumberGenerator) -> Array:
	var idx: Array = []
	for i in range(count):
		idx.append(i)
	_shuffle(idx, rng)
	var groups: Array = [[], [], []]
	for k in range(idx.size()):
		groups[k % 3].append(idx[k])
	return groups


## One D3 roll (section 1-3) per group; re-roll while ALL groups would deploy in the same section.
static func assign_sections(group_count: int, rng: RandomNumberGenerator) -> Array:
	if group_count <= 0:
		return []
	while true:
		var sections: Array = []
		for i in range(group_count):
			sections.append(rng.randi_range(1, 3))
		if group_count == 1:
			return sections
		var all_same := true
		for s in sections:
			if int(s) != int(sections[0]):
				all_same = false
				break
		if not all_same:
			return sections
	return []


## The rect of section 1-3: the AI zone split into 3 equal strips along its table-edge axis (x).
static func section_rect(zone: Rect2, section: int) -> Rect2:
	var w := zone.size.x / 3.0
	return Rect2(Vector2(zone.position.x + w * float(clampi(section, 1, 3) - 1), zone.position.y), Vector2(w, zone.size.y))


## Placement order: units deploy one at a time in RANDOM order, but Scout units always deploy LAST and
## Ambush units are excluded entirely (reserve, start of round 2). `units` = [{id, scout, ambush}].
static func placement_order(units: Array, rng: RandomNumberGenerator) -> Array:
	var normal: Array = []
	var scouts: Array = []
	for u in units:
		var d := u as Dictionary
		if bool(d.get("ambush", false)):
			continue
		if bool(d.get("scout", false)):
			scouts.append(d.get("id"))
		else:
			normal.append(d.get("id"))
	_shuffle(normal, rng)
	_shuffle(scouts, rng)
	return normal + scouts


## The free, terrain-legal spot inside `section` closest to the nearest objective (rule: "as close as
## possible to the nearest objective"). `occupied` = [{pos: Vector2, radius: float}] already-placed
## footprints; `blocked` = Callable(Vector2) -> bool for difficult/dangerous terrain (pass an invalid
## Callable for units with Strider/Flying, which ignore it). Returns Vector2.INF when nothing fits.
static func best_spot(section: Rect2, objectives: Array, occupied: Array, radius: float, blocked: Callable, step: float = 0.05) -> Vector2:
	var best := Vector2.INF
	var best_score := INF
	var y := section.position.y + radius
	while y <= section.end.y - radius + 0.0001:
		var x := section.position.x + radius
		while x <= section.end.x - radius + 0.0001:
			var p := Vector2(x, y)
			if _spot_free(p, radius, occupied) and not (blocked.is_valid() and bool(blocked.call(p))):
				var score := _nearest_objective_distance(p, objectives, section)
				if score < best_score:
					best_score = score
					best = p
			x += step
		y += step
	return best


# === Private ===

static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


static func _spot_free(p: Vector2, radius: float, occupied: Array) -> bool:
	for o in occupied:
		var od := o as Dictionary
		if p.distance_to(od.get("pos", Vector2.INF)) < radius + float(od.get("radius", 0.0)):
			return false
	return true


## Distance to the nearest objective; with no objectives on the table, aim for the section centre so
## the group still forms up coherently instead of degenerating to the rect origin.
static func _nearest_objective_distance(p: Vector2, objectives: Array, section: Rect2) -> float:
	if objectives.is_empty():
		return p.distance_to(section.get_center())
	var best := INF
	for obj in objectives:
		best = minf(best, p.distance_to(obj))
	return best
