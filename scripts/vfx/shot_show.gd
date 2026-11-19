class_name ShotShow
extends Node3D
## Combat effects, the shooting show on top of the rule-true chalk lines: per weapon family a muzzle moment (star
## flash, small warm base-local pooled OmniLight3D, drifting cordite smoke, bow snap, flamer gout, energy charge-up,
## machine-gun stutter, artillery thump), batched 1-draw-call HDR tracer ribbons (VfxRibbonBatch with dark sand-contrast
## edge) or arced projectiles along the SAME eye-to-eye sight line, and a neutral impact where it arrives.
## Reduce Motion: instant static sight-line threads (0.5 s fade) and static blast rings (no flying bolts or flicker);
## Performance: no picture; Low: half the particles, 0 lights. All randomness from the cue's seed; every round emits
## `sound_cue` when it leaves and lands, picture or not.

signal sound_cue(family: int, moment: String, at: Vector3)   # sound-ready hook: launch / impact / blast, per round

const F := VolleyCue.Family
## family -> [flight s, projectile tint (HDR), projectile length m, projectile radius m, arc height per metre]
## (a beam has no length: it stands from muzzle to target for its flight time)
const SHOTS := {
	F.NEUTRAL: [0.2, Color(1.6, 1.6, 1.5), 0.0, 0.0, 0.0],
	F.BALLISTIC: [0.24, Color(5.0, 3.6, 1.6), 0.022, 0.0012, 0.0],
	F.BOW: [0.45, Color(1.1, 1.0, 0.85), 0.03, 0.0011, 0.18],
	F.FLAME: [0.3, Color(4.0, 1.6, 0.4), 0.0, 0.0, 0.0],
	F.ENERGY: [0.26, Color(1.2, 3.6, 5.0), 0.012, 0.004, 0.0],
	F.AUTO: [0.16, Color(5.0, 3.0, 1.1), 0.014, 0.0008, 0.0],
	F.ARTILLERY: [0.6, Color(3.0, 1.8, 0.75), 0.011, 0.005, 0.3],   # the shell: bigger and hotter, it is the warning
	F.THROWN: [0.5, Color(1.0, 0.92, 0.75), 0.035, 0.0015, 0.32],
	F.BEAM: [0.12, Color(4.0, 1.1, 1.3), 0.0, 0.0011, 0.0],
}
const RIBBON_WIDTHS := {
	F.NEUTRAL: 0.0046,
	F.BALLISTIC: 0.0056,
	F.AUTO: 0.0048,
	F.ENERGY: 0.0074,
}
const CHAOS_S := 0.6            # every model fires at its own moment inside this window
const JITTER_M := 0.008         # where the visible round lands inside the target's base (the rule line stays exact)
const ECHO_CHANCE := 0.35       # share of shots that throw a second, offset impact
const AUTO_ROUNDS := 4          # a machine gun's burst per model
const ROUND_GAP_S := 0.06
const MAX_LIGHTS := 4           # small pooled ring buffer (Forward+ clustered)
const MAX_MUZZLE_LIGHTS_PER_VOLLEY := 2   # muzzle and impact lights are counted apart, so a squad never stacks them
const MAX_IMPACT_LIGHTS_PER_VOLLEY := 2
const IMPACT_LIGHT_K := 0.6     # an impact glints at 0.6x the muzzle's energy
## Godot's omni falloff is window(d / range) * d^-attenuation in WORLD units: the table is in metres, so at 2 cm a decay of
## 2.4 multiplies the energy by ~12,000 (the white puddle of iteration 2). With a decay near 0 the soft range window alone
## shapes the pool, and the energy can be a normal number.
const LIGHT_RANGE_M := 0.08     # one base and a half around the flash (~25-40 mm bases)
const LIGHT_RANGE_END_K := 0.6  # the pool pulls in to this share of its range as the flash dies (no edge popping off)
const LIGHT_ATTENUATION := 0.2
const LIGHT_LIFE_S := 0.07
const LIGHT_ENERGY := 2.2
const LIGHT_LIFT_M := 0.018     # the light hangs this high over the muzzle / impact point and grazes the ground
const LIGHT_POOL_IDLE_S := 0.35
const STATIC_THREAD_LIFE_S := 0.5
const WAVE_S := 0.28            # the blast's ring front: fast out, 1.6x the blast radius at the end
const WAVE_END_K := 1.6
const RETICLE_S := 0.25         # the dark ground mark that warns of the shell, this long before it lands
const RETICLE_START_K := 1.4    # ... shrinking from 1.4x the blast radius to 1.0x
const BLAST_RING := "shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform float progress = 0.0;
void fragment() {
	float r = length(UV * 2.0 - 1.0); float at = mix(0.2, 1.0, progress);
	ALBEDO = vec3(1.6, 1.0, 0.5); ALPHA = (1.0 - smoothstep(0.0, 0.08, abs(r - at))) * (1.0 - progress) * 0.8;
}"

