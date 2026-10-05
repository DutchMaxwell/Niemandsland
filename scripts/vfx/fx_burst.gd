class_name FxBurst
extends MultiMeshInstance3D
## VFX v2: one burst of billboard particles, drawn and animated by ONE shader from per-instance data written once
## from a RandomNumberGenerator seeded by the cue. Not CPUParticles3D / GPUParticles3D: an emitting CPUParticles3D
## draws from the game's global RNG even with a fixed seed (measured), and engine particles differ per peer. Same
## seed, same burst on every screen; no per-frame CPU work. Performance draws none, Low half the particles.

enum Look { PUFF, SPARK, EMBER, MIST, DUST, FLASH, SHARD, FROST, WISP, MOTE, BONE, DROP, CHIP }
## look -> [start colour, end colour, additive, start size m, end size m, speed m/s, gravity m/s², life s, spread]
const LOOKS := {
	Look.PUFF: [Color(0.62, 0.6, 0.56, 0.75), Color(0.45, 0.45, 0.44, 0.0), false, 0.006, 0.03, 0.05, -0.03, 0.9, 0.8],
	Look.SPARK: [Color(3.0, 2.2, 0.9, 1.0), Color(1.2, 0.4, 0.1, 0.0), true, 0.003, 0.0015, 0.5, 1.2, 0.3, 1.0],
	Look.EMBER: [Color(3.0, 1.3, 0.3, 1.0), Color(0.8, 0.15, 0.05, 0.0), true, 0.006, 0.002, 0.18, -0.12, 0.8, 0.6],
	Look.MIST: [Color(0.55, 0.04, 0.04, 0.85), Color(0.3, 0.02, 0.02, 0.0), false, 0.004, 0.016, 0.12, 0.1, 0.6, 1.0],
	Look.DUST: [Color(0.6, 0.53, 0.42, 0.8), Color(0.5, 0.45, 0.38, 0.0), false, 0.006, 0.026, 0.09, 0.05, 0.9, 0.5],
	Look.FLASH: [Color(2.4, 2.0, 1.3, 1.0), Color(1.2, 0.7, 0.25, 0.0), true, 0.016, 0.006, 0.0, 0.0, 0.1, 0.0],
	Look.SHARD: [Color(2.2, 1.0, 2.6, 1.0), Color(0.8, 0.3, 1.0, 0.0), true, 0.005, 0.003, 0.35, 0.9, 0.7, 1.0],
	Look.FROST: [Color(1.6, 2.2, 3.0, 1.0), Color(0.7, 0.9, 1.2, 0.0), true, 0.004, 0.006, 0.08, 0.04, 1.0, 1.0],
	Look.WISP: [Color(0.25, 0.08, 0.35, 0.8), Color(0.05, 0.02, 0.08, 0.0), false, 0.008, 0.03, 0.06, -0.08, 1.1, 0.7],
	Look.MOTE: [Color(2.2, 1.2, 3.0, 1.0), Color(0.9, 0.4, 1.4, 0.0), true, 0.004, 0.002, 0.07, -0.1, 1.0, 1.0],
	Look.BONE: [Color(0.85, 0.82, 0.72, 0.85), Color(0.6, 0.58, 0.5, 0.0), false, 0.004, 0.014, 0.1, 0.4, 0.7, 1.0],
	Look.DROP: [Color(0.5, 0.02, 0.02, 0.95), Color(0.32, 0.01, 0.01, 0.0), false, 0.0026, 0.002, 0.24, 1.4, 0.55, 0.9],
	Look.CHIP: [Color(0.9, 0.87, 0.78, 1.0), Color(0.72, 0.7, 0.62, 0.0), false, 0.003, 0.003, 0.26, 1.5, 0.6, 0.9],
}
const SHADER := "shader_type spatial;
render_mode unshaded, skip_vertex_transform, cull_disabled, depth_draw_never, %s;
uniform float progress = 0.0; uniform vec4 c0 : source_color; uniform vec4 c1 : source_color;
uniform float s0; uniform float s1; uniform float life; uniform float gravity;
varying float t;
void vertex() {
	t = clamp(progress / mix(0.55, 1.0, INSTANCE_CUSTOM.w), 0.0, 1.0);
	float tt = t * life;
	vec3 p = MODEL_MATRIX[3].xyz + INSTANCE_CUSTOM.xyz * tt * (1.0 - 0.4 * t) - vec3(0.0, 0.5 * gravity * tt * tt, 0.0);
	VERTEX = (VIEW_MATRIX * vec4(p, 1.0)).xyz + vec3(VERTEX.xy * mix(s0, s1, t), 0.0);
}
void fragment() {
	vec4 c = mix(c0, c1, t);
	ALBEDO = c.rgb; ALPHA = clamp(c.a, 0.0, 1.0) * (1.0 - smoothstep(0.3, 1.0, length(UV * 2.0 - 1.0))) * step(t, 0.999);
}"
static var _shaders := {}


## Particles a burst of `count` gets at the current quality (Performance 0, Low half).
static func budget(count: int, preset: int) -> int:
	return 0 if preset <= 0 else (ceili(count * 0.5) if preset == 1 else count)


## The burst's particles as [start offset, Color(velocity xyz, life jitter)] pairs — pure: the cue's seed alone
## decides them, so every peer computes the same burst.
static func instances(look: Look, dir: Vector3, n: int, rng_seed: int, scale := 1.0, flat := false) -> Array:
	var cfg: Array = LOOKS[look]
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var d := dir.normalized() if dir.length() > 0.0001 else Vector3.ZERO
	var out: Array = []
	for i in n:
		var r := Vector3(rng.randf_range(-1, 1), 0.0 if flat else rng.randf_range(-0.2, 1), rng.randf_range(-1, 1)).normalized()
		var v := (d + r * float(cfg[8])).normalized() * float(cfg[5]) * rng.randf_range(0.5, 1.0) * scale
		out.append([r * 0.003 * scale, Color(v.x, v.y, v.z, rng.randf())])
	return out


## Spawn a burst under `parent` at `at`, thrown along `dir` (zero = all around), its colours multiplied by `tint`;
## null when the budget is 0.
static func spawn(parent: Node, look: Look, at: Vector3, dir: Vector3, count: int, rng_seed: int, preset: int,
		scale := 1.0, tint := Color.WHITE, flat := false) -> FxBurst:
	var n := budget(count, preset)
	if n <= 0 or parent == null:
		return null
	var cfg: Array = LOOKS[look]
	var add: bool = cfg[2]
	if not _shaders.has(add):
		_shaders[add] = Shader.new()
		(_shaders[add] as Shader).code = SHADER % ("blend_add" if add else "blend_mix")
	var mat := ShaderMaterial.new()
	mat.shader = _shaders[add]
	mat.set_shader_parameter("c0", (cfg[0] as Color) * tint)
	mat.set_shader_parameter("c1", (cfg[1] as Color) * tint)
	mat.set_shader_parameter("s0", float(cfg[3]) * scale)
	mat.set_shader_parameter("s1", float(cfg[4]) * scale)
	mat.set_shader_parameter("gravity", float(cfg[6]))
	mat.set_shader_parameter("life", float(cfg[7]))
	mat.set_shader_parameter("progress", 0.0)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var quad := QuadMesh.new()
	quad.size = Vector2(2, 2)   # the shader sizes it
	mm.mesh = quad
	mm.instance_count = n
	var data := instances(look, dir, n, rng_seed, scale, flat)   # flat: a ring along the ground
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
	tw.tween_property(mat, "shader_parameter/progress", 1.0, float(cfg[7]))
	tw.tween_callback(b.queue_free)
	return b
