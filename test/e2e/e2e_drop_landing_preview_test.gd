extends GdUnitTestSuite
## E2E - Automodus rework step 2.1: ObjectManager.preview_drop_landing() asks the drop's own
## resolver where a drop would leave the dragged bases, without moving anything or emitting.
## Step 2.2: while a model drag runs in the PLAYING phase, LandingPreview shows one ghost base per
## model at that landing; the drop and Esc clear it, deployment shows none.
## Step 2.3b: ONE line per enemy unit the dragged unit reaches and sees from the landing. Ghosts and lines take
## turns on the throttled tick, a lines-tick checks one enemy, and the ghosts recompute only after a 0.25" move.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const TOL := 1e-4
const INCH := 0.0254

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _separated_count := 0
var _aim := Vector3.ZERO   # the cursor's table point; _ticks re-aims at it


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(10)


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _unit_of(node: Node3D, uid: String, player: int) -> void:
	_unit_of_all([node], uid, player)


func _unit_of_all(nodes: Array, uid: String, player: int) -> void:
	var unit := GameUnit.new()
	unit.unit_id = uid
	unit.unit_properties = {"player_id": player, "name": uid, "quality": 4, "defense": 4}
	for node in nodes:
		var mi := ModelInstance.new()
		mi.is_alive = true
		mi.unit = unit
		mi.node = node
		unit.models.append(mi)
		node.set_meta("game_unit", unit)
		node.set_meta("model_instance", mi)
	_main.get_node("OPRArmyManager").game_units[uid] = unit


func test_preview_matches_the_drop() -> void:
	var om: Object = _main.object_manager
	var mover: Node3D = om.call("spawn_miniature", Vector3(0.0, 0.0, 0.0), false)
	# 0.3" (7.6 mm) outside base contact for the default 32 mm round base.
	var enemy: Node3D = om.call("spawn_miniature", Vector3(0.032 + 0.00762, 0.0, 0.0), false)
	_unit_of(mover, "am21_mover", 1)
	_unit_of(enemy, "am21_enemy", 2)
	om.set("_selected_objects", [mover] as Array[Node3D])
	om.set("_is_dragging", true)
	om.connect("drop_separated", func(_applied: bool) -> void: _separated_count += 1)
	var start := mover.global_position

	var preview: Dictionary = om.call("preview_drop_landing")

	assert_bool(preview.has(mover)).is_true()
	assert_vector(mover.global_position).is_equal(start)
	assert_int(_separated_count).is_equal(0)
	var landing: Vector3 = preview[mover]
	assert_float(Vector2(landing.x, landing.z).distance_to(Vector2(start.x, start.z))) \
		.override_failure_message("the 0.3 inch near miss should have been snapped, else this test proves nothing") \
		.is_greater(0.001)

	om.call("_stop_dragging")
	assert_float(mover.global_position.x).is_equal_approx(landing.x, TOL)
	assert_float(mover.global_position.z).is_equal_approx(landing.z, TOL)
	assert_int(_separated_count).is_equal(1)


## Step 2.2 fixture: a 3-model unit of `player` picked up through the real drag path and dragged 4"
## (+z), in `phase`. An enemy waits 0.3" outside contact of the third model's end spot, so that model's
## landing is the resolver's snap, not the cursor position. Returns the three model nodes.
func _drag_three(phase: int, player: int = 1) -> Array[Node3D]:
	var om: Object = _main.object_manager
	_main.get_node("OPRArmyManager").call("set_game_phase", phase)
	var models: Array[Node3D] = []
	for i in 3:
		models.append(om.call("spawn_miniature", Vector3(0.05 * i, 0.0, 0.0), false))
	_unit_of_all(models, "am22_mover", player)
	var end_z := 0.1016
	var enemy: Node3D = om.call("spawn_miniature", Vector3(0.1, 0.0, end_z + 0.032 + 0.00762), false)
	_unit_of(enemy, "am22_enemy", 3 - player)
	om.call("select_objects", models)
	var cam := _main.get_viewport().get_camera_3d()
	om.call("_start_dragging", cam.unproject_position(models[0].global_position))
	om.set("_coherency_update_timer", 1.0)  # the next _update_drag runs the throttled tick
	om.call("_update_drag", cam.unproject_position(models[0].global_position + Vector3(0.0, -_drag_lift(), end_z)))
	return models


func _drag_lift() -> float:
	return float(_main.object_manager.get("drag_lift_height"))


