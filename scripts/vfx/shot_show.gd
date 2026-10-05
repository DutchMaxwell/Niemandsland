class_name ShotShow
extends Node3D
## Combat effects, the shooting show on top of the rule-true chalk lines: a muzzle moment (a gun's flash and smoke)
## and a NEUTRAL impact where the round arrives (dust, sparks, a little light) after the family's flight time. The impact claims nothing about the dice; blood and
## ricochets come from the resolver's results. A volley is chaotic, not a row: every model fires at its own moment and
## lands somewhere inside the target's base, from the cue's seed alone, so every peer sees the same chaos.
## Performance and Reduce Motion: no picture. Low: half the particles, no lights.

const F := VolleyCue.Family
## family -> [flight s, projectile tint (HDR), projectile length m, projectile radius m, arc height per metre]
const SHOTS := {
	F.NEUTRAL: [0.2, Color(1.6, 1.6, 1.5), 0.0, 0.0, 0.0],
	F.BALLISTIC: [0.16, Color(5.0, 3.6, 1.6), 0.022, 0.0012, 0.0],
}
const CHAOS_S := 0.6       # every model fires at its own moment inside this window
const JITTER_M := 0.008    # where the visible round lands inside the target's base (the rule line stays exact)
const ECHO_CHANCE := 0.35  # share of shots that throw a second, offset impact
const MAX_LIGHTS := 3

var enabled := true
var force_for_tests := false
var _lights := 0


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
		_:
			FxBurst.spawn(self, FxBurst.Look.PUFF, muzzle, Vector3.UP, 3, s, p, 0.5)
	var shot: Array = SHOTS.get(family, SHOTS[F.NEUTRAL])
	var tw := create_tween()
	tw.tween_interval(float(shot[0]))   # the round's flight
	tw.tween_callback(_impact.bind(b, -dir, family, s + 2, p))
	if echo:   # a second round of the burst lands a hair later, a little off
		tw.tween_interval(0.07)
		tw.tween_callback(_impact.bind(b + Vector3(-dir.z, 0.0, dir.x) * JITTER_M, -dir, family, s + 5, p))


func _impact(at: Vector3, back: Vector3, family: int, s: int, p: int) -> void:
	match family:
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
