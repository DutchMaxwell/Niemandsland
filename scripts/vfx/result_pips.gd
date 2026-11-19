class_name ResultPips
extends Node3D
## VFX #1: marks AT the models a resolved attack touched — depth-tested base-rim arcs (y = 2 mm) plus one compact
## floating unit summary badge (+45 mm) and a 0.10 s Fresnel rim-flash on the struck miniature's mesh. Never hides
## which model was hit (0% torso occlusion); still/static form on Performance/Low and Reduce Motion. Read off the
## resolver's own allocation, never rolled or written back, no RNG.

enum Kind { WOUND, KILL, HIT, SAVE }
const COLORS := [Color(1.0, 0.76, 0.14), Color(0.76, 0.08, 0.10), Color(0.96, 0.93, 0.84), Color(0.28, 0.88, 1.0)]
const NEUTRAL_KILL := Color(0.8, 0.78, 0.72)   # the casualty marker with Gore Off
const EXTRA_KILL_K := 1.25                      # Gore Extra: a bigger splat/rim
const SIZE_M := 0.018
const LIFT_M := 0.01
const RISE_M := 0.012
const RIM_Y_M := 0.004                          # base-rim arcs sit just above the turf/unit outline (0% torso occlusion)
const BADGE_LIFT_M := 0.048                     # compact unit summary badge floats +48 mm above unit/model center
const DEFAULT_BASE_R := 0.016                   # 32 mm base radius fallback when mark() is called without ModelInstance
const CLUSTER_RADIUS_M := 0.18                  # coalesce nearby pips into 1 unit summary badge
const CLUSTER_WINDOW_MS := 350
const FLASH_S := 0.10                           # 0.10 s instance-uniform hit rim-flash
const LIFE_S := 2.2
const MAX_LIVE := 32
const MAX_TICKS := 10
const SHADER_RES: Shader = preload("res://shaders/vfx_base_rim_pip.gdshader")
static var SHADER: String = SHADER_RES.code

var enabled: bool = true
var force_for_tests: bool = false   # plain headless never spawns (FloatingRuleText's orphan lesson)
var _clusters: Array[Dictionary] = []


func _ready() -> void:
	var gs := get_node_or_null("/root/GraphicsSettings")
	enabled = gs != null and bool(gs.get("show_combat_effects"))


## Still form: no rise or strobe flash on Performance (0) / Low (1), nor with Reduce Motion — steady cue and fade.
static func still_form(preset: int, reduce_motion: bool) -> bool:
	return reduce_motion or preset <= 1


## Mark `count` results of `kind` on a model: base-rim arc at its real base height + 0.10 s hit rim-flash on its mesh.
func mark_model(kind: Kind, mi: ModelInstance, count: int) -> MeshInstance3D:
	var eye := eye_of(mi)
	if eye == Vector3.INF:
		return null
	var base_r := VolumetricLos.model_base_radius_m(mi)
	var pip := mark(kind, eye, count, mi.node.global_position.y, base_r)
	if pip != null:
		flash_model(mi.node, kind)
	return pip


## A model's sight-cylinder top (its node's spot + its base-table height) in metres; INF without a live node.
static func eye_of(mi: ModelInstance) -> Vector3:
	if mi == null or mi.node == null or not is_instance_valid(mi.node):
		return Vector3.INF
	return mi.node.global_position + Vector3.UP * VolumetricLos.height_in_for_base_mm(
		VolumetricLos.model_base_radius_m(mi) * 2000.0) * VolumetricLos.INCHES_TO_METERS


## Brief 0.10 s Fresnel rim-flash via `bone_texture.gdshader`'s `hit_flash` instance uniform (no material copies,
## zero torso occlusion, suppressed under Reduce Motion to avoid flicker). Returns flashed MeshInstance3D count.
func flash_model(model: Node3D, kind: Kind = Kind.WOUND, duration_s: float = FLASH_S) -> int:
	if not enabled or UiMotion.reduced() or model == null or not is_instance_valid(model):
		return 0
	var gs := get_node_or_null("/root/GraphicsSettings")
	var gore: int = int(gs.get("gore_level")) if gs != null and gs.get("gore_level") != null else 1
	var col: Color = NEUTRAL_KILL if kind == Kind.KILL and gore <= 0 else COLORS[kind]
	var flashed := 0
	var stack: Array[Node] = [model]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is MeshInstance3D:
			var m := cur as MeshInstance3D
			m.set_instance_shader_parameter(&"hit_flash_color", col)
			m.set_instance_shader_parameter(&"hit_flash", 1.0)
			if m.is_inside_tree():
				var tw := m.create_tween()
				tw.tween_method(func(v: float) -> void:
					if is_instance_valid(m):
						m.set_instance_shader_parameter(&"hit_flash", v), 1.0, 0.0, maxf(duration_s, 0.01))
			flashed += 1
		for child in cur.get_children():
			stack.append(child)
	return flashed


