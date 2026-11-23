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


## Every placement of the houses class: {module, xf (metres, board space), cls}.
static func plan(layout: Dictionary, ctx: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var meta: Dictionary = ctx.get("meta", {})
	if meta.is_empty() and ctx.has("kit"):
		meta = (ctx["kit"] as BoardgenDressKit).meta
	var story: Dictionary = ctx.get("story", BoardgenDressStory.of(layout))
	var fronts := {}
	for f: Dictionary in BoardgenTownDressing.frontage(layout):
		if String(f["front"]) != "":
			fronts[int(f["lot"])] = String(f["front"])
	for lot: Dictionary in layout["lots"]:
		if lot["kind"] != "Roofed":
			continue
		var id := int(lot["id"])
		var x0 := int(lot["x"])
		var z0 := int(lot["z"])
		var x1 := x0 + int(lot["w"])
		var z1 := z0 + int(lot["h"])
		var style := "tb" if BoardgenDressStory.pick(id, 0x71, 10) < 6 else "st"
		var free: Array[Dictionary] = []
		for cz in range(z0, z1):
			for cx in range(x0, x1):
				for k in 4:
					var nb: Vector2i = Vector2i(cx, cz) + DIRS[k]
					if BoardgenDressRules.top_in(layout, nb.x, nb.y) < 2.5:
						free.append({"cx": cx, "cz": cz, "k": k})
		var front := String(fronts.get(id, _longest_face(free)))
		var door := _middle_edge(free, FACE_NAMES.find(front))
		var prev := {}
		var lit := false
		var door_done := false
		for e: Dictionary in free:
			var cx: int = e["cx"]
			var cz: int = e["cz"]
			var k: int = e["k"]
			var d := BoardgenDressStory.damage(story, Vector2(cx + 0.5 - int(layout["nx"]) * 0.5, cz + 0.5 - int(layout["nz"]) * 0.5) * float(layout["cell_in"]))
			var lean := -(float(BoardgenDressStory.KNOBS["lean_base_deg"]) + float(BoardgenDressStory.KNOBS["lean_gain_deg"]) * d)
			var module := "dr_house_%s_door" % style
			if door == e and not door_done:
				door_done = true
			else:
				var v := (BoardgenDressStory.pick(id, 0x33 + k, 3) + (cx if k % 2 == 0 else cz)) % 3
				if d > 0.5 and v == 0:
					v = 1   # fallen plaster
				var name := _panel(v)
				if name == String(prev.get(k, "")):
					name = _panel(v + 1)
				if name == "window" and style == "tb" and not lit and BoardgenDressStory.pick(id, 0x5A + k, 10) < 4:
					name = "window_lit"
					lit = true
				prev[k] = name
				module = "dr_house_%s_%s" % [style, name]
			var m: Dictionary = meta["modules"].get(module, {})
			var proud := float((m.get("proud_in", {}) as Dictionary).get("low", 0.06))
			var inset := maxf(proud, 0.06 + 0.08 * float(BoardgenDressStory.pick(id, k + 0x1F, 16)) / 15.0)
			out.append({"module": module, "xf": _place(layout, cx, cz, k, inset, 0.0, lean), "cls": CLS})
		var corner := "dr_house_tb_post" if style == "tb" else "dr_house_st_quoin"
		var cells := [Vector2i(x0, z0), Vector2i(x1 - 1, z0), Vector2i(x1 - 1, z1 - 1), Vector2i(x0, z1 - 1)]
		for i in 4:
			out.append({"module": corner, "xf": _corner(layout, cells[i], CORNER_FACE[i], meta["modules"][corner]), "cls": CLS})
	return out


## A face module's transform: left foot at the face's start point (optionally shifted along it), moved `inset` into the mass, tipped out by `lean` degrees.
static func _place(layout: Dictionary, cx: int, cz: int, k: int, inset: float, shift: float, lean: float) -> Transform3D:
	var c := float(layout["cell_in"])
	var o := Vector3((cx - int(layout["nx"]) * 0.5) * c, 0.0, (cz - int(layout["nz"]) * 0.5) * c)
	var along: Vector3 = [Vector3(-1, 0, 0), Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, 0, 1)][k]
	var away: Vector3 = [Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0)][k]
	var start: Vector3 = [o + Vector3(c, 0, 0), o + Vector3(c, 0, c), o + Vector3(0, 0, c), o][k]
	return BoardgenDressRules.face_xf(start + along * shift, along, away, inset, lean)


## A corner piece flush inside the lot: shifted by its left overhang, inset by its mounting depth, so no part pokes into the neighbour cell.
static func _corner(layout: Dictionary, cell: Vector2i, k: int, m: Dictionary) -> Transform3D:
	var lo := Vector3(float(m["aabb_in"][0][0]), float(m["aabb_in"][0][1]), float(m["aabb_in"][0][2]))
	var hi := Vector3(float(m["aabb_in"][1][0]), float(m["aabb_in"][1][1]), float(m["aabb_in"][1][2]))
	return _place(layout, cell.x, cell.y, k, hi.z, -lo.x, 0.0)


## A panel variant: 0 plain_a, 1 plain_b, 2 window (window_lit for timber is chosen by the caller).
static func _panel(v: int) -> String:
	return ["plain_a", "plain_b", "window"][posmod(v, 3)]


## The middle free edge of face `k` (the door's edge), or {} when that face has none.
static func _middle_edge(free: Array[Dictionary], k: int) -> Dictionary:
	var edges := free.filter(func(e: Dictionary) -> bool: return int(e["k"]) == k)
	if edges.is_empty():
		return {}
	edges.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (int(a["cx"]) if k % 2 == 0 else int(a["cz"])) < (int(b["cx"]) if k % 2 == 0 else int(b["cz"])))
	return edges[edges.size() / 2]


## The face with the most free edges (the fallback front when a lot has no street front).
static func _longest_face(free: Array[Dictionary]) -> String:
	var n := [0, 0, 0, 0]
	for e: Dictionary in free:
		n[int(e["k"])] += 1
	var best := 0
	for k in 4:
		best = k if n[k] > n[best] else best
	return FACE_NAMES[best]