func _ghost_xz() -> Array:
	var out: Array = []
	var root: Node = _main.landing_preview.get_node_or_null("LandingPreviewRoot")
	if root != null:
		for disc in root.get_children():
			out.append(Vector2((disc as Node3D).global_position.x, (disc as Node3D).global_position.z))
	return out


func test_ghosts_follow_a_drag() -> void:
	assert_object(_main.object_manager.get("landing_preview")).is_same(_main.landing_preview)
	var models := _drag_three(OPRArmyManager.GamePhase.PLAYING)
	assert_int(_main.landing_preview.ghost_count()).is_equal(3)
	var ghosts := _ghost_xz()
	var cursor_xz := Vector2(models[2].global_position.x, models[2].global_position.z)

	_main.object_manager.call("_stop_dragging")
	assert_int(_main.landing_preview.ghost_count()).is_equal(0)
	for m in models:
		var landed := Vector2(m.global_position.x, m.global_position.z)
		var nearest := INF
		for g in ghosts:
			nearest = minf(nearest, landed.distance_to(g))
		assert_float(nearest).override_failure_message("no ghost within 1 mm of %s" % m.name).is_less_equal(0.001)
	assert_float(Vector2(models[2].global_position.x, models[2].global_position.z).distance_to(cursor_xz)) \
		.override_failure_message("the 0.3 inch near miss should have been snapped, else this test proves nothing") \
		.is_greater(0.001)


func test_esc_clears_the_ghosts() -> void:
	_drag_three(OPRArmyManager.GamePhase.PLAYING)
	assert_int(_main.landing_preview.ghost_count()).is_equal(3)
	_main.object_manager.call("_cancel_drag")
	assert_int(_main.landing_preview.ghost_count()).is_equal(0)


func test_no_ghosts_in_deployment() -> void:
	_drag_three(OPRArmyManager.GamePhase.DEPLOYMENT)
	assert_bool(bool(_main.object_manager.get("_is_dragging"))).is_true()
	assert_int(_main.landing_preview.ghost_count()).is_equal(0)


## An off-turn drag on a hotseat Automatic table snaps back on release, so no ghost may promise a
## landing; the ghost tick never logs (the release writes the one "not on turn" line).
func test_no_ghosts_on_an_off_turn_hotseat_drag() -> void:
	_main.opr_army_manager.rules_automation = RulesAutomation.Level.AUTOMATIC
	_drag_three(OPRArmyManager.GamePhase.PLAYING, 2)  # P1 opens the round, so P2 is off-turn
	assert_int(_main.landing_preview.ghost_count()).is_equal(0)
	_main.object_manager.call("_stop_dragging")
	var lines := 0
	for e in _main.battle_log.entries():
		if str((e as Dictionary)["text"]).find("is not on turn") != -1:
			lines += 1
	assert_int(lines).is_equal(1)


## Step 2.3 fixture: `uid` over `nodes`, armed with one 12" rifle (the volley reads the OPR weapons).
func _armed(nodes: Array, uid: String, player: int) -> GameUnit:
	_unit_of_all(nodes, uid, player)
	var opr := OPRApiClient.OPRUnit.new()
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Rifle"
	w.range_value = 12
	opr.weapons = [w]
	var unit: GameUnit = _main.get_node("OPRArmyManager").game_units[uid]
	unit.source_type = "opr"
	unit.source_data = opr
	return unit


## Pick `models` up through the real drag path and move them `dz` metres (+z); the throttled tick runs once.
func _drag_by(models: Array, dz: float) -> void:
	var om: Object = _main.object_manager
	om.call("select_objects", models)
	om.call("_start_dragging", _main.get_viewport().get_camera_3d().unproject_position(models[0].global_position))
	_aim = models[0].global_position + Vector3(0.0, -_drag_lift(), dz)
	_ticks(1)


## `n` throttled drag ticks with the cursor on `_aim`, moved `dz` metres (+z) first.
func _ticks(n: int, dz := 0.0) -> void:
	_aim.z += dz
	var cam := _main.get_viewport().get_camera_3d()
	for i in n:
		_main.object_manager.set("_coherency_update_timer", 1.0)
		_main.object_manager.call("_update_drag", cam.unproject_position(_aim))