func mark(kind: Kind, eye: Vector3, count: int, base_y: float = NAN, base_r: float = DEFAULT_BASE_R) -> MeshInstance3D:
	if not enabled or count <= 0 or (DisplayServer.get_name() == "headless" and not force_for_tests):
		return null
	while get_child_count() >= MAX_LIVE:
		var oldest := get_child(0)
		remove_child(oldest)
		oldest.queue_free()
	var gs := get_node_or_null("/root/GraphicsSettings")
	var gore: int = int(gs.get("gore_level")) if gs != null and gs.get("gore_level") != null else 1
	var kill := kind == Kind.KILL
	var gore_scale := EXTRA_KILL_K if kill and gore >= 2 else 1.0
	var tint_col: Color = NEUTRAL_KILL if kill and gore <= 0 else COLORS[kind]
	var shown := mini(count, MAX_TICKS)
	var mat := ShaderMaterial.new()
	mat.shader = SHADER_RES
	mat.set_shader_parameter("tint", tint_col)
	mat.set_shader_parameter("shape", int(kind))
	mat.set_shader_parameter("count", shown)
	mat.set_shader_parameter("fade", 1.0)
	var ring_y := (base_y if is_finite(base_y) else maxf(0.0, eye.y - 0.036)) + RIM_Y_M
	var rim_mult := 1.78 if kill else (1.66 if kind == Kind.SAVE else 1.62)
	var ring_r := maxf(base_r, 0.014) * rim_mult * gore_scale
	mat.set_shader_parameter("ring_radius", ring_r)
	mat.set_shader_parameter("ring_y", ring_y)
	var quad := QuadMesh.new()
	quad.size = Vector2(SIZE_M * shown, SIZE_M) * gore_scale
	var pip := MeshInstance3D.new()
	pip.mesh = quad
	pip.material_override = mat
	pip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pip.extra_cull_margin = 0.12
	add_child(pip)
	pip.global_position = eye + Vector3.UP * LIFT_M
	var still := still_form(int(gs.current_preset) if gs != null else 2, UiMotion.reduced())
	var badge := _attach_unit_badge(pip, kind, count, tint_col, eye)
	var tw := pip.create_tween()   # bound to the pip: an evicted pip takes its tween with it
	if not still:
		tw.tween_property(badge, "position:y", badge.position.y + RISE_M, LIFE_S)
	tw.parallel().tween_property(mat, "shader_parameter/fade", 0.0, 0.4).set_delay(LIFE_S - 0.4)
	tw.parallel().tween_property(badge, "modulate:a", 0.0, 0.4).set_delay(LIFE_S - 0.4)
	tw.parallel().tween_property(badge, "outline_modulate:a", 0.0, 0.4).set_delay(LIFE_S - 0.4)
	tw.tween_callback(pip.queue_free)
	return pip


func _attach_unit_badge(pip: MeshInstance3D, kind: Kind, count: int, accent: Color, eye: Vector3) -> Label3D:
	var now_ms := Time.get_ticks_msec()
	var kept: Array[Dictionary] = []
	var cluster: Dictionary = {}
	var xz := Vector2(eye.x, eye.z)
	for entry in _clusters:
		var old_badge: Variant = entry.get("badge")
		if now_ms - int(entry.get("ms", 0)) > CLUSTER_WINDOW_MS or old_badge == null \
				or not is_instance_valid(old_badge) or (old_badge as Node).is_queued_for_deletion():
			continue
		if cluster.is_empty() and (entry.get("xz", Vector2.INF) as Vector2).distance_to(xz) <= CLUSTER_RADIUS_M:
			cluster = entry
		else:
			kept.append(entry)
	if not cluster.is_empty():
		var prev := cluster["badge"] as Label3D
		if is_instance_valid(prev) and not prev.is_queued_for_deletion():
			prev.visible = false
	else:
		cluster = {"xz": xz, "wounds": 0, "kills": 0, "hits": 0, "saves": 0}
	match kind:
		Kind.WOUND:
			cluster["wounds"] = int(cluster["wounds"]) + count
		Kind.KILL:
			cluster["kills"] = int(cluster["kills"]) + count
		Kind.HIT:
			cluster["hits"] = int(cluster["hits"]) + count
		Kind.SAVE:
			cluster["saves"] = int(cluster["saves"]) + count
	var badge := Label3D.new()
	badge.name = "UnitDeltaBadge"
	badge.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	badge.no_depth_test = false
	badge.fixed_size = false
	badge.pixel_size = 0.00058
	badge.font_size = 28
	badge.outline_size = 14
	badge.modulate = Color(1.0, 0.98, 0.92, 1.0).lerp(accent, 0.28)
	badge.outline_modulate = Color(0.03, 0.04, 0.06, 0.96)
	badge.text = _badge_text(cluster)
	badge.position = Vector3(0.0, BADGE_LIFT_M, 0.0)
	pip.add_child(badge)
	cluster["badge"] = badge
	cluster["ms"] = now_ms
	kept.append(cluster)
	_clusters = kept
	return badge


static func _badge_text(cluster: Dictionary) -> String:
	var parts: Array[String] = []
	var kills := int(cluster.get("kills", 0))
	var wounds := int(cluster.get("wounds", 0))
	var saves := int(cluster.get("saves", 0))
	var hits := int(cluster.get("hits", 0))
	if kills > 0:
		parts.append("%d KILLED" % kills)
	if wounds > 0:
		parts.append("-%d WOUND%s" % [wounds, "S" if wounds != 1 else ""])
	if saves > 0:
		parts.append("SAVED x%d" % saves)
	if parts.is_empty() and hits > 0:
		parts.append("%d HIT%s" % [hits, "S" if hits != 1 else ""])
	return " · ".join(parts)
