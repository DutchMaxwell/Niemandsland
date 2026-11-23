class_name BoardgenDressHouses
extends RefCounted
## The house planner of the ruin-town dressing (docs/adr/0003-generated-board-dressing.md): walls, corners and doors of every Roofed lot. Gables, roofs and chimneys are not dressed yet.
## Pure data, board inches: one panel per free cell edge (neighbour top below the house's 2.5 in), the middle edge of the lot's frontage carries the one door, the four lot corners carry a post /
## quoin flush inside the lot. Style, picks and damage come from BoardgenDressStory; every transform comes from BoardgenDressRules.face_xf. Panels lean IN by the KNOBS angle (out would poke over R1).

const MODULES: Array[String] = [
	"dr_house_tb_blank", "dr_house_tb_door", "dr_house_tb_plain_a", "dr_house_tb_plain_b", "dr_house_tb_post",
	"dr_house_tb_window", "dr_house_tb_window_lit",
	"dr_house_st_door", "dr_house_st_plain_a", "dr_house_st_plain_b", "dr_house_st_quoin", "dr_house_st_window"]
const CLS := "houses"
const DIRS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
const FACE_NAMES := ["N", "E", "S", "W"]
const CORNER_FACE := [3, 0, 1, 2]
## Salts of BoardgenDressStory.pick. Every choice of a lot draws with its own salt so the choices do not correlate (a low
## style pick must not also mean a lit window); the per-face salts add the face index 0..3 so the four faces of a lot differ.
const SALT_STYLE := 0x71   # timber or stone house
const SALT_PANEL := 0x33   # + face: where the panel sequence of a face starts
const SALT_LIT_WINDOW := 0x5A   # + face: whether a timber window on this face is the lot's one lit window
const SALT_INSET := 0x1F   # + face: how deep a panel sits in the wall
const TIMBER_IN_TEN := 6   # 6 of 10 houses are timber, the rest stone
const LIT_WINDOW_IN_TEN := 4   # 4 of 10 timber windows may be the lot's lit one
const PANEL_VARIANTS := 3   # plain_a, plain_b, window
const FALLEN_PLASTER_DAMAGE := 0.5   # above this damage a first-variant panel shows fallen plaster instead
const INSET_MIN_IN := 0.06   # the shallowest panel inset, also the default proud depth of a module without one
const INSET_SPREAD_IN := 0.08   # how much deeper the inset pick may go
const INSET_STEPS := 16


