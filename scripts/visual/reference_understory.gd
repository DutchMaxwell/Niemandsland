extends Node3D
## Non-colliding surface dressing for the grassland art-direction reference.
## Density concentrates around the review camera; rule surfaces remain flat.

var _rng := RandomNumberGenerator.new()
const ReferenceMaterials = preload("res://scripts/visual/reference_materials.gd")
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
	var herb_transforms: Array[Transform3D] = []
	var herb_colors: Array[Color] = []
	var tall_transforms: Array[Transform3D] = []
	var tall_colors: Array[Color] = []
	var stone_transforms: Array[Transform3D] = []
	var stone_colors: Array[Color] = []
	var litter_transforms: Array[Transform3D] = []
	var litter_colors: Array[Color] = []
	var count := int(size.x*size.y*26000)
	for i in count:
		var point := Vector2(_rng.randf_range(-size.x*0.5,size.x*0.5),_rng.randf_range(-size.y*0.5,size.y*0.5))
		var hero := point.x<0.1 and point.y>0.06
		if not hero and _rng.randf()>0.18:
			continue
		var forest := _forest_amount(point)
		var gh := ReferenceMaterials.ground_height(point)
		var noise: float = presentation._surface_noise(point*10.0)*0.65+presentation._surface_noise(point*43.0)*0.35
		var path := _path_amount(point)
		var wall := _wall_distance(point)
		var excluded := _excluded(point)
		var clump := _clump_amount(point)
		var density := smoothstep(0.34,0.63,noise)*0.92
		density *= (1.0-forest*0.80)*(1.0-path*0.98)*(0.55+1.05*clump)
		if wall<0.015:
			density = maxf(density,0.35)*(1.0-path*0.8)
		var chance := _rng.randf()
		if not excluded and chance<density:
			var scale_value := _rng.randf_range(0.35,0.85)*(0.72+0.55*clump)
			if _rng.randf()<0.12:
				scale_value *= 1.25
			if forest>0.65:
				scale_value *= 0.72
			var basis := Basis(Vector3.UP,_rng.randf()*TAU).scaled(Vector3(scale_value,scale_value*_rng.randf_range(0.7,1.3),scale_value))
			grass_transforms.append(Transform3D(basis,Vector3(point.x,gh+0.00005,point.y)))
			var age := clampf((1.0-clump)*0.9+_rng.randf()*0.45,0.0,1.0)
			var col := Color(0.22,0.28,0.07).lerp(Color(0.51,0.46,0.24),age)
			grass_colors.append(col.srgb_to_linear())
		if not excluded and _rng.randf()<density*0.14:
			var h := _rng.randf_range(0.65,1.30)
			var basis := Basis(Vector3.UP,_rng.randf()*TAU).scaled(Vector3(h,h,h))
			herb_transforms.append(Transform3D(basis,Vector3(point.x,gh+0.0001,point.y)))
			herb_colors.append(Color(0.75,0.78,0.50).lerp(Color(1.0,0.94,0.70),_rng.randf()))
		if not excluded and _rng.randf()<density*0.09 and wall>0.006:
			var h := _rng.randf_range(0.70,1.45)
			var basis := Basis(Vector3.UP,_rng.randf()*TAU).scaled(Vector3(h,h*_rng.randf_range(0.8,1.2),h))
			tall_transforms.append(Transform3D(basis,Vector3(point.x,gh-0.0002,point.y)))
			var straw := Color(0.43,0.46,0.20).lerp(Color(0.72,0.63,0.38),_rng.randf())
			tall_colors.append(straw.srgb_to_linear())
		if not excluded and _rng.randf()<(0.16 if wall<0.03 else 0.05+path*0.07):
			var scale_value := _rng.randf_range(0.0008,0.0032)
			var basis := Basis.from_euler(Vector3(_rng.randf()*0.3,_rng.randf()*TAU,_rng.randf()*0.3)).scaled(Vector3(scale_value,scale_value*_rng.randf_range(0.20,0.40),scale_value*_rng.randf_range(0.75,1.3)))
			stone_transforms.append(Transform3D(basis,Vector3(point.x,gh+scale_value*0.06,point.y)))
			stone_colors.append(Color(0.36,0.34,0.28).lerp(Color(0.65,0.61,0.50),_rng.randf()).srgb_to_linear())
		if not excluded and _rng.randf()<forest*(1.60+2.40*clump)+0.10+(1.0-path)*0.30*clump:
			var s := _rng.randf_range(0.0042,0.0100)
			var basis := Basis.from_euler(Vector3(_rng.randf_range(-0.2,0.2),_rng.randf()*TAU,_rng.randf_range(-0.2,0.2))).scaled(Vector3.ONE*s)
			litter_transforms.append(Transform3D(basis,Vector3(point.x,gh+0.00025,point.y)))
			litter_colors.append(Color(0.28,0.17,0.065).lerp(Color(0.64,0.40,0.18),_rng.randf()).srgb_to_linear())
	for i in 90:
		var point := Vector2(_rng.randf_range(-size.x*0.5,size.x*0.5),_rng.randf_range(-size.y*0.5,size.y*0.5))
		var forest := _forest_amount(point)
		if forest<0.2 or forest>0.90 or _excluded(point):
			continue
		var shrub := MeshInstance3D.new()
		shrub.mesh = presentation._trees[i%3]
		shrub.position = Vector3(point.x,ReferenceMaterials.ground_height(point)-0.001,point.y)
		var h := _rng.randf_range(0.009,0.019)
		shrub.scale = Vector3(h*1.35,h,h*1.35)
		shrub.rotation.y = _rng.randf()*TAU
		add_child(shrub)
	_contact_details(litter_transforms,litter_colors)
	_litter_drifts(litter_transforms,litter_colors,size)
	_multimesh("MeadowClumps",_tuft_mesh(),grass_transforms,grass_colors)
	var thatch_transforms: Array[Transform3D] = []
	var thatch_colors: Array[Color] = []
	for i in grass_transforms.size():
		if i%3==0:
			thatch_transforms.append(grass_transforms[i])
			thatch_colors.append(Color(0.42,0.35,0.20).lerp(Color(0.68,0.58,0.36),_rng.randf()).srgb_to_linear())
	_multimesh("FallenStraw",_thatch_mesh(),thatch_transforms,thatch_colors)
	_multimesh("MeadowHerbs",_herb_mesh(),herb_transforms,herb_colors)
	_multimesh("DryFescue",_fescue_mesh(),tall_transforms,tall_colors)
	_multimesh("FieldPebbles",_stone_mesh(),stone_transforms,stone_colors)
	_multimesh("LeafLitter",_litter_mesh(),litter_transforms,litter_colors)
	print("REFERENCE_UNDERSTORY grass=",grass_transforms.size()," stones=",stone_transforms.size()," leaves=",litter_transforms.size()," fescue=",tall_transforms.size())


