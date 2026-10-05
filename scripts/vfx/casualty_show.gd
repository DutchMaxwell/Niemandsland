class_name CasualtyShow
extends Node3D
## Combat effects: what a resolved hit does to the models — drawn only from the resolver's results, never deciding
## one: a burst where a wound landed (blood mist and drops on flesh, sparks and an oil spot on machines, bone dust on
## the undead), pools on the ground by the Gore setting (Off: dust, no blood), ricochet sparks on the defending models
## when saves hold; where a model fell, a dust burst plus a GHOST of it that tips over and sinks while the real model
## is parked at once (state timing unchanged; the ghost is only meshes — no script, group or collision). A heavy kill
## shakes the camera a little through its h/v offset, never the controller. Reduce Motion: no show at all.

enum Gore { OFF, NORMAL, EXTRA }
const SPLAT_LIFE_S := [0.0, 10.0, 30.0]   # per Gore level
const SKIP_PARTS := ["Marker", "Ring", "Preview", "Selection", "Overlay", "Highlight", "Aura"]   # never on a ghost
const COLLAPSE_S := 0.7

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


## A model fell at `base` (its base spot): dust, the wound burst at its eye, and a shake when `heavy`.
func kill(eye: Vector3, base: Vector3, stuff: ModelStuff.Stuff, heavy: bool, rng_seed: int) -> void:
	var p := _preset()
	if p < 0:
		return
	wound(eye, base, stuff, 2, rng_seed, true)
	FxBurst.spawn(self, FxBurst.Look.DUST, base, Vector3.UP, 12, rng_seed + 3, p, 1.2)
	if heavy:
		shake(0.006)


## The picture of a falling model: a mesh-only copy tips over and sinks while the real one is already parked.
func collapse(model: Node3D, rng_seed: int) -> Node3D:
	if _preset() < 0 or model == null or not is_instance_valid(model) or not model.is_inside_tree():
		return null
	var ghost := Node3D.new()
	add_child(ghost)
	ghost.global_transform = model.global_transform
	_copy_meshes(model, model, ghost)
	var axis := Vector3(cos(rng_seed * 0.7), 0.0, sin(rng_seed * 0.7))   # a fixed fall direction per seed, no RNG
	var tw := ghost.create_tween()
	tw.tween_property(ghost, "transform:basis", Basis(axis, deg_to_rad(80.0)) * ghost.transform.basis,
		COLLAPSE_S * 0.6).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(ghost, "position:y", ghost.position.y - 0.01, COLLAPSE_S * 0.4)
	tw.tween_callback(ghost.queue_free)
	return ghost


func _copy_meshes(root: Node3D, n: Node, ghost: Node3D) -> void:
	for c in n.get_children():
		if SKIP_PARTS.any(func(s: String) -> bool: return String(c.name).contains(s)):
			continue
		if c is MeshInstance3D and (c as MeshInstance3D).is_visible_in_tree() and (c as MeshInstance3D).skin == null:
			var m := MeshInstance3D.new()
			m.mesh = (c as MeshInstance3D).mesh
			m.material_override = (c as MeshInstance3D).material_override
			for si in (m.mesh.get_surface_count() if m.mesh != null else 0):
				m.set_surface_override_material(si, (c as MeshInstance3D).get_surface_override_material(si))
			ghost.add_child(m)
			m.transform = root.global_transform.affine_inverse() * (c as MeshInstance3D).global_transform
		_copy_meshes(root, c, ghost)


## A small decaying camera shake through h/v offset (a fixed pattern, no RNG).
func shake(strength: float) -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null or _preset() < 0:
		return
	var h0 := float(cam.get_meta("vfx_h0", cam.h_offset))   # the offsets as they were before any shake began
	var v0 := float(cam.get_meta("vfx_v0", cam.v_offset))
	cam.set_meta("vfx_h0", h0)
	cam.set_meta("vfx_v0", v0)
	var tw := cam.create_tween()
	for i in 6:
		var k := strength * (1.0 - i / 6.0)
		tw.tween_property(cam, "h_offset", h0 + k * (1.0 if i % 2 == 0 else -1.0), 0.035)
		tw.parallel().tween_property(cam, "v_offset", v0 + k * 0.6 * (1.0 if i % 3 == 0 else -1.0), 0.035)
	tw.tween_property(cam, "h_offset", h0, 0.04)
	tw.parallel().tween_property(cam, "v_offset", v0, 0.04)
	tw.tween_callback(func() -> void:
		cam.remove_meta("vfx_h0")
		cam.remove_meta("vfx_v0"))
