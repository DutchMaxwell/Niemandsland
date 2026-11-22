class_name BoardgenSurround
extends MeshInstance3D
## The table round the ruin town (plan PLAN_RUINTOWN_TEXTURES step 8, decision D-TEX4 (a)): one plane of board size + 36 in on every side, 2 mm under the table top,
## dark oiled planks fading into the town's dusk sky (shaders/ruintown_surround.gdshader), instead of the navy void that filled three quarters of the start view.
## Honest and not playable: it is the gaming table, never more board. No collider, casts no shadow; the board's child, so it leaves with the board. Visual only.

const MARGIN_IN := 36.0
const DROP_M := 0.002
const SHADER := preload("res://shaders/ruintown_surround.gdshader")


## The surround of `layout` for a table of `table_feet` (its rim, scripts/table.gd, sits 15 mm outside that).
static func make(layout: Dictionary, table_feet: Vector2) -> BoardgenSurround:
	var node := BoardgenSurround.new()
	node.name = "Surround"
	var plane := PlaneMesh.new()
	plane.size = (Vector2(layout["nx"], layout["nz"]) * float(layout["cell_in"]) + Vector2.ONE * MARGIN_IN * 2.0) * BoardgenGreybox.INCHES_TO_METERS
	node.mesh = plane
	node.position.y = -DROP_M
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("plane_half", plane.size * 0.5)
	node.material_override = mat
	node.fit_table(table_feet)
	return node


## The contact shadow follows the table's rim when the table is resized under the board.
func fit_table(table_feet: Vector2) -> void:
	(material_override as ShaderMaterial).set_shader_parameter("table_half", table_feet * 0.3048 * 0.5 + Vector2.ONE * 0.015)
