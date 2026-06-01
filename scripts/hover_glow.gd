class_name HoverGlow
extends RefCounted
## Applies a non-destructive glowing highlight to the model currently under the
## cursor, so it is unambiguous which object a click will select.
##
## The glow is rendered via [member GeometryInstance3D.material_overlay] on the
## target's MeshInstance3Ds — an extra render pass that never touches the model's
## real materials (so it sidesteps the material-restore bugs the selection ring
## was written to avoid). The overlay is emissive above the environment's HDR
## glow threshold, so with bloom enabled the model actually glows.

# === Constants ===

## Highlight colour (warm gold — distinct from the blue selection ring).
const COLOR: Color = Color(1.0, 0.8, 0.25)
## Emission energy; must exceed the WorldEnvironment glow HDR threshold to bloom.
const EMISSION_ENERGY: float = 2.0
## Overlay tint opacity.
const TINT_ALPHA: float = 0.40
## Outward shell growth for a subtle edge that pops against neighbours (metres).
const GROW_AMOUNT: float = 0.003
## Child nodes with this name (the selection ring) are never glowed.
const SKIP_NODE_NAME: String = "SelectionHighlight"

# === Private variables ===

var _material: StandardMaterial3D = null
var _target: Node3D = null
var _meshes: Array[MeshInstance3D] = []
## Previous material_overlay per mesh, restored on clear (usually null).
var _prev_overlays: Dictionary = {}

# === Lifecycle ===

func _init() -> void:
	_material = _make_material()

# === Public API ===

## The object currently glowing, or null.
func get_target() -> Node3D:
	return _target


## Glows the given object's meshes (pass null to clear). No-op if unchanged.
func set_target(obj: Node3D) -> void:
	if obj == _target:
		return
	clear()
	if obj == null or not is_instance_valid(obj):
		return
	_target = obj
	for mesh: MeshInstance3D in _collect_meshes(obj):
		_prev_overlays[mesh] = mesh.material_overlay
		mesh.material_overlay = _material
		_meshes.append(mesh)


## Removes the glow and restores the previous overlays.
func clear() -> void:
	for mesh: MeshInstance3D in _meshes:
		if is_instance_valid(mesh):
			mesh.material_overlay = _prev_overlays.get(mesh, null)
	_meshes.clear()
	_prev_overlays.clear()
	_target = null

# === Private helpers ===

func _collect_meshes(obj: Node3D) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for node: Node in obj.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh and not _is_skipped(mesh, obj):
			result.append(mesh)
	return result


## True if [param node] lives under a SKIP_NODE_NAME node (up to [param stop]).
func _is_skipped(node: Node, stop: Node) -> bool:
	var current: Node = node
	while current != null and current != stop:
		if current.name == SKIP_NODE_NAME:
			return true
		current = current.get_parent()
	return false


func _make_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(COLOR.r, COLOR.g, COLOR.b, TINT_ALPHA)
	mat.emission_enabled = true
	mat.emission = COLOR
	mat.emission_energy_multiplier = EMISSION_ENERGY
	mat.grow = true
	mat.grow_amount = GROW_AMOUNT
	return mat
