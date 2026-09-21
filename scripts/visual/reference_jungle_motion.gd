extends Node3D
## Shared jungle clock and instance-only bending for existing dangerous-terrain plants.

const PROP_SHADER = preload("res://shaders/visual/reference_woody_prop.gdshader")
var _materials: Array[ShaderMaterial] = []


func build(main: Node,presentation: Node3D,understory: Node3D) -> void:
	_materials.append_array(presentation._biome_forest._wind_materials)
	for child in understory.get_children():
		if child is MultiMeshInstance3D and child.name in ["JungleFerns","JungleBroadleaves"]:
			_materials.append(child.multimesh.mesh.surface_get_material(0))
	var plants := 0
	# The overlay records the actual non-overlapping hazard instances at these points.
	for center: Vector2 in main.terrain_overlay._crater_positions:
		for original: Node3D in main.terrain_overlay._object_instances:
			if Vector2(original.position.x,original.position.z).distance_squared_to(center)<0.000001:
				shade_hazard(original,plants)
				plants += 1
				break
	set_time(0.0)
	print("REFERENCE_JUNGLE_MOTION hazards=",plants," materials=",_materials.size())


func set_time(value: float) -> void:
	for material in _materials:
		material.set_shader_parameter("wind_time",value)


func shade_hazard(root: Node3D,index: int) -> void:
	var meshes := root.find_children("*","MeshInstance3D",true,false)
	var bounds := AABB()
	var first := true
	for mesh: MeshInstance3D in meshes:
		var frame: Transform3D = root.global_transform.affine_inverse()*mesh.global_transform
		var box: AABB = frame*mesh.mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	for mesh: MeshInstance3D in meshes:
		var frame: Transform3D = root.global_transform.affine_inverse()*mesh.global_transform
		for surface in mesh.mesh.get_surface_count():
			var source := mesh.get_active_material(surface) as BaseMaterial3D
			if source == null or source.albedo_texture == null:
				continue
			var material := ShaderMaterial.new()
			material.shader = PROP_SHADER
			material.set_shader_parameter("albedo_tex",source.albedo_texture)
			material.set_shader_parameter("albedo_tint",source.albedo_color)
			material.set_shader_parameter("base_roughness",source.roughness)
			material.set_shader_parameter("base_specular",source.metallic_specular)
			material.set_shader_parameter("base_metallic",source.metallic)
			if source.normal_enabled and source.normal_texture != null:
				material.set_shader_parameter("has_normal",true)
				material.set_shader_parameter("normal_tex",source.normal_texture)
			material.set_shader_parameter("tree_bottom",bounds.position.y)
			material.set_shader_parameter("tree_height",bounds.size.y)
			material.set_shader_parameter("wind_to_plant",frame)
			material.set_shader_parameter("jungle_sway",true)
			material.set_shader_parameter("wind_amount",0.026)
			material.set_shader_parameter("wind_phase",float(index)*2.39996)
			mesh.set_surface_override_material(surface,material)
			_materials.append(material)
		# Convert the maximum plant-frame excursion into this mesh's local units.
		var inverse_basis := frame.basis.inverse()
		var reach := bounds.size.y*0.035*(inverse_basis.x.length()+inverse_basis.z.length())
		mesh.custom_aabb = mesh.mesh.get_aabb().grow(reach)
