class_name FxBurst
extends MultiMeshInstance3D
## VFX v3: one burst of billboard particles driven by ONE shader + a startup 256×256 RGBA channel atlas
## (R = soft puff, G = FBM eroded smoke, B = velocity-stretched spark/slash taper, A = angular clod silhouette)
## from per-instance data written once from a RandomNumberGenerator seeded by the cue. Never touches global RNG;
## same seed, same burst on every peer; zero per-frame CPU work. Supports vertex-shader y = 0 turf bounce
## (CHIP / BONE / SPARK / DROP), 2.2 s wind-drifting cordite smoke (PUFF, alpha <= 0.35), sand-contrast rim, and
## a WCAG 2.3.3 reduced-motion static keyframe path (no strobe, no flight motion).

enum Look { PUFF, SPARK, EMBER, MIST, DUST, FLASH, SHARD, FROST, WISP, MOTE, BONE, DROP, CHIP, FIREBALL, COLUMN, FLAME }
enum Channel { PUFF_R = 0, SMOKE_G = 1, SPARK_B = 2, CLOD_A = 3 }

const ATLAS_SIZE := 256
const REDUCED_LIFE_S := 0.35
const SHADER_MIX: Shader = preload("res://shaders/fx_burst_v3.gdshader")
const SHADER_ADD: Shader = preload("res://shaders/fx_burst_v3_add.gdshader")

## look -> [start colour, end colour, additive, start size m, end size m, speed m/s, gravity m/s², life s, spread]
## Smoke/dust/mist/wisp start alpha clamped <= 0.45 (cordite gunsmoke <= 0.35) so bursts never hide hit models.
const LOOKS := {
	Look.PUFF: [Color(0.76, 0.73, 0.68, 0.35), Color(0.47, 0.48, 0.49, 0.0), false, 0.006, 0.032, 0.04, -0.015, 2.2, 0.85],
	Look.SPARK: [Color(3.0, 2.2, 0.9, 1.0), Color(1.2, 0.4, 0.1, 0.0), true, 0.003, 0.0014, 0.52, 1.4, 0.38, 1.0],
	Look.EMBER: [Color(3.0, 1.3, 0.3, 1.0), Color(0.8, 0.15, 0.05, 0.0), true, 0.0055, 0.0018, 0.18, -0.10, 0.8, 0.6],
	Look.MIST: [Color(0.62, 0.08, 0.08, 0.42), Color(0.32, 0.04, 0.04, 0.0), false, 0.004, 0.016, 0.12, 0.1, 0.6, 1.0],
	Look.DUST: [Color(0.62, 0.55, 0.44, 0.42), Color(0.48, 0.43, 0.36, 0.0), false, 0.006, 0.026, 0.09, 0.05, 0.9, 0.5],
	Look.FLASH: [Color(2.4, 1.75, 0.78, 1.0), Color(1.4, 0.62, 0.14, 0.0), true, 0.016, 0.006, 0.0, 0.0, 0.095, 0.0],
	Look.SHARD: [Color(2.2, 1.0, 2.6, 1.0), Color(0.8, 0.3, 1.0, 0.0), true, 0.005, 0.003, 0.35, 0.9, 0.7, 1.0],
	Look.FROST: [Color(1.6, 2.2, 3.0, 1.0), Color(0.7, 0.9, 1.2, 0.0), true, 0.004, 0.006, 0.08, 0.04, 1.0, 1.0],
	Look.WISP: [Color(0.28, 0.10, 0.38, 0.42), Color(0.05, 0.02, 0.08, 0.0), false, 0.008, 0.03, 0.06, -0.08, 1.1, 0.7],
	Look.MOTE: [Color(2.2, 1.2, 3.0, 1.0), Color(0.9, 0.4, 1.4, 0.0), true, 0.004, 0.002, 0.07, -0.1, 1.0, 1.0],
	Look.BONE: [Color(0.86, 0.82, 0.72, 0.90), Color(0.62, 0.58, 0.50, 0.0), false, 0.004, 0.009, 0.14, 1.2, 0.75, 1.0],
	Look.DROP: [Color(0.54, 0.03, 0.03, 0.92), Color(0.32, 0.02, 0.02, 0.0), false, 0.0026, 0.002, 0.24, 1.4, 0.55, 0.9],
	Look.CHIP: [Color(0.88, 0.84, 0.74, 0.95), Color(0.68, 0.64, 0.56, 0.0), false, 0.0034, 0.003, 0.28, 1.5, 0.75, 0.9],
	# a blast's second beat: white-hot soft puffs that swell and cool to red (additive, eroded edge), 0.30 s
	Look.FIREBALL: [Color(4.0, 2.0, 0.6, 1.0), Color(1.2, 0.25, 0.04, 0.0), true, 0.007, 0.026, 0.16, -0.10, 0.30, 0.6],
	# its third beat: a dark smoke column that rises and lingers (alpha <= 0.40, so it never hides the struck models)
	Look.COLUMN: [Color(0.30, 0.28, 0.25, 0.40), Color(0.52, 0.50, 0.48, 0.0), false, 0.007, 0.030, 0.10, -0.05, 1.6, 0.30],
	# a flamer's gout: soft eroded tongues, white-yellow core -> orange -> red -> gone; speed 1.0 = scaled per shot by `speed_k`
	Look.FLAME: [Color(3.4, 2.2, 0.7, 0.9), Color(0.9, 0.16, 0.03, 0.0), true, 0.005, 0.018, 1.0, -0.06, 0.40, 0.16],
}

