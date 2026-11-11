extends GdUnitTestSuite
## E2E — the maintainer's 29.10.2026 play test: "Die Figuren sollten sich in Richtung ihrer Bewegung drehen."
## While an engine-executed move glides (AI moves, the player's Automodus verbs, pile-ins), each model turns
## its +Z front (ObjectManager.facing_rotation_to) to the leg it travels, so nothing slides sideways or
## backwards; once the unit has glided it turns back to the yaw the executed move left it (the state).
## Presentation only: the second case runs the real executor, then the real glide, and requires every
## rule observable (digest, positions, yaws, oval footprint gap, decision log, rng) bit-identical.
##
## Real: scenes/main.tscn with its real _ready(), the real _ensure_solo_controller wiring, the real
## SoloController executor (activate_next_ai_unit) and the real presentation calls an AI activation makes
## (_solo_present_move_start, _solo_animate_move). Constructed: the GameUnits and their model nodes.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const TOL_DEG := 5.0

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _register(pid: int, unit_name: String, positions: Array, yaw := 0.0) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, positions)
	for m in u.models:
		(m as ModelInstance).node.rotation.y = yaw
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## Runs _solo_animate_move without awaiting it and samples `nodes` every frame until it returns.
## Returns [[{pos, yaw} per node] per frame].
func _glide_sampled(paths: Array, nodes: Array, allow_snap := true) -> Array:
	var done := [false]
	var run := func() -> void:
		await _main._solo_animate_move(paths, allow_snap)
		done[0] = true
	run.call()
	var frames: Array = []
	var deadline := Time.get_ticks_msec() + 30000
	while not done[0] and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		var f: Array = []
		for n in nodes:
			f.append({"pos": (n as Node3D).global_position, "yaw": (n as Node3D).rotation.y})
		frames.append(f)
	assert_bool(done[0]).override_failure_message("the glide never finished").is_true()
	return frames


static func _off_deg(yaw: float, want: float) -> float:
	return absf(rad_to_deg(angle_difference(yaw, want)))


## An L-shaped route (+X, then +Z): on each leg, past its first inch (the turn), the model faces the leg.
## After the glide it is back at the yaw the move left it, to the bit, standing on the route's end.
func test_a_gliding_model_faces_each_leg_then_its_end_facing(timeout := 120000) -> void:
	_main._solo_batch = true    # no attention beats; the glide itself runs at the normal pace
	var a := Vector3(-0.3, 0.0, -0.2)
	var b := Vector3(-0.1, 0.0, -0.2)
	var c := Vector3(-0.1, 0.0, 0.0)
	var u := _register(2, "Glider", [a], 0.7)
	var node := (u.models[0] as ModelInstance).node
	var yaw0 := node.rotation.y   # the stored float32, not the 0.7 literal
	var frames: Array = await _glide_sampled([{"model": u.models[0], "path": [a, b, c], "radius_m": 0.0125}], [node], false)
	var worst := [0.0, 0.0]
	var seen := [0, 0]
	for f in frames:
		var p: Vector3 = (f[0] as Dictionary)["pos"]
		var yaw: float = (f[0] as Dictionary)["yaw"]
		if absf(p.z - a.z) < 0.0001 and p.x > a.x + 0.04 and p.x < b.x - 0.005:        # leg 1, +X
			worst[0] = maxf(worst[0], _off_deg(yaw, PI / 2.0))
			seen[0] += 1
		elif absf(p.x - b.x) < 0.0001 and p.z > b.z + 0.04 and p.z < c.z - 0.005:      # leg 2, +Z
			worst[1] = maxf(worst[1], _off_deg(yaw, 0.0))
			seen[1] += 1
	for leg in 2:
		assert_int(int(seen[leg])).override_failure_message("premise: frames sampled on leg %d" % (leg + 1)) \
			.is_greater_equal(3)
		assert_float(float(worst[leg])).override_failure_message(
			"while gliding leg %d the model faces up to %.1f deg off its direction of travel" % [leg + 1, worst[leg]]) \
			.is_less_equal(TOL_DEG)
	assert_float(node.rotation.y).override_failure_message("after the glide the yaw must be the move's own: %f" % node.rotation.y) \
		.is_equal(yaw0)
	assert_float(node.global_position.x).is_equal_approx(c.x, 0.000001)
	assert_float(node.global_position.z).is_equal_approx(c.z, 0.000001)


