class_name ShotShow
extends Node3D
## Combat effects, the shooting show on top of the rule-true chalk lines: per weapon family a muzzle moment (rifle
## flash and smoke, bow snap, flamer gout, energy charge-up), a visible round along the SAME eye-to-eye sight line
## (tracer bullet, arrow on an arc above it, glowing bolt) and a NEUTRAL impact where it arrives (dust, sparks, a
## little light). The impact claims nothing about the dice; blood and
## ricochets come from the resolver's results. A volley is chaotic, not a row: every model fires at its own moment and
## lands somewhere inside the target's base, from the cue's seed alone, so every peer sees the same chaos.
## Performance and Reduce Motion: no picture. Low: half the particles, no lights.

const F := VolleyCue.Family
## family -> [flight s, projectile tint (HDR), projectile length m, projectile radius m, arc height per metre]
const SHOTS := {
	F.NEUTRAL: [0.2, Color(1.6, 1.6, 1.5), 0.0, 0.0, 0.0],
	F.BALLISTIC: [0.16, Color(5.0, 3.6, 1.6), 0.022, 0.0012, 0.0],
	F.BOW: [0.45, Color(1.1, 1.0, 0.85), 0.03, 0.0011, 0.18],
	F.FLAME: [0.3, Color(4.0, 1.6, 0.4), 0.0, 0.0, 0.0],
	F.ENERGY: [0.26, Color(1.2, 3.6, 5.0), 0.012, 0.004, 0.0],
}
const CHAOS_S := 0.6       # every model fires at its own moment inside this window
const JITTER_M := 0.008    # where the visible round lands inside the target's base (the rule line stays exact)
const ECHO_CHANCE := 0.35  # share of shots that throw a second, offset impact
const MAX_LIGHTS := 3

var enabled := true
var force_for_tests := false
var _lights := 0
static var _meshes := {}


func _ready() -> void:
	var gs := get_node_or_null("/root/GraphicsSettings")
	enabled = gs != null and gs.get("show_combat_effects") == true


func _preset() -> int:
	var gs := get_node_or_null("/root/GraphicsSettings")
	return -1 if not enabled or UiMotion.reduced() or (DisplayServer.get_name() == "headless" and not force_for_tests) \
		else (int(gs.current_preset) if gs != null else 2)


## The chaos of a real volley, from the cue's seed alone, so every peer sees the same: per shot a start delay inside
## CHAOS_S, a landing spread inside the target's base, a muzzle size and whether it throws a second impact.
static func plan(n: int, rng_seed: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var out: Array = []
	for i in n:
		out.append({"delay": rng.randf_range(0.0, CHAOS_S), "muzzle": rng.randf_range(0.7, 1.4),
			"jitter": Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.5, 0.5), rng.randf_range(-1, 1)) * JITTER_M,
			"echo": rng.randf() < ECHO_CHANCE})
	return out


## One volley: `pairs` are the rule's [from_eye, to_eye] segments, `rng_seed` the cue's cosmetic seed.
func volley(pairs: Array, family: int, rng_seed: int) -> void:
	var p := _preset()
	if p <= 0:
		return
	var shots := plan(pairs.size(), rng_seed)
	for i in pairs.size():
		var tw := create_tween()
		tw.tween_interval(float(shots[i]["delay"]))
		tw.tween_callback(_fire.bind(pairs[i][0], pairs[i][1] + shots[i]["jitter"], family, rng_seed + 7919 * i, p,
			float(shots[i]["muzzle"]), bool(shots[i]["echo"])))


