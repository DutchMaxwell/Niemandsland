extends GdUnitTestSuite
## E2E — Automodus rework step 1.5: main's _solo_preview_for runs the player's verb through the one
## executor in its sandbox (preview_intent) and reads the shooting lines AT THE LANDING through the
## volley's own sight truth (_solo_volley_sighted). Nothing moves; a refusal comes back as is
## (boot pattern: e2e_auto_advance_test.gd).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254

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
	MovementPlanner.fast_planner = false   # deterministic precise planner (as e2e_auto_advance_test.gd)
	MovementPlanner.fast_planner_guard = MovementPlanner.FAST_PLANNER_GUARD
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main._solo_fast = true


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## `models` models in a line across the firing lane (1.5" apart), each with one 12" rifle.
func _shooter(pid: int, unit_name: String, x_in: float, models := 1) -> GameUnit:
	var spots: Array = []
	for i in models:
		spots.append(Vector3(x_in * INCH, 0, (i - (models - 1) / 2.0) * 1.5 * INCH))
	var u := E2EBoot.make_unit(_main, pid, unit_name, spots)
	var opr := OPRApiClient.OPRUnit.new()
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Rifle"
	w.range_value = 12
	w.attacks = 1
	opr.weapons = [w]
	u.source_type = "opr"
	u.source_data = opr
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func _board() -> Array:
	var out: Array = []
	for u in _main.opr_army_manager.game_units.values():
		out.append_array(SoloController.alive_positions(u as GameUnit))
	return out


## The N of the volley's "<unit>: N/M models with line of sight + range" log line (-1 when absent).
func _logged_sighted(unit_name: String) -> int:
	var re := RegEx.create_from_string("%s: (\\d+)/\\d+ models? with line of sight \\+ range" % unit_name)
	for e in _main.battle_log.entries():
		var hit := re.search(str((e as Dictionary)["text"]))
		if hit != null:
			return int(hit.get_string(1))
	return -1


func test_preview_shows_landing_and_shooters(timeout := 60000) -> void:
	_shooter(2, "Watchers", -50.0)   # the AI's eligible reply, far off (e2e_auto_advance_test.gd)
	var shooter := _shooter(1, "Riflemen", 0.0, 3)
	var enemy := _shooter(2, "Foe", 16.0)   # out of the 12" reach now, inside it after a 6" Advance
	enemy.is_activated = true
	assert_int(_main._solo_volley_sighted(shooter, enemy)).is_equal(0)
	var board_before := _board()
	var preview: Dictionary = _main._solo_preview_for(shooter, AiDecision.Action.ADVANCE, enemy)
	assert_array(_board()).is_equal(board_before)
	var landing: Array = preview.get("landing", [])
	assert_int(landing.size()).is_equal(shooter.get_alive_models().size())
	var lines: Array = preview.get("lines", [])
	assert_int(lines.size()).override_failure_message("no shooting line from the landing").is_greater(0)
	for line in lines:   # every line starts at a landing ghost, never at the model's current spot
		assert_bool(landing.any(func(l: Dictionary) -> bool:
			return (l["pos"] as Vector3).is_equal_approx(line["from"]))).is_true()
	await _main._run_player_intent(shooter, AiDecision.Action.ADVANCE, enemy)
	await E2EBoot.settle(get_tree())
	assert_int(lines.size()).is_equal(_logged_sighted("Riflemen"))


func test_charge_preview_has_no_lines(timeout := 60000) -> void:
	var charger := _shooter(1, "Chargers", 0.0, 3)
	var enemy := _shooter(2, "Foe", 8.0)
	var board_before := _board()
	var preview: Dictionary = _main._solo_preview_for(charger, AiDecision.Action.CHARGE, enemy)
	assert_int((preview.get("landing", []) as Array).size()).is_equal(3)
	assert_array(preview.get("lines", ["missing"])).is_empty()
	assert_array(_board()).is_equal(board_before)


func test_shaken_preview_is_refused_and_moves_nothing(timeout := 60000) -> void:
	var shaky := _shooter(1, "Shaky", 0.0, 3)
	shaky.is_shaken = true
	var enemy := _shooter(2, "Foe", 16.0)
	var board_before := _board()
	var preview: Dictionary = _main._solo_preview_for(shaky, AiDecision.Action.ADVANCE, enemy)
	assert_str(str(preview.get("refused", ""))).contains("Shaken")
	assert_bool(preview.has("landing")).is_false()
	assert_array(_board()).is_equal(board_before)


# --- Automodus step 1.7: hover shows the preview; leaving, Esc or right-click clears it ---

## A one-model rifle unit whose model is a REAL spawned miniature (StaticBody3D + collider), so the
## real pick ray can hit it (pattern: e2e_mp_los_line_test.gd).
func _pickable(pid: int, unit_name: String, x_in: float) -> GameUnit:
	var u := _shooter(pid, unit_name, x_in)
	var m := u.models[0] as ModelInstance
	var body: Node3D = (_main.object_manager as Object).call("spawn_miniature", m.node.global_position, false)
	body.set_meta("game_unit", u)
	m.node.queue_free()
	m.node = body
	return u