## The blast's ring: a thick orange front, fast out (cubic ease), soft glow behind it, cooling from white-orange to red.
const BLAST_WAVE := "shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform float progress = 0.0;
void fragment() {
	float r = length(UV * 2.0 - 1.0); float e = 1.0 - pow(1.0 - progress, 3.0);
	float d = r - mix(0.12, 0.95, e);
	float a = smoothstep(-0.22, 0.0, d) * (1.0 - smoothstep(0.0, 0.05, d));
	ALBEDO = mix(vec3(2.6, 0.9, 0.2), vec3(1.0, 0.25, 0.05), progress); ALPHA = a * (1.0 - progress) * 0.8;
}"
## The shell's warning: a dark ring (plus a faint dark disc) on the ground that shrinks onto the landing point.
const BLAST_RETICLE := "shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;
uniform float progress = 0.0;
void fragment() {
	float r = length(UV * 2.0 - 1.0); float at = mix(1.0, 1.0 / 1.4, progress);
	float ring = 1.0 - smoothstep(0.0, 0.07, abs(r - at));
	ALBEDO = vec3(0.02, 0.015, 0.01); ALPHA = (ring * 0.35 + (1.0 - smoothstep(0.0, at, r)) * 0.10) * smoothstep(0.0, 0.25, progress);
}"

var enabled := true
var force_for_tests := false
var _ribbon_batch: VfxRibbonBatch = null
var _light_pool: Array[OmniLight3D] = []
var _light_age := PackedFloat32Array()
var _light_life := PackedFloat32Array()
var _light_peak := PackedFloat32Array()
var _light_cursor := 0
var _light_idle_s := 0.0
var _next_volley_id := 1
var _current_volley_id := 0
var _volley_lights := {}        # volley id -> Vector2i(muzzle lights, impact lights) lit so far
var _volley_open := {}          # volley id -> rounds that have not landed yet (the entry above goes with the last one)
var light_starts := 0           # lights lit since this show exists (tests and the capture read it)
static var _meshes := {}
static var _ring_shader: Shader
static var _wave_shader: Shader
static var _reticle_shader: Shader


func _ready() -> void:
	var gs := get_node_or_null("/root/GraphicsSettings")
	enabled = gs != null and gs.get("show_combat_effects") == true
	set_process(false)


func _exit_tree() -> void:
	_light_pool.clear()
	_light_age.clear()
	_light_life.clear()
	_light_peak.clear()
	_volley_lights.clear()
	_volley_open.clear()
	_current_volley_id = 0
	_ribbon_batch = null


func _preset() -> int:
	var gs := get_node_or_null("/root/GraphicsSettings")
	return -1 if not enabled or UiMotion.reduced() or (DisplayServer.get_name() == "headless" and not force_for_tests) \
		else (int(gs.current_preset) if gs != null else 2)


func _ensure_ribbon_batch() -> VfxRibbonBatch:
	if _ribbon_batch == null or not is_instance_valid(_ribbon_batch) or _ribbon_batch.is_queued_for_deletion():
		_ribbon_batch = VfxRibbonBatch.new()
		_ribbon_batch.name = "TracerRibbonBatch"
		_ribbon_batch.auto_free_when_empty = true
		add_child(_ribbon_batch)
	return _ribbon_batch


