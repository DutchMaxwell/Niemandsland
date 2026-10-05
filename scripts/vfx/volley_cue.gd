class_name VolleyCue
extends Node3D
## VFX #2: a short tracer per firing model along the RULE sight pair — the eye-to-eye segment the volumetric
## LOS check itself tested (VolumetricLos.eye), never a muzzle ray the rules never saw. The tint names only the
## weapon FAMILY (family_for: name words from a data table, then the rules); anything unknown stays neutral chalk. Full
## form: a slug travels the segment and leaves a fading chalk line. Still form (Performance/Low, Reduce Motion):
## the line alone. No RNG; off unless GraphicsSettings.show_combat_effects (default off until the look GO).

enum Family { NEUTRAL, BALLISTIC, BOW, FLAME, ENERGY, AUTO, ARTILLERY, THROWN, BEAM }   # append only: cues carry the int
const TINTS := [Color(0.93, 0.92, 0.86), Color(1.0, 0.84, 0.52), Color(0.8, 0.66, 0.42), Color(1.0, 0.5, 0.16),
	Color(0.45, 0.9, 1.0), Color(1.0, 0.76, 0.42), Color(0.92, 0.72, 0.5), Color(0.78, 0.72, 0.62), Color(1.0, 0.42, 0.48)]
## Which family a weapon draws is data (assets/vfx/weapon_families.json): name words first, then the rules.
const DATA := "res://assets/vfx/weapon_families.json"
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


static var _table := {}


static func table() -> Dictionary:
	if _table.is_empty() and FileAccess.file_exists(DATA):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA))
		_table = parsed if parsed is Dictionary else {}
	return _table


## The family a weapon NAME names: the first family in the table with a word starting with one of its prefixes or
## ending with one of its suffixes; NEUTRAL when none does.
static func family_of(weapon_name: String) -> Family:
	var words := weapon_name.to_lower().replace("-", " ").split(" ", false)
	for entry: Variant in table().get("families", []):
		if not (entry is Dictionary):
			continue
		var pre: Array = (entry as Dictionary).get("prefixes", [])
		var suf: Array = (entry as Dictionary).get("suffixes", [])
		for w in words:
			if pre.any(func(p: Variant) -> bool: return w.begins_with(str(p))) \
					or suf.any(func(x: Variant) -> bool: return w.ends_with(str(x))):
				return Family.get(str((entry as Dictionary).get("family", "")).to_upper(), Family.NEUTRAL)
	return Family.NEUTRAL


## The family of a shooting profile (ai_shooting's shape: name, attacks, count, blast, indirect): the name first; a
## nameless kind falls to the rules (Indirect or Blast = artillery); a ballistic weapon without Blast and with many
## attacks per copy is a machine gun.
static func family_for(profile: Dictionary) -> Family:
	var f := family_of(str(profile.get("name", "")))
	if f == Family.NEUTRAL and (bool(profile.get("indirect", false)) or int(profile.get("blast", 0)) > 0):
		return Family.ARTILLERY
	var copies := maxi(int(profile.get("count", 1)), 1)
	if f == Family.BALLISTIC and int(profile.get("blast", 0)) <= 0 and int(profile.get("attacks", 0)) >= int(table().get("auto_min_attacks", 4)) * copies:
		return Family.AUTO
	return f


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
