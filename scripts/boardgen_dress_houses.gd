class_name BoardgenDressHouses
extends DressPlanner
## The house planner of the ruin-town dressing (docs/adr/0003-generated-board-dressing.md): walls,
## corners, doors, gables, roofs and chimneys of every Roofed lot. Pure data, board inches: one
## panel per free cell edge (neighbour top below the house's 2.5 in), the middle edge of the lot's
## frontage carries the one door, the four lot corners carry a post / quoin flush inside the lot.
## Style, picks and damage come from BoardgenDressStory; every transform comes from
## BoardgenDressRules.face_xf. Panels lean IN by the KNOBS angle (out would poke over R1). Roofs
## follow BoardgenTownDressing.roofs() (ridge axis, annex, rise); a span over 6 in flips the ridge
## to the other axis. Hip and catslide draw as gables, and a damaged roof (holed / rafters by D, at
## least 60 % whole per half) draws as mid_b until the kit has modules for them: a name outside
## MODULES falls back. Roof segments carry `lot` and their look for the tests.

const MODULES: Array[String] = [
	"dr_house_tb_blank",
	"dr_house_tb_door",
	"dr_house_tb_plain_a",
	"dr_house_tb_plain_b",
	"dr_house_tb_post",
	"dr_house_tb_window",
	"dr_house_tb_window_lit",
	"dr_house_st_door",
	"dr_house_st_plain_a",
	"dr_house_st_plain_b",
	"dr_house_st_quoin",
	"dr_house_st_window",
	"dr_roof_s3_mid_a",
	"dr_roof_s3_mid_b",
	"dr_roof_s3_verge",
	"dr_roof_s6_mid_a",
	"dr_roof_s6_mid_b",
	"dr_roof_s6_verge",
	"dr_gable_tb_s3",
	"dr_gable_tb_s3_b",
	"dr_gable_tb_s6",
	"dr_gable_tb_s6_b",
	"dr_gable_st_s3",
	"dr_gable_st_s6",
	"dr_chimney_a"
]
const CLS := "houses"
const DIRS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
const FACE_NAMES := ["N", "E", "S", "W"]
const CORNER_FACE := [3, 0, 1, 2]
## Salts of BoardgenDressStory.pick. Every choice of a lot draws with its own salt so the choices
## do not correlate (a low style pick must not also mean a lit window); the per-face salts add the
## face index 0..3 so the four faces of a lot differ.
const SALT_STYLE := 0x71  # timber or stone house
const SALT_PANEL := 0x33  # + face: where the panel sequence of a face starts
const SALT_LIT_WINDOW := 0x5A  # + face: whether a timber window here is the lot's one lit window
const SALT_INSET := 0x1F  # + face: how deep a panel sits in the wall
const TIMBER_IN_TEN := 6  # 6 of 10 houses are timber, the rest stone
const LIT_WINDOW_IN_TEN := 4  # 4 of 10 timber windows may be the lot's lit one
const PANEL_VARIANTS := 3  # plain_a, plain_b, window
const FALLEN_PLASTER_DAMAGE := 0.5  # above this a first-variant panel shows fallen plaster
const INSET_MIN_IN := 0.06  # the shallowest inset, also the default proud depth without one
const INSET_SPREAD_IN := 0.08  # how much deeper the inset pick may go
const INSET_STEPS := 16
const EAVES_IN := 2.5
const VARIANT_ROLE := {"holed": "broken", "rafters": "rafters"}


