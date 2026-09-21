extends Node3D
## Reference-only woody vegetation. Rule anchors, forest areas and colliders stay intact.
## Native terrain mixes with reconstructed pine/acacia; volcanic terrain stays mineral.

const Materials = preload("res://scripts/visual/reference_materials.gd")
const PROP_SHADER = preload("res://shaders/visual/reference_woody_prop.gdshader")
var _biome := ""
var _hero: PackedScene
var _templates: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _main: Node
var _presentation: Node3D
var _zones: Array = []
var _ellipses: Array = []
var _units: Array[Vector2] = []
var _walls: Array = []
var _anchors: Array[Vector2] = []
var _anchor_parents: Array[Node3D] = []
var _anchor_heights: Array[float] = []
var _wind_materials: Array[ShaderMaterial] = []


func prepare(biome: String) -> void:
	_biome = biome
	_rng.seed = 210921
	if biome in ["volcanic_ash","alien_jungle"]:
		_hero = null
		return
	var kind := "open-pine" if biome == "frozen_tundra" else "dry-acacia"
	var path := "res://assets/terrain/reference/forest/" + kind + ".json"
	if not FileAccess.file_exists(path):
		return
	var entry: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not entry is Dictionary or not entry.has("url") or not entry.has("sha256"):
		return
	var downloader := AssetDownloadManager.new()
	downloader.cache_dir = "user://reference_terrain_cache"
	add_child(downloader)
	var cached: String = await downloader.ensure(AssetCDN.expand(entry.url),entry.sha256)
	downloader.queue_free()
	if cached.is_empty():
		push_warning("Reference forest source unavailable; existing tree sources used.")
		return
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	if document.append_from_file(cached,state) != OK:
		return
	var root := document.generate_scene(state)
	if root == null:
		return
	_own(root,root)
	_hero = PackedScene.new()
	_hero.pack(root)
	root.free()
	print("REFERENCE_FOREST_SOURCE_READY ",kind)


func apply(main: Node,presentation: Node3D) -> void:
	_main = main
	_presentation = presentation
	var overlay: Node3D = main.terrain_overlay
	_walls = overlay.get_wall_segments_world()
	for model in main.object_manager.get_children():
		if model is Node3D and model.is_in_group("selectable"):
			_units.append(Vector2(model.global_position.x,model.global_position.z))
	var dims: Vector2i = overlay._calculate_grid_dims(overlay.table_size_feet)
	var cell_size: float = overlay.GRID_SIZE_INCHES * overlay.INCHES_TO_METERS
	var rotation: float = deg_to_rad(float(overlay.grid_rotation_degrees))
	for zone: Dictionary in overlay._terrain_zones(overlay.grid_cells):
		if zone.type != overlay.TerrainType.FOREST:
			continue
		for cell: Vector2i in zone.cells:
			var center: Vector3 = overlay._cell_to_world(float(cell.x),float(cell.y),dims,cell_size,rotation)
			_zones.append({"center":Vector2(center.x,center.z),"half":cell_size*0.5,"angle":rotation})
	var dressed := 0
	for obj: Dictionary in overlay._last_objects:
		if obj.get("object_type","") != "tree":
			continue
		var cell: Vector2i = obj.cell
		var offset: Vector2 = obj.offset
		var p := Vector2((cell.x-dims.x/2.0+offset.x)*cell_size,(cell.y-dims.y/2.0+offset.y)*cell_size).rotated(rotation)
		var source_rng := RandomNumberGenerator.new()
		source_rng.seed = overlay._placed_object_seed(obj)
		var source_index := int(source_rng.randi() % 3)
		for original: Node3D in overlay._object_instances:
			if Vector2(original.position.x,original.position.z).distance_squared_to(p)>0.000001:
				continue
			# Reuse cacti at their existing anchors; replace only the woody desert variant.
			var bounds: AABB = overlay._model_space_aabb(original)
			var height := clampf(bounds.size.y,0.08,0.20)
			var tree := _instance(source_index,dressed,height,Materials.ground_height(p))
			if tree == null:
				break
			_hide_meshes(original)
			original.add_child(tree)
			if _biome == "alien_jungle":
				tree.position += original.global_basis.inverse()*Vector3(0,-original.global_position.y,0)
			_anchors.append(p)
			_anchor_parents.append(self)
			_anchor_heights.append(0.0)
			dressed += 1
			break
	var groups := _dress_groups()
	var young := _young_growth()
	_apply_ground_contact()
	print("REFERENCE_BIOME_FOREST ",_biome," trees=",dressed," grouped=",groups," young=",young)


