extends RefCounted
## Sparse low sand ribbons following the visual terrain, with quiet gaps between gusts.
## Baked placement avoids the initial miniatures and walls; no particles leave the board.

const Materials = preload("res://scripts/visual/reference_materials.gd")
const SHADER = preload("res://shaders/visual/reference_sand_veil.gdshader")
const WIND := Vector2(0.97, 0.24)


static func build(main: Node, ground: ShaderMaterial, size: Vector2) -> MeshInstance3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2192026
	var units: Array[Vector2] = []
	for model in main.object_manager.get_children():
		if model is Node3D and model.is_in_group("selectable"):
			units.append(Vector2(model.global_position.x, model.global_position.z))
	var walls: Array = main.terrain_overlay.get_wall_segments_world()
	var drifts: PackedVector4Array = ground.get_shader_parameter("drift_points")
	var drift_count: int = ground.get_shader_parameter("drift_count")
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count := 0
	for attempt in 240:
		var center := Vector2(rng.randf_range(-size.x*0.45,size.x*0.45),rng.randf_range(-size.y*0.45,size.y*0.45))
		var length := rng.randf_range(0.10,0.24)
		var width := rng.randf_range(0.008,0.020)
		var angle := WIND.angle() + rng.randf_range(-0.08,0.08)
		var direction := Vector2(cos(angle),sin(angle))
		var crosswind := Vector2(-direction.y,direction.x)
		var clear := true
		# Test the whole ribbon, including its width, not only the emission centre.
		for step in 9:
			var p := center + direction * (float(step)/8.0-0.5)*length
			if absf(p.x)>size.x*0.49 or absf(p.y)>size.y*0.49:
				clear = false
			for unit in units:
				if p.distance_to(unit)<0.040+width:
					clear = false
			for wall: Array in walls:
				if p.distance_to(Geometry2D.get_closest_point_to_segment(p,wall[0],wall[1]))<0.015+width:
					clear = false
		if not clear:
			continue
		var variation := Color(rng.randf(),rng.randf(),rng.randf(),1.0)
		var bend := rng.randf_range(-0.008,0.008)
		for segment in 16:
			for lane in 2:
				for corner: Vector2 in [Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,0),Vector2(1,1),Vector2(0,1)]:
					var u := (float(segment)+corner.x)/16.0
					var v := (float(lane)+corner.y)/2.0
					var taper := sin(u*PI)
					var p := center + direction*(u-0.5)*length + crosswind*((v-0.5)*width*taper+sin(u*TAU)*bend)
					var y := _height(p,walls,drifts,drift_count) + 0.0007 + taper*(1.0-absf(v*2.0-1.0))*0.0022
					st.set_normal(Vector3.UP)
					st.set_uv(Vector2(u,v))
					st.set_color(variation)
					st.add_vertex(Vector3(p.x,y,p.y))
		count += 1
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("sand_tex",ground.get_shader_parameter("meadow_tex"))
	var streams := MeshInstance3D.new()
	streams.name = "SandStreams"
	streams.mesh = st.commit()
	streams.material_override = material
	streams.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	print("REFERENCE_SAND_STREAMS ",count)
	return streams


static func _height(p: Vector2,walls: Array,drifts: PackedVector4Array,drift_count: int) -> float:
	# Same vertex-only relief as the desert ground; the ribbons follow its mounds.
	var height := Materials.ground_height(p)*0.45
	for i in drift_count:
		var point := drifts[i]
		var distance := p.distance_to(Vector2(point.x,point.y))/maxf(point.z,0.0001)
		var mask := 1.0-smoothstep(0.0,1.0,distance)
		height += mask*mask*point.z*0.20
	for wall: Array in walls:
		var distance := p.distance_to(Geometry2D.get_closest_point_to_segment(p,wall[0],wall[1]))
		var mask := 1.0-smoothstep(0.0,0.030,distance)
		height += mask*mask*0.007
	return height