## Every placement of the houses class: a typed placement per panel, corner, roof piece and chimney.
func plan(ctx: DressContext) -> Array[DressPlacement]:
	var out: Array[DressPlacement] = []
	var layout: Dictionary = ctx.layout
	var story: Dictionary = ctx.story
	var fronts := {}
	for frontage: Dictionary in BoardgenTownDressing.frontage(layout):
		if String(frontage["front"]) != "":
			fronts[int(frontage["lot"])] = String(frontage["front"])
	var roofs := {}
	for r: Dictionary in BoardgenTownDressing.roofs(layout):
		roofs[int(r["lot"])] = roofs.get(int(r["lot"]), []) + [r]
	var variants := _variants(roofs, story)
	var ladders: Array = (layout["connectors"] as Array).reduce(
		func(acc: Array, cn: Dictionary) -> Array: return acc + [int(cn["low"]), int(cn["high"])],
		[]
	)
	for lot: Dictionary in layout["lots"]:
		if lot["kind"] != "Roofed":
			continue
		var id := int(lot["id"])
		var x0 := int(lot["x"])
		var z0 := int(lot["z"])
		var x1 := x0 + int(lot["w"])
		var z1 := z0 + int(lot["h"])
		var style := "tb" if BoardgenDressStory.pick(id, SALT_STYLE, 10) < TIMBER_IN_TEN else "st"
		var free: Array[Dictionary] = []  # every cell edge a panel goes on: {cx, cz, k = face}
		for cz in range(z0, z1):
			for cx in range(x0, x1):
				for face in 4:
					var neighbour: Vector2i = Vector2i(cx, cz) + DIRS[face]
					if ctx.top_in(neighbour.x, neighbour.y) < BoardgenGreybox.SOLID_IN:
						free.append({"cx": cx, "cz": cz, "k": face})
		var front := String(fronts.get(id, _longest_face(free)))
		var door := _middle_edge(free, FACE_NAMES.find(front))
		var previous := {}  # face -> the panel name placed last on it, so two neighbours differ
		var lit := false
		var door_done := false
		for edge: Dictionary in free:
			var cx: int = edge["cx"]
			var cz: int = edge["cz"]
			var face: int = edge["k"]
			var centre_in := (
				Vector2(cx + 0.5 - int(layout["nx"]) * 0.5, cz + 0.5 - int(layout["nz"]) * 0.5)
				* float(layout["cell_in"])
			)
			var damage := BoardgenDressStory.damage(story, centre_in)
			var lean := -(
				float(BoardgenDressStory.KNOBS["lean_base_deg"])
				+ float(BoardgenDressStory.KNOBS["lean_gain_deg"]) * damage
			)
			var module := "dr_house_%s_door" % style
			if door == edge and not door_done:
				door_done = true
			else:
				var along := cx if face % 2 == 0 else cz
				var variant := (
					(BoardgenDressStory.pick(id, SALT_PANEL + face, PANEL_VARIANTS) + along)
					% PANEL_VARIANTS
				)
				if damage > FALLEN_PLASTER_DAMAGE and variant == 0:
					variant = 1  # fallen plaster
				var name := _panel(variant)
				if name == String(previous.get(face, "")):
					name = _panel(variant + 1)
				var may_light := name == "window" and style == "tb" and not lit
				if (
					may_light
					and BoardgenDressStory.pick(id, SALT_LIT_WINDOW + face, 10) < LIT_WINDOW_IN_TEN
				):
					name = "window_lit"
					lit = true
				previous[face] = name
				module = "dr_house_%s_%s" % [style, name]
			var spec := ctx.spec(module)
			var proud := spec.proud_low if spec != null else INSET_MIN_IN
			var inset_pick := float(BoardgenDressStory.pick(id, face + SALT_INSET, INSET_STEPS))
			var inset := maxf(
				proud, INSET_MIN_IN + INSET_SPREAD_IN * inset_pick / float(INSET_STEPS - 1)
			)
			out.append(
				DressPlacement.new(module, _place(layout, cx, cz, face, inset, 0.0, lean), CLS)
			)
		var corner := "dr_house_tb_post" if style == "tb" else "dr_house_st_quoin"
		var cells := [
			Vector2i(x0, z0), Vector2i(x1 - 1, z0), Vector2i(x1 - 1, z1 - 1), Vector2i(x0, z1 - 1)
		]
		for i in 4:
			out.append(
				DressPlacement.new(
					corner, _corner(layout, cells[i], CORNER_FACE[i], ctx.spec(corner)), CLS
				)
			)
		for r: Dictionary in roofs.get(id, []):
			out.append_array(_roof(ctx, r, style, String(variants.get(id, "whole")), ladders))
	for b: Dictionary in BoardgenTownDressing.chimneys(layout):
		# the chimney's Y follows the box (the smoke emitter's) height: (roof height + 0.9) / 2.9
		var box := AABB(b["lo"], b["hi"] - b["lo"])
		out.append(
			DressPlacement.new(
				"dr_chimney_a",
				Transform3D(
					Basis.from_scale(Vector3(1.0, box.size.y / 2.9, 1.0)),
					(
						(box.get_center() - Vector3(0.0, box.size.y * 0.5, 0.0))
						* Units.INCHES_TO_METERS
					)
				),
				CLS
			)
		)
	return out


