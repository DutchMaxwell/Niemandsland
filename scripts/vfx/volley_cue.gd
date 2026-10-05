class_name VolleyCue
extends Node3D
## VFX #2: a short tracer per firing model along the RULE sight pair — the eye-to-eye segment the volumetric
## LOS check itself tested (VolumetricLos.eye), never a muzzle ray the rules never saw. The tint names only the
## weapon FAMILY from its name (bow / flame / energy / ballistic); anything unknown stays neutral chalk. Full
## form: a slug travels the segment and leaves a fading chalk line. Still form (Performance/Low, Reduce Motion):
## the line alone. No RNG; off unless GraphicsSettings.show_combat_effects (default off until the look GO).

enum Family { NEUTRAL, BALLISTIC, BOW, FLAME, ENERGY }
const TINTS := [Color(0.93, 0.92, 0.86), Color(1.0, 0.84, 0.52), Color(0.8, 0.66, 0.42), Color(1.0, 0.5, 0.16),
	Color(0.45, 0.9, 1.0)]
## Word prefixes (and a few suffixes: "Longbow", "Machinegun", "Autocannon") per family, in this order.
const WORDS := [[Family.FLAME, ["flame", "inferno", "pyro", "incinerat", "burn"], []],
	[Family.ENERGY, ["las", "plasma", "beam", "fusion", "melta", "lightning", "energy", "tesla", "gauss",
		"photon", "disintegrat"], []],
	[Family.BOW, ["bow", "crossbow", "sling", "javelin", "arrow", "dart", "throwing"], ["bow"]],
	[Family.BALLISTIC, ["rifle", "gun", "shotgun", "pistol", "carbine", "cannon", "musket", "sniper",
		"blunderbuss", "launcher"], ["gun", "cannon"]]]
const LINE_R := 0.0009
const SLUG_R := 0.0016
const TRAVEL_S := 0.22
const LINGER_S := 0.6
const STAGGER_S := 0.03
const MAX_LIVE := 24

var enabled: bool = true
var force_for_tests: bool = false


func _ready() -> void:
	var gs := get_node_or_null("/root/GraphicsSettings")
	enabled = gs != null and gs.get("show_combat_effects") == true


static func family_of(weapon_name: String) -> Family:
	var words := weapon_name.to_lower().replace("-", " ").split(" ", false)
	for entry in WORDS:
		for w in words:
			if (entry[1] as Array).any(func(p: String) -> bool: return w.begins_with(p)) \
					or (entry[2] as Array).any(func(x: String) -> bool: return w.ends_with(x)):
				return entry[0]
	return Family.NEUTRAL


## One tracer per [from_eye, to_eye] pair; returns how many were drawn.
func fire(pairs: Array, family: Family) -> int:
	if not enabled or (DisplayServer.get_name() == "headless" and not force_for_tests):
		return 0
	var gs := get_node_or_null("/root/GraphicsSettings")
	var still: bool = UiMotion.reduced() or (int(gs.current_preset) if gs != null else 2) <= 1   # Performance / Low
	var n := 0
	for pair in pairs:
		while get_child_count() > MAX_LIVE - 2:   # room for the line AND its slug
			var oldest := get_child(0)
			remove_child(oldest)
			oldest.queue_free()
		var line := _segment(pair[0], pair[1], LINE_R, TINTS[family])
		var tw := line.create_tween()
		tw.tween_interval(n * STAGGER_S + (0.0 if still else TRAVEL_S))
		tw.tween_property(line, "transparency", 1.0, LINGER_S)
		tw.tween_callback(line.queue_free)
		if not still:
			var dir: Vector3 = (pair[1] - pair[0]).normalized()
			var slug_len := minf(0.05, (pair[1] - pair[0]).length() * 0.3)
			var slug := _segment(pair[0], pair[0] + dir * slug_len, SLUG_R, TINTS[family].lightened(0.3))
			var tm := slug.create_tween()
			tm.tween_interval(n * STAGGER_S)
			tm.tween_property(slug, "global_position", pair[1] - dir * slug_len * 0.5, TRAVEL_S)
			tm.tween_callback(slug.queue_free)
		n += 1
	return n


## One shared unit cylinder and one material per tint: a burst used to build a mesh + material per tracer
## (measured ~+0.35 ms GPU p50 on Medium for a 10-model volley every 0.8 s). The length and radius ride the
## transform's scale; the fade rides GeometryInstance3D.transparency, so nothing per-tracer is uploaded.
static var _unit_cylinder: CylinderMesh
static var _materials := {}


func _segment(a: Vector3, b: Vector3, r: float, tint: Color) -> MeshInstance3D:
	if _unit_cylinder == null:
		_unit_cylinder = CylinderMesh.new()
		_unit_cylinder.top_radius = 1.0
		_unit_cylinder.bottom_radius = 1.0
		_unit_cylinder.height = 1.0
		_unit_cylinder.radial_segments = 6
		_unit_cylinder.rings = 1
	if not _materials.has(tint):
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = tint
		_materials[tint] = mat
	var seg := MeshInstance3D.new()
	seg.mesh = _unit_cylinder
	seg.material_override = _materials[tint]
	seg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(seg)
	var dir := (b - a).normalized()
	var basis := Basis(Quaternion(Vector3.UP, dir)) if dir.length() > 0.5 else Basis()
	seg.global_transform = Transform3D(basis.scaled_local(Vector3(r, maxf(a.distance_to(b), 0.001), r)), (a + b) * 0.5)
	return seg