func _ensure_light_pool() -> void:
	if not _light_pool.is_empty():
		return
	_light_age.resize(MAX_LIGHTS)
	_light_life.resize(MAX_LIGHTS)
	_light_peak.resize(MAX_LIGHTS)
	_light_age.fill(0.0)
	_light_life.fill(0.0)
	_light_peak.fill(0.0)
	for i in MAX_LIGHTS:
		var l := OmniLight3D.new()
		l.name = "MuzzleLight_%d" % i
		l.shadow_enabled = false
		l.omni_range = LIGHT_RANGE_M
		l.omni_attenuation = LIGHT_ATTENUATION
		l.light_energy = 0.0
		l.visible = false
		add_child(l)
		_light_pool.append(l)
	_light_cursor = 0
	_light_idle_s = 0.0
	set_process(true)


func release_light_pool() -> void:
	for l in _light_pool:
		if is_instance_valid(l):
			l.queue_free()
	_light_pool.clear()
	_light_age.clear()
	_light_life.clear()
	_light_peak.clear()
	_light_idle_s = 0.0   # the per-volley counts stay: a volley's cap must survive an idle pool release
	set_process(false)


func light_pool_size() -> int:
	return _light_pool.size()


func _process(delta: float) -> void:
	if _light_pool.is_empty():
		set_process(false)
		return
	var any_active := false
	for i in _light_pool.size():
		var life := _light_life[i]
		if life <= 0.0:
			continue
		var l := _light_pool[i]
		if not is_instance_valid(l) or l.is_queued_for_deletion():
			_light_life[i] = 0.0
			continue
		var next_age := _light_age[i] + delta
		if next_age >= life:
			_light_life[i] = 0.0
			_light_age[i] = 0.0
			l.light_energy = 0.0
			l.visible = false
		else:
			_light_age[i] = next_age
			var a := next_age / life
			l.light_energy = _light_peak[i] * light_curve(a)
			l.omni_range = LIGHT_RANGE_M * lerpf(1.0, LIGHT_RANGE_END_K, a)
			any_active = true
	if any_active:
		_light_idle_s = 0.0
	else:
		_light_idle_s += delta
		if _light_idle_s >= LIGHT_POOL_IDLE_S:
			release_light_pool()


## The flash's energy over its life (a = 0 at the flash, 1 at its end): smoothstep-eased so it starts at full strength,
## has no kink where it ends and never cuts off.
static func light_curve(a: float) -> float:
	var k := 1.0 - clampf(a, 0.0, 1.0)
	return k * k * (3.0 - 2.0 * k)


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


## One volley: `pairs` are the rule's [from_eye, to_eye] segments, `rng_seed` the cue's cosmetic seed, `blast` the
## weapon's Blast(X) (0 = none) and `ground_drop` how far below the target eye the ground lies (for the blast ring).
func volley(pairs: Array, family: int, rng_seed: int, blast := 0, ground_drop := 0.0) -> void:
	if not enabled or (DisplayServer.get_name() == "headless" and not force_for_tests):
		return
	var p := _preset()
	if UiMotion.reduced():
		_draw_reduced_motion_volley(pairs, family, blast, ground_drop)
	var vid := _next_volley_id
	_next_volley_id += 1
	_volley_lights[vid] = Vector2i.ZERO
	var shots := plan(pairs.size(), rng_seed)
	var rounds := AUTO_ROUNDS if family == F.AUTO else 1
	_volley_open[vid] = pairs.size() * rounds
	for i in pairs.size():
		var side: Vector3 = Vector3(-(pairs[i][1] - pairs[i][0]).z, 0.0, (pairs[i][1] - pairs[i][0]).x).normalized()
		for k in rounds:   # a burst walks across the target base
			var tw := create_tween()
			tw.tween_interval(float(shots[i]["delay"]) + k * ROUND_GAP_S)
			tw.tween_callback(_fire_in_volley.bind(vid, pairs[i][0], pairs[i][1] + shots[i]["jitter"] + side * JITTER_M * (k - (rounds - 1) * 0.5) * 0.5,
				family, rng_seed + 7919 * i + 131 * k, p, float(shots[i]["muzzle"]) * (0.6 if rounds > 1 else 1.0),
				bool(shots[i]["echo"]) and rounds == 1, blast, ground_drop))


