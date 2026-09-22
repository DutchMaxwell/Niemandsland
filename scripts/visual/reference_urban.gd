extends "res://scripts/visual/reference_jungle.gd"
## Low decorative masonry and pioneer weeds. Native urban props remain untouched.

const CONTACT_WIDTH := 256
const CONTACT_REACH := 0.044
const RELIEF_SCALE := 0.15
const FRAGMENT_RADIUS := 0.71
const REFRESH_DELAY := 0.12
const Anchor = preload("res://scripts/visual/reference_urban_anchor.gd")

var _main: Node
var _timer: Timer
var _rebuilding := false
var _owners: Dictionary = {}
var _watchers: Dictionary = {}
var _clearance: ImageTexture
var _rubble_material: ShaderMaterial
var _weather_material: ShaderMaterial
var _marks: Array[Vector4] = []
var revision := 0
var _surface_check := 0.0


func build(presentation: Node3D,main: Node,size: Vector2) -> void:
	_presentation = presentation
	_main = main
	_board_size = size
	_rubble_material = ShaderMaterial.new()
	_rubble_material.shader = preload("res://shaders/visual/reference_urban_rubble.gdshader")
	_rubble_material.set_shader_parameter("earth_tex",presentation._ground.get_shader_parameter("earth_tex"))
	_weather_material = ShaderMaterial.new()
	_weather_material.shader = preload("res://shaders/visual/reference_urban_weather.gdshader")
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.wait_time = REFRESH_DELAY
	add_child(_timer)
	_timer.timeout.connect(rebuild_now)
	if is_inside_tree():
		get_tree().node_added.connect(_on_node_added)
		get_tree().node_removed.connect(_on_node_removed)
	var table := main.get_node_or_null("Table")
	if table != null:
		table.table_resized.connect(_on_table_resized)
	if "save_manager" in main and main.save_manager != null:
		main.save_manager.load_completed.connect(_on_load_completed)
	rebuild_now()


## Rebuild only after a scene edit settles. Visual children never enter terrain bounds.
func rebuild_now() -> void:
	if not is_instance_valid(_main) or _rebuilding:
		return
	_rebuilding = true
	_timer.stop()
	_exclusions.clear()
	_blockers.clear()
	_walls.clear()
	_marks.clear()
	var overlay: Node3D = _main.terrain_overlay
	var roots: Array[Node3D] = [overlay]
	var monitored: Array[Node3D] = [overlay]
	for obj in _main.object_manager.get_children():
		if not obj is Node3D or obj.is_queued_for_deletion():
			continue
		monitored.append(obj)
		if obj.has_method("wall_segments_world"):
			roots.append(obj)
		elif obj.is_in_group("terrain"):
			_add_blocker(obj)
			continue
		if obj is Node3D and obj.is_in_group("selectable"):
			if obj.has_method("wall_segments_world"):
				continue
			var model: ModelInstance = _main.object_manager._object_model_instance(obj)
			var radius := maxf(0.024,VolumetricLos.model_base_radius_m(model)+0.008) if model != null else 0.024
			_exclusions.append(Vector3(obj.global_position.x,obj.global_position.z,radius))
	for obj: Node3D in overlay._object_instances:
		if is_instance_valid(obj) and not obj.is_queued_for_deletion():
			_add_blocker(obj)
	for id: int in _owners.keys():
		var entry: Dictionary = _owners[id]
		if not is_instance_valid(entry.owner) or entry.owner not in roots:
			entry.rig.free()
			_owners.erase(id)
	for owner_node in roots:
		var id := owner_node.get_instance_id()
		if not _owners.has(id):
			var rig := Node3D.new()
			rig.name = "UrbanTerrainDressing"
			add_child(rig)
			_owners[id] = {"owner":owner_node,"rig":rig,"edges":[],"seed":int(owner_node.get_meta("network_id",21961))}
		var entry: Dictionary = _owners[id]
		entry.rig.global_transform = owner_node.global_transform
		entry.edges = overlay.get_wall_segments_world() if owner_node == overlay else owner_node.wall_segments_world()
		_walls.append_array(entry.edges)
	for owner_node in monitored:
		_watch(owner_node)
	for id: int in _watchers.keys():
		if not is_instance_valid(_watchers[id]):
			_watchers.erase(id)
			continue
		var observer: Node = _watchers[id]
		if observer.get_parent() not in monitored:
			observer.free()
			_watchers.erase(id)
	_clearance = _clearance_texture()
	for material in [_rubble_material,_weather_material]:
		material.set_shader_parameter("urban_board_size",_board_size)
		material.set_shader_parameter("clearance_mask",_clearance)
		material.set_shader_parameter("clearance_enabled",true)
	var fragment_count := 0
	for entry: Dictionary in _owners.values():
		for child in entry.rig.get_children():
			child.free()
		fragment_count += _dress_owner(entry)
	var mask := _contact_texture()
	for material: ShaderMaterial in [_presentation._ground,_presentation._base]:
		material.set_shader_parameter("urban_board_size",_board_size)
		material.set_shader_parameter("urban_contact_mask",mask)
		material.set_shader_parameter("urban_contact_enabled",true)
	revision += 1
	_rebuilding = false
	print("REFERENCE_URBAN revision=",revision," owners=",_owners.size()," fragments=",fragment_count)


