extends SceneTree
## Read-only, headless validation of exported meshes, packed weights and pose samples.

func _initialize() -> void:
	var report: Array = JSON.parse_string(FileAccess.get_file_as_string(OS.get_cmdline_user_args()[0]))
	var cache := OS.get_cmdline_user_args()[1]
	var errors: Array = []
	for row: Dictionary in report:
		var entry: Dictionary = row.idle
		var mesh := load(cache.path_join(entry.mesh.sha256 + ".res")) as ArrayMesh
		var texture := load(cache.path_join(entry.poses.sha256 + ".res")) as ImageTexture
		var image := texture.get_image()
		if image.get_width() != int(entry.bones) * 3 or image.get_height() != int(entry.frames):
			errors.append(row.key + ": pose dimensions")
			continue
		var changes := 0
		for bone in int(entry.bones):
			if image.get_pixel(bone*3, 0) != image.get_pixel(bone*3, 108):
				changes += 1
		if changes < 10:
			errors.append(row.key + ": no real idle movement")
		var count := 0
		for s in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(s)
			var ids: PackedByteArray = arrays[Mesh.ARRAY_CUSTOM0]
			var weights: PackedByteArray = arrays[Mesh.ARRAY_CUSTOM1]
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			if ids.size() != vertices.size()*4 or weights.size() != ids.size():
				errors.append(row.key + ": attribute sizes")
				continue
			for v in vertices.size():
				var total := 0
				for k in 4:
					if int(ids[v*4+k]) >= int(entry.bones):
						errors.append(row.key + ": joint index")
					total += weights[v*4+k]
				if total < 253 or total > 257:
					errors.append(row.key + ": weight normalization")
			count += vertices.size()
		print("IDLE_PAYLOAD_VALIDATED ", row.key, " vertices=", count, " moving_palette_entries=", changes)
	print("IDLE_VALIDATION_ERRORS ", errors)
	quit(0 if errors.is_empty() else 1)
