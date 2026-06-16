class_name RangeRingController
extends Node3D
## Per-model, base-anchored range rings ("auras"): a flat coloured ring at a chosen
## distance from a model's base edge, so a player reads 3"/6"/… at a glance without
## laying a ruler. Display-only (shows range, decides/enforces nothing) and LOCAL — not
## synced to other players and not written to the .nml save, exactly like the
## special-weapon rings whose flat-annulus + base-radius + player-colour logic this
## reuses (radial_menu_controller.gd). The ring is parented to the model node, so it
## follows the model automatically — no per-frame tracking.

# === Constants ===

const INCHES_TO_METERS: float = 0.0254
const RING_NODE_NAME: String = "RangeRing"
## The ranges the cycle steps through (inches). Index -1 = off.
const RING_RANGES_INCHES: Array[int] = [3, 6, 9, 12, 18, 24]
## Custom minis without a player_id use this neutral colour.
const NEUTRAL_COLOR: Color = Color(0.6, 0.6, 0.65)
const DEFAULT_BASE_RADIUS_M: float = 0.016  # 32 mm base
const RING_Y: float = 0.005
const RING_SEGMENTS: int = 48
const RING_BAND_M: float = 0.004  # 4 mm visible band
const LABEL_FONT_SIZE: int = 22
const LABEL_PIXEL_SIZE: float = 0.001
const LABEL_OUTLINE: int = 6

# === Private variables ===

var _state: Dictionary = {}  # model_node (Node3D) -> index into RING_RANGES_INCHES (-1 = off)

# === Public: pure logic (unit-tested) ===

## Outer ring radius (metres) = base edge radius + range. Round bases use half the round
## size; oval bases use the averaged radius (same approximation as the special-weapon
## ring). Empty props → the default 32 mm base radius.
func base_radius_for_props(props: Dictionary) -> float:
	var oval_w: float = props.get("base_size_oval_width", 0)
	var oval_l: float = props.get("base_size_oval_length", 0)
	if oval_w > 0 and oval_l > 0:
		return ((oval_w + oval_l) / 4.0) * 0.001
	if props.has("base_size_round"):
		return (float(props["base_size_round"]) / 2.0) * 0.001
	return DEFAULT_BASE_RADIUS_M


func ring_outer_radius_for_props(props: Dictionary, range_inches: int) -> float:
	return base_radius_for_props(props) + float(range_inches) * INCHES_TO_METERS


func color_for_props(props: Dictionary) -> Color:
	if props.has("player_id"):
		return OPRArmyManager.PLAYER_COLORS.get(int(props["player_id"]), NEUTRAL_COLOR)
	return NEUTRAL_COLOR


## Next index in the cycle: off (-1) → 0 → … → last → off.
func cycle_next_index(index: int) -> int:
	var next := index + 1
	return -1 if next >= RING_RANGES_INCHES.size() else next

# === Public: ring management ===

## Advance every given model's ring one step (off → 3 → 6 → … → 24 → off) and rebuild.
func cycle(model_nodes: Array) -> void:
	for node in model_nodes:
		if not (node is Node3D) or not is_instance_valid(node):
			continue
		set_range_for(node, cycle_next_index(_state.get(node, -1)))


## Set a model's ring to a specific range index (-1 = off) and (re)build the visual.
func set_range_for(model_node: Node3D, index: int) -> void:
	if not is_instance_valid(model_node):
		return
	_clear_ring_node(model_node)
	if index < 0 or index >= RING_RANGES_INCHES.size():
		_state.erase(model_node)
		return
	_state[model_node] = index
	_build_ring(model_node, RING_RANGES_INCHES[index])


## Current ring range for a model in inches, or 0 if off.
func current_range_inches(model_node: Node3D) -> int:
	var idx: int = _state.get(model_node, -1)
	return RING_RANGES_INCHES[idx] if idx >= 0 else 0


func clear(model_node: Node3D) -> void:
	_clear_ring_node(model_node)
	_state.erase(model_node)


func clear_all() -> void:
	for node in _state.keys():
		if is_instance_valid(node):
			_clear_ring_node(node)
	_state.clear()


func active_count() -> int:
	return _state.size()

# === Private ===

func _build_ring(model_node: Node3D, range_inches: int) -> void:
	var props := _props_of(model_node)
	var outer := ring_outer_radius_for_props(props, range_inches)
	var inner := maxf(0.001, outer - RING_BAND_M)
	var color := color_for_props(props).lightened(0.25)
	color.a = 0.7

	var root := Node3D.new()
	root.name = RING_NODE_NAME

	var ring := MeshInstance3D.new()
	ring.name = "Ring"
	ring.mesh = _make_flat_ring_mesh(inner, outer, RING_SEGMENTS)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	ring.material_override = mat
	ring.position = Vector3(0, RING_Y, 0)
	root.add_child(ring)

	var label := Label3D.new()
	label.name = "RangeLabel"
	label.text = "%d\"" % range_inches
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED  # always readable regardless of facing
	label.no_depth_test = true
	label.pixel_size = LABEL_PIXEL_SIZE
	label.font_size = LABEL_FONT_SIZE
	label.modulate = Color.WHITE
	label.outline_modulate = Color.BLACK
	label.outline_size = LABEL_OUTLINE
	label.position = Vector3(0, RING_Y + 0.02, outer)  # at the ring's front, lifted a touch
	root.add_child(label)

	model_node.add_child(root)


func _clear_ring_node(model_node: Node3D) -> void:
	if not is_instance_valid(model_node):
		return
	var existing := model_node.get_node_or_null(RING_NODE_NAME)
	if existing:
		existing.free()  # immediate, so a same-call rebuild gets a clean node


## A model node's unit_properties (game_unit meta, or via model_instance.unit), or {}.
func _props_of(model_node: Node3D) -> Dictionary:
	if model_node.has_meta("game_unit"):
		var gu = model_node.get_meta("game_unit")
		if gu is GameUnit and gu.unit_properties != null:
			return gu.unit_properties
	if model_node.has_meta("model_instance"):
		var m = model_node.get_meta("model_instance")
		if m is ModelInstance and m.unit is GameUnit and m.unit.unit_properties != null:
			return m.unit.unit_properties
	return {}


## Flat ring (annulus) mesh in the XZ plane between inner and outer radius. Mirrors
## radial_menu_controller._make_flat_ring_mesh.
func _make_flat_ring_mesh(inner: float, outer: float, segments: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(segments):
		var a0 := TAU * i / segments
		var a1 := TAU * (i + 1) / segments
		var ci0 := Vector3(cos(a0) * inner, 0, sin(a0) * inner)
		var co0 := Vector3(cos(a0) * outer, 0, sin(a0) * outer)
		var ci1 := Vector3(cos(a1) * inner, 0, sin(a1) * inner)
		var co1 := Vector3(cos(a1) * outer, 0, sin(a1) * outer)
		for v in [co0, ci0, ci1, co0, ci1, co1]:
			st.set_normal(Vector3.UP)
			st.add_vertex(v)
	return st.commit()
