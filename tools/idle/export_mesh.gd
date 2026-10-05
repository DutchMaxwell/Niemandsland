extends RefCounted
## Pack real bound vertices into shared GPU joint/weight attributes.

static func pack(records: Array, job: Dictionary) -> Dictionary:
	var output_mesh := ArrayMesh.new()
	var material_entries: Array = []
	var flags := (Mesh.ARRAY_CUSTOM_RGBA8_UNORM << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) | (Mesh.ARRAY_CUSTOM_RGBA8_UNORM << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT) | Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES
	# Keep CPU arrays for a measured animation envelope over every sampled frame.
	var points: Array = []
	for record: Dictionary in records:
		var mi: MeshInstance3D = record.mi
		var frame: Transform3D = record.frame
		for s in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(s)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT] if arrays[Mesh.ARRAY_TANGENT] != null else PackedFloat32Array()
			var ids := PackedByteArray()
			var weights := PackedByteArray()
			ids.resize(vertices.size() * 4)
			weights.resize(vertices.size() * 4)
			var source_ids: PackedInt32Array = arrays[Mesh.ARRAY_BONES] if arrays[Mesh.ARRAY_BONES] != null else PackedInt32Array()
			var source_weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS] if arrays[Mesh.ARRAY_WEIGHTS] != null else PackedFloat32Array()
			if mi.skin != null and source_ids.size() != vertices.size() * 4:
				push_error("Expected four real joint weights per vertex")
				return {}
			for v in vertices.size():
				vertices[v] = frame * vertices[v]
				normals[v] = (frame.basis.inverse().transposed() * normals[v]).normalized()
				if tangents.size() == vertices.size() * 4:
					var tangent := (frame.basis * Vector3(tangents[v*4], tangents[v*4+1], tangents[v*4+2])).normalized()
					tangents[v*4] = tangent.x
					tangents[v*4+1] = tangent.y
					tangents[v*4+2] = tangent.z
				for k in 4:
					ids[v*4+k] = record.offset + (source_ids[v*4+k] if mi.skin != null else 0)
					weights[v*4+k] = clampi(roundi(source_weights[v*4+k] * 255.0), 0, 255) if mi.skin != null else (255 if k == 0 else 0)
			arrays[Mesh.ARRAY_VERTEX] = vertices
			arrays[Mesh.ARRAY_NORMAL] = normals
			arrays[Mesh.ARRAY_TANGENT] = tangents if not tangents.is_empty() else null
			arrays[Mesh.ARRAY_BONES] = null
			arrays[Mesh.ARRAY_WEIGHTS] = null
			arrays[Mesh.ARRAY_CUSTOM0] = ids
			arrays[Mesh.ARRAY_CUSTOM1] = weights
			output_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
			var material := mi.mesh.surface_get_material(s).duplicate() as StandardMaterial3D
			if material.albedo_texture != null:
				if not job.materials_by_name.has(material.resource_name):
					push_error("No ctex material for " + material.resource_name)
					return {}
				var texture_entry: Dictionary = job.materials_by_name[material.resource_name].duplicate(true)
				texture_entry.surface = output_mesh.get_surface_count()-1
				material_entries.append(texture_entry)
			material.albedo_texture = null
			material.normal_texture = null
			material.normal_enabled = false
			material.ao_texture = null
			material.emission_texture = null
			material.metallic = 0.0
			material.roughness = 0.7
			material.metallic_texture = null
			material.roughness_texture = null
			material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
			output_mesh.surface_set_material(output_mesh.get_surface_count()-1, material)
			var box := AABB(vertices[0], Vector3.ZERO)
			for vertex in vertices:
				box = box.expand(vertex)
			var used := {}
			for i in ids.size():
				if weights[i] > 0:
					used[int(ids[i])] = true
			points.append({"box": box, "used": used})
	return {"mesh": output_mesh, "materials": material_entries, "points": points}

static func save(output_mesh: ArrayMesh, image: Image, bounds: AABB, bones: int, material_entries: Array, job: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(job.out)
	var mesh_path: String = str(job.out).path_join("mesh.res")
	var pose_path: String = str(job.out).path_join("poses.res")
	var mesh_error := ResourceSaver.save(output_mesh, mesh_path, ResourceSaver.FLAG_COMPRESS)
	var pose_error := ResourceSaver.save(ImageTexture.create_from_image(image), pose_path, ResourceSaver.FLAG_COMPRESS)
	if mesh_error != OK or pose_error != OK:
		return false
	var entry := {"version": 1, "godot_version": "4.6", "frames": 216, "fps": 24.0,
		"bones": bones, "materials": material_entries, "bounds": [bounds.position.x, bounds.position.y, bounds.position.z, bounds.size.x, bounds.size.y, bounds.size.z],
		"source_sha256": FileAccess.get_sha256(job.source), "recipe": job.recipe,
		"tail_bones": job.tail_bones, "twohand": job.twohand}
	for pair in [["mesh", mesh_path], ["poses", pose_path]]:
		var sha := FileAccess.get_sha256(pair[1])
		var dest: String = str(job.out).path_join(sha + ".res")
		DirAccess.rename_absolute(pair[1], dest)
		entry[pair[0]] = {"sha256": sha, "url": dest, "size": FileAccess.get_file_as_bytes(dest).size()}
	var file := FileAccess.open(str(job.out).path_join("idle.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(entry, "  "))
	return true
