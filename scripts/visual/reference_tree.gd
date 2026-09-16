extends RefCounted
## Original procedural tree study. Geometry is visual only; no collision or rules data.

static func build(variant: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 8160 + variant * 131
	var wood := SurfaceTool.new()
	var leaves := SurfaceTool.new()
	wood.begin(Mesh.PRIMITIVE_TRIANGLES)
	leaves.begin(Mesh.PRIMITIVE_TRIANGLES)
	var trunk := [Vector3.ZERO, Vector3(0.015,0.25,0.008), Vector3(-0.015,0.50,0.01), Vector3(0.025,0.76,-0.015), Vector3(0.01,0.96,0.01)]
	for i in 4:
		_branch(wood,trunk[i],trunk[i+1],0.036 * pow(0.60,i),0.036 * pow(0.60,i+1),9)
	for i in 7:
		var angle := i * 2.39996 + rng.randf_range(-0.2,0.2)
		var dir := Vector3(cos(angle),0,sin(angle))
		var base := Vector3(0,0.26 + i * 0.077,0)
		var reach := 0.31 * (1.0 - i * 0.055) * rng.randf_range(0.80,1.15)
		var elbow := base + dir * reach * 0.55 + Vector3.UP * 0.11
		var end := base + dir * reach + Vector3.UP * rng.randf_range(0.19,0.29)
		_branch(wood,base,elbow,0.018 - i * 0.0014,0.010 - i * 0.0007,7)
		_branch(wood,elbow,end,0.010 - i * 0.0007,0.002,6)
		for j in 5:
			var t := 0.25 + j * 0.17
			var start: Vector3 = elbow.lerp(end,t)
			var side := dir.rotated(Vector3.UP,(-1.0 if j % 2 == 0 else 1.0) * 0.8)
			var tip := start + side * rng.randf_range(0.055,0.13) + Vector3.UP * rng.randf_range(0.04,0.09)
			_branch(wood,start,tip,0.004,0.0008,5)
			for k in 76:
				var offset := Vector3(rng.randfn(0,0.045),rng.randfn(0,0.030),rng.randfn(0,0.045))
				_leaf(leaves,tip + offset,rng)
	for i in 7:
		var a := i * TAU / 7.0
		_branch(wood,Vector3(cos(a)*0.09,0.003,sin(a)*0.09),Vector3(0,0.065,0),0.004,0.018,6)
	for i in 110:
		_leaf(leaves,Vector3(0.01,0.95,0.01)+Vector3(rng.randfn(0,0.05),rng.randfn(0,0.035),rng.randfn(0,0.05)),rng)
	var bark := ShaderMaterial.new()
	bark.shader = preload("res://shaders/visual/reference_bark.gdshader")
	wood.set_material(bark)
	var mesh := wood.commit()
	var foliage := ShaderMaterial.new()
	foliage.shader = preload("res://shaders/visual/reference_foliage.gdshader")
	leaves.set_material(foliage)
	leaves.commit(mesh)
	return mesh


static func _branch(st: SurfaceTool, a: Vector3, b: Vector3, ra: float, rb: float, sides: int) -> void:
	var axis := (b-a).normalized()
	var x := axis.cross(Vector3.FORWARD).normalized()
	if x.length_squared() < 0.1:
		x = axis.cross(Vector3.RIGHT).normalized()
	var z := axis.cross(x).normalized()
	for i in sides:
		var n0 := x*cos(TAU*i/sides)+z*sin(TAU*i/sides)
		var n1 := x*cos(TAU*(i+1)/sides)+z*sin(TAU*(i+1)/sides)
		var points := [a+n0*ra,b+n0*rb,b+n1*rb,a+n0*ra,b+n1*rb,a+n1*ra]
		var norms := [n0,n0,n1,n0,n1,n1]
		var uvs := [Vector2(float(i)/sides,0),Vector2(float(i)/sides,1),Vector2(float(i+1)/sides,1),Vector2(float(i)/sides,0),Vector2(float(i+1)/sides,1),Vector2(float(i+1)/sides,0)]
		for j in 6:
			st.set_normal(norms[j]); st.set_uv(uvs[j]); st.add_vertex(points[j])


static func _leaf(st: SurfaceTool, p: Vector3, rng: RandomNumberGenerator) -> void:
	var rotation := Basis.from_euler(Vector3(rng.randf_range(-1.1,1.1),rng.randf()*TAU,rng.randf_range(-1.0,1.0)))
	var size := rng.randf_range(0.008,0.017)
	var points := [Vector3(0,0,-size),Vector3(-size*0.45,0,0),Vector3(0,size*0.13,size),Vector3(size*0.45,0,0)]
	var uvs := [Vector2(0.5,0),Vector2(0,0.5),Vector2(0.5,1),Vector2(1,0.5)]
	var normal := rotation * Vector3.UP
	var color := Color(0.22,0.30,0.08).lerp(Color(0.40,0.46,0.17),rng.randf())
	for i in [0,1,2,0,2,3]:
		st.set_color(color.srgb_to_linear()); st.set_normal(normal); st.set_uv(uvs[i]); st.add_vertex(p + rotation * points[i])
