extends Node3D
## Reference-only TRELLIS terrain props using the project's verified asset cache.
var _rock: PackedScene
var _bounds := AABB()
var _tree: PackedScene
var _tree_bounds := AABB()

func prepare() -> void:
	var rock_data: Dictionary = await _load_asset("rock")
	if not rock_data.is_empty():
		_rock = rock_data.scene
		_bounds = rock_data.bounds
	var tree_data: Dictionary = await _load_asset("oak")
	if not tree_data.is_empty():
		_tree = tree_data.scene
		_tree_bounds = tree_data.bounds


func has_tree() -> bool:
	return _tree!=null


func tree_instance(height: float,index: int) -> Node3D:
	var wrapper := Node3D.new()
	var tree: Node3D = _tree.instantiate()
	wrapper.add_child(tree)
	tree.position = -Vector3(_tree_bounds.get_center().x,_tree_bounds.position.y,_tree_bounds.get_center().z)
	var scale_value := height/maxf(_tree_bounds.size.y,0.001)
	wrapper.scale = Vector3.ONE*scale_value
	wrapper.rotation.y = float(index)*2.39996
	return wrapper


func _load_asset(kind: String) -> Dictionary:
	var manifest := "res://assets/terrain/reference/hero/"+kind+".json"
	if not FileAccess.file_exists(manifest):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest))
	if not parsed is Dictionary or not parsed.has("url") or not parsed.has("sha256"):
		push_warning("Invalid reference prop manifest; using procedural fallback.")
		return {}
	var entry: Dictionary = parsed
	var downloader := AssetDownloadManager.new()
	downloader.cache_dir = "user://reference_terrain_cache"
	add_child(downloader)
	var path: String = await downloader.ensure(AssetCDN.expand(entry.url),entry.sha256)
	downloader.queue_free()
	if path.is_empty():
		push_warning("Reference terrain unavailable; procedural fallback remains visible.")
		return {}
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	if document.append_from_file(path,state)!=OK:
		return {}
	var root := document.generate_scene(state)
	if root==null:
		return {}
	if kind == "rock":
		_rock_materials(root)
	if kind == "oak":
		preload("res://scripts/visual/reference_canopy.gd").dress(root)
	var bounds := _mesh_bounds(root,Transform3D.IDENTITY,AABB())
	if bounds.size.y <= 0.0 or maxf(bounds.size.x,bounds.size.z) <= 0.0:
		root.free()
		return {}
	_own(root,root)
	var packed := PackedScene.new()
	packed.pack(root)
	root.free()
	print("REFERENCE_TRELLIS_READY ",kind)
	return {"scene":packed,"bounds":bounds}


func dress(presentation: Node3D,size: Vector2) -> void:
	if _rock==null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 17122
	var placed := 0
	for i in 150:
		var point := Vector2(rng.randf_range(-size.x*0.49,0.05),rng.randf_range(0.10,size.y*0.49))
		var near_forest := false
		for r: Vector4 in presentation._regions:
			if r.z<=0 or r.w<=0:
				continue
			if ((point-Vector2(r.x,r.y))/Vector2(r.z,r.w)).length()<1.2:
				near_forest = true
		if not near_forest and rng.randf()>0.18:
			continue
		var clear := true
		for obj in presentation._main.object_manager.get_children():
			if obj is Node3D and obj.is_in_group("selectable") and point.distance_to(Vector2(obj.global_position.x,obj.global_position.z))<0.025:
				clear = false
		if not clear:
			continue
		_place_rock(point,rng.randf_range(0.004,0.013),rng)
		placed += 1
	for segment: Array in presentation._main.terrain_overlay.get_wall_segments_world():
		var a: Vector2 = segment[0]
		var b: Vector2 = segment[1]
		if (a.x+b.x)*0.5>0.1 or (a.y+b.y)*0.5<0.06:
			continue
		var dir := (b-a).normalized()
		var side := Vector2(-dir.y,dir.x)
		for i in 22:
			var point := a.lerp(b,rng.randf())+side*rng.randf_range(-0.012,0.012)
			var clear := true
			for obj in presentation._main.object_manager.get_children():
				if obj is Node3D and obj.is_in_group("selectable") and point.distance_to(Vector2(obj.global_position.x,obj.global_position.z))<0.025:
					clear = false
			if clear:
				_place_rock(point,rng.randf_range(0.004,0.010),rng)
				placed += 1
	print("REFERENCE_TRELLIS_ROCKS ",placed)


func _own(node: Node,root: Node) -> void:
	for child in node.get_children():
		child.owner = root
		_own(child,root)


func _mesh_bounds(node: Node,xform: Transform3D,bounds: AABB) -> AABB:
	if node is Node3D:
		xform = xform*node.transform
	if node is MeshInstance3D and node.mesh!=null:
		var b: AABB = xform*node.mesh.get_aabb()
		bounds = b if bounds.size==Vector3.ZERO else bounds.merge(b)
	for child in node.get_children():
		bounds = _mesh_bounds(child,xform,bounds)
	return bounds


func _place_rock(point: Vector2,width: float,rng: RandomNumberGenerator) -> void:
	var wrapper := Node3D.new()
	var rock: Node3D = _rock.instantiate()
	wrapper.add_child(rock)
	rock.position = -Vector3(_bounds.get_center().x,_bounds.position.y,_bounds.get_center().z)
	var scale_value := width/maxf(_bounds.size.x,_bounds.size.z)
	wrapper.scale = Vector3(scale_value,scale_value*rng.randf_range(0.6,1.05),scale_value)
	wrapper.rotation.y = rng.randf()*TAU
	wrapper.position = Vector3(point.x,-0.00025,point.y)
	add_child(wrapper)


func _rock_materials(node: Node) -> void:
	if node is MeshInstance3D and node.mesh != null:
		for i in node.mesh.get_surface_count():
			var material := node.mesh.surface_get_material(i) as StandardMaterial3D
			if material != null:
				material.albedo_color = Color(0.68,0.63,0.53)
				material.metallic = 0.0
				material.metallic_texture = null
				material.roughness = 0.95
				material.roughness_texture = null
	for child in node.get_children():
		_rock_materials(child)
