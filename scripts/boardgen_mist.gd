class_name BoardgenMist
extends MultiMeshInstance3D
## Low ground mist over the open floor of a seeded boardgen board: three translucent noise planes between ankle and knee height of a
## 28 mm miniature, drifting at different speeds, thicker over the toxic sumps and in the wells between tiers, absent over raised tiers.
## ONE draw call (a MultiMesh of three planes with one shader). VISUAL ONLY: no collider, no shadow, nothing the rules or the sight
## lines read, and thin enough that a base and a model's feet stay readable from the table camera.

const INCHES_TO_METERS := 0.0254
## Plane heights over the table in inches: ankle, shin, knee.
const LAYER_HEIGHTS_IN: Array[float] = [0.10, 0.24, 0.40]
const MARGIN_IN := 1.0
const SHADER := preload("res://shaders/tiefwerk_mist.gdshader")
const DIRS8: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]


## One RG pair per cell, row by row: R = how thick the mist lies there (0 over a raised tier; open floor 0.35 plus a little for each raised
## neighbour, so a well between tiers fills; a sump and its rim 1), G = how toxic it is (a sump 255, the cells round it 128).
static func density(layout: Dictionary) -> PackedByteArray:
	var nx: int = layout["nx"]
	var nz: int = layout["nz"]
	var cells: Array = layout["cells"]
	var out := PackedByteArray()
	for z in nz:
		for x in nx:
			var me: Dictionary = cells[z * nx + x]
			var raised := 0
			var sump := 0
			for d in DIRS8:
				var o := Vector2i(x, z) + d
				if o.x >= 0 and o.y >= 0 and o.x < nx and o.y < nz:
					var c: Dictionary = cells[o.y * nx + o.x]
					raised += 1 if c["level"] > 0 else 0
					sump += 1 if c["level"] == 0 and c["lot_kind"] == "Hazard" else 0
			var thick := 0.0 if me["level"] > 0 else 0.35 + 0.06 * raised
			var toxic := 0.0
			if me["level"] == 0 and me["lot_kind"] == "Hazard":
				thick = 1.0
				toxic = 1.0
			elif me["level"] == 0 and sump > 0:
				thick = maxf(thick, 0.75)
				toxic = 0.5
			out.append_array([int(round(clampf(thick, 0.0, 1.0) * 255.0)), int(round(toxic * 255.0))])
	return out


func build(layout: Dictionary) -> void:
	var board := Vector2(layout["board_in"][0], layout["board_in"][1])
	var plane := PlaneMesh.new()
	plane.size = (board + Vector2.ONE * MARGIN_IN * 2.0) * INCHES_TO_METERS
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = plane
	mm.instance_count = LAYER_HEIGHTS_IN.size()
	for i in LAYER_HEIGHTS_IN.size():
		mm.set_instance_transform(i, Transform3D(Basis(), Vector3(0.0, LAYER_HEIGHTS_IN[i] * INCHES_TO_METERS, 0.0)))
		mm.set_instance_custom_data(i, Color(float(i), 0.0, 0.0, 0.0))
	multimesh = mm
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("cells", ImageTexture.create_from_image(Image.create_from_data(layout["nx"], layout["nz"], false, Image.FORMAT_RG8, density(layout))))
	mat.set_shader_parameter("board_in", board)
	material_override = mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