## look -> [channel_mode, stretch (neg = star-flash), bounce (y=0 damping), wind Vector3, contrast_rim, alpha_cap]
const LOOK_V3 := {
	Look.PUFF: [Channel.SMOKE_G, 0.0, 0.0, FireProp.SMOKE_WIND_DRIFT, 0.45, 0.35],
	Look.SPARK: [Channel.SPARK_B, 4.2, 0.45, Vector3.ZERO, 0.0, 1.0],
	Look.EMBER: [Channel.SPARK_B, 2.4, 0.25, FireProp.SMOKE_WIND_DRIFT * 0.6, 0.0, 1.0],
	Look.MIST: [Channel.SMOKE_G, 0.0, 0.0, Vector3.ZERO, 0.35, 0.45],
	Look.DUST: [Channel.SMOKE_G, 0.0, 0.0, FireProp.SMOKE_WIND_DRIFT * 0.5, 0.55, 0.45],
	Look.FLASH: [Channel.PUFF_R, -1.0, 0.0, Vector3.ZERO, 0.0, 1.0],
	Look.SHARD: [Channel.CLOD_A, 0.0, 0.38, Vector3.ZERO, 0.0, 1.0],
	Look.FROST: [Channel.PUFF_R, 0.0, 0.0, Vector3.ZERO, 0.0, 1.0],
	Look.WISP: [Channel.SMOKE_G, 0.0, 0.0, FireProp.SMOKE_WIND_DRIFT * 0.5, 0.25, 0.45],
	Look.MOTE: [Channel.PUFF_R, 0.0, 0.0, Vector3.ZERO, 0.0, 1.0],
	Look.BONE: [Channel.CLOD_A, 0.0, 0.40, Vector3.ZERO, 0.60, 0.95],
	Look.DROP: [Channel.CLOD_A, 0.0, 0.28, Vector3.ZERO, 0.40, 0.95],
	Look.CHIP: [Channel.CLOD_A, 0.0, 0.45, Vector3.ZERO, 0.65, 0.96],
	Look.FIREBALL: [Channel.SMOKE_G, 0.0, 0.0, Vector3.ZERO, 0.0, 1.0],
	Look.COLUMN: [Channel.SMOKE_G, 0.0, 0.0, FireProp.SMOKE_WIND_DRIFT, 0.0, 0.40],
	Look.FLAME: [Channel.SMOKE_G, 1.2, 0.0, Vector3.ZERO, 0.0, 1.0],
}

