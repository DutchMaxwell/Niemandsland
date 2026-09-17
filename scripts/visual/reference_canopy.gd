extends RefCounted
## Keep reconstructed branch anatomy while replacing waxy foliage surfaces with
## fine, folded leaf cards. Runs once per reference asset; instances share the mesh.

static func dress(node: Node) -> void:
	if node is MeshInstance3D and node.mesh != null:
		_rebuild(node)
	for child in node.get_children():
		dress(child)


static func _rebuild(instance: MeshInstance3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 170946
	var leaves := SurfaceTool.new()
	leaves.begin(Mesh.PRIMITIVE_TRIANGLES)
	var result := ArrayMesh.new()
	var leaf_count := 0
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
				if rng.randf()<0.078:
					var center := (vertices[a]+vertices[b]+vertices[c])/3.0
					preload("res://scripts/visual/reference_tree.gd")._leaf(leaves,center,rng,0.70)
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
	material.set_shader_parameter("foliage_tint",Vector3(0.91,0.85,0.67))
	leaves.set_material(material)
	leaves.commit(result)
	instance.mesh = result
	print("REFERENCE_CANOPY_LEAVES ",leaf_count)
