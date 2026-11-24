class_name BoardgenTownFrames
## Half-timber shells as real geometry: the kit's frame panels (posts, rails, braces 0.07 in proud of the face, dark openings with
## depth, shutters, boards, lath where the plaster fell) on the drawn faces of the intact houses and on the faces of the ruined tiers; timber gable ends, snapped corner
## posts and chimney stacks on the ruined lots; one burnt shell per board half. VISUAL ONLY: every piece lies on a face (<= 0.2 in proud of the collider) or on a tier top
## inside the 0.75 in edge strip; nothing changes a collider, a level or a cell. While a module is not cached the shader's painted frame stays.

const IN_M := 0.0254
## The panel kinds in the order they follow each other along a face (each differs from both neighbours, the cycle too): a face walks this list from an offset by hash.
const PANELS := ["hf_panel_window", "hf_panel_brace1", "hf_panel_lath", "hf_panel_plain", "hf_panel_boarded", "hf_panel_shutter", "hf_panel_brace"]
const MODULES := ["hf_panel_window", "hf_panel_shutter", "hf_panel_boarded", "hf_panel_brace", "hf_panel_lath", "hf_panel_plain", "hf_panel_brace1", "hf_door", "hf_post", "hf_gable", "hf_gable_burnt", "hf_stub_post", "hf_beam_fallen"]
const GABLE_W_IN := 3.03   # the gable module's width at scale 1, rounded up so its ends stay inside the face
const GABLE_H_IN := 1.942   # the gable module's peak at scale 1 (its peak is scaled to the masonry gable's, never above it)
const CHARRED := Color(0.16, 0.15, 0.14)
## (lead 21.11.: C's timber is dark weathered grey-brown - not black - on dirty cream-grey infill) the instance colour of the timber set on a frame, varied +-15 % per panel.
const TIMBER := Color(0.66, 0.6, 0.53)
const DIRS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]   # N, E, S, W
const TIMBER_SHARE := 0.5
const STACK_SHARE := 0.6   # (lead 21.11., skyline) a ruined lot in this share keeps a chimney stack on its gable
const STACK_TOP_IN := 8.9   # a stack never reaches the 9 in tower crown
const STACK_IN := 0.75   # the chimney module's 0.76 in corbel scaled to 0.57, its middle 0.4 in inside the face: inside the 0.75 in strip


## A 0..1 hash that mixes well over neighbouring integers (BoardgenTownDressing._hash repeats along a run of cells).
static func _rnd(a: int, b: int, salt: int) -> float:
	return fposmod(sin(float(a) * 12.9898 + float(b) * 78.233 + float(salt) * 37.719) * 43758.5453, 1.0)


## The panel kind at position `along` (a cell or bay index along a face) of the face line `line`: the list walked from a hashed offset, so two neighbours never match.
static func _pick(line: int, along: int, salt: int) -> String:
	return PANELS[posmod(along + int(_rnd(line, salt, 300) * 7.0), PANELS.size())]


## A frame panel's basis: turned to face `a`, a crooked lean (<= 2 degrees about the face normal) for one in five (`lean` false keeps it square, e.g. under a tier's top), stretched to the bay.
static func _panel_basis(a: float, scale: Vector3, seed: int, lean: bool) -> Basis:
	var roll := (_rnd(seed, 7, 302) - 0.5) * 0.07 if lean and _rnd(seed, 7, 301) < 0.2 else 0.0
	return Basis(Vector3.UP, a) * Basis(Vector3.BACK, roll) * Basis.from_scale(scale)


static func _timber(seed: int) -> Color:
	return TIMBER * (0.85 + 0.3 * _rnd(seed, 3, 303))


static func _item(module: String, basis: Basis, at_in: Vector3, colour := Color.WHITE) -> Dictionary:
	return {"module": module, "xf": Transform3D(basis, at_in * IN_M), "colour": colour}


