class_name FxBolt
extends RefCounted
## Combat effects: one jagged lightning bolt from `a` to `b` under `holder` — seven thin segments of one shared unit
## mesh, bent sideways and upwards by the seed `s` (the same bolt on every screen; never the game's RNG). `radius` and
## `sway` are metres; `mat` overrides the default HDR white (an aura draws in its own tint). The hero auras use it.

static var _bolt: CylinderMesh


static func jag(holder: Node3D, a: Vector3, b: Vector3, s: int, radius := 0.0022, sway := 0.012, mat: Material = null) -> void:
	if _bolt == null:
		_bolt = CylinderMesh.new()
		_bolt.top_radius = 1.0
		_bolt.bottom_radius = 1.0
		_bolt.height = 1.0
		_bolt.radial_segments = 4
		_bolt.rings = 1
		var white := StandardMaterial3D.new()
		white.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		white.albedo_color = Color(2.4, 3.4, 5.0)
		_bolt.material = white
	var rng := RandomNumberGenerator.new()
	rng.seed = s
	var side := (b - a).cross(Vector3.UP).normalized()
	var prev := a
	for k in range(1, 8):
		var t := k / 7.0
		var at := a.lerp(b, t) + (side * rng.randf_range(-1, 1) + Vector3.UP * rng.randf_range(-0.5, 1)) \
			* sway * sin(PI * t) if k < 7 else b
		var seg := MeshInstance3D.new()
		seg.mesh = _bolt
		seg.material_override = mat
		seg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(seg)
		var dir := (at - prev).normalized()
		seg.global_transform = Transform3D(Basis(Quaternion(Vector3.UP, dir)).scaled_local(
			Vector3(radius, maxf(prev.distance_to(at), 0.001), radius)), (prev + at) * 0.5)
		prev = at