func _fire_in_volley(vid: int, a: Vector3, b: Vector3, family: int, s: int, p: int, muzzle_k := 1.0, echo := false,
		blast := 0, ground_drop := 0.0) -> void:
	var prev := _current_volley_id
	_current_volley_id = vid
	_fire(a, b, family, s, p, muzzle_k, echo, blast, ground_drop)
	_current_volley_id = prev


## WCAG 2.3.3 static keyframe volley under Reduce Motion: instant sight-line threads (0.5 s fade) + static blast ring,
## zero flying bolts, zero strobe lights.
func _draw_reduced_motion_volley(pairs: Array, family: int, blast: int, ground_drop: float) -> void:
	if pairs.is_empty():
		return
	var batch := _ensure_ribbon_batch()
	var tint := VolleyCue.hdr_tint(family)
	for pair in pairs:
		batch.push_ribbon(pair[0], pair[1], tint, 0.0036, STATIC_THREAD_LIFE_S, 0.0, true, 1.3)
		if blast > 0:
			_static_blast_ring(pair[1] - Vector3.UP * ground_drop, blast)


func _fire(a: Vector3, b: Vector3, family: int, s: int, p: int, muzzle_k := 1.0, echo := false, blast := 0,
		ground_drop := 0.0) -> void:
	var vid := _current_volley_id
	var dir := (b - a).normalized()
	var muzzle := a + dir * 0.012
	var star_at := muzzle + dir * 0.008 + Vector3.UP * 0.004
	_sound(family, "launch", muzzle)
	match family:
		F.BALLISTIC, F.AUTO:
			FxBurst.spawn(self, FxBurst.Look.FLASH, star_at, dir, 1, s, p, 0.72 * muzzle_k)
			FxBurst.spawn(self, FxBurst.Look.PUFF, muzzle, dir + Vector3.UP, 6 if family == F.BALLISTIC else 2, s + 1, p, 0.7 * muzzle_k)
			_light(muzzle, Color(1.0, 0.72, 0.34), p, LIGHT_LIFE_S, vid)
		F.BOW:
			FxBurst.spawn(self, FxBurst.Look.DUST, muzzle, Vector3.UP, 2, s, p, 0.3)   # the string's snap: no flash
		F.FLAME:
			FxBurst.spawn(self, FxBurst.Look.FLASH, star_at, dir, 1, s + 2, p, 0.62, Color(1.0, 0.55, 0.22))
			FxBurst.spawn(self, FxBurst.Look.MOTE, muzzle, dir, 10, s + 3, p, a.distance_to(b) / 0.18, Color(1.75, 0.58, 0.12))
			FxBurst.spawn(self, FxBurst.Look.EMBER, muzzle, dir, 28, s, p, a.distance_to(b) / 0.15)
			FxBurst.spawn(self, FxBurst.Look.PUFF, muzzle, dir + Vector3.UP, 6, s + 1, p, 1.2)
			_light(muzzle, Color(1.0, 0.52, 0.16), p, LIGHT_LIFE_S, vid)
		F.ENERGY:
			FxBurst.spawn(self, FxBurst.Look.MOTE, muzzle, Vector3.ZERO, 10, s, p, 0.6)
		F.BEAM:
			FxBurst.spawn(self, FxBurst.Look.MOTE, muzzle, Vector3.ZERO, 6, s, p, 0.4, Color(1.6, 0.5, 0.5))
		F.ARTILLERY:
			FxBurst.spawn(self, FxBurst.Look.FLASH, star_at, dir, 1, s, p, 0.78 * muzzle_k)
			FxBurst.spawn(self, FxBurst.Look.PUFF, muzzle, dir + Vector3.UP, 12, s + 1, p, 1.4 * muzzle_k)
			_light(muzzle, Color(1.0, 0.68, 0.32), p, LIGHT_LIFE_S, vid)
		F.THROWN:
			pass   # the throw itself is the look
		_:
			FxBurst.spawn(self, FxBurst.Look.PUFF, muzzle, Vector3.UP, 3, s, p, 0.5)
	var shot: Array = SHOTS.get(family, SHOTS[F.NEUTRAL])
	if family == F.ARTILLERY and blast > 0 and p >= 2:   # anticipation: the landing point is marked before the shell arrives
		var warn := create_tween()
		warn.tween_interval(maxf(float(shot[0]) - RETICLE_S, 0.0))
		warn.tween_callback(_blast_reticle.bind(b - Vector3.UP * ground_drop, blast))
	var tw := create_tween()
	if family == F.ENERGY or family == F.BEAM:
		tw.tween_interval(0.12 if family == F.ENERGY else 0.05)   # the charge-up before it leaves
	var uses_ribbon: bool = p > 0 and RIBBON_WIDTHS.has(family)
	var bolt: Node3D = _projectile(family, shot) if (p > 0 and not uses_ribbon) else null
	if family == F.BEAM:
		tw.tween_callback(_beam.bind(muzzle, b, shot, p))
		tw.tween_interval(0.03)
	elif uses_ribbon:
		var flight_s := float(shot[0])
		var width_m := float(RIBBON_WIDTHS[family]) * (0.85 if p == 1 else 1.0)
		var tint := VolleyCue.hdr_tint(family)
		tw.tween_callback(func() -> void:
			_ensure_ribbon_batch().push_ribbon(muzzle, b, tint, width_m, flight_s, 0.0, false, 2.6))
		tw.tween_interval(flight_s)
	elif bolt != null:
		bolt.global_position = muzzle
		var arc: float = float(shot[4]) * a.distance_to(b)
		var trail := [0]
		tw.tween_method(func(t: float) -> void:
			var at := muzzle.lerp(b, t) + Vector3.UP * arc * 4.0 * t * (1.0 - t)
			if at.distance_to(bolt.global_position) > 0.0001:
				bolt.look_at_from_position(bolt.global_position, at, Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT)
			if family == F.ARTILLERY and int(t * 6.0) != trail[0]:   # the shell trails smoke and sparks
				trail[0] = int(t * 6.0)
				FxBurst.spawn(self, FxBurst.Look.PUFF, at, Vector3.UP, 1, s + 40 + trail[0], p, 0.5)
				FxBurst.spawn(self, FxBurst.Look.EMBER, at, Vector3.UP, 2, s + 50 + trail[0], p, 0.4)
			bolt.global_position = at, 0.0, 1.0, float(shot[0]))
		tw.tween_callback(bolt.queue_free)
	else:
		tw.tween_interval(float(shot[0]))
	tw.tween_callback(_impact.bind(b, -dir, family, s + 2, p, blast, ground_drop, true, vid))
	if echo:   # a second round of the burst lands a hair later, a little off
		tw.tween_interval(0.07)
		tw.tween_callback(_impact.bind(b + Vector3(-dir.z, 0.0, dir.x) * JITTER_M, -dir, family, s + 5, p, 0, 0.0, false, vid))