## Drifts read as wind-piled leaves instead of an even sprinkle. Centres sit in
## the open field and thicken near woodland edges, where litter actually gathers.
func _litter_drifts(litter_transforms: Array[Transform3D],litter_colors: Array[Color],size: Vector2) -> void:
	for i in 130:
		var center := Vector2(_rng.randf_range(-size.x*0.5,size.x*0.5),_rng.randf_range(-size.y*0.5,size.y*0.5))
		if _excluded(center) or _path_amount(center)>0.35:
			continue
		var forest := _forest_amount(center)
		var radius := _rng.randf_range(0.020,0.055)*(0.6+forest)
		for j in int(10.0+22.0*forest):
			var a := _rng.randf()*TAU
			var r := sqrt(_rng.randf())*radius
			var p := center+Vector2(cos(a),sin(a))*r
			if _excluded(p):
				continue
			var s := _rng.randf_range(0.0035,0.0085)
			var basis := Basis.from_euler(Vector3(_rng.randf_range(-0.25,0.25),_rng.randf()*TAU,_rng.randf_range(-0.25,0.25))).scaled(Vector3(s,s*_rng.randf_range(0.8,1.2),s))
			litter_transforms.append(Transform3D(basis,Vector3(p.x,ReferenceMaterials.ground_height(p)+0.00028,p.y)))
			litter_colors.append(Color(0.26,0.15,0.055).lerp(Color(0.62,0.40,0.18),_rng.randf()).srgb_to_linear())


func _excluded(p: Vector2) -> bool:
	for e in _exclusions:
		if p.distance_squared_to(Vector2(e.x,e.y))<e.z*e.z:
			return true
	return false


