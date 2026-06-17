class_name MovementRangeController
extends Node3D
## Per-model movement reach indicator: two flat, base-anchored rings showing how far a
## model may move this turn — the inner Advance band and the outer Rush/Charge band — so a
## player can eyeball reach without a ruler. Display-only (shows reach, decides/enforces
## NOTHING — it never moves the model) and LOCAL: not synced to other players and not
## written to the .nml save, exactly like the base-anchored range rings whose flat-annulus +
## base-radius + player-colour logic this reuses. Each indicator is parented to the model
## node, so it follows the model automatically — no per-frame tracking.
##
## OPR core movement (Grimdark Future / Age of Fantasy): Advance = 6", Rush/Charge = 12".
## The "Fast" special rule adds +2"/+4" and "Slow" subtracts -2"/-4" (Advance / Rush+Charge);
## both are read from the unit's special_rules so the bands match the actual unit.

# === Constants ===

const INCHES_TO_METERS: float = 0.0254
const ROOT_NODE_NAME: String = "MovementRange"
## Custom minis without a player_id use this neutral colour.
const NEUTRAL_COLOR: Color = Color(0.6, 0.6, 0.65)
const DEFAULT_BASE_RADIUS_M: float = 0.016  # 32 mm base

## OPR core move distances (inches). See class doc for the OPR reference.
const OPR_ADVANCE_INCHES: int = 6
const OPR_RUSH_CHARGE_INCHES: int = 12
## OPR "Fast": +2" Advance, +4" Rush/Charge. "Slow": the same magnitudes, subtracted.
const FAST_ADVANCE_BONUS: int = 2
const FAST_RUSH_BONUS: int = 4

const RING_Y: float = 0.004
const RING_SEGMENTS: int = 48
const RING_BAND_M: float = 0.004  # 4 mm visible band
const ADVANCE_ALPHA: float = 0.85
const RUSH_ALPHA: float = 0.4     # outer band dimmer so the two read apart
const LABEL_FONT_SIZE: int = 20
const LABEL_PIXEL_SIZE: float = 0.001
const LABEL_OUTLINE: int = 6

# === Private variables ===

var _active: Dictionary = {}  # model_node (Node3D) -> true while its indicator is shown

# === Public: pure logic (unit-tested) ===

## Base edge radius (metres) for a unit's props — round bases use half the round size, oval
## bases the averaged radius (same approximation as the range rings); empty props → 32 mm.
func base_radius_for_props(props: Dictionary) -> float:
	if props.get("base_is_oval", false) or props.get("base_is_square", false):
		var w: float = float(props.get("base_width_mm", 0))
		var d: float = float(props.get("base_depth_mm", 0))
		if w > 0.0 and d > 0.0:
			return ((w + d) / 4.0) * 0.001
	if props.has("base_size_round"):
		return (float(props["base_size_round"]) / 2.0) * 0.001
	return DEFAULT_BASE_RADIUS_M


## The Advance + Rush/Charge distances (inches) for a unit, applying the OPR Fast / Slow
## special rules. Returns {"advance": int, "rush": int}. A unit is never both Fast and Slow.
func move_bands_for_props(props: Dictionary) -> Dictionary:
	var advance := OPR_ADVANCE_INCHES
	var rush := OPR_RUSH_CHARGE_INCHES
	var rules: Array = props.get("special_rules", [])
	if _has_rule(rules, "Fast"):
		advance += FAST_ADVANCE_BONUS
		rush += FAST_RUSH_BONUS
	elif _has_rule(rules, "Slow"):
		advance -= FAST_ADVANCE_BONUS
		rush -= FAST_RUSH_BONUS
	return {"advance": advance, "rush": rush}


## Outer radius (metres) of a band = base edge radius + the band distance.
func band_radius_for_props(props: Dictionary, band_inches: int) -> float:
	return base_radius_for_props(props) + float(band_inches) * INCHES_TO_METERS


func color_for_props(props: Dictionary) -> Color:
	if props.has("player_id"):
		return OPRArmyManager.PLAYER_COLORS.get(int(props["player_id"]), NEUTRAL_COLOR)
	return NEUTRAL_COLOR


func _has_rule(rules: Array, rule_name: String) -> bool:
	for r in rules:
		if str(r) == rule_name:
			return true
	return false

# === Public: indicator management ===

## Toggle the movement indicator on each given model (shown ⇄ hidden), independently.
func toggle(model_nodes: Array) -> void:
	for node in model_nodes:
		if not (node is Node3D) or not is_instance_valid(node):
			continue
		if _active.has(node):
			clear(node)
		else:
			_build_indicator(node)
			_active[node] = true


func is_active(model_node: Node3D) -> bool:
	return _active.has(model_node)


func clear(model_node: Node3D) -> void:
	_clear_node(model_node)
	_active.erase(model_node)


func clear_all() -> void:
	for node in _active.keys():
		if is_instance_valid(node):
			_clear_node(node)
	_active.clear()


func active_count() -> int:
	return _active.size()

# === Private ===

func _build_indicator(model_node: Node3D) -> void:
	var props := _props_of(model_node)
	var bands := move_bands_for_props(props)
	var base_color := color_for_props(props)

	var root := Node3D.new()
	root.name = ROOT_NODE_NAME
	# Outer (Rush/Charge) first so the inner Advance band draws on top of it.
	_add_band(root, props, int(bands["rush"]), base_color, RUSH_ALPHA, "Rush/Charge")
	_add_band(root, props, int(bands["advance"]), base_color, ADVANCE_ALPHA, "Advance")
	model_node.add_child(root)


func _add_band(root: Node3D, props: Dictionary, dist_inches: int, base_color: Color,
		alpha: float, tag: String) -> void:
	var outer := band_radius_for_props(props, dist_inches)
	var inner := maxf(0.001, outer - RING_BAND_M)
	var color := base_color.lightened(0.2)
	color.a = alpha

	var ring := MeshInstance3D.new()
	ring.name = "%sRing" % tag.replace("/", "")
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
	label.name = "%sLabel" % tag.replace("/", "")
	label.text = "%s %d\"" % [tag, dist_inches]
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.pixel_size = LABEL_PIXEL_SIZE
	label.font_size = LABEL_FONT_SIZE
	label.modulate = Color.WHITE
	label.outline_modulate = Color.BLACK
	label.outline_size = LABEL_OUTLINE
	label.position = Vector3(0, RING_Y + 0.02, outer)
	root.add_child(label)


func _clear_node(model_node: Node3D) -> void:
	if not is_instance_valid(model_node):
		return
	var existing := model_node.get_node_or_null(ROOT_NODE_NAME)
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


## Flat ring (annulus) mesh in the XZ plane between inner and outer radius.
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