## Arced projectiles (BOW, THROWN, ARTILLERY) and standing BEAM share one mesh/material per family.
func _projectile(family: int, shot: Array) -> Node3D:
	if float(shot[2]) <= 0.0 and family != F.BEAM:
		return null
	if not _meshes.has(family):
		var mesh: PrimitiveMesh = CapsuleMesh.new() if family in [F.ENERGY, F.ARTILLERY] else CylinderMesh.new()
		if mesh is CapsuleMesh:
			(mesh as CapsuleMesh).radius = float(shot[3])
			(mesh as CapsuleMesh).height = float(shot[2])
		else:
			(mesh as CylinderMesh).top_radius = 1.0 if family == F.BEAM else float(shot[3])
			(mesh as CylinderMesh).bottom_radius = 1.0 if family == F.BEAM else float(shot[3])
			(mesh as CylinderMesh).height = 1.0 if family == F.BEAM else float(shot[2])
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = shot[1]
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if family == F.BEAM else BaseMaterial3D.TRANSPARENCY_DISABLED
		mesh.material = mat
		_meshes[family] = mesh
	if family == F.BEAM:
		return null   # _beam() builds its own instance
	var holder := Node3D.new()
	var m := MeshInstance3D.new()
	m.mesh = _meshes[family]
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.rotation_degrees.x = 90.0
	holder.add_child(m)
	add_child(holder)
	return holder


