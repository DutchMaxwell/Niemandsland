class_name BoardgenTownFrames
## Half-timber shells as real geometry (plan PLAN_RUINTOWN_TARGET_C, train 3): the kit's frame panels (posts, rails, braces 0.07 in proud of the face, dark openings with
## depth, shutters, boards, lath where the plaster fell) on the drawn faces of the intact houses and on the faces of the ruined tiers. VISUAL ONLY: every piece lies on a
## face (<= 0.2 in proud of the collider); nothing changes a collider, a level or a cell. While a module is not cached the shader's painted frame stays.

const IN_M := 0.0254
## The panel kinds in the order they follow each other along a face (each differs from both neighbours, the cycle too): a face walks this list from an offset by hash.
const PANELS := ["hf_panel_window", "hf_panel_brace1", "hf_panel_lath", "hf_panel_plain", "hf_panel_boarded", "hf_panel_shutter", "hf_panel_brace"]
const MODULES := ["hf_panel_window", "hf_panel_shutter", "hf_panel_boarded", "hf_panel_brace", "hf_panel_lath", "hf_panel_plain", "hf_panel_brace1", "hf_door", "hf_post"]
## (lead 21.11.: C's timber is DARK, weathered grey-brown to near black, the infill pale) the instance colour of the timber set on a frame, varied +-15 % per panel.
const TIMBER := Color(0.36, 0.33, 0.31)
const DIRS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]   # N, E, S, W


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
## part's tone exactly as the shader shifts them, two rows of panels each, one ground bay in four a doorway; never on a face a ladder leans on. [{module, xf, colour}]
static func tier_items(layout: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var nx: int = layout["nx"]
	var nz: int = layout["nz"]
	var cell_in := float(layout["cell_in"])
	var origin := Vector2(nx, nz) * cell_in * -0.5
	var tiers := BoardgenTownDressing.tier_parts(layout)
	var ladders := BoardgenTownSilhouette._ladder_tops(layout)
	var level_in: Array = layout["level_in"]
	for i in nx * nz:
		var cd: Dictionary = layout["cells"][i]
		var level: int = cd["level"]
		if level < 1 or level > 2 or ["Wall", "Roofed"].has(cd["lot_kind"]):
			continue   # (every 3 / 6 in cell the shader paints as a ruined row: Block, Deck, a raised Terrace or a street sector's raised ruin)
		var half := 1 if int(cd["z"]) * 2 >= nz else 0
		var shift := (float((1 + int(float(tiers["shade"]["%d/%d" % [cd["lot_id"], tiers["cells"][i]]]) * 253.0)) if tiers["cells"].has(i) else 128) / 255.0 - 0.5) * 0.7   # the shader's uv.y shift of this cell's storey bands (the ground map's green: a tier part's tone, else 128)
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
					var door: bool = bd[2] and row == 0 and BoardgenTownDressing._hash(i * 4 + side, half, 331) < 0.25   # a doorway from the ground up through the plinth
					var m := "hf_door" if door else _pick(line * 4 + row + (2 if bd[2] else 0), int(cd["x"]) if d.y != 0 else int(cd["z"]), 2)
					out.append(_item(m, _panel_basis(a, Vector3(cell_in / 3.0, y0 + h if door else h, 1.0), salt, row == 0 and rows == 2 and not door), Vector3(mid.x, 0.0 if door else y0 + h * float(row), mid.y),
						_timber(salt)))
	return out


## Everything above by module: {module: [{xf, colour}]} (BoardgenTownKit.plan merges it).
static func plan(layout: Dictionary) -> Dictionary:
	var out := {}
	for item: Dictionary in house_items(layout) + tier_items(layout):
		(out.get_or_add(item["module"], []) as Array).append(item)
	return out
