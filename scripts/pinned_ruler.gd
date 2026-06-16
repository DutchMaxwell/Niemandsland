class_name PinnedRuler
extends Node3D
## A persistent, shared distance ruler dropped on the table by a player (a "pinned"
## measurement). Unlike the transient measure tool in object_manager.gd, it stays until
## removed and is replicated to every player in the OWNER's colour, so the opponent can
## see it — the trust gap that plagues measuring in Tabletop Simulator. Display-only: it
## shows the distance + a line-of-sight 🚫 marker, it never decides or enforces anything.
## Session-only (not saved to .nml), like remote cursors.
##
## The visual deliberately mirrors the measure tool (object_manager._update_measure_line):
## a thin flat BoxMesh line just above the table + a flat Label3D with the inch distance.

# === Constants ===

const LINE_Y: float = 0.005            # line height above the table (matches measure tool)
const LABEL_Y: float = 0.02
const LOS_MARKER_Y: float = 0.08
const LINE_HEIGHT_M: float = 0.001     # 1 mm
const LINE_THICKNESS_M: float = 0.002  # 2 mm
const LABEL_FONT_SIZE: int = 24
const LABEL_PIXEL_SIZE: float = 0.001
const LABEL_OUTLINE: int = 8
const LOS_MARKER_FONT_SIZE: int = 32
const LOS_MARKER_TEXT: String = "🚫"
## A pinned ruler reads slightly brighter than its owner colour so the line stays
## visible against same-coloured units/terrain.
const LINE_EMISSION_ENERGY: float = 1.0
## Minimum length (metres) below which the ruler has nothing to draw.
const MIN_LENGTH_M: float = 0.001

# === Public state (the pinned measurement, frozen at pin time) ===

var id: int = -1
var owner_peer: int = 1
var from_pos: Vector3 = Vector3.ZERO
var to_pos: Vector3 = Vector3.ZERO
var distance_inches: float = 0.0
var blocked: bool = false
var color: Color = Color.WHITE

# === Private variables ===

var _line: MeshInstance3D = null
var _label: Label3D = null
var _los_marker: Label3D = null

# === Public ===

## Freeze a measurement into this ruler and (re)build its visual.
func setup(p_id: int, p_owner: int, p_from: Vector3, p_to: Vector3,
		p_distance_inches: float, p_blocked: bool, p_color: Color) -> void:
	id = p_id
	owner_peer = p_owner
	from_pos = p_from
	to_pos = p_to
	distance_inches = p_distance_inches
	blocked = p_blocked
	color = p_color
	_build_line()
	_build_label()
	_build_los_marker()


## Shortest distance (metres, XZ plane) from a table point to this ruler's segment —
## used by the right-click "remove the ruler under the cursor" hit-test.
func distance_to_point(xz: Vector3) -> float:
	var a := Vector2(from_pos.x, from_pos.z)
	var b := Vector2(to_pos.x, to_pos.z)
	var p := Vector2(xz.x, xz.z)
	var ab := b - a
	var ab_len_sq := ab.length_squared()
	if ab_len_sq < 0.000001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / ab_len_sq, 0.0, 1.0)
	return p.distance_to(a + ab * t)

# === Private ===

func _build_line() -> void:
	if _line == null:
		_line = MeshInstance3D.new()
		_line.name = "RulerLine"
		var line_mat := StandardMaterial3D.new()
		line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		line_mat.no_depth_test = true
		line_mat.render_priority = 0
		_line.material_override = line_mat
		add_child(_line)

	var direction := Vector3(to_pos.x - from_pos.x, 0.0, to_pos.z - from_pos.z)
	var length := direction.length()
	if length < MIN_LENGTH_M:
		_line.visible = false
		return
	_line.visible = true

	var box := BoxMesh.new()
	box.size = Vector3(length, LINE_HEIGHT_M, LINE_THICKNESS_M)
	_line.mesh = box

	var midpoint := (from_pos + to_pos) * 0.5
	midpoint.y = LINE_Y
	_line.global_position = midpoint
	_line.rotation = Vector3(0.0, atan2(direction.x, direction.z) + PI * 0.5, 0.0)

	var mat := _line.material_override as StandardMaterial3D
	if mat:
		mat.albedo_color = color
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = LINE_EMISSION_ENERGY


func _build_label() -> void:
	if _label == null:
		_label = Label3D.new()
		_label.name = "RulerLabel"
		_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED  # align flat with the line
		_label.no_depth_test = true
		_label.render_priority = 1  # on top of the line
		_label.pixel_size = LABEL_PIXEL_SIZE
		_label.font_size = LABEL_FONT_SIZE
		_label.outline_size = LABEL_OUTLINE
		_label.modulate = Color.WHITE
		_label.outline_modulate = Color.BLACK
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(_label)

	var midpoint := (from_pos + to_pos) * 0.5
	_label.global_position = Vector3(midpoint.x, LABEL_Y, midpoint.z)
	_label.text = "%.1f\"" % distance_inches
	var direction := Vector3(to_pos.x - from_pos.x, 0.0, to_pos.z - from_pos.z)
	_label.rotation = Vector3(-PI * 0.5, atan2(direction.x, direction.z), 0.0)


func _build_los_marker() -> void:
	if not blocked:
		if _los_marker:
			_los_marker.visible = false
		return
	if _los_marker == null:
		_los_marker = Label3D.new()
		_los_marker.name = "RulerLosMarker"
		_los_marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_los_marker.no_depth_test = true
		_los_marker.font_size = LOS_MARKER_FONT_SIZE
		_los_marker.modulate = Color.RED
		_los_marker.text = LOS_MARKER_TEXT
		add_child(_los_marker)
	_los_marker.visible = true
	var midpoint := (from_pos + to_pos) * 0.5
	_los_marker.global_position = Vector3(midpoint.x, LOS_MARKER_Y, midpoint.z)