## A beam: muzzle to target at once, then it thins out (GeometryInstance3D.transparency, nothing uploaded per beam).
func _beam(a: Vector3, b: Vector3, shot: Array, p: int) -> void:
	if p <= 0 or not _meshes.has(F.BEAM):
		return
	var m := MeshInstance3D.new()
	m.mesh = _meshes[F.BEAM]
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m)
	var dir := (b - a).normalized()
	var basis := Basis(Quaternion(Vector3.UP, dir)) if dir.length() > 0.5 else Basis()
	m.global_transform = Transform3D(basis.scaled_local(Vector3(float(shot[3]), maxf(a.distance_to(b), 0.001), float(shot[3]))),
		(a + b) * 0.5)
	var tw := m.create_tween()
	tw.tween_property(m, "transparency", 1.0, float(shot[0]))
	tw.tween_callback(m.queue_free)


func _impact(at: Vector3, back: Vector3, family: int, s: int, p: int, blast := 0, ground_drop := 0.0,
		primary := true, volley_id := 0) -> void:
	if primary:
		_sound(family, "impact", at)
	match family:
		F.FLAME:
			FxBurst.spawn(self, FxBurst.Look.EMBER, at, Vector3.UP, 14, s, p, 1.0, Color(1.15, 0.85, 0.55))
			FxBurst.spawn(self, FxBurst.Look.MOTE, at, Vector3.UP, 6, s + 2, p, 0.85, Color(1.7, 0.52, 0.10))
			FxBurst.spawn(self, FxBurst.Look.PUFF, at, Vector3.UP, 6, s + 1, p, 1.1, Color(0.32, 0.28, 0.26))
		F.ENERGY:
			FxBurst.spawn(self, FxBurst.Look.FLASH, at, Vector3.ZERO, 1, s, p, 0.7)
			FxBurst.spawn(self, FxBurst.Look.SPARK, at, back, 6, s + 1, p)
			_impact_light(at, Color(0.4, 0.8, 1.0), p, LIGHT_LIFE_S, volley_id, primary)
		F.BEAM:
			FxBurst.spawn(self, FxBurst.Look.FLASH, at, Vector3.ZERO, 1, s, p, 0.6, Color(1.0, 0.45, 0.45))
			FxBurst.spawn(self, FxBurst.Look.SPARK, at, back, 8, s + 1, p, 1.0, Color(1.4, 0.6, 0.5))
			FxBurst.spawn(self, FxBurst.Look.EMBER, at, Vector3.UP, 4, s + 2, p, 0.5)
			_impact_light(at, Color(1.0, 0.4, 0.4), p, LIGHT_LIFE_S, volley_id, primary)
		F.BOW, F.THROWN:
			FxBurst.spawn(self, FxBurst.Look.DUST, at, back + Vector3.UP, 4 if family == F.BOW else 6, s, p, 0.6)
			FxBurst.spawn(self, FxBurst.Look.CHIP, at, back + Vector3.UP, 3, s + 1, p, 0.6)
		F.ARTILLERY:   # three beats: a very short flash, the fireball, then smoke that rises and lingers (+ debris, dust ring)
			var bk := _blast_radius(blast) / _blast_radius(3)   # 1.0 for Blast(3); a bigger blast is a bigger fire
			var low := at - Vector3.UP * ground_drop * 0.5
			FxBurst.spawn(self, FxBurst.Look.FLASH, at, Vector3.ZERO, 1, s, p, 3.0 * bk, Color.WHITE, false, 0.0, 0.7)
			FxBurst.spawn(self, FxBurst.Look.FIREBALL, low, Vector3.ZERO, 8, s + 1, p, bk)
			FxBurst.spawn(self, FxBurst.Look.CHIP, low, Vector3.UP, 18, s + 2, p, 1.6 * bk, Color(0.6, 0.45, 0.32))   # earth, not confetti
			FxBurst.spawn(self, FxBurst.Look.COLUMN, low, Vector3.UP, 10, s + 4, p, 2.0 * bk)
			FxBurst.spawn(self, FxBurst.Look.DUST, at - Vector3.UP * ground_drop, Vector3.ZERO, 24, s + 3, p, 1.6 * bk, Color.WHITE, true)
			_impact_light(at, Color(1.0, 0.65, 0.35), p, LIGHT_LIFE_S, volley_id, primary)
		F.AUTO:
			FxBurst.spawn(self, FxBurst.Look.DUST, at, back + Vector3.UP, 3, s, p, 0.6)
			FxBurst.spawn(self, FxBurst.Look.SPARK, at, back, 3, s + 1, p, 0.8)
		_:
			FxBurst.spawn(self, FxBurst.Look.DUST, at, back + Vector3.UP, 6, s, p, 0.8)
			FxBurst.spawn(self, FxBurst.Look.SPARK, at, back, 5, s + 1, p)
			_impact_light(at, Color(1.0, 0.7, 0.4), p, LIGHT_LIFE_S, volley_id, primary)
	if primary and blast > 0:
		_sound(family, "blast", at)
		_blast_ring(at - Vector3.UP * ground_drop, blast, p)
	if primary and volley_id > 0:   # the volley's light budget goes with its last round
		var left := int(_volley_open.get(volley_id, 0)) - 1
		if left <= 0:
			_volley_open.erase(volley_id)
			_volley_lights.erase(volley_id)
		else:
			_volley_open[volley_id] = left