## Roof variant per lot by the damage at its main roof's centre: rafters above KNOBS
## roof_rafters_from, holed above roof_holed_from, else whole; per half the least damaged
## roof_whole_share of the lots stay whole whatever their D.
static func _variants(roofs: Dictionary, story: Dictionary) -> Dictionary:
	var k := BoardgenDressStory.KNOBS
	var halves := [[], []]
	for id: int in roofs:
		for r: Dictionary in roofs[id]:
			if not r["annex"]:
				halves[int(r["half"])].append(
					{"lot": id, "d": BoardgenDressStory.damage(story, r["centre"])}
				)
	var out := {}
	for half: Array in halves:
		half.sort_custom(
			func(a: Dictionary, b: Dictionary) -> bool: return float(a["d"]) < float(b["d"])
		)
		var whole := ceili(float(k["roof_whole_share"]) * half.size() - 0.001)
		for i in half.size():
			var d := float(half[i]["d"])
			out[half[i]["lot"]] = (
				"whole"
				if i < whole or d <= float(k["roof_holed_from"])
				else ("rafters" if d > float(k["roof_rafters_from"]) else "holed")
			)
	return out


## One roof of roofs(): segments per 3 in of ridge on the front eaves plane, a verge at both ends
## (the start one turned 180 deg, on the back plane), a gable on both end faces; all at the eaves,
## Y scaled to the rise (an annex at the lowest, 1.7). A TIGHT side (a walkable tier or a ladder
## cell beside it, diagonals included) gets no overhang: eaves and gable jetties are squeezed to
## the wall plane and the verge moves inside the end, because the honesty rules (R4, R5) allow
## nothing of a roof over a tier top or in a ladder strip.
static func _roof(
	ctx: DressContext, r: Dictionary, style: String, variant: String, ladders: Array
) -> Array[DressPlacement]:
	var out: Array[DressPlacement] = []
	var layout: Dictionary = ctx.layout
	var c := float(layout["cell_in"])
	var id := int(r["lot"])
	var size := (
		Vector2(float(r["length"]), float(r["width"]))
		- Vector2.ONE * 2.0 * BoardgenTownDressing.OVERHANG_IN
	)  # run along, extent across the ridge
	var ext := size if r["along_x"] else Vector2(size.y, size.x)
	var ax: bool = r["along_x"] != (size.y > 6.0 + BoardgenDressRules.TOL)  # the span rule
	var lo: Vector2 = (
		(r["centre"] - ext * 0.5) / c + Vector2(int(layout["nx"]), int(layout["nz"])) * 0.5
	)
	var a := Vector2i(roundi(lo.x), roundi(lo.y))
	var b := a + Vector2i(roundi(ext.x / c), roundi(ext.y / c))
	var span := roundi(ext.y if ax else ext.x)
	var length := ext.x if ax else ext.y
	var s := 0.85 if r["annex"] else clampf(float(r["height"]), 1.7, 2.3) / 2.0
	var tight := [false, false, false, false]
	for cz in range(a.y - 1, b.y + 1):
		for cx in range(a.x - 1, b.x + 1):
			var near := (
				(cx < a.x or cx >= b.x or cz < a.y or cz >= b.y)
				and cx >= 0
				and cz >= 0
				and cx < int(layout["nx"])
				and cz < int(layout["nz"])
			)
			if (
				near
				and (
					ladders.has(cz * int(layout["nx"]) + cx)
					or (
						ctx.walkable(cz * int(layout["nx"]) + cx)
						and ctx.top_in(cx, cz) > BoardgenDressRules.FLAT
					)
				)
			):
				for k in 4:
					tight[k] = tight[k] or [cz < a.y, cx >= b.x, cz >= b.y, cx < a.x][k]
	var kf := 2 if ax else 1
	var role := String(VARIANT_ROLE.get(variant, ""))
	# the start cell of each face of the rectangle
	var cells := [Vector2i(b.x - 1, a.y), Vector2i(b.x - 1, b.y - 1), Vector2i(a.x, b.y - 1), a]
	for i in roundi(length / c):
		var name := (
			"dr_roof_s%d_%s"
			% [
				span,
				(
					role
					if role != ""
					else ["mid_a", "mid_b"][(BoardgenDressStory.pick(id, 0x41, 2) + i) % 2]
				)
			]
		)
		# a name the kit lacks falls back to the whole roof
		name = name if MODULES.has(name) else "dr_roof_s%d_mid_b" % span
		var xf := _place(layout, cells[kf].x, cells[kf].y, kf, 0.0, i * c, 0.0)
		out.append(
			DressPlacement.new(
				name,
				_fit(
					xf,
					ctx.spec(name),
					s,
					Vector2(-INF, INF),
					Vector2(-span if tight[kf ^ 2] else -INF, 0.0 if tight[kf] else INF)
				),
				CLS,
				id,
				variant
			)
		)
	for k: int in [kf, kf ^ 2]:
		var verge := "dr_roof_s%d_verge" % span
		var xf := _place(
			layout,
			cells[k].x,
			cells[k].y,
			k,
			0.0,
			length - (0.32 if tight[(k + 3) % 4] else 0.0),
			0.0
		)
		out.append(
			DressPlacement.new(
				verge,
				_fit(
					xf,
					ctx.spec(verge),
					s,
					Vector2(-INF, INF),
					Vector2(-span if tight[k ^ 2] else -INF, 0.0 if tight[k] else INF)
				),
				CLS
			)
		)
	for k: int in [1, 3] if ax else [0, 2]:
		var gable := (
			"dr_gable_%s_s%d%s"
			% [
				style,
				span,
				"_b" if style == "tb" and BoardgenDressStory.pick(id, 0x47 + k, 2) == 1 else ""
			]
		)
		var xf := _place(layout, cells[k].x, cells[k].y, k, 0.0, 0.0, 0.0)
		out.append(
			DressPlacement.new(
				gable,
				_fit(
					xf,
					ctx.spec(gable),
					s,
					Vector2(
						0.0 if tight[(k + 1) % 4] else -INF, span if tight[(k + 3) % 4] else INF
					),
					Vector2(-INF, 0.0 if tight[k] else INF)
				),
				CLS
			)
		)
	return out