func _fire(a: Vector3, b: Vector3, family: int, s: int, p: int, muzzle_k := 1.0, echo := false) -> void:
	var dir := (b - a).normalized()
	var muzzle := a + dir * 0.012
	match family:
		F.BALLISTIC:
			FxBurst.spawn(self, FxBurst.Look.FLASH, muzzle, Vector3.ZERO, 1, s, p, 0.45 * muzzle_k)
			FxBurst.spawn(self, FxBurst.Look.PUFF, muzzle, dir + Vector3.UP, 6, s + 1, p, 0.7 * muzzle_k)
			_light(muzzle, Color(1.0, 0.75, 0.4), p)
		F.BOW:
			FxBurst.spawn(self, FxBurst.Look.DUST, muzzle, Vector3.UP, 2, s, p, 0.3)   # the string's snap: no flash
		F.FLAME:
			FxBurst.spawn(self, FxBurst.Look.FLASH, muzzle, Vector3.ZERO, 1, s + 2, p, 0.5, Color(1.0, 0.6, 0.3))
			FxBurst.spawn(self, FxBurst.Look.EMBER, muzzle, dir, 28, s, p, a.distance_to(b) / 0.15)
			FxBurst.spawn(self, FxBurst.Look.PUFF, muzzle, dir + Vector3.UP, 6, s + 1, p, 1.2)
		F.ENERGY:
			FxBurst.spawn(self, FxBurst.Look.MOTE, muzzle, Vector3.ZERO, 10, s, p, 0.6)
		_:
			FxBurst.spawn(self, FxBurst.Look.PUFF, muzzle, Vector3.UP, 3, s, p, 0.5)
	var shot: Array = SHOTS.get(family, SHOTS[F.NEUTRAL])
	var tw := create_tween()
	if family == F.ENERGY:
		tw.tween_interval(0.12)   # the charge-up before the bolt leaves
	var bolt := _projectile(family, shot)
	if bolt != null:
		bolt.global_position = muzzle
		var arc: float = float(shot[4]) * a.distance_to(b)
		tw.tween_method(func(t: float) -> void:
			var at := muzzle.lerp(b, t) + Vector3.UP * arc * 4.0 * t * (1.0 - t)
			if at.distance_to(bolt.global_position) > 0.0001:
				bolt.look_at_from_position(bolt.global_position, at, Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT)
			bolt.global_position = at, 0.0, 1.0, float(shot[0]))
		tw.tween_callback(bolt.queue_free)
	else:
		tw.tween_interval(float(shot[0]))   # a flamer's gout is its own flight
	tw.tween_callback(_impact.bind(b, -dir, family, s + 2, p))
	if echo:   # a second round of the burst lands a hair later, a little off
		tw.tween_interval(0.07)
		tw.tween_callback(_impact.bind(b + Vector3(-dir.z, 0.0, dir.x) * JITTER_M, -dir, family, s + 5, p))


## The round: a holder that look_at() points along the flight, the mesh's long axis turned onto it. Meshes and
## materials are shared per family (one per tracer cost +0.35 ms GPU in the v1 measurement).
func _projectile(family: int, shot: Array) -> Node3D:
	if float(shot[2]) <= 0.0:
		return null
	if not _meshes.has(family):
		var mesh: PrimitiveMesh = CapsuleMesh.new() if family == F.ENERGY else CylinderMesh.new()
		if mesh is CapsuleMesh:
			(mesh as CapsuleMesh).radius = float(shot[3])
			(mesh as CapsuleMesh).height = float(shot[2])
		else:
			(mesh as CylinderMesh).top_radius = float(shot[3])
			(mesh as CylinderMesh).bottom_radius = float(shot[3])
			(mesh as CylinderMesh).height = float(shot[2])
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = shot[1]
		mesh.material = mat
		_meshes[family] = mesh
	var holder := Node3D.new()
	var m := MeshInstance3D.new()
	m.mesh = _meshes[family]
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.rotation_degrees.x = 90.0
	holder.add_child(m)
	add_child(holder)
	return holder


func _impact(at: Vector3, back: Vector3, family: int, s: int, p: int) -> void:
	match family:
		F.FLAME:
			FxBurst.spawn(self, FxBurst.Look.EMBER, at, Vector3.UP, 10, s, p, 0.8)
			FxBurst.spawn(self, FxBurst.Look.PUFF, at, Vector3.UP, 4, s + 1, p, 0.9, Color(0.5, 0.46, 0.44))
		F.ENERGY:
			FxBurst.spawn(self, FxBurst.Look.FLASH, at, Vector3.ZERO, 1, s, p, 0.7)
			FxBurst.spawn(self, FxBurst.Look.SPARK, at, back, 6, s + 1, p)
			_light(at, Color(0.4, 0.8, 1.0), p)
		F.BOW:
			FxBurst.spawn(self, FxBurst.Look.DUST, at, back + Vector3.UP, 4, s, p, 0.6)
			FxBurst.spawn(self, FxBurst.Look.CHIP, at, back + Vector3.UP, 3, s + 1, p, 0.6)
		_:
			FxBurst.spawn(self, FxBurst.Look.DUST, at, back + Vector3.UP, 6, s, p, 0.8)
			FxBurst.spawn(self, FxBurst.Look.SPARK, at, back, 5, s + 1, p)
			_light(at, Color(1.0, 0.7, 0.4), p)


func _light(at: Vector3, color: Color, p: int) -> void:
	if p < 2 or _lights >= MAX_LIGHTS:
		return
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = 1.2
	l.omni_range = 0.08
	l.shadow_enabled = false
	add_child(l)
	l.global_position = at
	_lights += 1
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, 0.12)
	tw.tween_callback(func() -> void:
		_lights -= 1
		l.queue_free())
