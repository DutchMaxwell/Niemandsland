extends "res://scripts/visual/reference_jungle.gd"
## Low decorative masonry and pioneer weeds. Native urban props remain untouched.

const CONTACT_WIDTH := 256
const CONTACT_REACH := 0.044
const RELIEF_SCALE := 0.15
const FRAGMENT_RADIUS := 0.71


func build(presentation: Node3D,main: Node,size: Vector2) -> void:
	_presentation = presentation
	_board_size = size
	_rng.seed = 21961
	_walls = main.terrain_overlay.get_wall_segments_world()
	for obj in main.object_manager.get_children():
		if obj is Node3D and obj.is_in_group("selectable"):
			var model: ModelInstance = main.object_manager._object_model_instance(obj)
			var radius := maxf(0.024,VolumetricLos.model_base_radius_m(model)+0.008) if model != null else 0.024
			_exclusions.append(Vector3(obj.global_position.x,obj.global_position.z,radius))
	for obj: Node3D in main.terrain_overlay._object_instances:
		var box: AABB = main.terrain_overlay._model_space_aabb(obj)
		box = obj.get_parent().global_transform*box
		var p := Vector2(box.get_center().x,box.get_center().z)
		_blockers.append(Vector3(p.x,p.y,Vector2(box.size.x,box.size.z).length()*0.5+0.003))
	var mask := _contact_texture()
	for material: ShaderMaterial in [presentation._ground,presentation._base]:
		material.set_shader_parameter("urban_board_size",size)
		material.set_shader_parameter("urban_contact_mask",mask)
	var fragments: Array[Transform3D] = []
	var fragment_colors: Array[Color] = []
	var weeds: Array[Transform3D] = []
	var weed_colors: Array[Color] = []
	for i in int(size.x*size.y*13000):
		var p := Vector2(_rng.randf_range(-size.x*0.5,size.x*0.5),_rng.randf_range(-size.y*0.5,size.y*0.5))
		var contact := contact_amount(p)
		var cluster := smoothstep(0.32,0.72,ReferenceMaterials._noise2(p*42.0))
		var quiet := _unit_quiet(p)
		var islands := ReferenceMaterials._noise2(p*4.0)*0.60+ReferenceMaterials._noise2(p*17.0)*0.25+ReferenceMaterials._noise2(p*73.0)*0.15
		var broken_edge := 1.0-smoothstep(0.015,0.055,absf(islands-0.48))
		if _rng.randf()<(0.015+contact*0.88+broken_edge*0.20)*cluster*quiet:
			var span := _rng.randf_range(0.0018,0.0080)
			if clear_footprint(p,span*FRAGMENT_RADIUS):
				var thickness := span*_rng.randf_range(0.16,0.34)
				var orientation := Basis(Vector3.UP,_rng.randf()*TAU).scaled(Vector3(span,thickness,span))
				fragments.append(Transform3D(orientation,Vector3(p.x,ground_height(p)-0.0001,p.y)))
				var color := Color(0.36,0.35,0.32).lerp(Color(0.62,0.59,0.53),_rng.randf())
				if i%6==0:
					color = Color(0.38,0.22,0.15).lerp(Color(0.55,0.35,0.24),_rng.randf())
				fragment_colors.append(color.srgb_to_linear())
		if _rng.randf()<contact*cluster*0.025*quiet:
			var scale_value := _rng.randf_range(0.55,0.90)
			if clear_footprint(p,0.006*scale_value):
				var orientation := Basis(Vector3.UP,_rng.randf()*TAU).scaled(Vector3.ONE*scale_value)
				weeds.append(Transform3D(orientation,Vector3(p.x,ground_height(p)-0.0001,p.y)))
				weed_colors.append(Color(0.21,0.25,0.11).lerp(Color(0.39,0.39,0.20),_rng.randf()).srgb_to_linear())
	_multimesh("UrbanMasonry",_fragment_mesh(),fragments,fragment_colors)
	_multimesh("UrbanWeeds",_turf_mesh(),weeds,weed_colors)
	print("REFERENCE_URBAN fragments=",fragments.size()," weeds=",weeds.size())


static func ground_height(p: Vector2) -> float:
	return ReferenceMaterials.ground_height(p)*RELIEF_SCALE


func contact_amount(p: Vector2) -> float:
	return 1.0-smoothstep(0.005,CONTACT_REACH,_wall_distance(p))


func _contact_texture() -> ImageTexture:
	var height := maxi(1,roundi(CONTACT_WIDTH*_board_size.y/_board_size.x))
	var image := Image.create(CONTACT_WIDTH,height,false,Image.FORMAT_R8)
	for y in height:
		for x in CONTACT_WIDTH:
			var p := (Vector2((x+0.5)/CONTACT_WIDTH,(y+0.5)/height)-Vector2(0.5,0.5))*_board_size
			var amount := contact_amount(p)
			image.set_pixel(x,y,Color(amount,amount,amount))
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


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