## How much the board's fire story burns a point (board inches), as the shader folds it (both halves the same story); 0..1.
static func fire_at(layout: Dictionary, p: Vector2) -> float:
	var st := BoardgenTownDressing.story(int(layout.get("seed", 0)))
	var q := (-p if p.y >= 0.0 else p) + Vector2(0.0, 12.0)
	return clampf(0.5 + 0.65 * clampf(q.dot(Vector2(st.r, st.g)) / (absf(st.r) * 24.0 + absf(st.g) * 12.0), -1.0, 1.0), 0.0, 1.0)


static func _lot_centre(layout: Dictionary, lot: Dictionary) -> Vector2:
	var cell_in := float(layout["cell_in"])
	return (Vector2(lot["x"], lot["z"]) + Vector2(lot["w"], lot["h"]) * 0.5 - Vector2(layout["nx"], layout["nz"]) * 0.5) * cell_in


## The ruined, walkable lots (Block / Deck) that are timber shells: half of them by hash, and the burnt ones. {lot id: true}
static func timber_lots(layout: Dictionary) -> Dictionary:
	var out := burnt_lots(layout)
	var tiers := BoardgenTownDressing.tier_parts(layout)
	for lot: Dictionary in layout["lots"]:
		if tiers["axis_x"].has(lot["id"]) and BoardgenTownDressing._hash(lot["id"], 1 if int(lot["z"]) * 2 >= int(layout["nz"]) else 0, 310) < TIMBER_SHARE:
			out[lot["id"]] = true
	return out


## The burnt shell (plan H5): in each board half the ruined, walkable lot the fire story burns most. {lot id: true}
static func burnt_lots(layout: Dictionary) -> Dictionary:
	var best := [-1.0, -1.0]
	var pick := [-1, -1]
	var tiers := BoardgenTownDressing.tier_parts(layout)
	for lot: Dictionary in layout["lots"]:
		if not tiers["axis_x"].has(lot["id"]):
			continue
		var c := _lot_centre(layout, lot)
		var half := 1 if c.y > 0.0 else 0
		var f := fire_at(layout, c)
		if f > best[half]:
			best[half] = f
			pick[half] = lot["id"]
	var out := {}
	for id: int in pick:
		if id >= 0:
			out[id] = true
	return out


## The panels of the intact houses: one per 3 in of every drawn face that looks at open ground (a level-0 cell that is not another house), a ground storey on the plinth and
## an upper storey above it (a jettied front keeps its ground storey on the recessed face), a door on the front, a corner post on every corner. [{module, xf, colour}]
static func house_items(layout: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for b: Dictionary in BoardgenTownDressing.house_bodies(layout):
		var lot: Dictionary = layout["lots"].filter(func(l: Dictionary) -> bool: return l["id"] == b["lot"]).front()
		var size: Vector2 = b["size"]
		var yaw := float(b["yaw"])
		var half: int = b["half"]
		var plinth := float(b["plinth"])
		var top := float(b["top"])
		var storey := float(b["storey"]) if float(b["jetty"]) > 0.0 else (plinth + top) * 0.5 if plinth + 0.9 > top - 0.75 else clampf(float(b["storey"]), plinth + 0.9, top - 0.75)
		var front := ["N", "E", "S", "W"].find(b["front"])
		var door_side := front if front >= 0 else (0 if size.x >= size.y else 1)
		var door_at := -1
		for side in 4:
			var d := DIRS[side]
			var along_x := d.y != 0
			var n: int = lot["w"] if along_x else lot["h"]
			var span := size.x if along_x else size.y
			var reach := (size.y if along_x else size.x) * 0.5
			var bw := span / float(n)
			var a := atan2(float(d.x), float(d.y))
			if side == door_side:
				door_at = int(BoardgenTownDressing._hash(b["lot"], half, 320) * float(n))
			for j in n:
				var cx: int = int(lot["x"]) + (j if along_x else (-1 if d.x < 0 else int(lot["w"])))
				var cz: int = int(lot["z"]) + (j if not along_x else (-1 if d.y < 0 else int(lot["h"])))
				var nb := BoardgenTownSilhouette._level(layout, cx, cz)
				if nb > 0 or (nb == 0 and layout["cells"][cz * int(layout["nx"]) + cx]["lot_kind"] == "Roofed"):
					continue   # a party wall or a raised neighbour: the face is hidden
				var u := -span * 0.5 + (float(j) + 0.5) * bw
				var along := Vector2(u, 0.0) if along_x else Vector2(0.0, u)
				for row in 2:
					var r := reach - (float(b["jetty"]) if row == 0 and side == front else 0.0)
					var at: Vector2 = b["centre"] + (Vector2(d) * r + along).rotated(-yaw)
					var door := row == 0 and side == door_side and j == door_at
					var y0 := 0.0 if door else (plinth if row == 0 else storey)
					var h := storey if door else (storey - plinth if row == 0 else top - storey)
					var m := "hf_door" if door else _pick(b["lot"] * 16 + side * 2 + row + half * 512, j, 1)
					var seed: int = b["lot"] * 64 + side * 16 + j * 2 + row + half * 4096
					out.append(_item(m, _panel_basis(yaw + a, Vector3(bw / 3.0, h, 1.0), seed, row == 0 and m != "hf_door"), Vector3(at.x, y0, at.y), _timber(seed)))
		for corner in 4:
			var sx := 1.0 if corner in [1, 2] else -1.0
			var sz := 1.0 if corner >= 2 else -1.0
			var jet := float(b["jetty"]) > 0.0 and ((front == 0 and sz < 0) or (front == 2 and sz > 0) or (front == 1 and sx > 0) or (front == 3 and sx < 0))
			var y0 := storey if jet else plinth
			var at: Vector2 = b["centre"] + Vector2(sx * size.x * 0.5, sz * size.y * 0.5).rotated(-yaw)
			out.append(_item("hf_post", Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(1.0, top - y0, 1.0)), Vector3(at.x, y0, at.y), _timber(b["lot"] * 8 + corner)))
	return out