func _dress_owner(entry: Dictionary) -> int:
	_rng.seed = entry.seed
	var rig: Node3D = entry.rig
	var owner_node: Node3D = entry.owner
	var inverse_owner := owner_node.global_transform.affine_inverse()
	var fragments: Array[Transform3D] = []
	var fragment_colors: Array[Color] = []
	var weeds: Array[Transform3D] = []
	var weed_colors: Array[Color] = []
	for edge: Array in entry.edges:
		var a: Vector2 = edge[0]
		var b: Vector2 = edge[1]
		var direction := (b-a).normalized()
		var normal := Vector2(-direction.y,direction.x)
		var length := a.distance_to(b)
		var burn := a.lerp(b,_rng.randf_range(0.10,0.90))+normal*_rng.randf_range(-0.013,0.013)
		_marks.append(Vector4(burn.x,burn.y,_rng.randf_range(0.025,0.050),_rng.randf()))
		for i in maxi(1,int(length*2100.0*_density())):
			var t := _rng.randf()
			var distance := _rng.randf_range(0.009,0.047)*_rng.randf_range(0.45,1.0)
			var p := a.lerp(b,t)+normal*distance*(-1.0 if i%2==0 else 1.0)
			var clump := 0.4+0.6*sin(t*17.0+float(entry.seed%19))*sin(t*17.0+float(entry.seed%19))
			var span := _rng.randf_range(0.0015,0.006)*(1.0+(1.0-distance/0.05)*0.6)
			var thickness := span*_rng.randf_range(0.15,0.48)
			var angle := _rng.randf()*TAU+owner_node.global_rotation.y
			var tint := _rng.randf()
			var chance := _rng.randf()
			if not clear_footprint(p,span*FRAGMENT_RADIUS) or chance>clump*_unit_quiet(p):
				continue
			var orientation := Basis(Vector3.UP,angle).scaled(Vector3(span,thickness,span))
			fragments.append(inverse_owner*Transform3D(orientation,Vector3(p.x,0,p.y)))
			var color := Color(0.34,0.32,0.28).lerp(Color(0.70,0.65,0.55),tint)
			if i%5==0:
				color = Color(0.30,0.13,0.08).lerp(Color(0.55,0.30,0.18),tint)
			elif i%7==0:
				color = Color(0.16,0.16,0.15)
			fragment_colors.append(color.srgb_to_linear())
			if i%37==0 and clear_footprint(p,0.006):
				weeds.append(inverse_owner*Transform3D(Basis(Vector3.UP,angle).scaled(Vector3.ONE*0.7),Vector3(p.x,ground_height(p),p.y)))
				weed_colors.append(Color(0.24,0.25,0.12).srgb_to_linear())
	_multimesh("UrbanMasonry",_fragment_mesh(),fragments,fragment_colors)
	var rubble: MultiMeshInstance3D = get_child(get_child_count()-1)
	rubble.set_meta("urban_cosmetic",true)
	rubble.reparent(rig,false)
	rubble.material_override = _rubble_material
	_multimesh("UrbanWeeds",_turf_mesh(),weeds,weed_colors)
	var plants: MultiMeshInstance3D = get_child(get_child_count()-1)
	plants.set_meta("urban_cosmetic",true)
	plants.reparent(rig,false)
	plants.material_override = _rubble_material
	var sources: Array = _main.terrain_overlay._wall_instances if owner_node == _main.terrain_overlay else [owner_node]
	for source: Node3D in sources:
		_add_weather(source,rig,inverse_owner)
	return fragments.size()


func _add_blocker(obj: Node3D) -> void:
	var box: AABB = _main.terrain_overlay._model_space_aabb(obj)
	box = obj.get_parent().global_transform*box
	var p := Vector2(box.get_center().x,box.get_center().z)
	_blockers.append(Vector3(p.x,p.y,Vector2(box.size.x,box.size.z).length()*0.5+0.003))


