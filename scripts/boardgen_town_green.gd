class_name BoardgenTownGreen
extends RefCounted
## Where the ruin town grows green (the GREEN MAP): the layout rasterised ONCE into an R8 texture, TEXELS_PER_IN texels per inch, texel centres symmetric about the
## board centre (the pattern of BoardgenTownGrit.map). Value = cover 0..1 on the open earth and the garden plots, 0 everywhere else:
##   NOISE x a fractal noise (period 6 in, seeded by the layout's seed, FOLDED by the half turn: a texel and its twin read the same noise)
##   + WALL_FOOT within WALL_FOOT_IN of a raised or solid cell (growth at the wall feet) + BAND inside the deployment bands + PLOT on a plot,
##   times smoothstep(0, VERGE_IN) of the distance to the nearest street cell (the trodden verge thins out), clamped 0..1;
##   0 in every ladder strip (BoardgenDressRules._ladder_zones) and every kept-clear cell (ladder ends, landmarks).
## Pure data: the rules never read it; the board shader and the blades do (later steps).

const TEXELS_PER_IN := 4
const NOISE := 0.5
const NOISE_PERIOD_IN := 6.0
const WALL_FOOT := 0.45
const WALL_FOOT_IN := 1.0
const BAND := 0.25
const DEPLOY_DEPTH_IN := 12.0   # the deployment band runs this far in from each long edge
const PLOT := 0.3
const VERGE_IN := 0.6
const OPEN := ["street", "ground", "rough", "yard", "hazard", "rubble"]   # level-0 kinds: everything else is raised or solid


static func map(layout: Dictionary) -> Image:
	var nx: int = layout["nx"]
	var nz: int = layout["nz"]
	var cell := float(layout["cell_in"])
	var half := Vector2(nx, nz) * cell * 0.5
	var w := int(round(nx * cell * TEXELS_PER_IN))
	var h := int(round(nz * cell * TEXELS_PER_IN))
	var kinds: Array[String] = []
	for cd: Dictionary in layout["cells"]:
		kinds.append(BoardgenGreybox._cell_kind(cd, true))
	var clear := BoardgenDressRules.kept_clear(layout)
	var ladders := BoardgenDressRules._ladder_zones(layout)
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.seed = int(layout.get("seed", 0))
	noise.frequency = 1.0 / NOISE_PERIOD_IN
	var bytes := PackedByteArray()
	bytes.resize(w * h)
	for tz in h:
		for tx in w:
			var p := Vector2((tx + 0.5) / TEXELS_PER_IN, (tz + 0.5) / TEXELS_PER_IN) - half
			var cx := clampi(int(floor((p.x + half.x) / cell)), 0, nx - 1)
			var cz := clampi(int(floor((p.y + half.y) / cell)), 0, nz - 1)
			var i := cz * nx + cx
			if kinds[i] not in ["ground", "rough"] or clear.has(i) or ladders.any(func(r: Rect2) -> bool: return r.has_point(p)):
				continue
			var q := -p if p.y >= 0.0 else p
			var v := NOISE * (noise.get_noise_2d(q.x, q.y) * 0.5 + 0.5)
			v += WALL_FOOT if _near(kinds, nx, nz, cell, half, p, cx, cz, false) <= WALL_FOOT_IN else 0.0
			v += BAND if absf(p.y) >= half.y - DEPLOY_DEPTH_IN else 0.0
			v += PLOT if kinds[i] == "rough" else 0.0
			v *= smoothstep(0.0, VERGE_IN, _near(kinds, nx, nz, cell, half, p, cx, cz, true))
			bytes[tz * w + tx] = int(round(clampf(v, 0.0, 1.0) * 255.0))
	return Image.create_from_data(w, h, false, Image.FORMAT_R8, bytes)


## Sets the map on the board's material (linear filter: the shader blends between texels).
static func apply(mat: ShaderMaterial, layout: Dictionary) -> void:
	mat.set_shader_parameter("green_map", ImageTexture.create_from_image(map(layout)))


## The distance (inches, capped at one cell) from `p` to the nearest of the 8 neighbour cells that is a street (`street`) or raised / solid (not `street`).
static func _near(kinds: Array[String], nx: int, nz: int, cell: float, half: Vector2, p: Vector2, cx: int, cz: int, street: bool) -> float:
	var best := cell
	for dz in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			var x: int = cx + dx
			var z: int = cz + dz
			if (dx == 0 and dz == 0) or x < 0 or z < 0 or x >= nx or z >= nz:
				continue
			var k := kinds[z * nx + x]
			if (k == "street") != street or (not street and k in OPEN):
				continue
			var lo := Vector2(x, z) * cell - half
			var d := Vector2(maxf(maxf(lo.x - p.x, p.x - lo.x - cell), 0.0), maxf(maxf(lo.y - p.y, p.y - lo.y - cell), 0.0))
			best = minf(best, d.length())
	return best
