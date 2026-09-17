extends Node3D
## Non-colliding surface dressing for the grassland art-direction reference.
## Density concentrates around the review camera; rule surfaces remain flat.

var _rng := RandomNumberGenerator.new()
var _presentation: Node3D
var _exclusions: Array[Vector3] = []
var _walls: Array = []

func build(presentation: Node3D,main: Node,size: Vector2) -> void:
	_presentation = presentation
	_rng.seed = 170927
	_walls = main.terrain_overlay.get_wall_segments_world()
	for obj in main.object_manager.get_children():
		if obj is Node3D and obj.is_in_group("selectable"):
			_exclusions.append(Vector3(obj.global_position.x,obj.global_position.z,0.021))
	var grass_transforms: Array[Transform3D] = []
	var grass_colors: Array[Color] = []
	var stone_transforms: Array[Transform3D] = []
	var stone_colors: Array[Color] = []
	var litter_transforms: Array[Transform3D] = []
	var litter_colors: Array[Color] = []
	var count := int(size.x*size.y*23000)
	for i in count:
		var point := Vector2(_rng.randf_range(-size.x*0.5,size.x*0.5),_rng.randf_range(-size.y*0.5,size.y*0.5))
		var hero := point.x<0.1 and point.y>0.06
		if not hero and _rng.randf()>0.18:
			continue
		var forest := _forest_amount(point)
		var noise: float = presentation._surface_noise(point*8.0)*0.70+presentation._surface_noise(point*35.0)*0.30
		var wall := _wall_distance(point)
		var excluded := _excluded(point)
		var density := smoothstep(0.33,0.64,noise)*0.88
		density *= 1.0-forest*0.48
		if wall<0.015:
			density = maxf(density,0.55)
		var chance := _rng.randf()
		if not excluded and chance<density:
			var scale_value := _rng.randf_range(0.45,1.25)
			if _rng.randf()<0.12:
				scale_value *= 1.65
			if forest>0.65:
				scale_value *= 0.72
			var basis := Basis(Vector3.UP,_rng.randf()*TAU).scaled(Vector3(scale_value,scale_value*_rng.randf_range(0.7,1.3),scale_value))
			grass_transforms.append(Transform3D(basis,Vector3(point.x,0.00005,point.y)))
			var col := Color(0.25,0.32,0.075).lerp(Color(0.57,0.48,0.23),_rng.randf()*0.78)
			grass_colors.append(col.srgb_to_linear())
		if not excluded and _rng.randf()<(0.36 if wall<0.03 else 0.22):
			var scale_value := _rng.randf_range(0.0005,0.0020)
			var basis := Basis.from_euler(Vector3(_rng.randf()*0.3,_rng.randf()*TAU,_rng.randf()*0.3)).scaled(Vector3(scale_value,scale_value*_rng.randf_range(0.45,0.8),scale_value*_rng.randf_range(0.75,1.3)))
			stone_transforms.append(Transform3D(basis,Vector3(point.x,scale_value*0.18,point.y)))
			stone_colors.append(Color(0.36,0.34,0.28).lerp(Color(0.65,0.61,0.50),_rng.randf()).srgb_to_linear())
		if not excluded and _rng.randf()<forest*0.65:
			var s := _rng.randf_range(0.0011,0.0026)
			var basis := Basis.from_euler(Vector3(_rng.randf_range(-0.2,0.2),_rng.randf()*TAU,_rng.randf_range(-0.2,0.2))).scaled(Vector3.ONE*s)
			litter_transforms.append(Transform3D(basis,Vector3(point.x,0.00025,point.y)))
			litter_colors.append(Color(0.24,0.15,0.065).lerp(Color(0.54,0.34,0.14),_rng.randf()).srgb_to_linear())
	for i in 420:
		var point := Vector2(_rng.randf_range(-size.x*0.5,size.x*0.5),_rng.randf_range(-size.y*0.5,size.y*0.5))
		var forest := _forest_amount(point)
		if forest<0.2 or forest>0.90 or _excluded(point):
			continue
		var shrub := MeshInstance3D.new()
		shrub.mesh = presentation._trees[i%3]
		shrub.position = Vector3(point.x,-0.001,point.y)
		var h := _rng.randf_range(0.012,0.028)
		shrub.scale = Vector3(h*1.35,h,h*1.35)
		shrub.rotation.y = _rng.randf()*TAU
		add_child(shrub)
	_multimesh("MeadowClumps",_tuft_mesh(),grass_transforms,grass_colors)
	var cards: Array[Transform3D] = []
	var card_colors: Array[Color] = []
	for i in grass_transforms.size():
		if i%2!=0:
			continue
		cards.append(grass_transforms[i])
		card_colors.append(Color(1,1,1).lerp(Color(0.85,0.90,0.65),_rng.randf()))
	_multimesh("PhotographicTufts",_tuft_cards(),cards,card_colors)
	_multimesh("FieldPebbles",_stone_mesh(),stone_transforms,stone_colors)
	_multimesh("LeafLitter",_litter_mesh(),litter_transforms,litter_colors)
	print("REFERENCE_UNDERSTORY grass=",grass_transforms.size()," stones=",stone_transforms.size()," leaves=",litter_transforms.size())


