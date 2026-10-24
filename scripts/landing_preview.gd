class_name LandingPreview
extends Node3D
## Automodus preview display: one translucent disc per model landing and one line per shooting
## pair. Display-only and local (never synced), like PickupGhostController. No physics bodies,
## so a ray-pick can never hit a ghost.
##
## show_preview(landing, lines): landing = [{pos: Vector3, radius_m: float}, ...],
## lines = [{from: Vector3, to: Vector3}, ...]. Each call REPLACES the earlier set.

const GHOST_COLOR := Color(0.3, 0.9, 0.4, 0.35)
const LINE_COLOR := Color(0.2, 0.9, 0.3)
const GHOST_HEIGHT_M := 0.002

var _root: Node3D = null
var _ghosts := 0
var _lines := 0


func show_preview(landing: Array, lines: Array) -> void:
	clear()
	_root = Node3D.new()
	_root.name = "LandingPreviewRoot"
	add_child(_root)
	for entry in landing:
		var pos: Vector3 = entry.get("pos", Vector3.ZERO)
		var disc := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = float(entry.get("radius_m", 0.0125))
		mesh.bottom_radius = mesh.top_radius
		mesh.height = GHOST_HEIGHT_M
		disc.mesh = mesh
		disc.material_override = _material(GHOST_COLOR, false)
		disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_root.add_child(disc)
		disc.global_position = pos
		_ghosts += 1
	if not lines.is_empty():
		var im := ImmediateMesh.new()
		im.surface_begin(Mesh.PRIMITIVE_LINES)
		for pair in lines:
			im.surface_add_vertex(pair.get("from", Vector3.ZERO))
			im.surface_add_vertex(pair.get("to", Vector3.ZERO))
			_lines += 1
		im.surface_end()
		var mi := MeshInstance3D.new()
		mi.mesh = im
		mi.material_override = _material(LINE_COLOR, true)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_root.add_child(mi)


## Detached at once so a re-show in the same frame never displays two sets.
func clear() -> void:
	if _root != null and is_instance_valid(_root):
		remove_child(_root)
		_root.queue_free()
	_root = null
	_ghosts = 0
	_lines = 0


func ghost_count() -> int:
	return _ghosts


func line_count() -> int:
	return _lines


func _material(color: Color, on_top: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.no_depth_test = on_top
	if color.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m
