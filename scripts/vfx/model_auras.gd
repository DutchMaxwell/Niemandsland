class_name ModelAuras
extends Node3D
## VFX: ambient hero auras, bound to the MODEL — a data table (assets/vfx/model_auras.json) keyed like the model library
## (faction folder / unit name) says which miniature carries which aura, so another hero gets one by adding a line.
## This node finds the miniatures and gives each its aura once; the aura lives under the model node, so it follows it
## and dies with it. Each aura glows softly at its anchor points (hands, staff) — the whole aura on Low and with Reduce
## Motion — and hides while its model is a casualty. Performance: nothing. Off unless
## GraphicsSettings.show_combat_effects, like every combat effect.

const DATA := "res://assets/vfx/model_auras.json"
const SCAN_S := 1.0          # how often new miniatures are looked up

var enabled := true
var force_for_tests := false
var _scan_t := 0.0
static var _table := {}


func _ready() -> void:
	var gs := get_node_or_null("/root/GraphicsSettings")
	enabled = gs != null and gs.get("show_combat_effects") == true


static func table() -> Dictionary:
	if _table.is_empty() and FileAccess.file_exists(DATA):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA))
		_table = (parsed as Dictionary).get("auras", {}) if parsed is Dictionary else {}
	return _table


## The aura spec of a model, or {} — keyed exactly as the model library keys the miniature.
static func spec_for(mi: ModelInstance) -> Dictionary:
	if mi == null or not (mi.unit is GameUnit):
		return {}
	var unit := mi.unit as GameUnit
	return table().get(ModelLibrary.make_key(str(unit.unit_properties.get("faction_folder", "")), unit.get_name()), {})


func _preset() -> int:
	var gs := get_node_or_null("/root/GraphicsSettings")
	return -1 if not enabled or (DisplayServer.get_name() == "headless" and not force_for_tests) \
		else (int(gs.current_preset) if gs != null else 2)


func _process(delta: float) -> void:
	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = SCAN_S
		refresh()


## Give every miniature its aura once.
func refresh() -> void:
	if _preset() <= 0:
		return
	for n in get_tree().get_nodes_in_group("miniature"):
		var mi: Variant = n.get_meta("model_instance") if n.has_meta("model_instance") else null
		if not (mi is ModelInstance) or n.get_node_or_null("ModelAura") != null:
			continue
		var spec := spec_for(mi)
		if spec.get("kind", "") == "lightning":
			var aura := ModelAura.new(mi, spec, self)
			aura.name = "ModelAura"
			(n as Node).add_child(aura)


class ModelAura extends Node3D:
	var mi: ModelInstance
	var spec: Dictionary
	var owner_show: ModelAuras
	var _anchors: Array = []

	func _init(model: ModelInstance, aura_spec: Dictionary, show: ModelAuras) -> void:
		mi = model
		spec = aura_spec
		owner_show = show

	## Anchors are data in base radii (x, z) and model heights (y); each gets a soft additive billboard glow.
	func _ready() -> void:
		var r := VolumetricLos.model_base_radius_m(mi)
		var h := VolumetricLos.height_in_for_base_mm(r * 2000.0) * VolumetricLos.INCHES_TO_METERS
		for a in spec.get("anchors", []):
			_anchors.append(Vector3(float(a[0]) * r, float(a[1]) * h, float(a[2]) * r))
		var t: Array = spec.get("tint", [0.6, 0.9, 1.6])
		var glow := StandardMaterial3D.new()
		glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		glow.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		glow.albedo_color = Color(float(t[0]), float(t[1]), float(t[2])) * 0.45
		var tex := GradientTexture2D.new()
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
		tex.gradient = Gradient.new()
		tex.gradient.set_color(0, Color(1, 1, 1, 1))
		tex.gradient.set_color(1, Color(1, 1, 1, 0))
		glow.albedo_texture = tex
		for p in _anchors:
			var quad := QuadMesh.new()
			quad.size = Vector2(0.014, 0.014)
			var g := MeshInstance3D.new()
			g.mesh = quad
			g.material_override = glow
			g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(g)
			g.position = p

	func _process(_delta: float) -> void:
		var p := owner_show._preset() if is_instance_valid(owner_show) else -1
		visible = mi.is_alive and p > 0
