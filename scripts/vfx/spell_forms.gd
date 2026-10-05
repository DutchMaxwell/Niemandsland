class_name SpellForms
extends RefCounted
## Small procedural spell meshes. Distances are metres, angles radians; no textures or game RNG.
## Rings and spirals have no spokes, no centre line and no crossbar: nothing here can draw a cross, star or wheel.
## The two materials, the tapered ribbon, the helix / ring, the target ripple, the fade-out, the braided stream from
## caster to target and the seeded ice prisms (scattered, never a radial star).

const INK := "shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_add;
uniform vec4 tint : source_color;
uniform float fade = 1.0;
uniform float head = 1.0;
uniform float tail = -0.1;
void fragment() {
	float edge = smoothstep(0.0, 0.18, UV.y) * smoothstep(0.0, 0.18, 1.0 - UV.y);
	float stroke = smoothstep(tail, tail + 0.08, UV.x) * (1.0 - smoothstep(head, head + 0.04, UV.x));
	ALBEDO = tint.rgb; ALPHA = edge * stroke * fade * tint.a;
}"
const SOFT := "shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;
uniform vec4 tint : source_color; uniform float fade = 1.0;
void fragment() { ALBEDO = tint.rgb; ALPHA = tint.a * fade; }"
const SEGMENTS := 64
static var _ink: Shader
static var _soft: Shader
static var _crystal: CylinderMesh


static func material(tint: Color, solid := false) -> ShaderMaterial:
	if _ink == null:
		_ink = Shader.new()
		_ink.code = INK
		_soft = Shader.new()
		_soft.code = SOFT
	var mat := ShaderMaterial.new()
	mat.shader = _soft if solid else _ink
	mat.set_shader_parameter("tint", tint)
	mat.set_shader_parameter("fade", 1.0)
	mat.set_shader_parameter("head", 1.0)
	mat.set_shader_parameter("tail", -0.1)
	return mat


## A tapered ribbon follows a curved path. Its two edges never turn into intersecting glyph strokes.
static func ribbon(host: Node3D, points: PackedVector3Array, width_m: float, tint: Color) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(points.size() - 1):
		var side := (points[i + 1] - points[i]).normalized().cross(Vector3.UP).normalized()
		if side.length_squared() < 0.1:
			side = Vector3.RIGHT
		var a := float(i) / (points.size() - 1)
		var b := float(i + 1) / (points.size() - 1)
		for pair: Vector2 in [Vector2(a, 0), Vector2(a, 1), Vector2(b, 1), Vector2(a, 0), Vector2(b, 1), Vector2(b, 0)]:
			var point: Vector3 = points[i] if pair.x == a else points[i + 1]
			st.set_uv(pair)
			st.add_vertex(point + side * (pair.y - 0.5) * width_m)
	var mesh := MeshInstance3D.new()
	mesh.mesh = st.commit()
	mesh.material_override = material(tint)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	host.add_child(mesh)
	return mesh


## An open helix or a closed horizontal ring. No centre line, crossbar, spokes or star vertices.
static func curl(host: Node3D, radius_m: float, rise_m: float, turns: float, width_m: float,
		tint: Color, phase := 0.0) -> MeshInstance3D:
	var points := PackedVector3Array()
	for i in SEGMENTS + 1:
		var t := float(i) / SEGMENTS
		var angle := t * TAU * turns + phase
		points.append(Vector3(cos(angle) * radius_m, rise_m * t, sin(angle) * radius_m))
	return ribbon(host, points, width_m, tint)


static func retire(node: Node3D, hold_s: float, fade_s := 0.35) -> void:
	var tw := node.create_tween()
	tw.tween_interval(hold_s)
	tw.tween_method(func(f: float) -> void: opacity(node, f), 1.0, 0.0, fade_s)
	tw.tween_callback(node.queue_free)


