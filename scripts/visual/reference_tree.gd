extends RefCounted
## Original oak geometry. Textured, folded leaves sit on branching twig clusters.
## These meshes never supply collision, footprints or line-of-sight geometry.

static func build(variant: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 170916 + variant * 137
	var wood := SurfaceTool.new()
	var leaves := SurfaceTool.new()
	wood.begin(Mesh.PRIMITIVE_TRIANGLES)
	leaves.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lean := Vector3(rng.randf_range(-0.08,0.08),0,rng.randf_range(-0.06,0.06))
	var trunk := [Vector3.ZERO, Vector3(0.012,0.16,0.004), Vector3(-0.018,0.36,0.014)+lean*0.4, Vector3(0.008,0.59,-0.008)+lean, Vector3(0.0,0.82,0.01)+lean]
	for i in 4:
		_branch(wood,trunk[i],trunk[i+1],0.031*pow(0.61,i),0.031*pow(0.61,i+1),10)
	for i in 10:
		var a := i*2.39996+rng.randf_range(-0.45,0.45)
		var dir := Vector3(cos(a),0,sin(a))
		var height := rng.randf_range(0.17,0.68)
		var start := Vector3(0,height,0)+lean*(height/0.65)
		var reach := rng.randf_range(0.28,0.45)*(1.0-i*0.025)
		var elbow := start+dir*reach*0.45+Vector3.UP*rng.randf_range(0.05,0.10)
		var end := start+dir*reach+Vector3.UP*rng.randf_range(0.15,0.27)
		_branch(wood,start,elbow,0.019-i*0.0013,0.010-i*0.0005,8)
		_branch(wood,elbow,end,0.010-i*0.0005,0.003,7)
		for j in 5:
			var t := 0.20+j*0.18
			var joint := elbow.lerp(end,t)
			var twig_dir := dir.rotated(Vector3.UP,(-1.0 if j%2==0 else 1.0)*rng.randf_range(0.5,1.4))
			var tip := joint+twig_dir*rng.randf_range(0.055,0.145)+Vector3.UP*rng.randf_range(0.035,0.12)
			_branch(wood,joint,tip,0.0038,0.0006,5)
			var cluster_scale := rng.randf_range(0.8,1.35)
			for k in 125:
				var offset := Vector3(rng.randfn(0,0.037),rng.randfn(0,0.028),rng.randfn(0,0.038))*cluster_scale
				_leaf(leaves,tip+offset,rng)
			for k in 2:
				var tip2 := tip+twig_dir.rotated(Vector3.UP,(-0.7 if k==0 else 0.7))*0.045+Vector3.UP*0.025
				_branch(wood,tip,tip2,0.0011,0.00025,4)
	for i in 180:
		_leaf(leaves,Vector3(0,0.85,0)+lean+Vector3(rng.randfn(0,0.055),rng.randfn(0,0.045),rng.randfn(0,0.055)),rng)
	for i in 6:
		var a := i*TAU/6.0+rng.randf_range(-0.25,0.25)
		_branch(wood,Vector3(cos(a)*0.075,0.001,sin(a)*0.075),Vector3(0,0.065,0),0.003,0.018,7)
	var bark := ShaderMaterial.new()
	bark.shader = preload("res://shaders/visual/reference_bark.gdshader")
	bark.set_shader_parameter("bark_tex",preload("res://scripts/visual/reference_materials.gd").texture("res://assets/terrain/reference/hero/bark.webp"))
	wood.set_material(bark)
	var mesh := wood.commit()
	var foliage := ShaderMaterial.new()
	foliage.shader = preload("res://shaders/visual/reference_foliage.gdshader")
	foliage.set_shader_parameter("leaf_tex",preload("res://scripts/visual/reference_materials.gd").texture("res://assets/terrain/reference/hero/leaf.webp"))
	foliage.set_shader_parameter("textured_leaf",true)
	leaves.set_material(foliage)
	leaves.commit(mesh)
	return mesh


static func _branch(st: SurfaceTool,a: Vector3,b: Vector3,ra: float,rb: float,sides: int) -> void:
	var axis := (b-a).normalized()
	var x := axis.cross(Vector3.FORWARD).normalized()
	if x.length_squared()<0.1:
		x = axis.cross(Vector3.RIGHT).normalized()
	var z := axis.cross(x).normalized()
	for i in sides:
		var angle0 := TAU*i/sides
		var angle1 := TAU*(i+1)/sides
		var n0 := x*cos(angle0)+z*sin(angle0)
		var n1 := x*cos(angle1)+z*sin(angle1)
		var p := [a+n0*ra,b+n0*rb,b+n1*rb,a+n0*ra,b+n1*rb,a+n1*ra]
		var ns := [n0,n0,n1,n0,n1,n1]
		var length_uv := a.y*3.5
		var end_uv := length_uv+(b-a).length()*3.5
		var uv := [Vector2(float(i)/sides,length_uv),Vector2(float(i)/sides,end_uv),Vector2(float(i+1)/sides,end_uv),Vector2(float(i)/sides,length_uv),Vector2(float(i+1)/sides,end_uv),Vector2(float(i+1)/sides,length_uv)]
		for j in 6:
			st.set_normal(ns[j]);st.set_uv(uv[j]);st.add_vertex(p[j])


static func _leaf(st: SurfaceTool,p: Vector3,rng: RandomNumberGenerator,size_factor: float = 1.0) -> void:
	var rotation := Basis.from_euler(Vector3(rng.randf_range(-1.3,1.3),rng.randf()*TAU,rng.randf_range(-1.1,1.1)))
	var size := rng.randf_range(0.020,0.035)*size_factor
	var points := [Vector3(-size*0.55,0,-size),Vector3(size*0.55,0,-size),Vector3(-size*0.55,0,size),Vector3(size*0.55,0,size),Vector3(0,size*0.18,0)]
	var uv := [Vector2(0,0),Vector2(1,0),Vector2(0,1),Vector2(1,1),Vector2(0.5,0.5)]
	var shade := rng.randf_range(0.63,1.10)
	var color := Color(shade,shade,rng.randf_range(0.82,0.98)*shade)
	for i in [0,4,1,0,2,4,2,3,4,1,4,3]:
		st.set_color(color);st.set_normal(rotation*Vector3.UP);st.set_uv(uv[i]);st.add_vertex(p+rotation*points[i])
