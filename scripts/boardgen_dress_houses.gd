class_name BoardgenDressHouses
extends RefCounted
## The house planner of the ruin-town dressing (docs/adr/0003-generated-board-dressing.md): walls, corners, doors, gables, roofs and chimneys of every Roofed lot.
## Pure data, board inches: one panel per free cell edge (neighbour top below the house's 2.5 in), the middle edge of the lot's frontage carries the one door, the four lot corners carry a post /
## quoin flush inside the lot. Style, picks and damage come from BoardgenDressStory; every transform comes from BoardgenDressRules.face_xf. Panels lean IN by the KNOBS angle (out would poke over R1).
## Roofs follow BoardgenTownDressing.roofs() (ridge axis, annex, rise); a span over 6 in flips the ridge to the other axis. Hip and catslide draw as gables, and a damaged roof (holed / rafters by
## D, at least 60 % whole per half) draws as mid_b until the kit has modules for them: a variant outside MODULES falls back. Roof segments carry `lot` and `variant` for the tests.

const MODULES: Array[String] = [
	"dr_house_tb_blank", "dr_house_tb_door", "dr_house_tb_plain_a", "dr_house_tb_plain_b", "dr_house_tb_post",
	"dr_house_tb_window", "dr_house_tb_window_lit",
	"dr_house_st_door", "dr_house_st_plain_a", "dr_house_st_plain_b", "dr_house_st_quoin", "dr_house_st_window",
	"dr_roof_s3_mid_a", "dr_roof_s3_mid_b", "dr_roof_s3_verge", "dr_roof_s6_mid_a", "dr_roof_s6_mid_b", "dr_roof_s6_verge", "dr_gable_tb_s3", "dr_gable_tb_s3_b",
	"dr_gable_tb_s6", "dr_gable_tb_s6_b", "dr_gable_st_s3", "dr_gable_st_s6", "dr_chimney_a"]
const CLS := "houses"
const DIRS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
const FACE_NAMES := ["N", "E", "S", "W"]
const CORNER_FACE := [3, 0, 1, 2]
const EAVES_IN := 2.5
const VARIANT_ROLE := {"holed": "broken", "rafters": "rafters"}


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
	var roofs := {}
	for r: Dictionary in BoardgenTownDressing.roofs(layout):
		roofs[int(r["lot"])] = roofs.get(int(r["lot"]), []) + [r]
	var variants := _variants(roofs, story)
	var ladders: Array = (layout["connectors"] as Array).reduce(func(acc: Array, cn: Dictionary) -> Array: return acc + [int(cn["low"]), int(cn["high"])], [])
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
		for r: Dictionary in roofs.get(id, []):
			out.append_array(_roof(layout, r, style, String(variants.get(id, "whole")), meta, ladders))
	for b: Dictionary in BoardgenTownDressing.chimneys(layout):
		var box := AABB(b["lo"], b["hi"] - b["lo"])   # the chimney's Y follows the box (the smoke emitter's) height: (roof height + 0.9) / 2.9
		out.append({"module": "dr_chimney_a", "xf": Transform3D(Basis.from_scale(Vector3(1.0, box.size.y / 2.9, 1.0)), (box.get_center() - Vector3(0.0, box.size.y * 0.5, 0.0)) * BoardgenDressRules.IN_M), "cls": CLS})
	return out


## Roof variant per lot by the damage at its main roof's centre: rafters above KNOBS roof_rafters_from, holed above roof_holed_from, else whole; per half the least damaged
## roof_whole_share of the lots stay whole whatever their D.
static func _variants(roofs: Dictionary, story: Dictionary) -> Dictionary:
	var k := BoardgenDressStory.KNOBS
	var halves := [[], []]
	for id: int in roofs:
		for r: Dictionary in roofs[id]:
			if not r["annex"]:
				halves[int(r["half"])].append({"lot": id, "d": BoardgenDressStory.damage(story, r["centre"])})
	var out := {}
	for half: Array in halves:
		half.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["d"]) < float(b["d"]))
		var whole := ceili(float(k["roof_whole_share"]) * half.size() - 0.001)
		for i in half.size():
			var d := float(half[i]["d"])
			out[half[i]["lot"]] = "whole" if i < whole or d <= float(k["roof_holed_from"]) else ("rafters" if d > float(k["roof_rafters_from"]) else "holed")
	return out