## A face transform raised to the eaves, scaled in Y by `s` (rise / 2.0), and squeezed so the
## module's local x / z extent stays inside the limits `lx` / `lz` (inches).
static func _fit(
	xf: Transform3D, spec: DressModuleSpec, s: float, lx: Vector2, lz: Vector2
) -> Transform3D:
	var lo: Array[float] = spec.aabb_lo_in
	var hi: Array[float] = spec.aabb_hi_in
	var f := Vector3.ONE
	var o := Vector3.ZERO
	for ai: int in [0, 2]:
		var t0 := maxf(lo[ai], [lx, lx, lz][ai].x)
		var t1 := minf(hi[ai], [lx, lx, lz][ai].y)
		f[ai] = (t1 - t0) / (hi[ai] - lo[ai])
		o[ai] = t0 - lo[ai] * f[ai]
	var out := xf * Transform3D(Basis.from_scale(Vector3(f.x, s, f.z)), o * Units.INCHES_TO_METERS)
	out.origin.y += EAVES_IN * Units.INCHES_TO_METERS
	return out


## A face module's transform: left foot at the face's start point (optionally shifted along it),
## moved `inset` into the mass, tipped out by `lean` degrees.
static func _place(
	layout: Dictionary, cx: int, cz: int, k: int, inset: float, shift: float, lean: float
) -> Transform3D:
	var cell_in := float(layout["cell_in"])
	var cell_corner := Vector3(
		(cx - int(layout["nx"]) * 0.5) * cell_in, 0.0, (cz - int(layout["nz"]) * 0.5) * cell_in
	)
	var along: Vector3 = [Vector3(-1, 0, 0), Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, 0, 1)][k]
	var away: Vector3 = [Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0)][k]
	var starts := [
		cell_corner + Vector3(cell_in, 0, 0),
		cell_corner + Vector3(cell_in, 0, cell_in),
		cell_corner + Vector3(0, 0, cell_in),
		cell_corner
	]
	var start: Vector3 = starts[k]
	return BoardgenDressRules.face_xf(start + along * shift, along, away, inset, lean)


## A corner piece flush inside the lot: shifted by its left overhang, inset by its mounting depth,
## so no part pokes into the neighbour cell.
static func _corner(
	layout: Dictionary, cell: Vector2i, k: int, spec: DressModuleSpec
) -> Transform3D:
	var lo := spec.aabb_lo
	var hi := spec.aabb_hi
	return _place(layout, cell.x, cell.y, k, hi.z, -lo.x, 0.0)


## A panel variant: 0 plain_a, 1 plain_b, 2 window (window_lit for timber is chosen by the caller).
static func _panel(variant: int) -> String:
	return ["plain_a", "plain_b", "window"][posmod(variant, PANEL_VARIANTS)]


## The middle free edge of face `k` (the door's edge), or {} when that face has none.
static func _middle_edge(free: Array[Dictionary], k: int) -> Dictionary:
	var edges := free.filter(func(edge: Dictionary) -> bool: return int(edge["k"]) == k)
	if edges.is_empty():
		return {}
	edges.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return (
				(int(a["cx"]) if k % 2 == 0 else int(a["cz"]))
				< (int(b["cx"]) if k % 2 == 0 else int(b["cz"]))
			)
	)
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
