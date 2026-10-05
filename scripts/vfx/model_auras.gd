class_name ModelAuras
extends Node3D
## VFX: ambient hero auras, bound to the MODEL — a data table (assets/vfx/model_auras.json) keyed like the model library
## (faction folder / unit name) says which miniature carries which aura, so another hero gets one by adding a line.
## This node finds the miniatures and gives each its aura once; the aura lives under the model node, so it follows it
## and dies with it. Today one kind, lightning: crackling arcs between the anchor points (hands, staff), now and then a
## strike into the ground, all much busier while the model casts. Each aura draws from its own RandomNumberGenerator
## (never the game's) and hides while its model is a casualty. Low and Reduce Motion: only the soft glow at the
## anchors; Performance: nothing. Off unless GraphicsSettings.show_combat_effects, like every combat effect.

const DATA := "res://assets/vfx/model_auras.json"
const SCAN_S := 1.0          # how often new miniatures are looked up
const ARC_S := 0.1           # one arc's life
const BOOST := 3.0           # rate multiplier while casting
const AFTER_S := 2.5         # how long an aura stays wild after its cast (the rune column hid it during the cast)
const ARC_R := 0.0005        # bolt radii in m: arc, side branch, ground strike (maintainer 05.10.: "thinner")
const BRANCH_R := 0.00035
const STRIKE_R := 0.0011

var enabled := true
var force_for_tests := false
var _scan_t := 0.0
var _casting := {}   # seal key -> the auras that cast is driving
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


## A cast begins at `at` (the caster's base): every aura within `radius` runs wild until the cast `key` settles.
func boost_near(key: String, at: Vector3, radius: float) -> void:
	var driven: Array = []
	for n in get_tree().get_nodes_in_group("miniature"):
		var aura := (n as Node).get_node_or_null("ModelAura") as ModelAura
		if aura != null and Vector2((n as Node3D).global_position.x - at.x, (n as Node3D).global_position.z - at.z).length() <= radius:
			aura.boost_until = Time.get_ticks_msec() / 1000.0 + 60.0
			driven.append(aura)
	_casting[key] = driven


## The cast `key` is over: its auras stay wild for `seconds` more, then calm down.
func settle(key: String, seconds := AFTER_S) -> void:
	for aura in _casting.get(key, []):
		if is_instance_valid(aura):
			(aura as ModelAura).boost_until = Time.get_ticks_msec() / 1000.0 + seconds
	_casting.erase(key)


class ModelAura extends Node3D:
	var mi: ModelInstance
	var spec: Dictionary
	var owner_show: ModelAuras
	var boost_until := 0.0
	var arcs := 0   # arcs drawn so far
	var _rng := RandomNumberGenerator.new()
	var _arc_t := 0.0
	var _strike_t := 1.0
	var _anchors: Array = []
	var _bolt_mat := StandardMaterial3D.new()   # the arcs in the aura's own tint, dimmer than a spell bolt: less bloom halo

	func _init(model: ModelInstance, aura_spec: Dictionary, show: ModelAuras) -> void:
		mi = model
		spec = aura_spec
		owner_show = show

	## Anchors are data in base radii (x, z) and model heights (y); each gets a soft additive billboard glow.
	func _ready() -> void:
		_rng.seed = get_parent().get_instance_id()
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
		_bolt_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_bolt_mat.albedo_color = Color(float(t[0]), float(t[1]), float(t[2])) * 1.3
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

	func _process(delta: float) -> void:
		var p := owner_show._preset() if is_instance_valid(owner_show) else -1
		visible = mi.is_alive and p > 0
		if not visible or p < 2 or UiMotion.reduced() or _anchors.size() < 2:
			return   # Low / Reduce Motion: the static glow only
		var k := BOOST if Time.get_ticks_msec() / 1000.0 < boost_until else 1.0
		_arc_t += delta * float(spec.get("arcs_per_s", 10.0)) * k
		while _arc_t >= 1.0:
			_arc_t -= 1.0
			arcs += 1
			var a: Vector3 = _anchors[_rng.randi() % _anchors.size()]
			var b: Vector3 = _anchors[_rng.randi() % _anchors.size()]
			if a == b:
				b = a + Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.3, 0.6), _rng.randf_range(-1, 1)) * 0.012
			_arc(to_global(a), to_global(b), ARC_R, 0.005, 3)
			if _rng.randf() < 0.5:   # a side branch off the middle: crackle, not a wire
				var mid := a.lerp(b, _rng.randf_range(0.3, 0.7))
				_arc(to_global(mid), to_global(mid + Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * 0.01),
					BRANCH_R, 0.003, 2)
		_strike_t -= delta * k
		if _strike_t <= 0.0:
			var range_s: Array = spec.get("strike_every_s", [2.5, 5.0])
			_strike_t = _rng.randf_range(float(range_s[0]), float(range_s[1]))
			var r := VolumetricLos.model_base_radius_m(mi)
			var ang := _rng.randf() * TAU
			var ground := (get_parent() as Node3D).global_position + Vector3(cos(ang), 0.0, sin(ang)) * r * _rng.randf_range(1.2, 2.6)
			var top: Vector3 = to_global(_anchors[_anchors.size() - 1])
			_arc(top, ground, STRIKE_R, 0.02, 3)
			FxBurst.spawn(owner_show, FxBurst.Look.SPARK, ground, Vector3.UP, 10, _rng.randi(), p, 0.8, Color(0.5, 0.9, 1.6))
			FxBurst.spawn(owner_show, FxBurst.Look.FLASH, ground, Vector3.ZERO, 1, _rng.randi(), p, 0.6, Color(0.6, 0.9, 1.4))

	## One arc that re-jags `flickers` times within ARC_S, then goes out.
	func _arc(a: Vector3, b: Vector3, radius: float, sway: float, flickers: int) -> void:
		var holder := Node3D.new()
		add_child(holder)
		var s := _rng.randi()
		var tw := holder.create_tween()
		for f in flickers:
			tw.tween_callback(func() -> void:
				for c in holder.get_children():
					c.queue_free()
				FxBolt.jag(holder, a, b, s + f * 31, radius, sway, _bolt_mat))
			tw.tween_interval(ARC_S / flickers)
		tw.tween_callback(holder.queue_free)