func _excluded(p: Vector2) -> bool:
	for e in _exclusions:
		if p.distance_squared_to(Vector2(e.x,e.y))<e.z*e.z:
			return true
	return false


func _forest_amount(p: Vector2) -> float:
	var value := 0.0
	for r: Vector4 in _presentation._regions:
		if r.z<=0.0 or r.w<=0.0:
			continue
		var d := ((p-Vector2(r.x,r.y))/Vector2(r.z,r.w)).length()
		value = maxf(value,1.0-smoothstep(0.72,1.2,d))
	return value


func _wall_distance(p: Vector2) -> float:
	var result := 100.0
	for segment: Array in _walls:
		var a: Vector2 = segment[0]
		var b: Vector2 = segment[1]
		var edge := b-a
		var t := clampf((p-a).dot(edge)/maxf(edge.length_squared(),0.000001),0,1)
		result = minf(result,p.distance_to(a+t*edge))
	return result


func _multimesh(label: String,mesh: Mesh,transforms: Array[Transform3D],colors: Array[Color]) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i,transforms[i])
		mm.set_instance_color(i,colors[i])
	var node := MultiMeshInstance3D.new()
	node.name = label
	node.multimesh = mm
	add_child(node)


func _tuft_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for blade in 32:
		var angle := _rng.randf()*TAU
		var dir := Vector3(cos(angle),0,sin(angle))
		var side := Vector3(-sin(angle),0,cos(angle))
		var root := dir*_rng.randf_range(0.0,0.0035)
		var height := _rng.randf_range(0.0025,0.007)
		var bend := _rng.randf_range(0.003,0.008)
		var width := _rng.randf_range(0.00009,0.00021)
		for j in 3:
			var t0 := float(j)/3.0
			var t1 := float(j+1)/3.0
			var p0 := root+Vector3.UP*height*t0+dir*bend*t0*t0
			var p1 := root+Vector3.UP*height*t1+dir*bend*t1*t1
			var s0 := side*width*(1.0-t0)
			var s1 := side*width*(1.0-t1)
			var points := [p0-s0,p1-s1,p1+s1,p0-s0,p1+s1,p0+s0]
			var uvs := [Vector2(0,t0),Vector2(0,t1),Vector2(1,t1),Vector2(0,t0),Vector2(1,t1),Vector2(1,t0)]
			var normal := (dir*0.6+Vector3.UP*0.8).normalized()
			for k in 6:
				st.set_normal(normal);st.set_uv(uvs[k]);st.add_vertex(points[k])
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/visual/reference_foliage.gdshader")
	st.set_material(mat)
	return st.commit()


func _stone_mesh() -> ArrayMesh:
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 9
	sphere.rings = 4
	var arrays := sphere.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in vertices.size():
		var p := vertices[i]
		var factor := 0.88+sin(p.x*9+p.y*5+p.z*7)*0.12
		vertices[i] = p*factor
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/visual/reference_stone.gdshader")
	mesh.surface_set_material(0,mat)
	return mesh


func _litter_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var points := [Vector3(-0.4,0,-1),Vector3(0.5,0,-0.5),Vector3(0.6,0.08,0.5),Vector3(0,0,1),Vector3(-0.6,0.02,0.3)]
	for i in [0,1,2,0,2,4,2,3,4]:
		st.set_normal(Vector3.UP);st.set_uv(Vector2(points[i].x+0.5,points[i].z*0.5+0.5));st.add_vertex(points[i])
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/visual/reference_foliage.gdshader")
	st.set_material(mat)
	return st.commit()


func _tuft_cards() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in 3:
		var angle := j*PI/3.0
		var side := Vector3(cos(angle),0,sin(angle))*0.0075
		var normal := Vector3(-sin(angle),0.7,cos(angle)).normalized()
		var points := [-side,side,-side+Vector3.UP*0.0085,side+Vector3.UP*0.0085]
		var uv := [Vector2(0,0.76),Vector2(1,0.76),Vector2(0,0.24),Vector2(1,0.24)]
		for i in [0,2,1,1,2,3]:
			st.set_normal(normal);st.set_uv(uv[i]);st.add_vertex(points[i])
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/visual/reference_tuft.gdshader")
	mat.set_shader_parameter("tuft_tex",load("res://assets/terrain/reference/hero/tuft.webp"))
	st.set_material(mat)
	return st.commit()