func _contact_details(litter_transforms: Array[Transform3D],litter_colors: Array[Color]) -> void:
	for tree_point in _presentation._tree_points:
		for i in 26:
			var angle := _rng.randf()*TAU
			var radius := _rng.randf_range(0.010,0.048)
			var p: Vector2 = tree_point+Vector2(cos(angle),sin(angle))*radius
			if _excluded(p):
				continue
			var s := _rng.randf_range(0.0040,0.0090)*(1.45-radius/0.048)
			var basis := Basis.from_euler(Vector3(_rng.randf_range(-0.18,0.18),angle+PI*0.5,_rng.randf_range(-0.18,0.18))).scaled(Vector3(s*1.7,s,s*1.25))
			litter_transforms.append(Transform3D(basis,Vector3(p.x,ReferenceMaterials.ground_height(p)+0.00030,p.y)))
			litter_colors.append(Color(0.24,0.14,0.055).lerp(Color(0.60,0.37,0.16),_rng.randf()).srgb_to_linear())
		for i in 6:
			var angle := float(i)*TAU/6.0+_rng.randf_range(-0.5,0.5)
			var dir := Vector2(cos(angle),sin(angle))
			var length := _rng.randf_range(0.018,0.042)
			var p: Vector2 = tree_point+dir*length*0.55
			if _excluded(p):
				continue
			var s := _rng.randf_range(0.0012,0.0026)
			var basis := Basis.from_euler(Vector3(_rng.randf_range(-0.2,0.2),-angle,_rng.randf_range(-0.2,0.2))).scaled(Vector3(length*0.9,s,s*1.1))
			litter_transforms.append(Transform3D(basis,Vector3(p.x,ReferenceMaterials.ground_height(p)+0.00022,p.y)))
			litter_colors.append(Color(0.20,0.12,0.05).lerp(Color(0.55,0.34,0.15),_rng.randf()).srgb_to_linear())
	for segment: Array in _walls:
		var a: Vector2 = segment[0]
		var b: Vector2 = segment[1]
		var side := Vector2(-(b-a).y,(b-a).x).normalized()
		for i in 12:
			var p := a.lerp(b,_rng.randf())+side*_rng.randf_range(0.004,0.020)
			if _excluded(p):
				continue
			var s := _rng.randf_range(0.0009,0.0020)
			var basis := Basis.from_euler(Vector3(_rng.randf_range(-0.2,0.2),_rng.randf()*TAU,_rng.randf_range(-0.2,0.2))).scaled(Vector3(s*1.4,s,s*1.2))
			litter_transforms.append(Transform3D(basis,Vector3(p.x,ReferenceMaterials.ground_height(p)+0.00030,p.y)))
			litter_colors.append(Color(0.24,0.15,0.06).lerp(Color(0.58,0.38,0.18),_rng.randf()).srgb_to_linear())


func _clump_amount(p: Vector2) -> float:
	var coarse: float = _presentation._surface_noise(p*4.6)
	var mid: float = _presentation._surface_noise(p*11.0)
	return smoothstep(0.34,0.66,coarse*0.7+mid*0.3)


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
		var height := _rng.randf_range(0.0035,0.009)
		var bend := _rng.randf_range(0.003,0.008)
		var width := _rng.randf_range(0.00012,0.00029)
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
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for i in range(0,indices.size(),3):
		var a := vertices[indices[i]]
		var b := vertices[indices[i+1]]
		var c := vertices[indices[i+2]]
		var normal := (c-a).cross(b-a).normalized()
		for point in [a,b,c]:
			st.set_normal(normal);st.add_vertex(point)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/visual/reference_stone.gdshader")
	st.set_material(mat)
	return st.commit()


func _litter_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var points := [Vector3(-0.4,0,-1),Vector3(0.5,0,-0.5),Vector3(0.6,0.08,0.5),Vector3(0,0,1),Vector3(-0.6,0.02,0.3)]
	for i in [0,1,2,0,2,4,2,3,4]:
		st.set_normal(Vector3.UP);st.set_uv(Vector2(points[i].x+0.5,points[i].z*0.5+0.5));st.add_vertex(points[i])
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/visual/reference_litter.gdshader")
	mat.set_shader_parameter("leaf_tex",preload("res://scripts/visual/reference_materials.gd").texture("res://assets/terrain/reference/hero/leaf.webp"))
	st.set_material(mat)
	return st.commit()