## A screen point the real pick ray resolves to `u` (INF when none: a fixture failure, asserted).
func _pick_point(u: GameUnit) -> Vector2:
	var cam: Camera3D = _main.get_viewport().get_camera_3d()
	var node: Node3D = (u.models[0] as ModelInstance).node
	for dy in [0.016, 0.03, 0.0]:
		var pt: Vector2 = cam.unproject_position(node.global_position + Vector3(0.0, dy, 0.0))
		if _main._solo_pick_unit_at(pt) == u:
			return pt
	return Vector2.INF


## The mouse moving over `pt` through the SAME targeting handler main._unhandled_input feeds.
func _hover(pt: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = pt
	ev.global_position = pt
	await _main._solo_targeting_input(ev)


## Since 1.8f only Charge picks a lit enemy (Advance and Rush aim at table points); a charge preview has no lines.
func test_hover_shows_and_clears_the_preview(timeout := 60000) -> void:
	var shooter := _shooter(1, "Riflemen", 0.0, 3)
	var foe := _pickable(2, "Foe", 8.0)   # inside the 12" charge reach: lit
	await _runner.simulate_frames(1)   # the pick is a raycast: let physics register the fresh body
	var pt := _pick_point(foe)
	assert_bool(pt.is_finite()).override_failure_message("fixture: the pick ray never hits Foe").is_true()
	await _main.solo_begin_auto(shooter, AiDecision.Action.CHARGE)
	var ghosts: LandingPreview = _main.landing_preview
	await _hover(pt)
	var previews: Dictionary = _main._solo_target_mode.get("auto_previews", {})
	var lines: Array = (previews.get(foe.get_instance_id(), {}) as Dictionary).get("lines", [])
	assert_int(ghosts.ghost_count()).is_equal(shooter.get_alive_models().size())
	assert_int(ghosts.line_count()).is_equal(lines.size())
	assert_object(_main._solo_los_line).override_failure_message("auto_verb hover drew the LOS line").is_null()
	var shown := ghosts.get_child(0)
	await _hover(pt)   # the same target again: no new planner run, no rebuild
	assert_int(previews.size()).is_equal(1)
	assert_object(ghosts.get_child(0)).is_same(shown)
	_main._solo_show_auto_preview(null)   # leaving: the empty table
	assert_int(ghosts.ghost_count()).is_equal(0)
	_main._solo_show_auto_preview(shooter)   # the own unit is not a lit target
	assert_int(ghosts.ghost_count()).is_equal(0)
	# Back on Foe the CACHED preview shows (a marked entry proves the planner did not run again).
	previews[foe.get_instance_id()] = {"landing": [{"pos": Vector3.ZERO, "radius_m": 0.0125}], "lines": []}
	await _hover(pt)
	assert_int(ghosts.ghost_count()).is_equal(1)
	var right_click := InputEventMouseButton.new()
	right_click.button_index = MOUSE_BUTTON_RIGHT
	right_click.pressed = true
	await _main._solo_targeting_input(right_click)
	assert_bool(_main._solo_target_mode.is_empty()).is_true()
	assert_int(ghosts.ghost_count() + ghosts.line_count()).is_equal(0)


func test_esc_clears_the_hover_preview(timeout := 60000) -> void:
	var shooter := _shooter(1, "Riflemen", 0.0, 3)
	var foe := _shooter(2, "Foe", 8.0)
	await _main.solo_begin_auto(shooter, AiDecision.Action.CHARGE)
	_main._solo_show_auto_preview(foe)
	assert_int(_main.landing_preview.ghost_count()).is_equal(3)
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	await _main._solo_targeting_input(esc)
	assert_bool(_main._solo_target_mode.is_empty()).is_true()
	assert_int(_main.landing_preview.ghost_count()).is_equal(0)


func test_a_refused_hover_shows_nothing_and_says_why_once(timeout := 60000) -> void:
	var shooter := _shooter(1, "Riflemen", 0.0, 3)
	var foe := _shooter(2, "Foe", 8.0)
	await _main.solo_begin_auto(shooter, AiDecision.Action.CHARGE)
	shooter.is_shaken = true   # lit at entry, refused by the time it is hovered
	var board_before := _board()
	for t in [foe, null, foe]:
		_main._solo_show_auto_preview(t)
	assert_int(_main.landing_preview.ghost_count()).is_equal(0)
	assert_array(_board()).is_equal(board_before)
	var said := 0
	for e in _main.battle_log.entries():
		if str((e as Dictionary)["text"]).begins_with("Auto: no preview for Foe (Shaken"):
			said += 1
	assert_int(said).is_equal(1)
	_main._solo_end_targeting()


# --- Automodus step 1.8: a click on a lit target executes, and nothing else does ---

## A left click on `pt` through the SAME targeting handler main._unhandled_input feeds.
func _click(pt: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = pt
	ev.global_position = pt
	await _main._solo_targeting_input(ev)


func _log_text() -> String:
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


## Bystanders so the AI's one owed reply does not exhaust both sides at once (e2e_auto_advance_test.gd).
func _bystanders() -> void:
	_shooter(1, "Reserves", 50.0)
	_shooter(2, "Watchers", -50.0)


## Opens `verb` for `unit`, hovers the lit `foe` and clicks it, both through the real pick ray. Returns the
## landing of the preview the hover showed (read before the click, which clears the ghosts).
func _hover_then_click(unit: GameUnit, foe: GameUnit, verb: int) -> Array:
	await _runner.simulate_frames(1)   # the pick is a raycast: let physics register the fresh body
	var pt := _pick_point(foe)
	assert_bool(pt.is_finite()).override_failure_message("fixture: the pick ray never hits the foe").is_true()
	await _main.solo_begin_auto(unit, verb)
	await _hover(pt)
	var previews: Dictionary = _main._solo_target_mode.get("auto_previews", {})
	var landing: Array = (previews.get(foe.get_instance_id(), {}) as Dictionary).get("landing", [])
	assert_int(landing.size()).override_failure_message("fixture: the hover showed no preview").is_greater(0)
	await _click(pt)
	await E2EBoot.settle(get_tree())
	return landing


## Every ghosted model stands within 1 mm of its ghost (`at`: positions recorded mid-flow, else now).
func _assert_on_the_ghosts(landing: Array, at := {}) -> void:
	for spot in landing:
		var m := spot["model"] as ModelInstance
		var pos: Vector3 = at.get(m, m.node.global_position)
		assert_float(pos.distance_to(spot["pos"])) \
			.override_failure_message("%s ends %.4f m from its ghost" % [m.node.name, pos.distance_to(spot["pos"])]) \
			.is_less_equal(0.001)


func test_own_base_click_no_longer_executes(timeout := 60000) -> void:
	_bystanders()
	var shooter := _pickable(1, "Riflemen", 0.0)
	var foe := _shooter(2, "Foe", 8.0)
	foe.is_activated = true
	await _runner.simulate_frames(1)
	var pt := _pick_point(shooter)
	assert_bool(pt.is_finite()).override_failure_message("fixture: the pick ray never hits Riflemen").is_true()
	await _main.solo_begin_auto(shooter, AiDecision.Action.CHARGE)
	var board_before := _board()
	await _click(pt)
	await E2EBoot.settle(get_tree())
	assert_array(_board()).override_failure_message("the own-base click moved models").is_equal(board_before)
	assert_bool(shooter.is_activated).is_false()
	assert_bool(_main._solo_target_mode.has("auto_verb")).override_failure_message("the click closed the mode").is_true()
	assert_str(_log_text()).contains("Auto: Riflemen is not a valid target for Charge (")
	_main._solo_end_targeting()


func test_an_unlit_click_moves_nothing_and_says_why(timeout := 60000) -> void:
	var charger := _shooter(1, "Chargers", 0.0)
	_shooter(2, "Near", 8.0)
	var far := _pickable(2, "Far", 20.0)   # outside the charge reach: not lit
	await _runner.simulate_frames(1)
	var pt := _pick_point(far)
	assert_bool(pt.is_finite()).override_failure_message("fixture: the pick ray never hits Far").is_true()
	await _main.solo_begin_auto(charger, AiDecision.Action.CHARGE)
	assert_bool((_main._solo_target_mode.get("auto_valid", []) as Array).has(far)).is_false()
	var board_before := _board()
	await _click(pt)
	await E2EBoot.settle(get_tree())
	assert_array(_board()).is_equal(board_before)
	assert_bool(_main._solo_target_mode.has("auto_verb")).override_failure_message("the click closed the mode").is_true()
	assert_str(_log_text()).contains("Auto: Far is not a valid target for Charge (")
	_main._solo_end_targeting()


## Automodus step 1.8b (OD 5): Rush goes to a FREE table point — no enemy is lit, the hover anywhere shows
## where the models end (clamped to the Rush reach), and the click there executes.
func test_rush_previews_and_goes_to_a_free_point(timeout := 60000) -> void:
	_bystanders()
	var runners := _shooter(1, "Runners", 0.0, 3)
	var foe := _shooter(2, "Foe", -24.0)   # an enemy on the table: Rush still lights no ring for it
	foe.is_activated = true
	var start: Vector3 = _main.solo_controller.unit_centre(runners)
	var pt: Vector2 = _main.get_viewport().get_camera_3d().unproject_position(start + Vector3(30.0 * INCH, 0, 0))
	await _main.solo_begin_auto(runners, AiDecision.Action.RUSH)
	assert_array(_main._solo_target_mode.get("cast_rings", ["no mode"])).override_failure_message("Rush lit an enemy").is_empty()
	_clock(0)
	await _hover(pt)   # 30" away, beyond the 12" Rush reach
	_clock(500)   # 1.8e: the cell is planned once the cursor rested on it
	var previews: Dictionary = _main._solo_target_mode.get("auto_previews", {})
	var landing: Array = (previews.get(_main._solo_target_mode.get("auto_hovered"), {}) as Dictionary).get("landing", [])
	assert_int(_main.landing_preview.ghost_count()).is_equal(3)
	assert_int(landing.size()).is_equal(3)
	var centre := Vector3.ZERO
	for spot in landing:
		centre += (spot["pos"] as Vector3) / maxf(landing.size(), 1)
	assert_float(MoveIntent.distance_inches(start, centre)).override_failure_message("ghosts not at the 12\" reach") \
		.is_between(11.5, 12.01)
	assert_float(centre.x - start.x).override_failure_message("ghosts not toward the hovered point").is_greater(11.0 * INCH)
	await _click(pt)
	await E2EBoot.settle(get_tree())
	assert_bool(runners.is_activated).override_failure_message("the click on the table did not execute").is_true()
	_assert_on_the_ghosts(landing)


func test_a_lit_charge_click_lands_on_the_snapped_preview(timeout := 60000) -> void:
	_bystanders()
	var charger := _shooter(1, "Chargers", 0.0)
	var foe := _pickable(2, "Foe", 8.0)
	# A friendly 1" zone holds the charge ~0.8" short of contact, so only the snap closes the gap
	# (fixture: solo_intent_preview_test.gd test_a_charge_held_short_lands_on_the_snap).
	var blocker := E2EBoot.make_unit(_main, 1, "Blocker", [Vector3(7.0 * INCH, 0, 1.7 * INCH)])
	_main.opr_army_manager.game_units[blocker.unit_id] = blocker
	var snapped := {}   # the charger's spots right after the snap, before the melee and consolidation
	_main.battle_log.entry_added.connect(func(e: Dictionary) -> void:
		if snapped.is_empty() and str(e.get("text", "")).contains("charges into base contact"):
			for m in charger.get_alive_models():
				snapped[m] = (m as ModelInstance).node.global_position)
	var landing := await _hover_then_click(charger, foe, AiDecision.Action.CHARGE)
	assert_bool(snapped.is_empty()).override_failure_message("fixture: the charge never snapped").is_false()
	_assert_on_the_ghosts(landing, snapped)


func test_the_suggested_target_wears_the_one_highlighted_ring(timeout := 60000) -> void:
	var unit := _shooter(1, "Riflemen", 0.0, 3)
	_shooter(2, "Far", 20.0)   # registered first: the suggestion is not simply the first lit ring
	_shooter(2, "Near", 8.0)
	var plain: MeshInstance3D = _main._solo_spawn_pulse_ring(Vector3.ZERO, Color.WHITE)
	var plain_radius: float = (plain.mesh as TorusMesh).outer_radius
	plain.free()
	for verb in [AiDecision.Action.CHARGE]:   # Rush and Advance light no target (1.8b, 1.8f; the shot pick: 1.8f test)
		await _main.solo_begin_auto(unit, verb)
		var valid: Array = _main._solo_target_mode.get("auto_valid", [])
		var rings: Array = _main._solo_target_mode.get("cast_rings", [])
		var highlighted: Array = []
		for i in mini(rings.size(), valid.size()):
			if ((rings[i] as MeshInstance3D).mesh as TorusMesh).outer_radius > plain_radius:
				highlighted.append(valid[i])
		var suggested: GameUnit = _main.solo_controller.suggest_target(unit, verb)
		assert_array(highlighted).override_failure_message("verb %d: highlighted %s, suggested %s" % [
			verb, str(highlighted.map(func(u: GameUnit) -> String: return u.get_name())), suggested.get_name()]) \
			.is_equal([suggested])
		assert_str(_log_text()).contains("Suggested: %s" % suggested.get_name())
		_main._solo_end_targeting()


## A tray seed whose first die shows `at_least` or more (batch mode draws the tray's faces from it).
func _seed_rolling(at_least: int) -> int:
	var rng := RandomNumberGenerator.new()
	for s in 1000:
		rng.seed = s
		if rng.randi_range(1, 6) >= at_least:
			return s
	return -1


## The ghosted models are NOT asserted on their ghosts here: the returned model moves the unit centre the
## engine plans the move from, so the whole landing shifts (measured 9.5 mm for this 3-model Rush).
func test_reanimated_models_are_named_in_the_log(timeout := 60000) -> void:
	_bystanders()
	var bots := _shooter(1, "Bots", 0.0, 3)
	bots.unit_properties["special_rules"] = ["Reanimation"]
	bots.unit_properties["faction_folder"] = "robot_legions"
	var fallen := bots.models[2] as ModelInstance
	fallen.wounds_max = 1
	fallen.wounds_current = 0
	fallen.is_alive = false
	_main.opr_army_manager.set_loose_model_dead(fallen.node, 1, true, bots.unit_id)
	var foe := _pickable(2, "Foe", 24.0)
	foe.is_activated = true
	_main._solo_batch = true   # tray faces from the seeded tray RNG, no allocation prompt
	_main.seed_tray_rng(_seed_rolling(SoloController.REANIMATION_TARGET))
	var shot := await _hover_then_click_point(bots, AiDecision.Action.ADVANCE, Vector3(10.0 * INCH, 0, 0))
	assert_int((shot["landing"] as Array).size()).is_equal(2)
	assert_bool(fallen.is_alive).override_failure_message("fixture: the Reanimation roll restored nothing").is_true()
	assert_str(_log_text()).contains("Auto: +1 model reanimated — not in the preview")
	assert_bool(bots.is_activated).override_failure_message("the verb did not run after the Reanimation").is_true()
	assert_str(_log_text()).contains("Advance & Shoot: no enemy in range and sight")


# --- Automodus step 1.8c (OD 6): Charge dims the enemies it cannot reach; hovering one names why ---

func test_charge_dims_unreachable_enemies(timeout := 60000) -> void:
	var charger := _shooter(1, "Chargers", 0.0)
	var near := _shooter(2, "Near", 8.0)
	var far := _shooter(2, "Far", 20.0)
	await _main.solo_begin_auto(charger, AiDecision.Action.CHARGE)
	assert_array(_main._solo_target_mode.get("auto_valid", [])).contains_exactly([near])
	var dimmed: Dictionary = _main._solo_target_mode.get("auto_dimmed", {})
	assert_array(dimmed.keys()).override_failure_message("auto_dimmed missing or wrong: %s" % str(dimmed)) \
		.contains_exactly([far])
	var why := str(dimmed.get(far, ""))
	var gap: float = _main.solo_controller.nearest_melee_gap_in(charger, far)
	assert_str(why).contains("%.1f\"" % gap)   # the distance
	assert_str(why).contains("12.0\"")   # the charge reach
	var lit_rings: Array = (_main._solo_target_mode.get("cast_rings", []) as Array).duplicate()
	var dim_rings: Array = (_main._solo_target_mode.get("auto_dim_rings", []) as Array).duplicate()
	assert_int(lit_rings.size()).is_equal(1)
	assert_int(dim_rings.size()).is_equal(1)
	_main._solo_show_auto_preview(near)
	assert_int(_main.landing_preview.ghost_count()).is_equal(1)
	for t in [far, null, far]:   # hovering the dimmed enemy clears the ghosts and says why, once per mode
		_main._solo_show_auto_preview(t)
	assert_int(_main.landing_preview.ghost_count()).is_equal(0)
	var said := 0
	for e in _main.battle_log.entries():
		if str((e as Dictionary)["text"]).begins_with("Auto: Far is not a valid target for Charge (%s" % why):
			said += 1
	assert_int(said).is_equal(1)
	var right_click := InputEventMouseButton.new()
	right_click.button_index = MOUSE_BUTTON_RIGHT
	right_click.pressed = true
	await _main._solo_targeting_input(right_click)
	await _runner.simulate_frames(2)
	for r in lit_rings + dim_rings:
		assert_bool(is_instance_valid(r)).override_failure_message("a ring outlived the cancel").is_false()


func test_a_suggestion_that_is_not_lit_is_not_named(timeout := 60000) -> void:
	var charger := _shooter(1, "Chargers", 0.0)
	# The hero is listed first (as army lists often do): the host's gap counts the hero's model too, so the
	# tie goes to the hero and suggest_target names it - but a joined hero is never lit.
	var hero := _shooter(2, "Hero", 6.0)
	var host := _shooter(2, "Host", 10.0)
	EquipmentDistributor.attach_hero_to_unit(hero, host)
	await _main.solo_begin_auto(charger, AiDecision.Action.CHARGE)
	var suggested: GameUnit = _main.solo_controller.suggest_target(charger, AiDecision.Action.CHARGE)
	assert_object(suggested).override_failure_message("fixture: the suggestion is %s, not the joined hero" % (
		suggested.get_name() if suggested != null else "null")).is_same(hero)
	assert_bool((_main._solo_target_mode.get("auto_valid", []) as Array).has(hero)).is_false()
	assert_str(_log_text()).not_contains("Suggested: Hero")
	_main._solo_end_targeting()


# --- Automodus step 1.8e: the point-Rush hover plans only the cell the cursor rests on ---

## The test clock (1.8e hook): set it to `ms`, then run the per-frame dwell check once. A no-op on a build
## without the hook, so main fails on behaviour, not on a missing name.
func _clock(ms: int) -> void:
	_main.set("_solo_fake_ms", ms)
	if _main.has_method("_solo_auto_point_dwell"):
		_main._solo_auto_point_dwell()

## A sweep across 10 grid cells, 10 ms apart (inside the 120 ms dwell), plans at most one of them (each plan is
## a full planner run). Resting on the last cell plans it once, and only once. The clock is the test hook.
func test_a_sweep_plans_nothing_a_rest_plans_once(timeout := 60000) -> void:
	_bystanders()
	var runners := _shooter(1, "Runners", 0.0, 3)
	var start: Vector3 = _main.solo_controller.unit_centre(runners)
	var cam := _main.get_viewport().get_camera_3d()
	await _main.solo_begin_auto(runners, AiDecision.Action.RUSH)
	_clock(1000)
	for i in 10:
		await _hover(cam.unproject_position(start + Vector3((8.0 + i) * INCH, 0, 0)))
		_clock(1010 + 10 * i)
	var planned: Dictionary = _main._solo_target_mode.get("auto_previews", {})
	var swept := planned.size()
	assert_int(swept).override_failure_message("a 10-cell sweep inside the dwell planned %d cells" % swept).is_less_equal(1)
	_clock(1300)
	_clock(1300)
	assert_int(planned.size()).override_failure_message("the rest planned %d times" % (planned.size() - swept)) \
		.is_equal(swept + 1)
	assert_int(_main.landing_preview.ghost_count()).is_equal(3)
	_main._solo_end_targeting()


## A click inside the unit's own footprint is no Rush: nothing moves, the activation stays, the mode stays open.
func test_an_own_spot_click_keeps_the_rush_open(timeout := 60000) -> void:
	_bystanders()
	var runners := _shooter(1, "Runners", 0.0, 3)
	var before := _board()
	await _main.solo_begin_auto(runners, AiDecision.Action.RUSH)
	await _click(_main.get_viewport().get_camera_3d().unproject_position(SoloController.alive_positions(runners)[1]))
	await E2EBoot.settle(get_tree())
	assert_bool(runners.is_activated).override_failure_message("the own-spot click spent the activation").is_false()
	assert_array(_board()).is_equal(before)
	assert_bool(_main._solo_target_mode.has("auto_point")).override_failure_message("the Rush mode closed").is_true()
	_main._solo_end_targeting()


# --- Automodus step 1.8d: Quick Shot after a point Rush ---

## A one-model 12" rifle unit that may shoot after a Rush. Quick Shot is faction-scoped in the rules mechanics
## map, so the unit needs a faction where it is a defined primitive (as in e2e_auto_rush_test.gd).
func _quick_shooter(unit_name: String) -> GameUnit:
	var u := _shooter(1, unit_name, 0.0)
	u.unit_properties["special_rules"] = ["Quick Shot"]
	u.unit_properties["faction_folder"] = "goblin_reclaimers"
	return u


## Point-Rushes `runner` 12" along +x (it ends at 12"). Near stands at `near_x` (20" = ~8" from the landing, in
## the rifle's range and sight), Far at -18" (30" from the landing). Both stay put; Watchers is the AI's reply.
func _rush_past(runner: GameUnit, near_x := 20.0) -> Array:
	_bystanders()
	var near := _pickable(2, "Near", near_x)
	var far := _pickable(2, "Far", -18.0)
	near.is_activated = true
	far.is_activated = true
	var goal: Vector3 = _main.solo_controller.unit_centre(runner) + Vector3(12.0 * INCH, 0, 0)
	await _main._run_player_intent(runner, AiDecision.Action.RUSH, null, goal)
	await _runner.simulate_frames(1)   # the pick is a raycast: let physics register the fresh bodies
	return [near, far]


func test_quick_shot_unit_may_shoot_after_a_point_rush(timeout := 60000) -> void:
	var runner := _quick_shooter("Skirmishers")
	var foes: Array = await _rush_past(runner)
	assert_bool(_main._solo_target_mode.has("auto_shot")) \
		.override_failure_message("no Quick Shot pick after the point Rush (log: %s)" % _log_text().strip_edges()) \
		.is_true()
	assert_array(_main._solo_target_mode.get("auto_valid", [])).contains_exactly([foes[0]])
	assert_int((_main._solo_target_mode.get("cast_rings", []) as Array).size()).is_equal(1)
	assert_bool(runner.is_activated).override_failure_message("the Rush completed before the shot").is_false()
	assert_str(_log_text()).contains("Skirmishers: Quick Shot — click a lit enemy to shoot, right-click or Esc for no shot")
	var far_pt := _pick_point(foes[1])
	assert_bool(far_pt.is_finite()).override_failure_message("fixture: the pick ray never hits Far").is_true()
	await _click(far_pt)
	assert_bool(_main._solo_target_mode.has("auto_shot")).override_failure_message("the unlit click closed the pick").is_true()
	assert_str(_log_text()).contains("Auto: Far is not a valid target for Quick Shot (not in range and sight)")
	assert_int(_logged_sighted("Skirmishers")).override_failure_message("the unlit click fired").is_equal(-1)
	var near_pt := _pick_point(foes[0])
	assert_bool(near_pt.is_finite()).override_failure_message("fixture: the pick ray never hits Near").is_true()
	await _click(near_pt)
	await E2EBoot.settle(get_tree())
	var text := _log_text()
	assert_str(text).contains("Quick Shot: shoots after its Rush action")
	assert_int(_logged_sighted("Skirmishers")).override_failure_message("no volley after the lit click").is_equal(1)
	assert_str(text).contains("fires Rifle at Near")
	assert_bool(runner.is_activated).is_true()
	assert_bool(_main._solo_target_mode.is_empty()).is_true()
	assert_int(_main._solo_pending_replies).override_failure_message("the AI's reply was never booked/resolved").is_equal(0)


func test_esc_after_a_point_rush_holds_the_quick_shot(timeout := 60000) -> void:
	var runner := _quick_shooter("Skirmishers")
	await _rush_past(runner)
	assert_bool(_main._solo_target_mode.has("auto_shot")).override_failure_message("no Quick Shot pick").is_true()
	var rings: Array = (_main._solo_target_mode.get("cast_rings", []) as Array).duplicate()
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	await _main._solo_targeting_input(esc)
	await E2EBoot.settle(get_tree())
	var text := _log_text()
	assert_str(text).contains("Quick Shot: Skirmishers holds its fire")
	assert_str(text).not_contains("fires Rifle at Near")
	assert_int(_logged_sighted("Skirmishers")).override_failure_message("the hold-fire rolled a volley").is_equal(-1)
	assert_bool(runner.is_activated).override_failure_message("Esc did not complete the activation").is_true()
	assert_bool(_main._solo_target_mode.is_empty()).is_true()
	assert_int(_main._solo_pending_replies).is_equal(0)
	for r in rings:
		assert_bool(is_instance_valid(r)).override_failure_message("a lit ring survived Esc").is_false()


func test_a_quick_shot_with_no_enemy_in_reach_completes(timeout := 60000) -> void:
	var runner := _quick_shooter("Skirmishers")
	await _rush_past(runner, -30.0)   # Near 42" from the landing: nothing to light
	await E2EBoot.settle(get_tree())
	assert_bool(_main._solo_target_mode.is_empty()).override_failure_message("a pick opened with nothing lit").is_true()
	assert_str(_log_text()).contains("Quick Shot: no enemy in range and sight")
	assert_bool(runner.is_activated).is_true()


func test_a_point_rush_without_quick_shot_completes_as_before(timeout := 60000) -> void:
	var runner := _shooter(1, "Runners", 0.0)
	await _rush_past(runner)
	await E2EBoot.settle(get_tree())
	assert_bool(_main._solo_target_mode.is_empty()).override_failure_message("a pick opened without Quick Shot").is_true()
	assert_str(_log_text()).not_contains("Quick Shot")
	assert_bool(runner.is_activated).is_true()


# --- Automodus step 1.8f (OD 13): Advance & Shoot goes to a free point, then picks its shot ---

## Opens `verb` for `unit`, hovers the table point `offset` (metres) from the unit's centre, rests past the dwell and
## clicks it, all through the real targeting handler. Returns the landing the hover showed (read before the click,
## which clears the ghosts), whether a point mode opened and how many enemies were lit before the move.
func _hover_then_click_point(unit: GameUnit, verb: int, offset: Vector3) -> Dictionary:
	var at: Vector3 = _main.solo_controller.unit_centre(unit) + offset
	var pt: Vector2 = _main.get_viewport().get_camera_3d().unproject_position(at)
	await _main.solo_begin_auto(unit, verb)
	var entry := {"point_mode": _main._solo_target_mode.has("auto_point"),
		"lit_at_entry": (_main._solo_target_mode.get("cast_rings", []) as Array).size()}
	_clock(0)
	await _hover(pt)
	_clock(500)   # 1.8e: the cell is planned once the cursor rested on it
	var previews: Dictionary = _main._solo_target_mode.get("auto_previews", {})
	entry["landing"] = (previews.get(_main._solo_target_mode.get("auto_hovered"), {}) as Dictionary).get("landing", [])
	await _click(pt)
	await _runner.simulate_frames(1)   # the shot pick is a raycast: let physics register the moved bodies
	return entry


## Point-Advances `unit` toward a point 10" along +x (the 6" reach ends it at 6"). Near stands at 16" (10" from the
## landing, in the rifle's range and sight), Far at -18" (24" away, never lit). Both stay put; Watchers is the AI's reply.
func _advance_past(unit: GameUnit) -> Array:
	_bystanders()
	var near := _pickable(2, "Near", 16.0)
	var far := _pickable(2, "Far", -18.0)
	near.is_activated = true
	far.is_activated = true
	await _hover_then_click_point(unit, AiDecision.Action.ADVANCE, Vector3(10.0 * INCH, 0, 0))
	return [near, far]


## The hover 10" away shows the ghosts at the 6" Advance reach, the click lands every model on its ghost, then the
## enemies in range and sight from the landing light up (the engine's suggestion on the highlighted ring) and one
## click on a lit enemy fires the normal volley. Before the move no enemy is lit: the player picks the destination.
func test_advance_previews_goes_to_a_free_point_then_shoots(timeout := 60000) -> void:
	_bystanders()
	var shooter := _shooter(1, "Riflemen", 0.0, 3)
	var near := _pickable(2, "Near", 16.0)   # 10" from the landing: in the 12" rifle's range and sight
	var far := _pickable(2, "Far", -18.0)   # 24" from the landing: never lit
	near.is_activated = true
	far.is_activated = true
	var start: Vector3 = _main.solo_controller.unit_centre(shooter)
	var shot := await _hover_then_click_point(shooter, AiDecision.Action.ADVANCE, Vector3(10.0 * INCH, 0, 0))
	assert_bool(shot["point_mode"]).override_failure_message("Advance opened no point mode (log: %s)" % _log_text().strip_edges()) \
		.is_true()
	assert_int(shot["lit_at_entry"]).override_failure_message("Advance lit enemies before the move").is_equal(0)
	var landing: Array = shot["landing"]
	assert_int(landing.size()).override_failure_message("the hover showed no ghosts").is_equal(3)
	var centre := Vector3.ZERO
	for spot in landing:
		centre += (spot["pos"] as Vector3) / maxf(landing.size(), 1)
	assert_float(MoveIntent.distance_inches(start, centre)).override_failure_message("ghosts not at the 6\" reach") \
		.is_between(5.5, 6.01)
	assert_float(centre.x - start.x).override_failure_message("ghosts not toward the hovered point").is_greater(5.5 * INCH)
	_assert_on_the_ghosts(landing)
	assert_bool(shooter.is_activated).override_failure_message("the move completed before the shot").is_false()
	assert_array(_main._solo_target_mode.get("auto_valid", [])).contains_exactly([near])
	assert_object(_main._solo_target_mode.get("auto_suggested")).override_failure_message("the suggestion is not pre-marked") \
		.is_same(_main.solo_controller.suggest_target(shooter, AiDecision.Action.ADVANCE))
	var rings: Array = _main._solo_target_mode.get("cast_rings", [])
	var plain: MeshInstance3D = _main._solo_spawn_pulse_ring(Vector3.ZERO, Color.WHITE)
	var plain_radius: float = (plain.mesh as TorusMesh).outer_radius
	plain.free()
	assert_int(rings.size()).is_equal(1)
	if rings.size() == 1:
		assert_float(((rings[0] as MeshInstance3D).mesh as TorusMesh).outer_radius) \
			.override_failure_message("the suggested target's ring is not the highlighted one").is_greater(plain_radius)
	var text := _log_text()
	assert_str(text).contains("Riflemen: Advance & Shoot — click a lit enemy to shoot, right-click or Esc for no shot")
	assert_str(text).contains("Suggested: Near")
	await _click(_pick_point(far))
	assert_bool(_main._solo_target_mode.has("auto_shot")).override_failure_message("the unlit click closed the pick").is_true()
	assert_str(_log_text()).contains("Auto: Far is not a valid target for Advance & Shoot (not in range and sight)")
	assert_int(_logged_sighted("Riflemen")).override_failure_message("the unlit click fired").is_equal(-1)
	var near_pt := _pick_point(near)
	assert_bool(near_pt.is_finite()).override_failure_message("fixture: the pick ray never hits Near").is_true()
	await _click(near_pt)
	await E2EBoot.settle(get_tree())
	text = _log_text()
	assert_int(_logged_sighted("Riflemen")).override_failure_message("no volley after the lit click").is_greater(0)
	assert_str(text).contains("fires Rifle at Near")
	assert_str(text).not_contains("Quick Shot")
	assert_bool(shooter.is_activated).is_true()
	assert_bool(_main._solo_target_mode.is_empty()).is_true()
	assert_int(_main._solo_pending_replies).override_failure_message("the AI's reply was never booked/resolved").is_equal(0)


## Enter takes the pre-marked suggestion: the volley fires at it and the activation ends.
func test_enter_after_a_point_advance_shoots_the_suggestion(timeout := 60000) -> void:
	var shooter := _shooter(1, "Riflemen", 0.0, 3)
	var foes: Array = await _advance_past(shooter)
	assert_object(_main._solo_target_mode.get("auto_suggested")) \
		.override_failure_message("no suggestion pre-marked (log: %s)" % _log_text().strip_edges()).is_same(foes[0])
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.pressed = true
	await _main._solo_targeting_input(enter)
	await E2EBoot.settle(get_tree())
	assert_str(_log_text()).contains("fires Rifle at Near")
	assert_bool(shooter.is_activated).override_failure_message("Enter did not end the activation").is_true()
	assert_bool(_main._solo_target_mode.is_empty()).is_true()
	assert_int(_main._solo_pending_replies).is_equal(0)


## Right-click/Esc after the point Advance is no shot: nothing is rolled, the activation still ends, the rings go.
func test_esc_after_a_point_advance_holds_fire(timeout := 60000) -> void:
	var shooter := _shooter(1, "Riflemen", 0.0, 3)
	await _advance_past(shooter)
	assert_bool(_main._solo_target_mode.has("auto_shot")).override_failure_message("no shot pick after the point Advance") \
		.is_true()
	var rings: Array = (_main._solo_target_mode.get("cast_rings", []) as Array).duplicate()
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	await _main._solo_targeting_input(esc)
	await E2EBoot.settle(get_tree())
	var text := _log_text()
	assert_str(text).contains("Advance & Shoot: Riflemen holds its fire")
	assert_int(_logged_sighted("Riflemen")).override_failure_message("the hold-fire rolled a volley").is_equal(-1)
	assert_bool(shooter.is_activated).override_failure_message("Esc did not complete the activation").is_true()
	assert_bool(_main._solo_target_mode.is_empty()).is_true()
	assert_int(_main._solo_pending_replies).is_equal(0)
	for r in rings:
		assert_bool(is_instance_valid(r)).override_failure_message("a lit ring survived Esc").is_false()
