extends GdUnitTestSuite
## E2E — #210 last slice: after the automatic legal wreck-spill placement the human owner
## gets the standard formation-at-cursor ghost over the wreck's 6" ring (the disembark-ghost
## path, PlacementGhost.circle_zone). The decided semantics: ESC / right-click CONFIRMS the
## automatic formation (a replay stays identical when nobody touches the ghost), a legal LMB
## drop inside the ring repositions, a drop outside is refused (the click is swallowed), and
## the AI never sees the ghost (headless/AI spill path unchanged).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _probe: Callable = Callable()
var _facts: Dictionary = {}


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_probe = Callable()
	_facts = {}


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _solo_playing_on() -> void:
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING


## Transport(6) truck at the origin + human cargo embarked, then the truck killed through the
## real dead-parking choke point — the cargo spills and is placed AUTOMATICALLY (the state half).
func _spilled_cargo(pid: int) -> Array:
	var truck := E2EBoot.make_unit(_main, pid, "Truck%d" % pid, [Vector3.ZERO])
	truck.unit_properties["special_rules"] = ["Transport(6)"]
	var cargo := E2EBoot.make_unit(_main, pid, "Riders%d" % pid, [Vector3(0.04, 0, 0)])
	for u in [truck, cargo]:
		_main.opr_army_manager.game_units[u.unit_id] = u
	assert_bool(_main.opr_army_manager.set_unit_embarked(cargo, truck, true)).is_true()
	var m := truck.models[0] as ModelInstance
	m.node.set_meta("model_instance", m)
	m.is_alive = false
	_main.opr_army_manager.set_loose_model_dead(m.node, pid, true, truck.unit_id)
	await _runner.simulate_frames(2)
	return [truck, cargo]


func _cargo_spots(cargo: GameUnit) -> Array:
	var out: Array = []
	for m in cargo.get_alive_models():
		var n: Node3D = (m as ModelInstance).node
		if n != null and is_instance_valid(n):
			out.append(n.global_position)
	return out


func _spots_equal(a: Array, b: Array, eps: float) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if (a[i] as Vector3).distance_to(b[i] as Vector3) > eps:
			return false
	return true


func _open_ghost() -> PlacementGhost:
	for c in _main.radial_menu_controller.get_children():
		if c is PlacementGhost:
			return c
	return null


## Timer hook: while _offer_spill_ghost is awaiting, hand the open ghost to the test's probe.
func _probe_open_ghost() -> void:
	var ghost := _open_ghost()
	_facts["offered"] = ghost != null
	if ghost == null:
		return
	if _probe.is_valid():
		_probe.call(ghost)


func _cancel_ghost() -> void:
	var g := _open_ghost()
	if g != null:
		(g as PlacementGhost)._finish(false)


func _click(button: MouseButton) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = true
	return ev


func test_the_spill_offers_the_ghost_over_the_six_inch_ring(timeout := 120000) -> void:
	_solo_playing_on()
	var tc := await _spilled_cargo(1)
	var truck: GameUnit = tc[0]
	var cargo: GameUnit = tc[1]
	assert_object(_main.opr_army_manager.transport_of(cargo)) \
		.override_failure_message("fixture check: the cargo never spilled") \
		.is_null()
	_probe = func(g: PlacementGhost) -> void:
		var zone: Dictionary = g._zone
		_facts["kind"] = str(zone.get("kind", ""))
		_facts["m"] = float(zone.get("m", -1.0))
		_facts["c"] = zone.get("c", Vector3.INF)
		var t_r: float = SeparationChecker.DEFAULT_BASE_RADIUS_M
		var ts := SeparationChecker.shape_for_model(truck.models[0] as ModelInstance)
		if ts != null:
			t_r = ts.bounding_radius()
		_facts["want_m"] = OPRArmyManager.DISEMBARK_ZONE_IN * 0.0254 + t_r
		(g as PlacementGhost)._finish(false)   # ESC: keep the auto formation
	get_tree().create_timer(0.2).timeout.connect(_probe_open_ghost)
	await _main.radial_menu_controller._offer_spill_ghost(truck, cargo)
	assert_bool(bool(_facts.get("offered", false))) \
		.override_failure_message("#210 — no formation-at-cursor ghost was offered after the spill") \
		.is_true()
	assert_str(str(_facts.get("kind", ""))) \
		.override_failure_message("#210 — the offered zone is not the 6\" circle zone") \
		.is_equal("circle")
	assert_float(float(_facts.get("m", -1.0))).is_equal_approx(float(_facts.get("want_m", -2.0)), 0.001)
	assert_vector(_facts.get("c", Vector3.INF) as Vector3) \
		.override_failure_message("#210 — the ghost is not anchored at the wreck's last table spot") \
		.is_equal_approx(Vector3.ZERO, Vector3(0.01, 0.01, 0.01))