## One roof of roofs(): segments per 3 in of ridge on the front eaves plane, a verge at both ends (the start one turned 180 deg, on the back plane), a gable on both end faces; all at
## the eaves, Y scaled to the rise (an annex at the lowest, 1.7). A TIGHT side (a walkable tier or a ladder cell beside it, diagonals included) gets no overhang: eaves and gable jetties are
## squeezed to the wall plane and the verge moves inside the end, because the honesty rules (R4, R5) allow nothing of a roof over a tier top or in a ladder strip.
static func _roof(layout: Dictionary, r: Dictionary, style: String, variant: String, meta: Dictionary, ladders: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var c := float(layout["cell_in"])
	var id := int(r["lot"])
	var size := Vector2(float(r["length"]), float(r["width"])) - Vector2.ONE * 2.0 * BoardgenTownDressing.OVERHANG_IN   # run along, extent across the ridge
	var ext := size if r["along_x"] else Vector2(size.y, size.x)
	var ax: bool = r["along_x"] != (size.y > 6.0 + BoardgenDressRules.TOL)   # the span rule
	var lo: Vector2 = (r["centre"] - ext * 0.5) / c + Vector2(int(layout["nx"]), int(layout["nz"])) * 0.5
	var a := Vector2i(roundi(lo.x), roundi(lo.y))
	var b := a + Vector2i(roundi(ext.x / c), roundi(ext.y / c))
	var span := roundi(ext.y if ax else ext.x)
	var length := ext.x if ax else ext.y
	var s := 0.85 if r["annex"] else clampf(float(r["height"]), 1.7, 2.3) / 2.0
	var tight := [false, false, false, false]
	for cz in range(a.y - 1, b.y + 1):
		for cx in range(a.x - 1, b.x + 1):
			var near := (cx < a.x or cx >= b.x or cz < a.y or cz >= b.y) and cx >= 0 and cz >= 0 and cx < int(layout["nx"]) and cz < int(layout["nz"])
			if near and (ladders.has(cz * int(layout["nx"]) + cx) or (BoardgenDressRules.walkable(layout, cz * int(layout["nx"]) + cx) and BoardgenDressRules.top_in(layout, cx, cz) > BoardgenDressRules.FLAT)):
				for k in 4:
					tight[k] = tight[k] or [cz < a.y, cx >= b.x, cz >= b.y, cx < a.x][k]
	var kf := 2 if ax else 1
	var role := String(VARIANT_ROLE.get(variant, ""))
	var cells := [Vector2i(b.x - 1, a.y), Vector2i(b.x - 1, b.y - 1), Vector2i(a.x, b.y - 1), a]   # the start cell of each face of the rectangle
	for i in roundi(length / c):
		var name := "dr_roof_s%d_%s" % [span, role if role != "" else ["mid_a", "mid_b"][(BoardgenDressStory.pick(id, 0x41, 2) + i) % 2]]
		name = name if MODULES.has(name) else "dr_roof_s%d_mid_b" % span   # damaged variants the kit lacks fall back to the whole roof
		var xf := _place(layout, cells[kf].x, cells[kf].y, kf, 0.0, i * c, 0.0)
		out.append({"module": name, "xf": _fit(xf, meta["modules"][name], s, Vector2(-INF, INF), Vector2(-span if tight[kf ^ 2] else -INF, 0.0 if tight[kf] else INF)), "cls": CLS, "lot": id, "variant": variant})
	for k: int in [kf, kf ^ 2]:
		var verge := "dr_roof_s%d_verge" % span
		var xf := _place(layout, cells[k].x, cells[k].y, k, 0.0, length - (0.32 if tight[(k + 3) % 4] else 0.0), 0.0)
		out.append({"module": verge, "xf": _fit(xf, meta["modules"][verge], s, Vector2(-INF, INF), Vector2(-span if tight[k ^ 2] else -INF, 0.0 if tight[k] else INF)), "cls": CLS})
	for k: int in ([1, 3] if ax else [0, 2]):
		var gable := "dr_gable_%s_s%d%s" % [style, span, "_b" if style == "tb" and BoardgenDressStory.pick(id, 0x47 + k, 2) == 1 else ""]
		var xf := _place(layout, cells[k].x, cells[k].y, k, 0.0, 0.0, 0.0)
		out.append({"module": gable, "xf": _fit(xf, meta["modules"][gable], s, Vector2(0.0 if tight[(k + 1) % 4] else -INF, span if tight[(k + 3) % 4] else INF), Vector2(-INF, 0.0 if tight[k] else INF)), "cls": CLS})
	return out


## A face transform raised to the eaves, scaled in Y by `s` (rise / 2.0), and squeezed so the module's local x / z extent stays inside the limits `lx` / `lz` (inches).
static func _fit(xf: Transform3D, m: Dictionary, s: float, lx: Vector2, lz: Vector2) -> Transform3D:
	var lo: Array = m["aabb_in"][0]
	var hi: Array = m["aabb_in"][1]
	var f := Vector3.ONE
	var o := Vector3.ZERO
	for ai: int in [0, 2]:
		var t0 := maxf(float(lo[ai]), [lx, lx, lz][ai].x)
		var t1 := minf(float(hi[ai]), [lx, lx, lz][ai].y)
		f[ai] = (t1 - t0) / (float(hi[ai]) - float(lo[ai]))
		o[ai] = t0 - float(lo[ai]) * f[ai]
	var out := xf * Transform3D(Basis.from_scale(Vector3(f.x, s, f.z)), o * BoardgenDressRules.IN_M)
	out.origin.y += EAVES_IN * BoardgenDressRules.IN_M
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
