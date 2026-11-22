class_name BoardgenTownLife
extends Node3D
## SOMETHING STILL MOVES, QUIETLY (plan PLAN_RUINTOWN_GRIT L1-L3, style bible 14): the lanterns and embers flicker +-6 % (smooth noise 2-7 Hz, a phase per light from the board seed), thin
## smoke rises from the chimneys of the intact houses and from the burnt yards (one GPUParticles3D per emitter, at most MAX_SMOKE, alpha <= 0.25, no shadow, above the roofs), a few crows sit
## on the merlons and rats run along the wall feet (tiny, dull, no collider, no shadow, never on standing room the core gives as cover: a crow sits on a merlon, a rat in the 0.75 in strip).
## Nothing here blocks or occludes a model. Off on Low and below; under the reduce-motion setting it stands still. `pinned` (the capture and the gate set it) freezes the clock at t = 0, so a
## still is reproducible.

const INCHES_TO_METERS := 0.0254
const FLICKER := 0.06
const MAX_SMOKE := 6
const CROWS := 8
const RATS := 4
static var pinned := false

var _lights: Array = []   # [light, base energy, phase]
var _rats: MultiMeshInstance3D = null
var _rat_paths: Array = []   # [from (m), to (m), phase]
var _t := 0.0
var _motion := true
var _kit_rat := false   # the A8 rat (its head on local +x) instead of the capsule


func build(layout: Dictionary, board: Node) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(layout.get("seed", 0)) * 911 + 5
	for n in board.find_children("*", "Light3D", true, false):
		var nm := str(n.name)
		if nm.begins_with("Lantern") or nm.begins_with("Ember"):
			if nm.begins_with("Ember"):
				(n as Light3D).light_energy *= 0.35   # embers glow LOW inside the heaps (lead 21.11.): a dull red, not a lamp
			_lights.append([n, (n as Light3D).light_energy, rng.randf() * 100.0])
	var town_kit := board.get_node_or_null("TownKit") as BoardgenTownKit   # the A8 crows and rats when they are cached (else the plain stand-ins)
	var kit: BoardgenKit = town_kit.kit if town_kit != null else null
	_add_smoke(layout, rng)
	_add_crows(layout, rng, kit)
	_add_rats(layout, rng, kit)
	apply_settings()


## Low and below: no life; reduce-motion: it stands still.
func apply_settings() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var gs: Node = tree.root.get_node_or_null("GraphicsSettings") if tree != null else null
	var on: bool = gs == null or int(gs.current_preset) >= 2
	visible = on
	_motion = on and not pinned and (gs == null or not bool(gs.reduce_motion))
	for p in find_children("*", "GPUParticles3D", true, false):
		(p as GPUParticles3D).emitting = on
		(p as GPUParticles3D).speed_scale = 1.0 if _motion else 0.0
	if not _motion:
		_set_lights(0.0)


func _process(delta: float) -> void:
	if not _motion:
		return
	_t += delta
	_set_lights(_t)
	if _rats != null:
		for i in _rat_paths.size():
			var r: Array = _rat_paths[i]
			var s := 0.5 + 0.5 * sin(_t * 0.35 + float(r[2]))
			var p: Vector3 = (r[0] as Vector3).lerp(r[1], s)
			var dir: Vector3 = (r[1] - r[0]).normalized() * (1.0 if cos(_t * 0.35 + float(r[2])) > 0.0 else -1.0)
			_rats.multimesh.set_instance_transform(i, Transform3D(_rat_basis(dir), p))


func _rat_basis(dir: Vector3) -> Basis:
	return Basis(Vector3.UP, atan2(-dir.z, dir.x)) if _kit_rat else Basis.looking_at(dir, Vector3.UP) * Basis(Vector3.RIGHT, PI * 0.5)


## Where the crows sit (board inches, the perch's top): the merlons, and the ridges of the whole gable roofs (a third and two thirds along) - perches no model can stand on.
static func crow_perches(layout: Dictionary) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for m: Dictionary in BoardgenTownDressing.merlons(layout):
		out.append(Vector3((m["lo"].x + m["hi"].x) * 0.5, float(m["hi"].y), (m["lo"].z + m["hi"].z) * 0.5))
	var strips: Array[Dictionary] = []
	for whole: Dictionary in BoardgenTownDressing.roofs(layout):
		strips.append_array(BoardgenTownDressing.ridge_strips(whole))   # (L1) each ridge of a twin roof
	for r: Dictionary in strips:
		if r["type"] != "gable" or (r.get("damage", "whole") != "whole" and r["strip"] == 0):
			continue   # (a broken roof of the kit has no whole ridge)
		var dir: Vector2 = (Vector2(1, 0) if r["along_x"] else Vector2(0, 1)).rotated(-float(r["yaw"]))
		for k in [-0.2, 0.2]:
			var at: Vector2 = r["centre"] + dir * float(r["length"]) * k
			out.append(Vector3(at.x, float(r["eaves"]) + float(r["height"]), at.y))
	return out