func test_esc_keeps_the_automatic_placement(timeout := 120000) -> void:
	# The decided cancel semantics: ESC (PlacementGhost._finish(false)) confirms the auto
	# formation — nobody touches the ghost, the replay stays byte-identical.
	_solo_playing_on()
	var tc := await _spilled_cargo(1)
	var truck: GameUnit = tc[0]
	var cargo: GameUnit = tc[1]
	var auto_spots := _cargo_spots(cargo)
	_probe = func(g: PlacementGhost) -> void:
		(g as PlacementGhost)._finish(false)
	get_tree().create_timer(0.2).timeout.connect(_probe_open_ghost)
	await _main.radial_menu_controller._offer_spill_ghost(truck, cargo)
	assert_bool(_spots_equal(_cargo_spots(cargo), auto_spots, 0.001)) \
		.override_failure_message("#210 — ESC moved the unit: the automatic spill placement must stand") \
		.is_true()
	assert_str(_log_text()).contains("keeps its automatic formation")


func test_a_legal_drop_inside_the_ring_repositions(timeout := 120000) -> void:
	_solo_playing_on()
	var tc := await _spilled_cargo(1)
	var truck: GameUnit = tc[0]
	var cargo: GameUnit = tc[1]
	var target := Vector3(0.12, 0, 0)   # ~4.7" from the wreck, clear of everything
	_probe = func(g: PlacementGhost) -> void:
		g._cursor = target
		_facts["valid"] = g.is_valid_now()
		_facts["want"] = g.placement_positions()
		(g as PlacementGhost)._finish(true)   # the LMB commit
	get_tree().create_timer(0.2).timeout.connect(_probe_open_ghost)
	await _main.radial_menu_controller._offer_spill_ghost(truck, cargo)
	assert_bool(bool(_facts.get("valid", false))) \
		.override_failure_message("fixture check: the target spot is not legal inside the ring") \
		.is_true()
	assert_bool(_spots_equal(_cargo_spots(cargo), _facts.get("want", []) as Array, 0.001)) \
		.override_failure_message("#210 — the legal drop did not reposition the unit inside the ring") \
		.is_true()
	assert_str(_log_text()).contains("re-forms beside the wreck")


func test_a_drop_outside_the_ring_is_refused(timeout := 120000) -> void:
	# The refusal rides the REAL click path: PlacementGhost._unhandled_input with a LEFT press
	# at an invalid cursor must be swallowed — no commit, ghost still open, auto spots stand.
	_solo_playing_on()
	var tc := await _spilled_cargo(1)
	var truck: GameUnit = tc[0]
	var cargo: GameUnit = tc[1]
	var auto_spots := _cargo_spots(cargo)
	_probe = func(g: PlacementGhost) -> void:
		g._cursor = Vector3(0.5, 0, 0)   # ~20" out — outside the 6" ring
		_facts["valid"] = g.is_valid_now()
		g._unhandled_input(_click(MOUSE_BUTTON_LEFT))
		_facts["still_open"] = not g.is_queued_for_deletion()
	get_tree().create_timer(0.2).timeout.connect(_probe_open_ghost)
	get_tree().create_timer(0.8).timeout.connect(_cancel_ghost)   # close the still-open ghost
	await _main.radial_menu_controller._offer_spill_ghost(truck, cargo)
	assert_bool(bool(_facts.get("valid", true))) \
		.override_failure_message("fixture check: the far cursor reads as legal — the ring is not enforced") \
		.is_false()
	assert_bool(bool(_facts.get("still_open", false))) \
		.override_failure_message("#210 — the invalid LMB drop committed instead of being refused") \
		.is_true()
	assert_bool(_spots_equal(_cargo_spots(cargo), auto_spots, 0.001)) \
		.override_failure_message("#210 — the refused drop moved the unit") \
		.is_true()


func test_the_ai_cargo_spills_without_a_ghost(timeout := 120000) -> void:
	# Solo controller path unchanged: NACHTMAHR's cargo spills automatically, no ghost is
	# offered, and the offer loop must not hang the spill replay.
	_solo_playing_on()
	var tc := await _spilled_cargo(2)
	var truck: GameUnit = tc[0]
	var cargo: GameUnit = tc[1]
	await _runner.simulate_frames(6)
	assert_bool(bool(_facts.get("offered", false))).is_false()
	assert_object(_main.opr_army_manager.transport_of(cargo)) \
		.override_failure_message("#210 — the AI cargo never spilled") \
		.is_null()
	assert_bool((cargo as GameUnit).is_shaken).is_true()
	assert_bool(_open_ghost() == null) \
		.override_failure_message("#210 — a ghost was offered for AI cargo") \
		.is_true()


func _log_text() -> String:
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text