func _instance(source_index: int,variant: int,height: float,base_y: float) -> Node3D:
	var winter := _biome == "frozen_tundra"
	var prefix := _native_prefix()
	var use_hero := source_index == 2 and _hero != null
	# Without the new pine, use an existing open spruce instead of the snow-pillow tree.
	var native_index := mini(source_index,1) if winter else source_index
	var key := ("hero" if use_hero else prefix+str(native_index)) + ":" + str(variant%4)
	if not _templates.has(key):
		var source: PackedScene = _hero if use_hero else _main.terrain_overlay._trees_library.get_model_scene(prefix+TreesLibrary.TREE_VARIANTS[native_index])
		if source == null:
			return null
		var root: Node3D = source.instantiate()
		var bounds: AABB = _main.terrain_overlay._model_space_aabb(root)
		if bounds.size.y<=0.001:
			root.free()
			return null
		# Cacti stay rigid. Wood sways above the fixed trunk and carries sparse snow.
		_shade(root,variant,(winter or use_hero or _biome == "alien_jungle") and _biome != "volcanic_ash",0.90 if winter and use_hero else 0.0)
		_own(root,root)
		var packed := PackedScene.new()
		packed.pack(root)
		root.free()
		_templates[key] = {"scene":packed,"bounds":bounds}
	var data: Dictionary = _templates[key]
	var bounds: AABB = data.bounds
	var model: Node3D = data.scene.instantiate()
	model.position = -Vector3(bounds.get_center().x,bounds.position.y,bounds.get_center().z)
	var wrapper := Node3D.new()
	wrapper.name = "ReferenceWoodyVegetation"
	if _biome == "volcanic_ash":
		wrapper.name = "ReferenceMonolith"
		wrapper.add_to_group("reference_volcanic_monolith")
	wrapper.add_child(model)
	var scale_value := height / bounds.size.y
	wrapper.scale = Vector3.ONE * scale_value
	wrapper.rotation.y = float(variant) * 2.39996
	wrapper.position.y = base_y
	return wrapper


func _young_growth() -> int:
	if _biome == "volcanic_ash":
		return 0
	var count := 0
	for i in _anchors.size():
		var anchor: Vector2 = _anchors[i]
		for j in 2:
			var angle := _rng.randf()*TAU
			var p := anchor + Vector2(cos(angle),sin(angle))*_rng.randf_range(0.022,0.052)
			if not _inside_forest(p) or not _clear(p):
				continue
			var winter := _biome == "frozen_tundra"
			var height := _rng.randf_range(0.024,0.052) if winter else _rng.randf_range(0.012,0.026)
			var parent := _anchor_parents[i]
			var base_y := Materials.ground_height(p) if parent == self else _anchor_heights[i]
			var tree := _instance(1 if winter else 2,100+i*2+j,height,0.0)
			if tree == null:
				continue
			parent.add_child(tree)
			tree.global_position = Vector3(p.x,base_y,p.y)
			count += 1
	return count


func _inside_forest(p: Vector2) -> bool:
	for zone: Dictionary in _zones:
		var d: Vector2 = (p-zone.center).rotated(-zone.angle)
		if absf(d.x)<zone.half-0.012 and absf(d.y)<zone.half-0.012:
			return true
	for ellipse: Dictionary in _ellipses:
		var d: Vector2 = (p-ellipse.center).rotated(-ellipse.angle)/ellipse.radius
		if d.length()<0.78:
			return true
	return false


func _dress_groups() -> int:
	var count := 0
	var prefix := _native_prefix()
	for group in get_tree().get_nodes_in_group("terrain_group_base"):
		if group.prop_kind != TerrainGroupBase.KIND_FOREST or group.biome_prefix != prefix:
			continue
		var radius: Vector2 = group.footprint_inches*0.0254*0.5
		_ellipses.append({"center":Vector2(group.global_position.x,group.global_position.z),"angle":group.global_rotation.y,"radius":radius})
		for member in group.get_children():
			if not member is Node3D or not member.has_meta(TerrainGroupBase.MEMBER_META):
				continue
			var bounds: AABB = _main.terrain_overlay._model_space_aabb(member)
			var tree := _instance(count%3,200+count,bounds.size.y,bounds.position.y)
			if tree == null:
				continue
			_hide_meshes(member)
			tree.position.x = member.position.x
			tree.position.z = member.position.z
			group.add_child(tree)
			_anchors.append(Vector2(tree.global_position.x,tree.global_position.z))
			_anchor_parents.append(group)
			_anchor_heights.append(tree.global_position.y)
			count += 1
		if is_instance_valid(group._floor_mesh):
			var floor_material: ShaderMaterial = _presentation._ground.duplicate()
			floor_material.set_shader_parameter("surface_relief",false)
			group._floor_mesh.material_override = floor_material
	return count


