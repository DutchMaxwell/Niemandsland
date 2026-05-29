extends RefCounted
class_name TerrainHologram
## Shared holographic material factory for procedural terrain props.
##
## Walls, trees, containers and dangerous hazards all render with the pale-blue
## transparent hologram look. A real texture can be layered on later by assigning
## the `albedo_tex` shader parameter and raising `texture_mix` toward 1.0.

# ==============================================================================
# CONSTANTS
# ==============================================================================

const SHADER_PATH := "res://assets/shaders/hologram.gdshader"

## Default pale-blue hologram tint.
const HOLOGRAM_COLOR := Color(0.5, 0.75, 1.0, 1.0)

# ==============================================================================
# STATE
# ==============================================================================

## Cached shader resource (loaded once, shared across all materials).
static var _shader: Shader = null

# ==============================================================================
# PUBLIC
# ==============================================================================

## Build a fresh holographic ShaderMaterial. Each prop gets its own instance so a
## texture can be applied per-piece later without affecting the others.
static func make_material(tint: Color = HOLOGRAM_COLOR) -> ShaderMaterial:
	if _shader == null:
		_shader = load(SHADER_PATH)
	var material := ShaderMaterial.new()
	material.shader = _shader
	material.set_shader_parameter("hologram_color", tint)
	return material