## Every rule observable the glide could touch, after the executor and again after the glide.
func _snapshot(units: Array, oval: GameUnit, foe: GameUnit) -> Dictionary:
	var solo: SoloController = _main.solo_controller
	var out := {"digest": solo.state_digest(), "rng": solo._rng.state, "log": [], "models": [],
		"gap": SeparationChecker.edge_distance(SeparationChecker.shape_for_model(oval.models[0]),
			SeparationChecker.shape_for_model(foe.models[0]))}
	for rec in solo.decision_log:
		(out["log"] as Array).append(SoloController.render_decision(rec as Dictionary))
	for u in units:
		for m in (u as GameUnit).models:
			var n := (m as ModelInstance).node
			(out["models"] as Array).append("%s x=%.9f z=%.9f yaw=%.9f" % [(u as GameUnit).get_name(),
				n.global_position.x, n.global_position.z, n.rotation.y])
	return out


## Outcome-identity control: two real AI activations (a round-base unit and an oval), each planned and
## applied by the executor, then replayed by the real glide in the interactive (non-batch) pace. The
## glide must turn a model (the oval swings from its side-on yaw to its travel) and leave every rule
## observable exactly as the executor left it — an oval's yaw IS its footprint, so a leftover turn
## would change base contact, coherency and ranges.
func test_the_glide_turn_changes_no_rule_outcome(timeout := 180000) -> void:
	_main._solo_batch = false
	_main._solo_fast = true
	var foe := _register(1, "Wall", [Vector3(0.0, 0.0, -0.5)])
	var raider := _register(2, "Raider", [Vector3(-0.3, 0.0, 0.45), Vector3(-0.26, 0.0, 0.45)])
	var oval := _register(2, "Crawler", [Vector3(0.3, 0.0, 0.45)], PI / 2.0)
	oval.unit_properties["base_is_oval"] = true
	oval.unit_properties["base_width_mm"] = 60
	oval.unit_properties["base_depth_mm"] = 100
	var units := [foe, raider, oval]
	var solo: SoloController = _main.solo_controller
	solo._rng.seed = 4242
	var turned_deg := 0.0
	for act in 2:
		var unit := solo.activate_next_ai_unit()
		assert_object(unit).override_failure_message("premise: activation %d picks an AI unit" % act).is_not_null()
		var paths: Array = solo.last_move_paths.duplicate()
		assert_bool(paths.is_empty()).override_failure_message("premise: %s really moves" % unit.get_name()).is_false()
		var before := _snapshot(units, oval, foe)
		var nodes: Array = []
		var end_yaws: Array = []
		for m in unit.models:
			nodes.append((m as ModelInstance).node)
			end_yaws.append((m as ModelInstance).node.rotation.y)
		_main._solo_present_move_start(paths)   # the activation's own order: back to the route start, then glide
		var frames: Array = await _glide_sampled(paths, nodes)
		for f in frames:
			for i in nodes.size():
				turned_deg = maxf(turned_deg, _off_deg(float((f[i] as Dictionary)["yaw"]), float(end_yaws[i])))
		var after := _snapshot(units, oval, foe)
		assert_str(str(after["digest"])).is_equal(str(before["digest"]))
		assert_array(after["models"] as Array).is_equal(before["models"] as Array)
		assert_float(float(after["gap"])).is_equal(float(before["gap"]))
		assert_array(after["log"] as Array).is_equal(before["log"] as Array)
		assert_int(int(after["rng"])).is_equal(int(before["rng"]))
	assert_float(turned_deg).override_failure_message("the glide never turned a model: %.1f deg at most" % turned_deg) \
		.is_greater(30.0)


## Control: a regiment tray's facing is an AoF: Regiments rule (a pivot) — it never turns while it glides.
func test_a_regiment_keeps_its_facing_while_it_glides(timeout := 120000) -> void:
	_main._solo_batch = true
	_main._solo_fast = true
	var a := Vector3(-0.3, 0.0, -0.2)
	var b := Vector3(-0.1, 0.0, -0.2)
	var u := _register(2, "Block", [a], 0.7)
	_main.opr_army_manager.regiments[u.unit_id] = {}
	var node := (u.models[0] as ModelInstance).node
	var yaw0 := node.rotation.y
	var frames: Array = await _glide_sampled([{"model": u.models[0], "path": [a, b], "radius_m": 0.0125}], [node], false)
	assert_int(frames.size()).override_failure_message("premise: frames sampled").is_greater_equal(3)
	for f in frames:
		assert_float(float((f[0] as Dictionary)["yaw"])).is_equal(yaw0)
	assert_float(node.global_position.x).is_equal_approx(b.x, 0.000001)