## Solo table (slot 2 = AI): a 3-model unit with 12" rifles; enemy A 15" ahead (11" after a 4" drag, out of
## reach before it), enemy B 26" ahead (22" after it). Returns the mover's model nodes.
func _solo_lines_table() -> Array[Node3D]:
	_main.solo_ai_slots = {2: true}
	_main.get_node("OPRArmyManager").call("set_game_phase", OPRArmyManager.GamePhase.PLAYING)
	var om: Object = _main.object_manager
	var models: Array[Node3D] = []
	for i in 3:
		models.append(om.call("spawn_miniature", Vector3(0.05 * i, 0.0, 0.0), false))
	var mover := _armed(models, "am23_mover", 1)
	var foe_a := _armed([om.call("spawn_miniature", Vector3(0.05, 0.0, 15 * INCH), false)], "am23_foe_a", 2)
	_armed([om.call("spawn_miniature", Vector3(0.05, 0.0, 26 * INCH), false)], "am23_foe_b", 2)
	assert_int(_main._solo_volley_sighted(mover, foe_a)) \
		.override_failure_message("A must be out of reach before the drag, else this test proves nothing").is_equal(0)
	return models


## OD 7: while the drag runs, exactly ONE line (for A, from the landing); the drop and Esc clear it.
func test_drag_shows_one_line_per_enemy_in_range() -> void:
	var models := _solo_lines_table()
	var om: Object = _main.object_manager
	_drag_by(models, 4 * INCH)
	_ticks(4)   # both enemies checked
	assert_int(_main.landing_preview.ghost_count()).is_equal(3)
	assert_int(_main.landing_preview.line_count()).is_equal(1)
	om.call("_stop_dragging")
	assert_int(_main.landing_preview.line_count()).is_equal(0)

	_drag_by(models, 0.5 * INCH)
	_ticks(4)
	assert_int(_main.landing_preview.line_count()).is_equal(1)
	om.call("_cancel_drag")
	assert_int(_main.landing_preview.line_count()).is_equal(0)


## Lines only for ONE unit's models: a joined hero is part of its host (GF p.14); another unit makes it mixed.
func test_lines_only_for_one_units_drag() -> void:
	var models := _solo_lines_table()
	var om: Object = _main.object_manager
	var mover: GameUnit = models[0].get_meta("game_unit")
	var hero_node: Node3D = om.call("spawn_miniature", Vector3(0.15, 0.0, 0.0), false)
	var hero := _armed([hero_node], "am23_hero", 1)
	hero.unit_properties["attached_to"] = mover
	mover.unit_properties["attached_heroes"] = [hero]
	_drag_by(models + [hero_node], 4 * INCH)
	_ticks(4)
	assert_int(_main.landing_preview.line_count()).is_equal(1)
	om.call("_cancel_drag")

	var other: Node3D = om.call("spawn_miniature", Vector3(-0.05, 0.0, 0.0), false)
	_unit_of(other, "am23_other", 1)
	_drag_by(models + [other], 4 * INCH)
	_ticks(4)
	assert_int(_main.landing_preview.ghost_count()).is_equal(4)
	assert_int(_main.landing_preview.line_count()).is_equal(0)


## Frame-time gate: a tick draws the ghosts OR checks ONE enemy unit, taking turns, and the round-robin reaches
## every enemy in range: A, then B (out of range), then C and D (both in range) - one line more per lines-tick.
func test_round_robin_reaches_every_enemy_in_range() -> void:
	var models := _solo_lines_table()
	var om: Object = _main.object_manager
	_armed([om.call("spawn_miniature", Vector3(-0.08, 0.0, 15 * INCH), false)], "am23_foe_c", 2)
	_armed([om.call("spawn_miniature", Vector3(0.18, 0.0, 15 * INCH), false)], "am23_foe_d", 2)
	_drag_by(models, 4 * INCH)
	var seen: Array = [_main.landing_preview.line_count()]
	for i in 9:
		_ticks(1)
		seen.append(_main.landing_preview.line_count())
	assert_array(seen).is_equal([0, 1, 1, 1, 1, 2, 2, 3, 3, 3])
	assert_int(_main.landing_preview.ghost_count()).is_equal(3)


## Frame-time gate: a move under 0.25" keeps the landing (no ghost recompute, the line verdicts stay); a
## larger one recomputes the ghosts and drops the old landing's lines.
func test_a_small_move_keeps_the_landing() -> void:
	var models := _solo_lines_table()
	_drag_by(models, 4 * INCH)
	_ticks(1)   # lines-tick: A
	assert_int(_main.landing_preview.line_count()).is_equal(1)
	var ghosts := _ghost_xz()
	_ticks(2, 0.1 * INCH)
	assert_array(_ghost_xz()).is_equal(ghosts)
	assert_int(_main.landing_preview.line_count()).is_equal(1)
	_ticks(1, 0.5 * INCH)   # a ghost turn
	assert_float((_ghost_xz()[0] as Vector2).distance_to(ghosts[0])).is_greater(0.01)
	assert_int(_main.landing_preview.line_count()).is_equal(0)
