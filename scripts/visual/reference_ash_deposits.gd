extends Node3D
## Visual ash skirts and sheltered wakes, attached to their existing terrain parents.
## World-space construction follows the ground; movable group children follow the group.

const Materials = preload("res://scripts/visual/reference_materials.gd")
const WIND := Vector2(0.93,0.37)
var materials: Array[ShaderMaterial] = []
var _units: Array[Vector2] = []
var _walls: Array = []
var _size := Vector2.ZERO


func prepare(main: Node) -> void:
	_size = main.get_node("Table").table_size*0.3048
	_walls = main.terrain_overlay.get_wall_segments_world()
	for unit in main.object_manager.get_children():
		if unit is Node3D and unit.is_in_group("selectable"):
			_units.append(Vector2(unit.global_position.x,unit.global_position.z))


func add_deposit(anchor: Node3D,radius: float,pool: bool,index: int) -> void:
	var parent := anchor.get_parent() as Node3D
	var center := Vector2(anchor.global_position.x,anchor.global_position.z)
	var grouped := parent.is_in_group("terrain_group_base")
	var inner := radius*0.95 if pool else radius*0.28
	var data := {"center":center,"inner":inner,"pool":pool,"phase":float(index)*2.39996,
		"parent":parent,"grouped":grouped,"floor_y":anchor.global_position.y}
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for segment in 64:
		for ring in 10:
			for corner: Vector2 in [Vector2(0,0),Vector2(1,1),Vector2(1,0),Vector2(0,0),Vector2(0,1),Vector2(1,1)]:
				var angle := (float(segment)+corner.x)/64.0*TAU
				var t := (float(ring)+corner.y)/10.0
				var direction := Vector2(cos(angle),sin(angle))
				var width := _width(direction,data)
				var p := center+direction*(inner+t*width)
				var clear := _clearance(p)
				var y := _floor(p,data)+_mound(t,direction,data)*clear+0.00018
				st.set_uv(p*5.0)
				st.set_color(Color(t,float(index%7)/7.0,0.0,clear))
				st.add_vertex(parent.to_local(Vector3(p.x,y,p.y)))
	st.generate_normals()
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/visual/reference_ash_deposit.gdshader")
	material.set_shader_parameter("ash_tex",Materials.texture("res://assets/terrain/reference/volcanic/fine-ash.webp"))
	var mesh := MeshInstance3D.new()
	mesh.name = "PoolAshDeposit" if pool else "MonolithAshDeposit"
	mesh.mesh = st.commit()
	mesh.material_override = material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mesh)
	_add_stream(data,index)


func _add_stream(data: Dictionary,index: int) -> void:
	var parent: Node3D = data.parent
	var center: Vector2 = data.center
	var crosswind := Vector2(-WIND.y,WIND.x)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Split flow around each obstacle, then sweep across its sheltered ash tail.
	for side: float in [-1.0,1.0]:
		for segment in 24:
			for lane in 4:
				for corner: Vector2 in [Vector2(0,0),Vector2(1,1),Vector2(1,0),Vector2(0,0),Vector2(0,1),Vector2(1,1)]:
					var u := (float(segment)+corner.x)/24.0
					var v := (float(lane)+corner.y)/4.0
					var along := lerpf(-0.024,0.095,u)
					var skirt: float = data.inner+0.010+sin(u*PI)*0.009
					var bend := skirt*(1.0-smoothstep(0.45,1.0,u))
					var p: Vector2 = center+WIND*along+crosswind*(side*bend+(v-0.5)*0.025*sin(u*PI))
					var delta := p-center
					var direction := delta.normalized()
					var t: float = (delta.length()-data.inner)/_width(direction,data)
					var clear := _clearance(p)*smoothstep(data.inner,data.inner+0.003,delta.length())
					var y := _floor(p,data)+_mound(t,direction,data)+0.0012+sin(u*PI)*0.0015
					st.set_normal(parent.global_basis.inverse()*Vector3.UP)
					st.set_uv(Vector2(u,v))
					st.set_color(Color(fmod(float(index)*0.618+side*0.14+1.0,1.0),float(index%5)/5.0,0.0,clear))
					st.add_vertex(parent.to_local(Vector3(p.x,y,p.y)))
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/visual/reference_ash_stream.gdshader")
	materials.append(material)
	var mesh := MeshInstance3D.new()
	mesh.name = "GroundAshFlow"
	mesh.mesh = st.commit()
	mesh.material_override = material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mesh)


static func _width(direction: Vector2,data: Dictionary) -> float:
	var lee := pow(maxf(0.0,direction.dot(WIND)),2.0)
	var angle := direction.angle()
	var irregular: float = 0.85+0.15*sin(angle*3.0+data.phase)+0.11*sin(angle*7.0-data.phase)+0.04*sin(angle*13.0)
	return (0.021+lee*0.040)*irregular


static func _mound(t: float,direction: Vector2,data: Dictionary) -> float:
	if t<0.0 or t>1.0:
		return 0.0
	var lee := maxf(0.0,direction.dot(WIND))
	var height := 0.0034 if data.pool else 0.006
	return sin(pow(t,0.65)*PI)*pow(1.0-t,1.2)*height*(0.70+lee*0.70)


static func _floor(p: Vector2,data: Dictionary) -> float:
	return float(data.floor_y) if data.grouped else Materials.ground_height(p)


func _clearance(p: Vector2) -> float:
	var amount := 1.0-smoothstep(0.0,0.005,maxf(absf(p.x)-_size.x*0.49,absf(p.y)-_size.y*0.49))
	for unit in _units:
		amount *= smoothstep(0.025,0.040,p.distance_to(unit))
	for wall: Array in _walls:
		amount *= smoothstep(0.003,0.009,p.distance_to(Geometry2D.get_closest_point_to_segment(p,wall[0],wall[1])))
	return amount
