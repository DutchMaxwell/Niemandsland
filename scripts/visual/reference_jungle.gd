extends "res://scripts/visual/reference_understory.gd"
## Layered jungle floor. All geometry is decorative and leaves rule surfaces unchanged.

var _board_size := Vector2.ZERO
var _blockers: Array[Vector3] = []


func build(presentation: Node3D,main: Node,size: Vector2) -> void:
	_presentation = presentation
	_board_size = size
	_rng.seed = 21927
	_walls = main.terrain_overlay.get_wall_segments_world()
	for obj in main.object_manager.get_children():
		if obj is Node3D and obj.is_in_group("selectable"):
			_exclusions.append(Vector3(obj.global_position.x,obj.global_position.z,0.024))
	# The table tier loads no biome forest (no TRELLIS replacement): no anchors, no forest shelter.
	var forest: Node3D = presentation._biome_forest
	var anchors: Array = forest._anchors if forest != null else []
	for obj: Node3D in main.terrain_overlay._object_instances:
		var p := Vector2(obj.global_position.x,obj.global_position.z)
		var is_tree := false
		for anchor: Vector2 in anchors:
			if anchor.distance_squared_to(p)<0.000001:
				is_tree = true
				break
		var box: AABB = main.terrain_overlay._model_space_aabb(obj)
		var radius := 0.009 if is_tree else maxf(box.size.x,box.size.z)*0.5+0.003
		_blockers.append(Vector3(p.x,p.y,radius))
	var ferns: Array[Transform3D] = []
	var fern_colors: Array[Color] = []
	var leaves: Array[Transform3D] = []
	var leaf_colors: Array[Color] = []
	var litter: Array[Transform3D] = []
	var litter_colors: Array[Color] = []
	for i in int(size.x*size.y*14500*_density()):
		var p := Vector2(_rng.randf_range(-size.x*0.5,size.x*0.5),_rng.randf_range(-size.y*0.5,size.y*0.5))
		var growth := ReferenceMaterials.jungle_growth(p)
		var shelter: float = 1.0 if forest != null and forest._inside_forest(p) else 0.0
		var patch := smoothstep(0.36,0.68,ReferenceMaterials._noise2(p*31.0))
		var density := (0.02+growth*0.24+shelter*0.50)*patch*_unit_quiet(p)
		if _rng.randf()<density:
			var scale_value := _rng.randf_range(0.55,1.10)
			var radius := 0.016*scale_value
			if clear_footprint(p,radius):
				var basis := Basis(Vector3.UP,_rng.randf()*TAU).scaled(Vector3.ONE*scale_value)
				ferns.append(Transform3D(basis,Vector3(p.x,ReferenceMaterials.ground_height(p)-0.0001,p.y)))
				fern_colors.append(Color(0.21,0.34,0.105).lerp(Color(0.44,0.53,0.23),_rng.randf()).srgb_to_linear())
		if _rng.randf()<density*0.20:
			var scale_value := _rng.randf_range(0.65,1.15)
			if clear_footprint(p,0.013*scale_value):
				var basis := Basis(Vector3.UP,_rng.randf()*TAU).scaled(Vector3.ONE*scale_value)
				leaves.append(Transform3D(basis,Vector3(p.x,ReferenceMaterials.ground_height(p)-0.0001,p.y)))
				var col := Color(0.18,0.32,0.20).lerp(Color(0.36,0.46,0.22),_rng.randf())
				if i%7==0:
					col = Color(0.28,0.24,0.35)
				leaf_colors.append(col.srgb_to_linear())
		if _rng.randf()<(0.14+shelter*0.22)*_unit_quiet(p) and clear_footprint(p,0.004):
			var s := _rng.randf_range(0.0012,0.0035)
			var basis := Basis.from_euler(Vector3(_rng.randf_range(-0.12,0.12),_rng.randf()*TAU,0)).scaled(Vector3(s,s,s*1.4))
			litter.append(Transform3D(basis,Vector3(p.x,ReferenceMaterials.ground_height(p)+0.00015,p.y)))
			litter_colors.append(Color(0.25,0.17,0.085).lerp(Color(0.53,0.36,0.17),_rng.randf()).srgb_to_linear())
	_multimesh("JungleFerns",_fern_mesh(),ferns,fern_colors)
	_multimesh("JungleBroadleaves",_broadleaf_mesh(),leaves,leaf_colors)
	_multimesh("JungleLitter",_litter_mesh(),litter,litter_colors)
	for child: MultiMeshInstance3D in get_children():
		child.custom_aabb = child.multimesh.get_aabb().grow(0.0015)
	print("REFERENCE_JUNGLE ferns=",ferns.size()," broadleaves=",leaves.size()," litter=",litter.size())