func _add_weather(source: Node,rig: Node3D,inverse_owner: Transform3D) -> void:
	if source is MeshInstance3D and source.mesh != null:
		var surface := MeshInstance3D.new()
		surface.name = "UrbanWallWeather"
		surface.set_meta("urban_cosmetic",true)
		surface.mesh = source.mesh
		surface.transform = inverse_owner*source.global_transform
		surface.material_override = _weather_material
		surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		rig.add_child(surface)
	for child in source.get_children():
		_add_weather(child,rig,inverse_owner)


func _watch(owner_node: Node3D) -> void:
	var id := owner_node.get_instance_id()
	if _watchers.has(id) or not owner_node.is_inside_tree():
		return
	var observer := Anchor.new()
	observer.name = "UrbanVisualObserver"
	observer.set_meta("urban_owner_id",id)
	owner_node.add_child(observer)
	observer.moved.connect(_on_owner_moved.bind(id))
	observer.leaving.connect(_on_owner_leaving.bind(id))
	_watchers[id] = observer


func _on_owner_moved(id: int) -> void:
	if _rebuilding:
		return
	if _owners.has(id):
		var entry: Dictionary = _owners[id]
		if is_instance_valid(entry.owner):
			entry.rig.global_transform = entry.owner.global_transform
	_request_refresh()


func _on_owner_leaving(id: int) -> void:
	if _owners.has(id):
		_owners[id].rig.visible = false
	_request_refresh()


func _on_node_added(node: Node) -> void:
	if _rebuilding or not (node is MeshInstance3D or node is CollisionObject3D):
		return
	if _main.terrain_overlay.is_ancestor_of(node) or _main.object_manager.is_ancestor_of(node):
		_request_refresh()


func _on_node_removed(node: Node) -> void:
	if not _rebuilding and node is MeshInstance3D and not node.get_meta("urban_cosmetic",false):
		_request_refresh()


func _request_refresh() -> void:
	if _rebuilding or not is_inside_tree() or not is_instance_valid(_timer):
		return
	# Do not leave the previous footprint on the floor while its owner is dragged.
	for material: ShaderMaterial in [_presentation._ground,_presentation._base]:
		material.set_shader_parameter("urban_contact_enabled",false)
	_timer.start()


func _on_table_resized(size_feet: Vector2) -> void:
	_board_size = size_feet*0.3048
	_restore_surface.call_deferred()


func _on_load_completed(_object_count: int) -> void:
	_restore_surface.call_deferred()


func _process(delta: float) -> void:
	# Native biome loading may finish after load_completed and replace the material.
	_surface_check += delta
	if _surface_check < 0.25 or not is_instance_valid(_main):
		return
	_surface_check = 0.0
	var table := _main.get_node_or_null("Table")
	if table != null and table.get_node("TableMesh").material_override != _presentation._ground:
		_restore_surface()


func _restore_surface() -> void:
	if not is_inside_tree():
		return
	var table: Node3D = _main.get_node("Table")
	_board_size = table.table_size*0.3048
	var surface: MeshInstance3D = table.get_node("TableMesh")
	if surface.mesh is PlaneMesh:
		var plane: PlaneMesh = surface.mesh.duplicate()
		plane.subdivide_width = 450
		plane.subdivide_depth = 300
		surface.mesh = plane
	surface.material_override = _presentation._ground
	_presentation._base = table.get_base_top_material()
	_presentation._base.shader = _presentation._ground.shader
	for texture_name in ["meadow","earth","woodland"]:
		_presentation._base.set_shader_parameter(texture_name+"_tex",_presentation._ground.get_shader_parameter(texture_name+"_tex"))
	_presentation._base.set_shader_parameter("urban_mode",true)
	_presentation._base.set_shader_parameter("clip_base",true)
	table.get_node("GrassField").visible = false
	_request_refresh()


func _exit_tree() -> void:
	_rebuilding = true
	for observer in _watchers.values():
		if is_instance_valid(observer):
			observer.queue_free()


static func ground_height(p: Vector2) -> float:
	return ReferenceMaterials.ground_height(p)*RELIEF_SCALE


func contact_amount(p: Vector2) -> float:
	return 1.0-smoothstep(0.005,CONTACT_REACH,_wall_distance(p))