## A shared winding wear mask also drives the ground material. It is visual only.
func _path_amount(p: Vector2) -> float:
	var center := -0.60+sin(p.y*8.0+0.4)*0.085
	var width: float = 0.020+_presentation._surface_noise(p*38.0)*0.020
	return (1.0-smoothstep(width,width+0.030,abs(p.x-center)))*smoothstep(0.02,0.15,p.y)


## Bent ribbons give dry grass a readable silhouette at the miniature scale.
func _fescue_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for blade in 150:
		var angle := _rng.randf()*TAU
		var dir := Vector3(cos(angle),0,sin(angle))
		var side := Vector3(-sin(angle),0,cos(angle))
		var root := dir*_rng.randf_range(0.0,0.0025)
		var height := _rng.randf_range(0.007,0.017)
		var bend := _rng.randf_range(0.004,0.015)
		var width := _rng.randf_range(0.00013,0.00028)
		var tint := _rng.randf_range(0.72,1.18)
		st.set_color(Color(tint,tint,tint))
		for j in 5:
			var t0 := float(j)/5.0
			var t1 := float(j+1)/5.0
			var p0 := root+Vector3.UP*height*sin(t0*2.25)+dir*bend*t0*t0
			var p1 := root+Vector3.UP*height*sin(t1*2.25)+dir*bend*t1*t1
			var s0 := side*width*(1.0-t0*0.92)
			var s1 := side*width*(1.0-t1*0.92)
			var points := [p0-s0,p1-s1,p1+s1,p0-s0,p1+s1,p0+s0]
			var uvs := [Vector2(0,t0),Vector2(0,t1),Vector2(1,t1),Vector2(0,t0),Vector2(1,t1),Vector2(1,t0)]
			for k in 6:
				st.set_normal((dir*0.45+Vector3.UP*0.89).normalized())
				st.set_uv(uvs[k]);st.add_vertex(points[k])
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/visual/reference_foliage.gdshader")
	st.set_material(mat)
	return st.commit()


func _herb_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 9:
		var angle := float(i)*2.39996
		var dir := Vector3(cos(angle),0,sin(angle))
		var side := Vector3(-sin(angle),0,cos(angle))
		var length := _rng.randf_range(0.0025,0.006)
		var width := length*0.36
		var center := dir*length*0.55+Vector3.UP*length*0.45
		var points := [Vector3.ZERO,center-side*width,dir*length+Vector3.UP*length*0.2,center+side*width,center+Vector3.UP*0.0003]
		var uv := [Vector2(0.5,1),Vector2(0,0.5),Vector2(0.5,0),Vector2(1,0.5),Vector2(0.5,0.5)]
		for j in [0,1,4,1,2,4,2,3,4,3,0,4]:
			st.set_normal((Vector3.UP-dir*0.2).normalized())
			st.set_color(Color.WHITE);st.set_uv(uv[j]);st.add_vertex(points[j])
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/visual/reference_foliage.gdshader")
	mat.set_shader_parameter("textured_leaf",true)
	mat.set_shader_parameter("leaf_tex",preload("res://scripts/visual/reference_materials.gd").texture("res://assets/terrain/reference/hero/leaf.webp"))
	mat.set_shader_parameter("foliage_tint",Vector3(0.72,0.83,0.65))
	st.set_material(mat)
	return st.commit()



func _thatch_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 36:
		var angle := _rng.randf()*TAU
		var dir := Vector3(cos(angle),0,sin(angle))
		var side := Vector3(-sin(angle),0,cos(angle))*_rng.randf_range(0.00007,0.00016)
		var origin := Vector3(_rng.randf_range(-0.007,0.007),0.00015,_rng.randf_range(-0.007,0.007))
		var length := _rng.randf_range(0.003,0.010)
		var middle := origin+dir*length*0.5+Vector3.UP*_rng.randf_range(0.0002,0.0009)
		var tip := origin+dir*length
		for segment in [[origin,middle],[middle,tip]]:
			var points := [segment[0]-side,segment[1]-side,segment[1]+side,segment[0]-side,segment[1]+side,segment[0]+side]
			for j in 6:
				st.set_normal(Vector3.UP)
				st.set_uv(Vector2(float(j%2),0.75));st.add_vertex(points[j])
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/visual/reference_foliage.gdshader")
	st.set_material(mat)
	return st.commit()