## Test the entire decorative footprint, including the maximum animated leaf reach.
func clear_footprint(p: Vector2,radius: float) -> bool:
	var reach := radius+0.0015
	if absf(p.x)+reach>_board_size.x*0.5-0.008 or absf(p.y)+reach>_board_size.y*0.5-0.008:
		return false
	for e in _exclusions:
		if p.distance_to(Vector2(e.x,e.y))<e.z+reach:
			return false
	for e in _blockers:
		if p.distance_to(Vector2(e.x,e.y))<e.z+reach:
			return false
	return _wall_distance(p)>reach+0.005


func _fern_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for frond in 7:
		var angle := float(frond)*2.39996
		var dir := Vector3(cos(angle),0,sin(angle))
		var side := Vector3(-sin(angle),0,cos(angle))
		var length := 0.010+float(frond%3)*0.0018
		for j in range(1,10):
			var t := float(j)/10.0
			var center := dir*length*t+Vector3.UP*(0.002+0.013*sin(t*1.8))*t
			var spread := (1.0-t)*0.0042
			for sign_value: float in [-1.0,1.0]:
				var tip := center+side*spread*sign_value+dir*0.0012
				_leaf(st,center-dir*0.0006,tip,dir,0.00082*(1.0-t*0.65),t)
			# Thin central rachis, continuous between each pair of pinnae.
			var t0 := float(j-1)/10.0
			var previous := dir*length*t0+Vector3.UP*(0.002+0.013*sin(t0*1.8))*t0
			_leaf(st,previous,center,side,0.00013,t)
	return _finish_leaf_mesh(st)


func _broadleaf_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for blade in 6:
		var angle := float(blade)*2.39996
		var dir := Vector3(cos(angle),0,sin(angle))
		var side := Vector3(-sin(angle),0,cos(angle))
		var height := 0.012+float(blade%3)*0.003
		for j in 7:
			var t0 := float(j)/7.0
			var t1 := float(j+1)/7.0
			var p0 := Vector3.UP*height*sin(t0*1.6)+dir*0.012*t0*t0
			var p1 := Vector3.UP*height*sin(t1*1.6)+dir*0.012*t1*t1
			var w0 := sin(t0*PI)*0.0030
			var w1 := sin(t1*PI)*0.0030
			for sign_value: float in [-1.0,1.0]:
				var e0 := p0+side*w0*sign_value-Vector3.UP*w0*0.35
				var e1 := p1+side*w1*sign_value-Vector3.UP*w1*0.35
				_triangle(st,p0,p1,e1,Vector2(0.5,t0),Vector2(0.5,t1),Vector2(0.5+sign_value*0.5,t1))
				_triangle(st,p0,e1,e0,Vector2(0.5,t0),Vector2(0.5+sign_value*0.5,t1),Vector2(0.5+sign_value*0.5,t0))
	return _finish_leaf_mesh(st)


func _leaf(st: SurfaceTool,root: Vector3,tip: Vector3,side: Vector3,width: float,height_uv: float) -> void:
	var mid := root.lerp(tip,0.48)+Vector3.UP*width*0.30
	_triangle(st,root,mid-side*width,tip,Vector2(0.5,0),Vector2(0,height_uv),Vector2(0.5,height_uv))
	_triangle(st,root,tip,mid+side*width,Vector2(0.5,0),Vector2(0.5,height_uv),Vector2(1,height_uv))


func _triangle(st: SurfaceTool,a: Vector3,b: Vector3,c: Vector3,ua: Vector2,ub: Vector2,uc: Vector2) -> void:
	var normal := (b-a).cross(c-a).normalized()
	if normal.y<0:
		normal = -normal
	for i in 3:
		st.set_normal(normal)
		st.set_uv([ua,ub,uc][i])
		st.add_vertex([a,b,c][i])


func _finish_leaf_mesh(st: SurfaceTool) -> ArrayMesh:
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/visual/reference_jungle_leaf.gdshader")
	st.set_material(material)
	return st.commit()