## +-FLICKER on every lantern and ember: three slow sines between 2 and 7 Hz, a phase per light (t = 0: the base energy exactly).
func _set_lights(t: float) -> void:
	for l: Array in _lights:
		var light: Light3D = l[0]
		if not is_instance_valid(light):
			continue
		var ph: float = l[2]
		var n := 0.5 * sin(TAU * 2.1 * t + ph) + 0.3 * sin(TAU * 4.3 * t + ph * 1.7) + 0.2 * sin(TAU * 6.8 * t + ph * 2.3)
		light.light_energy = float(l[1]) * (1.0 + FLICKER * (n if t > 0.0 else 0.0))


func _add_smoke(layout: Dictionary, rng: RandomNumberGenerator) -> void:
	var spots: Array[Vector3] = []
	for c: Dictionary in BoardgenTownDressing.chimneys(layout):
		var lo: Vector3 = c["lo"]
		var hi: Vector3 = c["hi"]
		spots.append(Vector3((lo.x + hi.x) * 0.5, hi.y + 0.2, (lo.z + hi.z) * 0.5))
	for s: Dictionary in BoardgenTownScenes.plan(layout)["scenes"]:
		if s["kind"] == "burnt":
			var at: Vector2 = s["at"]
			spots.append(Vector3(at.x, 0.7, at.y))
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(0.55, 0.55, 0.56, 1.0)
	var puff := GradientTexture2D.new()   # a soft round puff, not a square
	puff.fill = GradientTexture2D.FILL_RADIAL
	puff.fill_from = Vector2(0.5, 0.5)
	puff.fill_to = Vector2(0.5, 0.0)
	var pg := Gradient.new()
	pg.set_color(0, Color(1, 1, 1, 1))
	pg.set_color(1, Color(1, 1, 1, 0))
	puff.gradient = pg
	puff.width = 64
	puff.height = 64
	mat.albedo_texture = puff
	var quad := QuadMesh.new()
	quad.size = Vector2(0.8, 0.8) * INCHES_TO_METERS
	quad.material = mat
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.0))
	fade.set_color(1, Color(1, 1, 1, 0.0))
	fade.add_point(0.25, Color(1, 1, 1, 0.16))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	var tale := BoardgenTownDressing.story(int(layout.get("seed", 0)))
	for k in mini(spots.size(), MAX_SMOKE):
		var p := GPUParticles3D.new()
		p.name = "Smoke%d" % k
		var pm := ParticleProcessMaterial.new()
		pm.direction = Vector3(0, 1, 0)
		pm.spread = 8.0
		pm.initial_velocity_min = 0.010
		pm.initial_velocity_max = 0.016
		pm.gravity = Vector3(tale.r, 0.0, tale.g) * 0.004   # the story's wind
		pm.scale_min = 0.8
		pm.scale_max = 2.2
		pm.color_ramp = ramp
		p.process_material = pm
		p.draw_pass_1 = quad
		p.amount = 10
		p.lifetime = 6.0
		p.preprocess = 6.0
		p.use_fixed_seed = true
		p.seed = rng.randi()
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		p.visibility_aabb = AABB(Vector3(-0.1, 0.0, -0.1), Vector3(0.2, 0.25, 0.2))
		p.position = spots[k] * INCHES_TO_METERS
		add_child(p)


func _add_crows(layout: Dictionary, rng: RandomNumberGenerator, kit: BoardgenKit = null) -> void:
	var perches := crow_perches(layout)
	if perches.is_empty():
		return
	var mesh: Mesh = null
	if kit != null and kit.usable(["crow_perched"]):
		mesh = kit.mesh_or("crow_perched")   # the A8 crow (matt black-grey, 0.21 in)
	if mesh == null:
		var prism := PrismMesh.new()   # a hunched body: 0.22 in long, dull black-grey, far from both armies' hues
		prism.size = Vector3(0.09, 0.1, 0.22) * INCHES_TO_METERS
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.06, 0.06, 0.065)
		mat.roughness = 0.6
		prism.material = mat
		mesh = prism
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	var n := mini(CROWS, perches.size())
	mm.instance_count = n
	var order := range(perches.size())
	BoardgenTownScenes._shuffle(order, rng)
	var ridges := order.filter(func(k: int) -> bool: return k >= BoardgenTownDressing.merlons(layout).size())
	order = ridges.slice(0, 3) + order.filter(func(k: int) -> bool: return not ridges.slice(0, 3).has(k))   # up to three on the roofs, the rest on the battlements
	for i in n:
		var top: Vector3 = perches[order[i]] + Vector3(0.0, 0.05 if mesh is PrismMesh else 0.0, 0.0)
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, rng.randf() * TAU), top * INCHES_TO_METERS))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Crows"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