static func opacity(node: Node, value: float) -> void:
	if node is GeometryInstance3D:
		var mat := (node as GeometryInstance3D).material_override as ShaderMaterial
		if mat != null:
			mat.set_shader_parameter("fade", value)
	for child in node.get_children():
		opacity(child, value)


## Target ripples occupy only a small annular mesh, never the whole rule-range disc.
static func ripple(host: Node3D, at: Vector3, tint: Color, radius_m := 0.075, inward := false,
		still := false) -> Node3D:
	var ring := curl(host, radius_m, 0.0, 1.0, 0.003, tint)
	ring.name = "InwardRipple" if inward else "OutwardRipple"
	ring.global_position = at
	if not still:
		ring.scale = Vector3.ONE * (1.2 if inward else 0.15)
		var tw := ring.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(ring, "scale", Vector3.ONE * (0.05 if inward else 1.0), 0.55)
	retire(ring, 0.25, 0.4)
	return ring


## A swept, seeded braid from caster to target; each strand is curved, with a moving head and trailing tail.
static func stream(host: Node3D, from: Vector3, to: Vector3, tint: Color, s: int, strands := 2) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = s
	var direction := (to - from).normalized()
	var side := direction.cross(Vector3.UP).normalized()
	for strand in strands:
		var points := PackedVector3Array()
		var phase := rng.randf_range(0.0, TAU)
		for i in SEGMENTS + 1:
			var t := float(i) / SEGMENTS
			var angle := t * TAU * 1.5 + phase
			points.append(from.lerp(to, t) + (Vector3.UP * (0.035 + sin(angle) * 0.018)
				+ side * cos(angle) * 0.018) * sin(PI * t))
		var trail := ribbon(host, points, 0.003 if strand == 0 else 0.0015, tint)
		var mat := trail.material_override as ShaderMaterial
		mat.set_shader_parameter("head", 0.0)
		var tw := trail.create_tween()
		tw.tween_property(mat, "shader_parameter/head", 1.05, 0.42)
		tw.parallel().tween_property(mat, "shader_parameter/tail", 0.95, 0.7).set_delay(0.08)
		tw.tween_callback(trail.queue_free)


## Seeded irregular crystal placement, not an evenly spaced radial mark. Shared by render and tests.
static func crystal_plan(s: int, count: int) -> Array[Transform3D]:
	var rng := RandomNumberGenerator.new()
	rng.seed = s
	var result: Array[Transform3D] = []
	for i in count:
		var angle := rng.randf_range(0.0, TAU)
		var radius := rng.randf_range(0.014, 0.065)
		var height := rng.randf_range(0.022, 0.065)
		var basis := Basis.from_euler(Vector3(rng.randf_range(-0.25, 0.25), angle, rng.randf_range(-0.3, 0.3)))
		result.append(Transform3D(basis.scaled_local(Vector3(0.007, height, 0.009)),
			Vector3(cos(angle) * radius, height * 0.4, sin(angle) * radius)))
	return result


static func crystals(host: Node3D, at: Vector3, s: int, count: int, still := false) -> void:
	if _crystal == null:
		_crystal = CylinderMesh.new()
		_crystal.top_radius = 0.0
		_crystal.bottom_radius = 0.65
		_crystal.height = 1.0
		_crystal.radial_segments = 5
		_crystal.rings = 1
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _crystal
	mm.instance_count = count
	var plan := crystal_plan(s, count)
	for i in count:
		mm.set_instance_transform(i, plan[i])
	var ice := MultiMeshInstance3D.new()
	ice.name = "IcePrisms"
	ice.multimesh = mm
	ice.material_override = material(Color(0.48, 0.85, 1.25, 0.9), true)
	ice.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	host.add_child(ice)
	ice.global_position = at
	if not still:
		ice.scale.y = 0.02
		ice.create_tween().tween_property(ice, "scale:y", 1.0, 0.32).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	retire(ice, 0.6, 0.45)