static var _atlas: ImageTexture
static var _unit_quad: QuadMesh


## Startup procedural 256×256 RGBA channel atlas (built once deterministically; never touches global RNG).
## R = soft puff, G = FBM eroded smoke, B = spark/slash taper, A = angular clod silhouette.
static func channel_atlas() -> ImageTexture:
	if _atlas != null:
		return _atlas
	var sz := ATLAS_SIZE
	var noise := FastNoiseLite.new()
	noise.seed = 1337
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.028
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 4
	noise.fractal_lacunarity = 2.0
	noise.fractal_gain = 0.52
	var noise_img := noise.get_seamless_image(sz, sz)
	var noise_data := noise_img.get_data()
	var bytes := PackedByteArray()
	bytes.resize(sz * sz * 4)
	var inv_half := 2.0 / float(sz)
	var idx := 0
	var n_idx := 0
	for y in sz:
		var ny := (float(y) + 0.5) * inv_half - 1.0
		var ny2 := ny * ny
		var spark_y := clampf(1.0 - absf(ny), 0.0, 1.0) * (0.35 + 0.65 * clampf((ny + 1.0) * 0.5, 0.0, 1.0))
		for x in sz:
			var nx := (float(x) + 0.5) * inv_half - 1.0
			var r := sqrt(nx * nx + ny2)
			var fbm := float(noise_data[n_idx]) * (1.0 / 255.0)
			n_idx += 1
			# R: soft radial puff
			var r_ch := clampf(1.0 - r, 0.0, 1.0)
			r_ch = r_ch * r_ch * (3.0 - 2.0 * r_ch)
			# G: FBM eroded smoke cloud
			var g_rad := clampf(1.0 - r * 1.05, 0.0, 1.0)
			var g_ch := clampf(g_rad * (0.38 + 0.85 * fbm), 0.0, 1.0)
			# B: spark / slash streak taper (aligned to +Y velocity axis)
			var b_core := exp(-nx * nx * 18.0) * spark_y
			var b_ch := clampf(b_core, 0.0, 1.0)
			# A: angular rocky clod / bone silhouette
			var ang := atan2(ny, nx)
			var clod_r := 0.56 + 0.14 * sin(3.0 * ang + 0.7) + 0.09 * cos(5.0 * ang - 0.4) + 0.10 * (fbm - 0.5)
			var a_ch := clampf((clod_r - r) * 8.0 + 0.5, 0.0, 1.0)
			bytes[idx] = int(r_ch * 255.0)
			bytes[idx + 1] = int(g_ch * 255.0)
			bytes[idx + 2] = int(b_ch * 255.0)
			bytes[idx + 3] = int(a_ch * 255.0)
			idx += 4
	var img := Image.create_from_data(sz, sz, false, Image.FORMAT_RGBA8, bytes)
	img.generate_mipmaps()
	_atlas = ImageTexture.create_from_image(img)
	return _atlas


## Particles a burst of `count` gets at the current quality (Performance 0, Low half).
static func budget(count: int, preset: int) -> int:
	return 0 if preset <= 0 else (ceili(count * 0.5) if preset == 1 else count)


## The burst's particles as [start offset, Color(velocity xyz, life jitter)] pairs — pure: the cue's seed alone
## decides them, so every peer computes the same burst. `speed_k` scales the speed alone (not the size); `streamed`
## puts particle i's birth step i in the integer part of the jitter (the shader then releases them one after another).
static func instances(look: Look, dir: Vector3, n: int, rng_seed: int, scale := 1.0, flat := false, speed_k := 1.0,
		streamed := false) -> Array:
	var cfg: Array = LOOKS[look]
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var d := dir.normalized() if dir.length() > 0.0001 else Vector3.ZERO
	var out: Array = []
	for i in n:
		var r := Vector3(rng.randf_range(-1, 1), 0.0 if flat else rng.randf_range(-0.2, 1), rng.randf_range(-1, 1)).normalized()
		var v := (d + r * float(cfg[8])).normalized() * float(cfg[5]) * rng.randf_range(0.5, 1.0) * scale * speed_k
		out.append([r * 0.003 * scale, Color(v.x, v.y, v.z, rng.randf() + (float(i) if streamed else 0.0))])
	return out