static func _blast_radius(blast: int) -> float:
	return 0.02 + 0.008 * clampi(blast, 1, 12)


## A flat shader plane lying on the ground at `ground`, `size_m` wide, whose `progress` uniform a tween drives 0 -> 1.
func _ground_plane(code: String, shader_cache: Shader, ground: Vector3, size_m: float) -> Array:
	var shader := shader_cache
	if shader == null:
		shader = Shader.new()
		shader.code = code
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * size_m
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("progress", 0.0)   # an unset uniform cannot be tweened
	var node := MeshInstance3D.new()
	node.mesh = plane
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	node.global_position = ground + Vector3.UP * 0.003
	return [node, mat, shader]


## Blast(X): the ring of light runs out over the ground where the round lands, wider for a bigger X (cosmetic: it does
## not draw the rule's hit area). Thick and orange, expo ease-out, WAVE_S long, ending at WAVE_END_K x the blast radius.
func _blast_ring(ground: Vector3, blast: int, p: int) -> void:
	if p <= 0:
		return
	var made := _ground_plane(BLAST_WAVE, _wave_shader, ground, _blast_radius(blast) * 2.0 * WAVE_END_K)
	_wave_shader = made[2]
	var tw := (made[0] as Node).create_tween()
	tw.tween_property(made[1], "shader_parameter/progress", 1.0, WAVE_S)
	tw.tween_callback((made[0] as Node).queue_free)


## The shell's warning on the ground, RETICLE_S before it lands (not on Low: the caller skips it).
func _blast_reticle(ground: Vector3, blast: int) -> void:
	var made := _ground_plane(BLAST_RETICLE, _reticle_shader, ground, _blast_radius(blast) * 2.0 * RETICLE_START_K)
	_reticle_shader = made[2]
	var tw := (made[0] as Node).create_tween()
	tw.tween_property(made[1], "shader_parameter/progress", 1.0, RETICLE_S)
	tw.tween_callback((made[0] as Node).queue_free)


