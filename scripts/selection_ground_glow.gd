class_name SelectionGroundGlow
extends Node3D
## A flat, pulsing, player-coloured halo cast on the ground under a selected
## miniature — the headline selection feedback for the AAA 3D overhaul.
##
## Added as a child of the selected wrapper (which has identity scale; the model
## scale lives on inner nodes), so it follows the mini when it is dragged without
## any per-frame script cost — the pulse is driven entirely by TIME in the shader.

# === Constants ===

const SHADER: Shader = preload("res://shaders/selection_ground_glow.gdshader")
## Child node name so object_manager can find/free the halo on deselect.
const NODE_NAME: StringName = &"SelectionGroundGlow"
## Lift above the base to avoid z-fighting with the ground/base (metres).
const Y_OFFSET: float = 0.004
## Halo radius relative to the object footprint (a touch wider than the base).
const RADIUS_MARGIN: float = 1.4
## Mesh group that the selection/hover model glow skips, so it never tints the halo.
const OVERLAY_GROUP: StringName = &"selection_overlay"
## Fallback colour for selectables with no player (dice, terrain, custom props).
const NEUTRAL_COLOR: Color = Color(0.45, 0.85, 1.0)

# === Private variables ===

var _mesh: MeshInstance3D = null

# === Public API ===

## Build the halo sized to a `footprint_radius` (metres) in `player_color`.
func setup(player_color: Color, footprint_radius: float) -> void:
	name = NODE_NAME
	var diameter: float = maxf(footprint_radius, 0.01) * 2.0 * RADIUS_MARGIN

	var plane := PlaneMesh.new()
	plane.size = Vector2(diameter, diameter)

	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("glow_color", player_color)

	_mesh = MeshInstance3D.new()
	_mesh.mesh = plane
	_mesh.material_override = mat
	_mesh.position.y = Y_OFFSET
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh.add_to_group(OVERLAY_GROUP)
	add_child(_mesh)