## Spawn a burst under `parent` at `at`, thrown along `dir` (zero = all around), its colours multiplied by `tint`;
## null when the budget is 0 (or FLASH under Reduce Motion). `life_k` stretches or shortens the look's life, `speed_k` its
## speed; `stream_s` > 0 releases the particles one after another over that many seconds (a continuous stream, 1 draw call).
static func spawn(parent: Node, look: Look, at: Vector3, dir: Vector3, count: int, rng_seed: int, preset: int,
		scale := 1.0, tint := Color.WHITE, flat := false, ground_y := 0.0, life_k := 1.0, speed_k := 1.0,
		stream_s := 0.0) -> FxBurst:
	var n := budget(count, preset)
	if n <= 0 or parent == null:
		return null
	var reduced := UiMotion.reduced()
	if reduced and look == Look.FLASH:
		return null
	var cfg: Array = LOOKS[look]
	var v3: Array = LOOK_V3[look]
	var add: bool = cfg[2]
	var mat := ShaderMaterial.new()
	mat.shader = SHADER_ADD if add else SHADER_MIX
	mat.set_shader_parameter("atlas_tex", channel_atlas())
	mat.set_shader_parameter("c0", (cfg[0] as Color) * tint)
	mat.set_shader_parameter("c1", (cfg[1] as Color) * tint)
	mat.set_shader_parameter("s0", float(cfg[3]) * scale)
	mat.set_shader_parameter("s1", float(cfg[4]) * scale)
	mat.set_shader_parameter("gravity", float(cfg[6]))
	var life_s: float = REDUCED_LIFE_S if reduced else float(cfg[7]) * life_k
	mat.set_shader_parameter("life", life_s)
	var streamed := stream_s > 0.0 and not reduced
	mat.set_shader_parameter("emit_gap", stream_s / float(n) if streamed else 0.0)
	mat.set_shader_parameter("span", (life_s + stream_s) / life_s if streamed else 1.0)
	mat.set_shader_parameter("progress", 0.0)
	mat.set_shader_parameter("channel_mode", int(v3[0]))
	mat.set_shader_parameter("stretch", float(v3[1]))
	mat.set_shader_parameter("bounce", float(v3[2]))
	mat.set_shader_parameter("ground_y", ground_y)
	mat.set_shader_parameter("wind", v3[3] as Vector3)
	mat.set_shader_parameter("contrast_rim", float(v3[4]))
	mat.set_shader_parameter("alpha_cap", float(v3[5]))
	mat.set_shader_parameter("static_mode", 1.0 if reduced else 0.0)
	if _unit_quad == null:
		_unit_quad = QuadMesh.new()
		_unit_quad.size = Vector2(2, 2)   # the shader sizes it
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _unit_quad
	mm.instance_count = n
	var data := instances(look, dir, n, rng_seed, scale, flat, speed_k, streamed)   # flat: a ring along the ground
	for i in n:
		mm.set_instance_transform(i, Transform3D(Basis(), data[i][0]))
		mm.set_instance_custom_data(i, data[i][1])
	var b := FxBurst.new()
	b.multimesh = mm
	b.material_override = mat
	b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	b.extra_cull_margin = 1.0
	parent.add_child(b)
	b.global_position = at
	var tw := b.create_tween()
	tw.tween_property(mat, "shader_parameter/progress", 1.0, life_s + (stream_s if streamed else 0.0))
	tw.tween_callback(b.queue_free)
	return b
