class_name BoardgenTownGrass
extends RefCounted
## The blade clumps of the ruin town (LOOK4 G3): where the green map (BoardgenTownGreen.map) says the cover grows, a jittered grid of points, each a clump of
## CLUMP_BLADES blades (shaders/ruintown_grass.gdshader). Soft vegetation: at most MAX_IN high, no collider, no shadow. The point set is half-turn symmetric
## (made on the -z half, then turned), so neither side of the table sees more grass. Not attached to any board yet.

const SHADER := preload("res://shaders/ruintown_grass.gdshader")
const CLUMP_BLADES := 5
const ROOT_W_IN := 0.035
const CLUMP_R_IN := 0.07
const MIN_IN := 0.16
const GROW_IN := 0.22
const MAX_IN := 0.38
const JITTER := 0.45
const DRY_SHARE := 0.15

static var _mesh: ArrayMesh


## The clump mesh, built once: 5 blades fanned round the centre, each 2 quads and a tip (5 triangles), bent 15-35 degrees outward.
static func mesh() -> ArrayMesh:
	if _mesh != null:
		return _mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows := [[0.0, 1.0], [0.4, 0.8], [0.75, 0.5]]   # (t, width factor); the tip at t = 1
	for b in CLUMP_BLADES:
		var ang := TAU * (float(b) + 0.3 * sin(b * 2.3)) / CLUMP_BLADES
		var out := Vector3(cos(ang), 0.0, sin(ang))
		var across := Vector3(-out.z, 0.0, out.x)
		var bend := deg_to_rad(15.0 + 20.0 * fmod(b * 0.618, 1.0))
		var root := out * CLUMP_R_IN * (0.3 + 0.7 * fmod(b * 0.382 + 0.2, 1.0))
		var spine := func(t: float) -> Vector3: return root + out * sin(bend) * t * t * 0.25 + Vector3(0.0, t, 0.0)   # 0.25 in lean at a 1-unit tip
		var normal := (out * -sin(bend) + Vector3.UP * cos(bend) * 0.3 + out * 0.2).normalized()
		var tip_v: Vector3 = spine.call(1.0)
		var verts: Array[Array] = []   # per row: [left, right, half width]
		for r: Array in rows:
			var hw: float = ROOT_W_IN * 0.5 * float(r[1])
			var c: Vector3 = spine.call(float(r[0]))
			verts.append([c - across * hw, c + across * hw, hw, float(r[0])])
		var add := func(p: Vector3, u: float, t: float, hw: float) -> void:
			st.set_normal(normal)
			st.set_tangent(Plane(across, 1.0))
			st.set_uv(Vector2(u, t))
			st.set_uv2(Vector2(hw, 0.0))
			st.add_vertex(p)
		for r in 2:
			var a: Array = verts[r]
			var n: Array = verts[r + 1]
			for tri in [[[a[0], 0.0, a[3], -a[2]], [a[1], 1.0, a[3], a[2]], [n[1], 1.0, n[3], n[2]]], [[a[0], 0.0, a[3], -a[2]], [n[1], 1.0, n[3], n[2]], [n[0], 0.0, n[3], -n[2]]]]:
				for v: Array in tri:
					add.call(v[0], v[1], v[2], v[3])
		var top: Array = verts[2]
		add.call(top[0], 0.0, top[3], -top[2])
		add.call(top[1], 1.0, top[3], top[2])
		add.call(tip_v, 0.5, 1.0, 0.0)
	_mesh = st.commit()
	return _mesh


## The clump points: [{at (board inches), h (inches), yaw, hash, dry}], half-turn symmetric.
static func plan(layout: Dictionary, green: Image, per_sq_in: float) -> Array[Dictionary]:
	var cell := float(layout["cell_in"])
	var nx: int = layout["nx"]
	var half := Vector2(nx, layout["nz"]) * cell * 0.5
	var tpi := float(green.get_width()) / (half.x * 2.0)
	var clear := BoardgenDressRules.kept_clear(layout)
	var ladders := BoardgenDressRules._ladder_zones(layout)
	var step := 1.0 / sqrt(per_sq_in)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(layout.get("seed", 0)), "grass"])
	var out: Array[Dictionary] = []
	var gx := int(ceil(half.x * 2.0 / step))
	var gz := int(ceil(half.y / step))
	for iz in gz:
		for ix in gx:
			var j := Vector2(rng.randf() - 0.5, rng.randf() - 0.5) * 2.0 * JITTER * step
			var h_rng := Vector3(rng.randf(), rng.randf(), rng.randf())   # keep, height, dry
			var yaw := rng.randf() * TAU
			var p := Vector2(-half.x + (ix + 0.5) * step, -half.y + (iz + 0.5) * step) + j
			if p.y >= 0.0 or absf(p.x) >= half.x or p.y <= -half.y:
				continue
			var cx := int(floor((p.x + half.x) / cell))
			var cz := int(floor((p.y + half.y) / cell))
			var i := cz * nx + cx
			var cover := green.get_pixel(clampi(int((p.x + half.x) * tpi), 0, green.get_width() - 1), clampi(int((p.y + half.y) * tpi), 0, green.get_height() - 1)).r
			if cover <= 0.0 or h_rng.x >= cover or clear.has(i) or ladders.any(func(r: Rect2) -> bool: return r.has_point(p) or r.has_point(-p)):
				continue
			if BoardgenGreybox._cell_kind(layout["cells"][i], true) not in ["ground", "rough"]:
				continue
			var h := minf(MIN_IN + GROW_IN * cover * (0.7 + 0.3 * h_rng.y), MAX_IN)
			var dry := 1.0 if h_rng.z < DRY_SHARE else 0.0
			out.append({"at": p, "h": h, "yaw": yaw, "hash": h_rng.x, "dry": dry})
			out.append({"at": -p, "h": h, "yaw": yaw + PI, "hash": h_rng.x, "dry": dry})
	return out


## The instance transforms (board-local metres) of plan(): the mesh's inches scaled to metres, its unit height to the clump's height.
static func points(layout: Dictionary, green: Image, per_sq_in: float) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	for c: Dictionary in plan(layout, green, per_sq_in):
		out.append(_xf(c))
	return out


## Four MultiMeshInstance3D, one per board quadrant (a MultiMesh culls all or none), no shadow, no collider.
static func build(layout: Dictionary, green: Image, per_sq_in: float) -> Node3D:
	var root := Node3D.new()
	root.name = "Grass"
	var quads: Array[Array] = [[], [], [], []]
	for c: Dictionary in plan(layout, green, per_sq_in):
		var at: Vector2 = c["at"]
		quads[int(at.x >= 0.0) + 2 * int(at.y >= 0.0)].append(c)
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	for q in 4:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = mesh()
		mm.instance_count = quads[q].size()
		for n in quads[q].size():
			var c: Dictionary = quads[q][n]
			mm.set_instance_transform(n, _xf(c))
			mm.set_instance_custom_data(n, Color(c["hash"], c["h"] / MAX_IN, c["dry"], 0.0))
		var mi := MultiMeshInstance3D.new()
		mi.name = "Grass%d" % q
		mi.multimesh = mm
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	return root


static func _xf(c: Dictionary) -> Transform3D:
	var s := Units.INCHES_TO_METERS
	var at: Vector2 = c["at"]
	return Transform3D(Basis(Vector3.UP, c["yaw"]).scaled(Vector3(s, s * float(c["h"]), s)), Vector3(at.x, 0.0, at.y) * s)