func _contact_texture() -> ImageTexture:
	var height := maxi(1,roundi(CONTACT_WIDTH*_board_size.y/_board_size.x))
	var image := Image.create(CONTACT_WIDTH,height,false,Image.FORMAT_RGBA8)
	image.fill(Color(0,0,0,0))
	for segment: Array in _walls:
		var a: Vector2 = segment[0]
		var b: Vector2 = segment[1]
		var rect := _pixel_rect(a.min(b)-Vector2.ONE*CONTACT_REACH,a.max(b)+Vector2.ONE*CONTACT_REACH,height)
		for y in range(rect.position.y,rect.end.y):
			for x in range(rect.position.x,rect.end.x):
				var p := _pixel_world(x,y,height)
				var edge := b-a
				var t := clampf((p-a).dot(edge)/maxf(edge.length_squared(),0.000001),0,1)
				var amount := 1.0-smoothstep(0.005,CONTACT_REACH,p.distance_to(a+edge*t))
				var pixel := image.get_pixel(x,y)
				pixel.r = maxf(pixel.r,amount)
				image.set_pixel(x,y,pixel)
	for mark: Vector4 in _marks:
		var center := Vector2(mark.x,mark.y)
		var rect := _pixel_rect(center-Vector2.ONE*mark.z,center+Vector2.ONE*mark.z,height)
		for y in range(rect.position.y,rect.end.y):
			for x in range(rect.position.x,rect.end.x):
				var p := _pixel_world(x,y,height)
				var amount := 1.0-smoothstep(0.1,1.0,p.distance_to(center)/mark.z)
				var pixel := image.get_pixel(x,y)
				pixel.g = maxf(pixel.g,amount if mark.w<0.65 else 0.0)
				pixel.b = maxf(pixel.b,amount if mark.w>0.65 and mark.w<0.85 else 0.0)
				pixel.a = maxf(pixel.a,amount if mark.w>0.85 else 0.0)
				image.set_pixel(x,y,pixel)
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


func _clearance_texture() -> ImageTexture:
	var height := maxi(1,roundi(CONTACT_WIDTH*_board_size.y/_board_size.x))
	var image := Image.create(CONTACT_WIDTH,height,false,Image.FORMAT_R8)
	image.fill(Color.BLACK)
	for exclusion: Vector3 in _exclusions+_blockers:
		var center := Vector2(exclusion.x,exclusion.y)
		var radius := exclusion.z+0.006
		var rect := _pixel_rect(center-Vector2.ONE*radius,center+Vector2.ONE*radius,height)
		for y in range(rect.position.y,rect.end.y):
			for x in range(rect.position.x,rect.end.x):
				if _pixel_world(x,y,height).distance_to(center)<radius:
					image.set_pixel(x,y,Color.WHITE)
	return ImageTexture.create_from_image(image)


func _pixel_rect(low: Vector2,high: Vector2,height: int) -> Rect2i:
	var dims := Vector2(CONTACT_WIDTH,height)
	var start := Vector2i(((low/_board_size+Vector2.ONE*0.5)*dims).floor()).clamp(Vector2i.ZERO,Vector2i(dims))
	var end := Vector2i(((high/_board_size+Vector2.ONE*0.5)*dims).ceil()).clamp(Vector2i.ZERO,Vector2i(dims))
	return Rect2i(start,end-start)


func _pixel_world(x: int,y: int,height: int) -> Vector2:
	return (Vector2((x+0.5)/CONTACT_WIDTH,(y+0.5)/height)-Vector2.ONE*0.5)*_board_size


## Irregular chipped slab, rooted at y=0, max horizontal reach < FRAGMENT_RADIUS.
func _fragment_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var outline := [Vector2(-0.48,-0.30),Vector2(0.16,-0.49),Vector2(0.48,-0.12),Vector2(0.35,0.43),Vector2(-0.36,0.39)]
	for i in outline.size():
		var a: Vector2 = outline[i]
		var b: Vector2 = outline[(i+1)%outline.size()]
		var bottom_a := Vector3(a.x,0,a.y)
		var bottom_b := Vector3(b.x,0,b.y)
		var top_a := Vector3(a.x*0.83,0.70+float(i%3)*0.12,a.y*0.83)
		var top_b := Vector3(b.x*0.83,0.70+float(((i+1)%outline.size())%3)*0.12,b.y*0.83)
		for vertex: Vector3 in [Vector3(0,0.96,0),top_a,top_b,bottom_a,bottom_b,top_b,bottom_a,top_b,top_a]:
			st.add_vertex(vertex)
	st.generate_normals()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 0.96
	st.set_material(mat)
	return st.commit()
