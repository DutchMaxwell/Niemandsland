extends Node3D
## Visual-only crater treatment and bounded volcanic atmosphere; no hazard relocation.

var _materials: Array[ShaderMaterial] = []


func build(main: Node,presentation: Node3D) -> void:
	var deposits := preload("res://scripts/visual/reference_ash_deposits.gd").new()
	add_child(deposits)
	deposits.prepare(main)
	var craters := 0
	for original: Node3D in main.terrain_overlay._object_instances:
		var lights := original.find_children("*","OmniLight3D",true,false)
		if lights.is_empty():
			continue
		# The volcanic overlay attaches a local glow light only to existing lava props.
		deposits.add_deposit(original,0.03048,true,craters)
		_shade_lava(original)
		for light: OmniLight3D in lights:
			light.light_energy = 0.16
			light.omni_range = 0.10
		var heat := MeshInstance3D.new()
		heat.name = "CraterHeatShimmer"
		var quad := QuadMesh.new()
		quad.size = Vector2(0.046,0.028)
		heat.mesh = quad
		var material := ShaderMaterial.new()
		material.shader = preload("res://shaders/visual/reference_heat.gdshader")
		heat.material_override = material
		heat.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		original.add_child(heat)
		heat.position.y = 0.022
		_materials.append(material)
		craters += 1
	var monoliths := 0
	for monolith: Node3D in get_tree().get_nodes_in_group("reference_volcanic_monolith"):
		var bounds: AABB = main.terrain_overlay._model_space_aabb(monolith)
		var radius := clampf(maxf(bounds.size.x,bounds.size.z)*0.42,0.006,0.028)
		deposits.add_deposit(monolith,radius,false,craters+monoliths)
		monoliths += 1
	_materials.append_array(deposits.materials)
	var size: Vector2 = main.get_node("Table").table_size*0.3048
	var rng := RandomNumberGenerator.new()
	rng.seed = 21926
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var flake := QuadMesh.new()
	flake.size = Vector2(0.0010,0.0006)
	mm.mesh = flake
	mm.instance_count = 480
	for i in mm.instance_count:
		mm.set_instance_transform(i,Transform3D(Basis.IDENTITY,Vector3(rng.randf_range(-size.x*0.45,size.x*0.45),0.0,rng.randf_range(-size.y*0.45,size.y*0.45))))
		mm.set_instance_custom_data(i,Color(rng.randf(),rng.randf(),0.0,1.0))
	var ash := MultiMeshInstance3D.new()
	ash.name = "SparseVolcanicAsh"
	ash.multimesh = mm
	ash.custom_aabb = AABB(Vector3(-size.x*0.5,-0.01,-size.y*0.5),Vector3(size.x,0.08,size.y))
	ash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ash_material := ShaderMaterial.new()
	ash_material.shader = preload("res://shaders/visual/reference_ash.gdshader")
	ash_material.set_shader_parameter("board_size",size*0.90)
	ash.material_override = ash_material
	main.get_node("Table/TableMesh").add_child(ash)
	_materials.append(ash_material)
	# Movable volcanic woodland floors use the same cool ground without mesh displacement.
	for group in get_tree().get_nodes_in_group("terrain_group_base"):
		if group.biome_prefix == "volcanic_" and is_instance_valid(group._floor_mesh):
			var ground: ShaderMaterial = presentation._ground.duplicate()
			ground.set_shader_parameter("surface_relief",false)
			ground.set_shader_parameter("woody_ground_enabled",false)
			group._floor_mesh.material_override = ground
	print("REFERENCE_VOLCANIC_EFFECTS craters=",craters," monoliths=",monoliths," deposits=",craters+monoliths," ash=",mm.instance_count)


func set_time(value: float) -> void:
	for material in _materials:
		material.set_shader_parameter("time",value)


func _shade_lava(node: Node) -> void:
	if node is MeshInstance3D and node.mesh != null:
		for surface in node.mesh.get_surface_count():
			var source := node.get_active_material(surface) as BaseMaterial3D
			if source == null or source.albedo_texture == null:
				continue
			var material := ShaderMaterial.new()
			material.shader = preload("res://shaders/visual/reference_lava.gdshader")
			material.set_shader_parameter("albedo_tex",source.albedo_texture)
			node.set_surface_override_material(surface,material)
			_materials.append(material)
	for child in node.get_children():
		_shade_lava(child)
