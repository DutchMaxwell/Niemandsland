class_name CasualtyShow
extends Node3D
## Combat effects: what a resolved hit does to the models — drawn only from the resolver's results, never deciding
## one: a burst where a wound landed (blood mist and drops on flesh, sparks and an oil spot on machines, bone dust on
## the undead), pools on the ground by the Gore setting (Off: dust, no blood), ricochet sparks on the defending models
## when saves hold. Reduce Motion: no show at all. (The falling model comes in the next step.)

enum Gore { OFF, NORMAL, EXTRA }
const SPLAT_LIFE_S := [0.0, 10.0, 30.0]   # per Gore level

var enabled := true
var force_for_tests := false


func _ready() -> void:
	var gs := get_node_or_null("/root/GraphicsSettings")
	enabled = gs != null and gs.get("show_combat_effects") == true


func _preset() -> int:
	var gs := get_node_or_null("/root/GraphicsSettings")
	return -1 if not enabled or UiMotion.reduced() or (DisplayServer.get_name() == "headless" and not force_for_tests) \
		else (int(gs.current_preset) if gs != null else 2)


func _gore() -> int:
	var gs := get_node_or_null("/root/GraphicsSettings")
	return clampi(int(gs.get("gore_level")) if gs != null and gs.get("gore_level") != null else Gore.NORMAL, 0, 2)


func _splats(p: int) -> Splatters:
	var sp := get_node_or_null("Splatters") as Splatters
	if sp == null:
		sp = Splatters.new()
		sp.name = "Splatters"
		add_child(sp)
	sp.cap = 8 if p <= 1 else (64 if _gore() == Gore.EXTRA else 24)
	return sp


## A wound landed on the model at `at` (its LOS eye; `base` its spot on the ground): blood by the Gore setting on
## flesh (Off: dust), sparks and an oil spot on machines, bone dust and chips on the undead.
func wound(at: Vector3, base: Vector3, stuff: ModelStuff.Stuff, n: int, rng_seed: int, big := false) -> void:
	var p := _preset()
	if p < 0:
		return
	var g := _gore()
	var k := (2.0 if big else 1.0) * (1.6 if g == Gore.EXTRA else 1.0)
	match stuff:
		ModelStuff.Stuff.MACHINE:
			FxBurst.spawn(self, FxBurst.Look.SPARK, at, Vector3.ZERO, int((6 + 2 * n) * k), rng_seed, p)
			FxBurst.spawn(self, FxBurst.Look.PUFF, at, Vector3.UP, int(3 * k), rng_seed + 1, p, 0.7, Color(0.35, 0.33, 0.3))
			if big:
				_splats(p).add(base, 0.035, Color(0.05, 0.04, 0.03, 0.9), rng_seed, maxf(SPLAT_LIFE_S[g], 10.0), 0.0)
		ModelStuff.Stuff.UNDEAD:
			FxBurst.spawn(self, FxBurst.Look.BONE, at, Vector3.ZERO, int((8 + 2 * n) * k), rng_seed, p)
			FxBurst.spawn(self, FxBurst.Look.CHIP, at, Vector3.UP, int((4 + n) * k), rng_seed + 1, p)
		_:
			if g == Gore.OFF:
				FxBurst.spawn(self, FxBurst.Look.DUST, at, Vector3.UP, 6 + 2 * n, rng_seed, p, 0.7)
				return
			FxBurst.spawn(self, FxBurst.Look.MIST, at, Vector3.ZERO, mini(int((10 + 4 * n) * k), 48), rng_seed, p)
			FxBurst.spawn(self, FxBurst.Look.DROP, at, Vector3.UP, int((6 + 2 * n) * k), rng_seed + 1, p)
			for i in (1 + (2 if big else 0) + (2 if g == Gore.EXTRA else 0)):
				var off := Vector3(cos(rng_seed + i * 2.1), 0.0, sin(rng_seed + i * 2.1)) * (0.0 if i == 0 else 0.012 * i)
				_splats(p).add(base + off, (0.04 if big and i == 0 else 0.016) * (1.3 if g == Gore.EXTRA else 1.0),
					Color(0.36, 0.02, 0.02, 0.92), rng_seed + i, SPLAT_LIFE_S[g])


## Saves held: a ricochet at each of the defending models given (unit-level saves, shown on its models).
func ricochets(points: Array, rng_seed: int) -> void:
	var p := _preset()
	for i in (points.size() if p >= 0 else 0):
		FxBurst.spawn(self, FxBurst.Look.SPARK, points[i], Vector3.UP, 5, rng_seed + i, p, 0.8)
		FxBurst.spawn(self, FxBurst.Look.FLASH, points[i], Vector3.ZERO, 1, rng_seed + i, p, 0.4)
