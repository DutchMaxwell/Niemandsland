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
## A raised tier is drawn at this thickness: the planes lie inside its block so none of it shows, but the texture is filtered, so the mist
## thickens towards a wall instead of thinning out (pooling along the walls).
const WALL_HALO := 0.65
const SHADER := preload("res://shaders/tiefwerk_mist.gdshader")
const DIRS8: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]


## One RG pair per cell, row by row: R = how thick the mist lies there (WALL_HALO over a raised tier; open floor only 0.14, so a street keeps wisps
## with clear gaps; +0.22 for each wall it touches and a little for each diagonal one, so mist pools along walls and in wells between
## tiers; a sump and its rim 0.8 to 1; the floor cell in front of a steam vent at least 0.75), G = how toxic it is (a sump 255, the cells
## round it 128).
static func density(layout: Dictionary, vent_cells: Array = []) -> PackedByteArray:
	var nx: int = layout["nx"]
	var nz: int = layout["nz"]
	var cells: Array = layout["cells"]
	var out := PackedByteArray()
	for z in nz:
		for x in nx:
			var me: Dictionary = cells[z * nx + x]
			var raised := 0
			var walled := 0
			var sump := 0
			for d in DIRS8:
				var o := Vector2i(x, z) + d
				if o.x >= 0 and o.y >= 0 and o.x < nx and o.y < nz:
					var c: Dictionary = cells[o.y * nx + o.x]
					raised += 1 if c["level"] > 0 else 0
					walled += 1 if c["level"] > 0 and (d.x == 0 or d.y == 0) else 0
					sump += 1 if c["level"] == 0 and c["lot_kind"] == "Hazard" else 0
			var thick := WALL_HALO if me["level"] > 0 else 0.14 + 0.22 * walled + 0.04 * (raised - walled)
			thick = maxf(thick, 0.75) if vent_cells.has(Vector2i(x, z)) else thick
			var toxic := 0.0
			if me["level"] == 0 and me["lot_kind"] == "Hazard":
				thick = 1.0
				toxic = 1.0
			elif me["level"] == 0 and sump > 0:
				thick = maxf(thick, 0.8)
				toxic = 0.5
			out.append_array([int(round(clampf(thick, 0.0, 1.0) * 255.0)), int(round(toxic * 255.0))])
	return out


func build(layout: Dictionary) -> void:
	var board := Vector2(layout["nx"], layout["nz"]) * float(layout["cell_in"])   # (a layout without board_in works too)
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
	mat.set_shader_parameter("cells", ImageTexture.create_from_image(Image.create_from_data(layout["nx"], layout["nz"], false, Image.FORMAT_RG8, density(layout, BoardgenSteam.vents(layout).map(func(v: Dictionary) -> Vector2i: return v["cell"])))))
	mat.set_shader_parameter("board_in", board)
	mat.set_shader_parameter("sump_only", 1.0)   # (LOOK5 F4r') the ground fog veils the board; the mist stays as the green shimmer over the sumps
	material_override = mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