func _static_blast_ring(ground: Vector3, blast: int) -> void:
	if _ring_shader == null:
		_ring_shader = Shader.new()
		_ring_shader.code = BLAST_RING
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * _blast_radius(blast) * 2.0
	var mat := ShaderMaterial.new()
	mat.shader = _ring_shader
	mat.set_shader_parameter("progress", 0.65)
	var ring := MeshInstance3D.new()
	ring.mesh = plane
	ring.material_override = mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	ring.global_position = ground + Vector3.UP * 0.003
	var tw := ring.create_tween()
	tw.tween_property(ring, "transparency", 1.0, STATIC_THREAD_LIFE_S)
	tw.tween_callback(ring.queue_free)


## The sound-ready hook: every round's launch, impact and blast moment as a signal; a family whose sound is set in
## the weapon-family table (sounds.<family>.<moment> = res:// path) also plays it. Nothing ships a sound today.
func _sound(family: int, moment: String, at: Vector3) -> void:
	sound_cue.emit(family, moment, at)
	var sounds: Variant = VolleyCue.table().get("sounds", {})
	var key := str(F.keys()[family]).to_lower() if family >= 0 and family < F.size() else ""
	var path := str((sounds as Dictionary).get(key, {}).get(moment, "")) if sounds is Dictionary \
		and (sounds as Dictionary).get(key) is Dictionary else ""
	var audio := get_node_or_null("/root/AudioManager")
	if path != "" and audio != null and ResourceLoader.exists(path):
		audio.call("play_sfx_at_path", path)


## An impact's light: only the round that lands for real lights it (the echo is a copy 70 ms later, 8 mm away).
func _impact_light(at: Vector3, color: Color, p: int, life_s: float, volley_id: int, primary: bool) -> void:
	if primary:
		_light(at, color, p, life_s, volley_id, true)


## Ring-buffered OmniLight3D muzzle/impact flash: hangs LIGHT_LIFT_M over the point, soft falloff (attenuation ~0.2,
## range 0.08 m), energy eased to zero over LIGHT_LIFE_S while the pool pulls in. Per volley at most 2 muzzle + 2 impact
## lights, impact at 0.6x the muzzle's energy, deduplicated against overlapping active lights. 0 lights on Low/Perf/Reduce Motion.
func _light(at: Vector3, color: Color, p: int, life_s: float = LIGHT_LIFE_S, volley_id: int = 0, impact := false) -> void:
	if p < 2:
		return
	if volley_id > 0:
		var used: Vector2i = _volley_lights.get(volley_id, Vector2i.ZERO)
		var n: int = used.y if impact else used.x
		if n >= (MAX_IMPACT_LIGHTS_PER_VOLLEY if impact else MAX_MUZZLE_LIGHTS_PER_VOLLEY):
			return
		_volley_lights[volley_id] = Vector2i(used.x, used.y + 1) if impact else Vector2i(used.x + 1, used.y)
	at += Vector3.UP * LIGHT_LIFT_M
	_ensure_light_pool()
	var slot := -1
	var min_sep := LIGHT_RANGE_M * 0.85
	for i in _light_pool.size():
		if _light_life[i] > 0.0 and is_instance_valid(_light_pool[i]) \
				and _light_pool[i].global_position.distance_to(at) < min_sep:
			slot = i
			break
	if slot < 0:
		slot = _light_cursor
		_light_cursor = (_light_cursor + 1) % MAX_LIGHTS
	var energy := LIGHT_ENERGY * (IMPACT_LIGHT_K if impact else 1.0)
	var l := _light_pool[slot]
	l.global_position = at
	l.light_color = color
	l.light_energy = energy
	l.omni_range = LIGHT_RANGE_M
	l.omni_attenuation = LIGHT_ATTENUATION
	l.visible = true
	_light_age[slot] = 0.0
	_light_life[slot] = maxf(life_s, 0.02)
	_light_peak[slot] = energy
	_light_idle_s = 0.0
	light_starts += 1
	set_process(true)