func _add_rats(layout: Dictionary, rng: RandomNumberGenerator, kit: BoardgenKit = null) -> void:
	var strips: Array = []   # wall-foot runs in the strip: [from, to] inches, 0.2 in off a wall face
	var c := float(layout["cell_in"])
	var origin := Vector2(layout["nx"], layout["nz"]) * c * -0.5
	var run := func(cell: Vector2, d: Vector2i) -> Array:   # the open cell `cell`, its wall in direction d
		var lo := origin + cell * c
		var a := Vector2(lo.x + 0.3, lo.y + 0.2) if d.y < 0 else (Vector2(lo.x + 0.3, lo.y + c - 0.2) if d.y > 0 else (Vector2(lo.x + 0.2, lo.y + 0.3) if d.x < 0 else Vector2(lo.x + c - 0.2, lo.y + 0.3)))
		return [a, a + (Vector2(c - 0.6, 0.0) if d.x == 0 else Vector2(0.0, c - 0.6))]
	for b: Dictionary in BoardgenTownDressing.props(layout):
		if typeof(b.get("face")) == TYPE_VECTOR2I:
			strips.append(run.call(b["at"], b["face"]))
	var nx: int = layout["nx"]
	var feet: Array[Vector2] = []   # the city wall's own feet (kit batch A7 wiring): the town side of a wall cell, where no buttress or spill stands
	var walls := BoardgenTownClutter.wall_feet(layout)
	for m: String in walls:
		for it: Dictionary in walls[m]:
			var o: Vector3 = (it["xf"] as Transform3D).origin / INCHES_TO_METERS
			feet.append(Vector2(o.x, o.z))
	var clear := BoardgenTownClutter._kept_clear(layout)
	for cd: Dictionary in layout["cells"]:
		if cd["lot_kind"] != "Wall" or int(cd["level"]) < 1:
			continue
		var d := Vector2i(1, 0) if int(cd["x"]) * 2 < nx else Vector2i(-1, 0)   # the town side
		var f := Vector2i(cd["x"], cd["z"]) + d
		if f.x < 0 or f.x >= nx or clear.has(f.y * nx + f.x):
			continue
		var fc: Dictionary = layout["cells"][f.y * nx + f.x]
		if int(fc["level"]) != 0 or ["Hazard", "Wall", "Rough"].has(fc["lot_kind"]):
			continue
		var r: Array = run.call(Vector2(f), -d)
		if feet.all(func(p: Vector2) -> bool: return p.distance_to((r[0] + r[1]) * 0.5) > 2.0):
			strips.append(r)
	if strips.is_empty():
		return
	BoardgenTownScenes._shuffle(strips, rng)
	var mesh: Mesh = null
	if kit != null and kit.usable(["rat_running"]):
		mesh = kit.mesh_or("rat_running")   # the A8 rat (0.14 in body, dull brown-grey)
		_kit_rat = mesh != null
	if mesh == null:
		var capsule := CapsuleMesh.new()   # 0.14 in long, 0.05 in high: far below anything a model could hide behind
		capsule.radius = 0.025 * INCHES_TO_METERS
		capsule.height = 0.14 * INCHES_TO_METERS
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.16, 0.13, 0.11)
		capsule.material = mat
		mesh = capsule
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	var n := mini(RATS, strips.size())
	mm.instance_count = n
	for i in n:
		var s: Array = strips[i]
		var y := 0.0 if _kit_rat else 0.025
		var from := Vector3(s[0].x, y, s[0].y) * INCHES_TO_METERS
		var to := Vector3(s[1].x, y, s[1].y) * INCHES_TO_METERS
		_rat_paths.append([from, to, rng.randf() * TAU])
		mm.set_instance_transform(i, Transform3D(_rat_basis((to - from).normalized()), from.lerp(to, 0.5)))
	_rats = MultiMeshInstance3D.new()
	_rats.name = "Rats"
	_rats.multimesh = mm
	_rats.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_rats)