func _native_prefix() -> String:
	return {"volcanic_ash":"volcanic_","frozen_tundra":"tundra_","alien_jungle":"jungle_"}.get(_biome,"desert_")


func _clear(p: Vector2) -> bool:
	for unit in _units:
		if p.distance_squared_to(unit)<0.040*0.040:
			return false
	for segment: Array in _walls:
		if p.distance_to(Geometry2D.get_closest_point_to_segment(p,segment[0],segment[1]))<0.020:
			return false
	return true


func _apply_ground_contact() -> void:
	if _biome == "volcanic_ash":
		return
	# Bake the small contact mask once, avoiding a per-pixel loop over every tree.
	var board_size: Vector2 = _main.get_node("Table").table_size * 0.3048
	const RESOLUTION := 256
	var mask := Image.create(RESOLUTION,RESOLUTION,false,Image.FORMAT_R8)
	mask.fill(Color.BLACK)
	for i in _anchors.size():
		# Movable groups keep their own floor; never leave a contact stain on the board.
		if _anchor_parents[i] != self:
			continue
		var center: Vector2 = _anchors[i]
		var radius := 0.038+float(i%4)*0.009
		var pixel: Vector2 = (center/board_size+Vector2.ONE*0.5)*RESOLUTION
		var span := Vector2.ONE*radius/board_size*RESOLUTION
		for y in range(maxi(0,int(pixel.y-span.y)-1),mini(RESOLUTION,int(pixel.y+span.y)+2)):
			for x in range(maxi(0,int(pixel.x-span.x)-1),mini(RESOLUTION,int(pixel.x+span.x)+2)):
				var point := ((Vector2(x,y)+Vector2.ONE*0.5)/RESOLUTION-Vector2.ONE*0.5)*board_size
				var edge := radius*(0.82+0.30*Materials._noise2(point*95.0))
				var amount := 1.0-smoothstep(edge*0.10,edge,point.distance_to(center))
				var previous := mask.get_pixel(x,y).r
				mask.set_pixel(x,y,Color(maxf(previous,amount),0.0,0.0))
	mask.generate_mipmaps()
	var texture := ImageTexture.create_from_image(mask)
	for material in [_presentation._ground,_presentation._base]:
		material.set_shader_parameter("woody_ground_enabled",true)
		material.set_shader_parameter("woody_ground_mask",texture)
		material.set_shader_parameter("woody_board_size",board_size)


func _shade(node: Node,variant: int,wind: bool,snow: float) -> void:
	if node is MeshInstance3D and node.mesh != null:
		var box: AABB = node.mesh.get_aabb()
		for surface in node.mesh.get_surface_count():
			var original := node.get_active_material(surface) as BaseMaterial3D
			if original == null or original.albedo_texture == null:
				continue
			var material := ShaderMaterial.new()
			material.shader = PROP_SHADER
			material.set_shader_parameter("albedo_tex",original.albedo_texture)
			material.set_shader_parameter("albedo_tint",original.albedo_color)
			if original.normal_enabled and original.normal_texture != null:
				material.set_shader_parameter("normal_tex",original.normal_texture)
				material.set_shader_parameter("has_normal",true)
			material.set_shader_parameter("tree_bottom",box.position.y)
			material.set_shader_parameter("tree_height",box.size.y)
			material.set_shader_parameter("crown_width",0.85+float(variant%4)*0.10)
			material.set_shader_parameter("crown_lean",Vector2(sin(float(variant)*2.3),cos(float(variant)*1.7))*0.025)
			material.set_shader_parameter("wind_amount",0.006 if wind else 0.0)
			if _biome == "alien_jungle":
				material.set_shader_parameter("jungle_sway",true)
				material.set_shader_parameter("wind_amount",0.015)
				material.set_shader_parameter("wind_phase",float(variant)*2.39996)
				_wind_materials.append(material)
			material.set_shader_parameter("snow_amount",snow)
			material.set_shader_parameter("charred",_biome == "volcanic_ash")
			node.set_surface_override_material(surface,material)
		# Vertex sway/variation may reach outside the source mesh's original bounds.
		node.custom_aabb = box.grow(box.size.length()*0.12)
	for child in node.get_children():
		_shade(child,variant,wind,snow)


func _hide_meshes(node: Node) -> void:
	if node is GeometryInstance3D:
		node.visible = false
	for child in node.get_children():
		_hide_meshes(child)


func _own(node: Node,root: Node) -> void:
	for child in node.get_children():
		child.owner = root
		_own(child,root)