## The panels of the ruined tiers (Block / Deck / raised Terrace): every open face of a raised tier cell in its GROUND storey (the shader's plastered frame over the 0.8 in rubble
## plinth, up to 3 in - never on a face onto a yard, which stays rubble) and, on a 6 in tier, its half-timber storey (the shader's band 1); both bands shifted by the
## part's tone exactly as the shader shifts them, two rows of panels each, one ground bay in four a doorway; never on a face a ladder leans on. A burnt lot's panels
## are charred and lath / brace only. [{module, xf, colour}]
static func tier_items(layout: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var nx: int = layout["nx"]
	var nz: int = layout["nz"]
	var cell_in := float(layout["cell_in"])
	var origin := Vector2(nx, nz) * cell_in * -0.5
	var tiers := BoardgenTownDressing.tier_parts(layout)
	var ladders := BoardgenTownSilhouette._ladder_tops(layout)
	var burnt := burnt_lots(layout)
	var level_in: Array = layout["level_in"]
	for i in nx * nz:
		var cd: Dictionary = layout["cells"][i]
		var level: int = cd["level"]
		if level < 1 or level > 2 or ["Wall", "Roofed"].has(cd["lot_kind"]):
			continue   # (every 3 / 6 in cell the shader paints as a ruined row: Block, Deck, a raised Terrace or a street sector's raised ruin)
		var lot_id: int = cd["lot_id"]
		var half := 1 if int(cd["z"]) * 2 >= nz else 0
		var shift := (float((1 + int(float(tiers["shade"]["%d/%d" % [lot_id, tiers["cells"][i]]]) * 253.0)) if tiers["cells"].has(i) else 128) / 255.0 - 0.5) * 0.7   # the shader's uv.y shift of this cell's storey bands (the ground map's green: a tier part's tone, else 128)
		var top: float = level_in[level]
		for side in 4:
			var d := DIRS[side]
			var nb := BoardgenTownSilhouette._level(layout, int(cd["x"]) + d.x, int(cd["z"]) + d.y)
			if nb >= level or (ladders.get(i, []) as Array).has(side):
				continue
			var yard := nb == 0 and BoardgenGreybox._cell_kind(layout["cells"][(int(cd["z"]) + d.y) * nx + int(cd["x"]) + d.x], true) == "yard"
			var bands: Array = []   # [y0, y1, ground]
			if nb <= 0 and not yard:
				bands.append([0.8 - shift, minf(3.0 - shift, top), true])
			if level >= 2:
				bands.append([maxf(3.0 - shift, float(level_in[maxi(nb, 0)])), minf(6.0 - shift, top), false])
			var a := atan2(float(d.x), float(d.y))
			var mid := origin + (Vector2(cd["x"], cd["z"]) + Vector2(0.5, 0.5) + Vector2(d) * 0.5) * cell_in
			for bd: Array in bands:
				var y0: float = bd[0]
				var y1: float = bd[1]
				if y1 - y0 < 1.2:
					continue
				var rows := 2 if y1 - y0 > 1.9 else 1
				var h := (y1 - y0) / float(rows)
				for row in rows:
					var salt: int = i * 16 + side * 4 + row + (2 if bd[2] else 0)
					var line: int = (int(cd["z"]) if d.y != 0 else int(cd["x"])) * 4 + side   # the face line this cell's face lies on; `along` walks it
					var door: bool = not burnt.has(lot_id) and bd[2] and row == 0 and BoardgenTownDressing._hash(i * 4 + side, half, 331) < 0.25   # a doorway from the ground up through the plinth
					var m := "hf_door" if door else _pick(line * 4 + row + (2 if bd[2] else 0), int(cd["x"]) if d.y != 0 else int(cd["z"]), 2)
					if burnt.has(lot_id):
						m = "hf_panel_lath" if BoardgenTownDressing._hash(salt, half, 330) < 0.6 else "hf_panel_brace"
					out.append(_item(m, _panel_basis(a, Vector3(cell_in / 3.0, y0 + h if door else h, 1.0), salt, row == 0 and rows == 2 and not door), Vector3(mid.x, 0.0 if door else y0 + h * float(row), mid.y),
						CHARRED if burnt.has(lot_id) else _timber(salt)))
	return out


## The skyline of the ruined lots: timber gable ends (H4) on the ladder-free gable faces of the timber lots, as high as the masonry gable they replace; a chimney stack in
## one gable of most ruined lots; snapped posts on the timber lots' bare corners. The burnt lots (H5) take the burnt gable, charred posts and a fallen beam at the foot of
## one open face (STRIP: on the ground below, <= 0.7 in out, never a ladder foot). [{module, xf, colour}]
static func ruin_items(layout: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var timber := timber_lots(layout)
	var burnt := burnt_lots(layout)
	var faces: Array = []
	BoardgenTownSilhouette.ruin_gables(layout, {}, faces)
	for f: Dictionary in faces:
		if not timber.has(f["lot"]) or not f["free"]:
			continue
		var d := DIRS[f["side"]]
		var a := atan2(float(d.x), float(d.y))
		var mid: Vector2 = f["mid"]
		var b := burnt.has(f["lot"])
		out.append(_item("hf_gable_burnt" if b else "hf_gable", Basis(Vector3.UP, a) * Basis.from_scale(Vector3(float(f["width"]) / GABLE_W_IN, float(f["peak"]) / GABLE_H_IN, 1.0)),
			Vector3(mid.x, f["top"], mid.y), CHARRED if b else _timber(int(f["lot"]) * 4 + int(f["side"]))))
	var stacked := {}
	for f: Dictionary in faces:   # a chimney stack standing in the gable (ruined lots, ladder-free gable faces, one per lot): the skyline of a town that lost its roofs
		if not f["free"] or stacked.has(f["lot"]) or _rnd(int(f["lot"]), 0, 350) >= STACK_SHARE or STACK_TOP_IN - float(f["top"]) < 1.0:   # no stack on a 9 in top: no room under the crown
			continue
		stacked[f["lot"]] = true
		var d := DIRS[f["side"]]
		var mid: Vector2 = f["mid"]
		var at := mid - Vector2(d) * 0.4
		var hgt := minf(float(f["peak"]) + 0.6, STACK_TOP_IN - float(f["top"]))
		out.append(_item("chimney_broken" if burnt.has(f["lot"]) or _rnd(int(f["lot"]), 1, 351) < 0.4 else "chimney_pots",
			Basis(Vector3.UP, atan2(float(d.x), float(d.y))) * Basis.from_scale(Vector3(STACK_IN, hgt / 3.78, STACK_IN)), Vector3(at.x, f["top"], at.y)))
	var nx: int = layout["nx"]
	var cell_in := float(layout["cell_in"])
	var origin := Vector2(nx, int(layout["nz"])) * cell_in * -0.5
	var gabled := {}   # "lot/side" of every timber gable placed
	for f: Dictionary in faces:
		if timber.has(f["lot"]) and f["free"]:
			gabled["%d/%d" % [f["lot"], f["side"]]] = true
	var ladder_tops: Array[Vector2] = []
	for c: Dictionary in layout["connectors"]:
		ladder_tops.append(Vector2(c["edge_in"][0], c["edge_in"][1]) + origin)
	for lot: Dictionary in layout["lots"]:   # snapped corner posts on the outer corners of a timber lot that no timber gable covers (inside a 0.4 in corner square)
		if not timber.has(lot["id"]):
			continue
		for corner in 4:
			var sx := 1 if corner in [1, 2] else 0
			var sz := 1 if corner >= 2 else 0
			var cx: int = int(lot["x"]) + sx * (int(lot["w"]) - 1)
			var cz: int = int(lot["z"]) + sz * (int(lot["h"]) - 1)
			var level := BoardgenTownSilhouette._level(layout, cx, cz)
			var side_x := 1 if sx == 1 else 3
			var side_z := 2 if sz == 1 else 0
			if level < 1 or BoardgenTownSilhouette._level(layout, cx + DIRS[side_x].x, cz) >= level or BoardgenTownSilhouette._level(layout, cx, cz + DIRS[side_z].y) >= level:
				continue
			if gabled.has("%d/%d" % [lot["id"], side_x]) or gabled.has("%d/%d" % [lot["id"], side_z]):
				continue
			var at := origin + Vector2(cx + sx, cz + sz) * cell_in + Vector2(0.2 if sx == 0 else -0.2, 0.2 if sz == 0 else -0.2)
			if ladder_tops.any(func(t: Vector2) -> bool: return t.distance_to(at) < BoardgenTownSilhouette.LADDER_GAP_IN + 0.2):
				continue
			out.append(_item("hf_stub_post", Basis(Vector3.UP, BoardgenTownDressing._hash(lot["id"] * 4 + corner, 0, 340) * TAU), Vector3(at.x, float(layout["level_in"][level]), at.y), CHARRED if burnt.has(lot["id"]) else _timber(int(lot["id"]) * 4 + corner)))
	var feet := {}
	for c: Dictionary in layout["connectors"]:
		feet[int(c["low"])] = true
	for lot: Dictionary in layout["lots"]:
		if not burnt.has(lot["id"]):
			continue
		var done := false
		for dz in int(lot["h"]):
			for dx in int(lot["w"]):
				for side in 4:
					var d := DIRS[side]
					var x := int(lot["x"]) + dx + d.x
					var z := int(lot["z"]) + dz + d.y
					if done or BoardgenTownSilhouette._level(layout, x, z) != 0 or feet.has(z * nx + x) or layout["cells"][z * nx + x]["lot_kind"] == "Hazard":
						continue
					var face := origin + (Vector2(int(lot["x"]) + dx, int(lot["z"]) + dz) + Vector2(0.5, 0.5) + Vector2(d) * 0.5) * cell_in
					out.append(_item("hf_beam_fallen", Basis(Vector3.UP, atan2(float(d.x), float(d.y))), Vector3(face.x, 0.0, face.y), CHARRED))
					done = true
	return out


## Everything above by module: {module: [{xf, colour}]} (BoardgenTownKit.plan merges it).
static func plan(layout: Dictionary) -> Dictionary:
	var out := {}
	for item: Dictionary in house_items(layout) + tier_items(layout) + ruin_items(layout):
		(out.get_or_add(item["module"], []) as Array).append(item)
	return out