## Every placement of the houses class: {module, xf (metres, board space), cls}.
static func plan(layout: Dictionary, ctx: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var meta: Dictionary = ctx.get("meta", {})
	if meta.is_empty() and ctx.has("kit"):
		meta = (ctx["kit"] as BoardgenDressKit).meta
	var story: Dictionary = ctx.get("story", BoardgenDressStory.of(layout))
	var fronts := {}
	for frontage: Dictionary in BoardgenTownDressing.frontage(layout):
		if String(frontage["front"]) != "":
			fronts[int(frontage["lot"])] = String(frontage["front"])
	for lot: Dictionary in layout["lots"]:
		if lot["kind"] != "Roofed":
			continue
		var id := int(lot["id"])
		var x0 := int(lot["x"])
		var z0 := int(lot["z"])
		var x1 := x0 + int(lot["w"])
		var z1 := z0 + int(lot["h"])
		var style := "tb" if BoardgenDressStory.pick(id, SALT_STYLE, 10) < TIMBER_IN_TEN else "st"
		var free: Array[Dictionary] = []   # every cell edge a panel goes on: {cx, cz, k = face}
		for cz in range(z0, z1):
			for cx in range(x0, x1):
				for face in 4:
					var neighbour: Vector2i = Vector2i(cx, cz) + DIRS[face]
					if BoardgenDressRules.top_in(layout, neighbour.x, neighbour.y) < BoardgenGreybox.SOLID_IN:
						free.append({"cx": cx, "cz": cz, "k": face})
		var front := String(fronts.get(id, _longest_face(free)))
		var door := _middle_edge(free, FACE_NAMES.find(front))
		var previous := {}   # face -> the panel name placed last on it, so two neighbours differ
		var lit := false
		var door_done := false
		for edge: Dictionary in free:
			var cx: int = edge["cx"]
			var cz: int = edge["cz"]
			var face: int = edge["k"]
			var centre_in := Vector2(cx + 0.5 - int(layout["nx"]) * 0.5, cz + 0.5 - int(layout["nz"]) * 0.5) * float(layout["cell_in"])
			var damage := BoardgenDressStory.damage(story, centre_in)
			var lean := -(float(BoardgenDressStory.KNOBS["lean_base_deg"]) + float(BoardgenDressStory.KNOBS["lean_gain_deg"]) * damage)
			var module := "dr_house_%s_door" % style
			if door == edge and not door_done:
				door_done = true
			else:
				var along := cx if face % 2 == 0 else cz
				var variant := (BoardgenDressStory.pick(id, SALT_PANEL + face, PANEL_VARIANTS) + along) % PANEL_VARIANTS
				if damage > FALLEN_PLASTER_DAMAGE and variant == 0:
					variant = 1   # fallen plaster
				var name := _panel(variant)
				if name == String(previous.get(face, "")):
					name = _panel(variant + 1)
				var may_light := name == "window" and style == "tb" and not lit
				if may_light and BoardgenDressStory.pick(id, SALT_LIT_WINDOW + face, 10) < LIT_WINDOW_IN_TEN:
					name = "window_lit"
					lit = true
				previous[face] = name
				module = "dr_house_%s_%s" % [style, name]
			var module_meta: Dictionary = meta["modules"].get(module, {})
			var proud := float((module_meta.get("proud_in", {}) as Dictionary).get("low", INSET_MIN_IN))
			var inset_pick := float(BoardgenDressStory.pick(id, face + SALT_INSET, INSET_STEPS))
			var inset := maxf(proud, INSET_MIN_IN + INSET_SPREAD_IN * inset_pick / float(INSET_STEPS - 1))
			out.append({"module": module, "xf": _place(layout, cx, cz, face, inset, 0.0, lean), "cls": CLS})
		var corner := "dr_house_tb_post" if style == "tb" else "dr_house_st_quoin"
		var cells := [Vector2i(x0, z0), Vector2i(x1 - 1, z0), Vector2i(x1 - 1, z1 - 1), Vector2i(x0, z1 - 1)]
		for i in 4:
			out.append({"module": corner, "xf": _corner(layout, cells[i], CORNER_FACE[i], meta["modules"][corner]), "cls": CLS})
	return out


## A face module's transform: left foot at the face's start point (optionally shifted along it), moved `inset` into the mass, tipped out by `lean` degrees.
static func _place(layout: Dictionary, cx: int, cz: int, k: int, inset: float, shift: float, lean: float) -> Transform3D:
	var cell_in := float(layout["cell_in"])
	var cell_corner := Vector3((cx - int(layout["nx"]) * 0.5) * cell_in, 0.0, (cz - int(layout["nz"]) * 0.5) * cell_in)
	var along: Vector3 = [Vector3(-1, 0, 0), Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, 0, 1)][k]
	var away: Vector3 = [Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0)][k]
	var starts := [
		cell_corner + Vector3(cell_in, 0, 0), cell_corner + Vector3(cell_in, 0, cell_in),
		cell_corner + Vector3(0, 0, cell_in), cell_corner]
	var start: Vector3 = starts[k]
	return BoardgenDressRules.face_xf(start + along * shift, along, away, inset, lean)


## A corner piece flush inside the lot: shifted by its left overhang, inset by its mounting depth, so no part pokes into the neighbour cell.
static func _corner(layout: Dictionary, cell: Vector2i, k: int, module_meta: Dictionary) -> Transform3D:
	var aabb: Array = module_meta["aabb_in"]
	var lo := Vector3(float(aabb[0][0]), float(aabb[0][1]), float(aabb[0][2]))
	var hi := Vector3(float(aabb[1][0]), float(aabb[1][1]), float(aabb[1][2]))
	return _place(layout, cell.x, cell.y, k, hi.z, -lo.x, 0.0)


## A panel variant: 0 plain_a, 1 plain_b, 2 window (window_lit for timber is chosen by the caller).
static func _panel(variant: int) -> String:
	return ["plain_a", "plain_b", "window"][posmod(variant, PANEL_VARIANTS)]


## The middle free edge of face `k` (the door's edge), or {} when that face has none.
static func _middle_edge(free: Array[Dictionary], k: int) -> Dictionary:
	var edges := free.filter(func(edge: Dictionary) -> bool: return int(edge["k"]) == k)
	if edges.is_empty():
		return {}
	edges.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (int(a["cx"]) if k % 2 == 0 else int(a["cz"])) < (int(b["cx"]) if k % 2 == 0 else int(b["cz"])))
	return edges[edges.size() / 2]


## The face with the most free edges (the fallback front when a lot has no street front).
static func _longest_face(free: Array[Dictionary]) -> String:
	var counts := [0, 0, 0, 0]
	for edge: Dictionary in free:
		counts[int(edge["k"])] += 1
	var best := 0
	for face in 4:
		best = face if counts[face] > counts[best] else best
	return FACE_NAMES[best]
