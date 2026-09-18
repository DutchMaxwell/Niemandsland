extends RefCounted
## Keep reconstructed branch anatomy while replacing waxy foliage surfaces with
## fine, folded leaf cards. Several deterministic crown distributions break the
## repeated spherical density: leaf cards cluster in irregular groups and branch
## voids stay visible. Built once per variant; instances share the meshes.

const VARIANTS := 6


static func dress(node: Node, variant: int = 0) -> void:
	if node is MeshInstance3D and node.mesh != null:
		_rebuild(node, variant)
	for child in node.get_children():
		dress(child, variant)


static func _rebuild(instance: MeshInstance3D, variant: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 170946 + variant * 7919
	var leaves := SurfaceTool.new()
	leaves.begin(Mesh.PRIMITIVE_TRIANGLES)
	var result := ArrayMesh.new()
	var leaf_count := 0
	var box := instance.mesh.get_aabb()
	var crown_center := box.get_center()
	var extent := maxf(maxf(box.size.x,box.size.y),box.size.z)
	# Per-variant group scale, so trees no longer share one statistical envelope.
	var coarse_size := maxf(extent / (4.0 + float(variant % 3)), 0.0001)
	var fine_size := maxf(extent / (9.0 + float(variant % 4)), 0.0001)
	var salt := variant * 97 + 13
	for surface in instance.mesh.get_surface_count():
		var mat := instance.mesh.surface_get_material(surface) as StandardMaterial3D
		if mat == null or mat.albedo_texture == null:
			return
		var source := mat.albedo_texture.get_image()
		if source.is_compressed():
			source.decompress()
		var arrays: Array = instance.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if indices.is_empty():
			for i in vertices.size():
				indices.append(i)
		var wood := SurfaceTool.new()
		wood.begin(Mesh.PRIMITIVE_TRIANGLES)
		var wood_count := 0
		for i in range(0,indices.size(),3):
			var a := indices[i]
			var b := indices[i+1]
			var c := indices[i+2]
			var uv := (uvs[a]+uvs[b]+uvs[c])/3.0
			var color := source.get_pixel(clampi(int(uv.x*source.get_width()),0,source.get_width()-1),clampi(int(uv.y*source.get_height()),0,source.get_height()-1))
			var foliage := color.g > color.r*0.82 and color.b < color.g*0.68
			if foliage:
				var center := (vertices[a]+vertices[b]+vertices[c])/3.0
				var clump := _clump_factor(center,coarse_size,fine_size,salt)
				var detail := _cell_rand(center,fine_size,salt+1)
				var pores := _cell_rand(center,fine_size*0.5,salt+3)
				# Denser near the crown shell, lighter in the core: an irregular edge
				# instead of one uniform ball over every tree.
				var rel := (center-crown_center).length()/maxf(extent*0.5,0.0001)
				var edge := smoothstep(0.55,1.05,rel)
				if rng.randf()<0.32*clump*(0.40+1.10*detail)*(0.55+0.65*pores)*(0.72+0.60*edge):
					var leaf_size := (0.34+0.30*clump)+0.42*detail+rng.randf_range(-0.06,0.09)
					preload("res://scripts/visual/reference_tree.gd")._leaf(leaves,center,rng,leaf_size)
					leaf_count += 1
			else:
				for j in [a,b,c]:
					wood.set_normal(normals[j])
					wood.set_uv(uvs[j])
					wood.add_vertex(vertices[j])
				wood_count += 1
		if wood_count>0:
			var bark: StandardMaterial3D = mat.duplicate()
			bark.metallic = 0.0
			bark.metallic_texture = null
			bark.roughness = 0.94
			bark.roughness_texture = null
			bark.metallic_specular = 0.15
			wood.set_material(bark)
			wood.generate_tangents()
			wood.commit(result)
	if leaf_count == 0:
		return
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/visual/reference_foliage.gdshader")
	material.set_shader_parameter("leaf_tex",preload("res://scripts/visual/reference_materials.gd").texture("res://assets/terrain/reference/hero/leaf.webp"))
	material.set_shader_parameter("textured_leaf",true)
	material.set_shader_parameter("foliage_tint",Vector3(1.0,0.96,0.74))
	leaves.set_material(material)
	leaves.commit(result)
	instance.mesh = result
	print("REFERENCE_CANOPY_LEAVES ",leaf_count," variant=",variant)


static func _clump_factor(point: Vector3,coarse: float,fine: float,salt: int) -> float:
	var clump := smoothstep(0.30,0.70,_cell_rand(point,coarse,salt))
	var grain := smoothstep(0.18,0.82,_cell_rand(point,fine,salt+2))
	return clump*(0.45+0.55*grain)


static func _cell_rand(point: Vector3,size: float,salt: int) -> float:
	var cell := Vector3i(int(floor(point.x/size)),int(floor(point.y/size)),int(floor(point.z/size)))
	var h: int = (cell.x*73856093) ^ (cell.y*19349663) ^ (cell.z*83492791) ^ (salt*2654435761)
	h = h & 0xffffffff
	h = ((h ^ (h >> 16))*0x45d9f3b) & 0xffffffff
	h = h ^ (h >> 16)
	return float(h & 0xffff)/65535.0
