extends GdUnitTestSuite
## HR-POS (G10 follow-up of #3001): in deny mode the core takes an AI HOLD volley of a Harassing (Hit & Run) unit whose
## target survives and steps the unit about 3" afterwards (`sim.rs` `tray_hit_and_run`). The delta now carries the stepped
## positions (`UnitDelta::positions`) and `land_delta` puts the models there, so the table ends where the core does; the
## landed once-per-round stamp keeps the table's own tail (`solo_controller.gd` `hit_and_run_move`) from stepping a second time.
## Per seed two readings on the same board and tray seed:
##   door - capture + `_run_ai_shooting` (the core takes the volley and lands its delta), then the table's own tail call,
##   core - capture + `CoreActivation.drive` (keep_handle): the positions the core's own state holds after the activation.
## RED (before HR-POS): the door leaves the models where they stood in 8/8 while the core's state moved them 3.00";
## without the stamp write in `_land_positions`, `land_delta` reports hit_and_run_round and moved_round split (2 per seed).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")
const INCH := 0.0254
const SIDE := {"quality": 4, "defense": 4, "tough": 1, "z_step_in": 1.2, "game_system": "gf",
	"faction_folder": "dark_elf_raiders", "rules": []}
const RIFLE := {"name": "Rifle", "range_in": 24, "attacks": 1, "count": 10, "rules": []}

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main._solo_batch = true
	_main._solo_auto_saves = true
	_main._autosave_controller.set_lesson_paused(true)
	CoreActivation._env = 1
	OS.set_environment("NML_CORE_SLICE", "deny")
	CoreSlice.reset_cache()


func after_test() -> void:
	OS.unset_environment("NML_CORE_SLICE")
	CoreSlice.reset_cache()
	CoreActivation.reset_all(_main)
	CoreActivation._env = -1
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _pair() -> Array:
	var att := ParityTable._make_unit(_main, SIDE.merged({"player": 2, "name": "Att", "models": 10, "x_in": 0.0,
		"rules": ["Harassing"]}, true), RIFLE)
	var foe := ParityTable._make_unit(_main, SIDE.merged({"player": 1, "name": "Def", "models": 20, "x_in": 12.0,
		"defense": 2}, true), {})
	return [att, foe]


func _positions(gu: GameUnit) -> Array:
	var a: Array = []
	for m in gu.get_alive_models():
		var p: Vector3 = (m as ModelInstance).node.global_position
		a.append([p.x, p.z])
	a.sort()
	return a


func _centre(a: Array) -> Array:
	var x := 0.0
	var z := 0.0
	for p in a:
		x += float(p[0])
		z += float(p[1])
	var n := maxi(a.size(), 1)
	return [x / n, z / n]


func _centre_in(a: Array, b: Array) -> float:
	var ca := _centre(a)
	var cb := _centre(b)
	return snappedf(Vector2(float(cb[0]) - float(ca[0]), float(cb[1]) - float(ca[1])).length() / INCH, 0.01)


## Same final spots (multiset, 0.1" tolerance): the two readings each start from their own spawn lattice, equal by value.
func _same_spots(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	var left: Array = b.duplicate(true)
	for p in a:
		var hit := -1
		for i in left.size():
			if Vector2(float(left[i][0]) - float(p[0]), float(left[i][1]) - float(p[1])).length() < 0.0025:
				hit = i
				break
		if hit < 0:
			return false
		left.remove_at(hit)
	return true


func _free(units: Array) -> void:
	for u in units:
		_main.opr_army_manager.game_units.erase((u as GameUnit).unit_id)
		for m in (u as GameUnit).models:
			if (m as ModelInstance).node != null and is_instance_valid((m as ModelInstance).node):
				(m as ModelInstance).node.free()
	_main.solo_controller._peeked_unit = null


func _plain_pos(plain: Dictionary, gu: GameUnit) -> Array:
	var units: Dictionary = plain.get("units", {})
	var e: Variant = units.get(gu.unit_id)
	if e == null:
		for k in units:
			if str((units[k] as Dictionary).get("profile", {}).get("name", "")) == gu.get_name():
				e = units[k]
				break
	if e == null:
		return []
	var out: Array = []
	for p in (e as Dictionary).get("positions", []):
		out.append([float(p[0]), float(p[2])])
	out.sort()
	return out


## The door reading: the volley through the core, then the table's own Hit & Run tail (`main.gd`, after the attack).
func _door(s: int) -> Dictionary:
	CoreActivation.reset_all(_main)
	CoreActivation._env = 1
	var units := _pair()
	var att: GameUnit = units[0]
	var before := _positions(att)
	_main.solo_controller._sidestep_budget = SoloController.SIDESTEP_BUDGET_PER_ROUND
	_main.seed_tray_rng(s)
	var runs := CoreActivation.ai_runs
	var splits := CoreActivation.stamp_splits
	_main._solo_core_ai_h = CoreActivation.capture(_main)
	var report := {"unit": att, "moved": false, "action": AiDecision.Action.HOLD, "can_shoot": true}
	await _main._run_ai_shooting(report)
	var landed := _positions(att)
	var tail: bool = _main.solo_controller.hit_and_run_move(att, true)
	var out := {"took": CoreActivation.ai_runs - runs, "tail": tail, "splits": CoreActivation.stamp_splits - splits, "hnr": int(att.unit_properties.get("hit_and_run_round", -1)),
		"centre_in": _centre_in(before, landed), "landed": landed, "after_tail": _positions(att),
		"foe_alive": (units[1] as GameUnit).get_alive_count()}
	if int(_main._solo_core_ai_h) != 0:
		_main.solo_controller._core_node_ready().release(int(_main._solo_core_ai_h))
		_main._solo_core_ai_h = 0
	_free(units)
	await _main.get_tree().process_frame
	return out


## The core reading: the same activation driven directly, the positions read off the core's own state.
func _core(s: int) -> Dictionary:
	CoreActivation.reset_all(_main)
	CoreActivation._env = 1
	var units := _pair()
	var att: GameUnit = units[0]
	var foe: GameUnit = units[1]
	var before := _positions(att)
	_main.seed_tray_rng(s)
	var h := CoreActivation.capture(_main)
	var at: Array = att.get_alive_models().map(func(m: ModelInstance) -> Vector3: return (m as ModelInstance).node.global_position)
	var trails: Array = att.get_alive_models().map(func(_m: ModelInstance) -> Array: return [])
	var t: Array = [{"t": "begin"}, {"t": "placed", "positions": at, "trails": trails},
		{"t": "intent", "kind": AiDecision.Action.HOLD, "shoot": foe.unit_id}]
	var r: Dictionary = await CoreActivation.drive(_main, h, att, t, true, Callable(), true)
	var after: Array = []
	var handle := int(r.get("handle", 0))
	if handle != 0:
		after = _plain_pos(_main.solo_controller._core_node_ready().plain_of(handle), att)
		_main.solo_controller._core_node_ready().release(handle)
	_free(units)
	await _main.get_tree().process_frame
	return {"step": str(r["step"]), "after": after, "centre_in": _centre_in(before, after)}


## HR-POS: 8 seeds. The core takes every volley, the table's models end on the core's spots (moved by the core's distance,
## about 3"), the landed stamp holds the table's tail back (false, nothing moves a second time).
func test_the_core_hit_and_run_step_lands_on_the_table() -> void:
	for s in 8:
		var door := await _door(s)
		var core := await _core(s)
		var why := "seed %d: door %s | core %s" % [s, str(door), str(core)]
		assert_int(int(door["took"])).override_failure_message("the door takes the volley: " + why).is_equal(1)
		assert_float(float(core["centre_in"])).override_failure_message("the core steps the unit: " + why).is_greater(2.5)
		assert_bool(_same_spots(door["landed"], core["after"])).override_failure_message(
			"the table's models stand where the core left them: " + why).is_true()
		assert_float(absf(float(door["centre_in"]) - float(core["centre_in"]))).override_failure_message(
			"moved by the core's distance: " + why).is_less(0.05)
		assert_int(int(door["hnr"])).override_failure_message("the once-per-round stamp landed: " + why).is_equal(1)
		assert_int(int(door["splits"])).override_failure_message(
			"the landed step leaves no stamp split (land_delta reports none): " + why).is_equal(0)
		assert_bool(bool(door["tail"])).override_failure_message("the table's own step does not run again: " + why).is_false()
		assert_bool(_same_spots(door["after_tail"], door["landed"])).override_failure_message("no second step: " + why).is_true()


## HR-POS: a unit that lost a model in its own activation (a Hazardous self-wound in the volley) and then stepped: the delta
## row is `unknown` (moved and lost) and carries the SURVIVORS' positions in slot order. Once the step landings removed the dead,
## `land_delta` puts every survivor on its spot. Constructed: the delta row (the core's shape, `UnitDelta::positions`).
## RED: map the row onto all start models instead of the living ones -> a count split, nothing moves.
func test_a_unit_that_lost_a_model_still_lands_its_step() -> void:
	CoreActivation.reset_all(_main)
	var units := _pair()
	var att: GameUnit = units[0]
	var start := CoreActivation._start_models(_main)
	var dead: ModelInstance = att.get_alive_models()[0]
	dead.apply_damage(dead.wounds_current)
	var step := Vector3(-3.0 * INCH, 0.0, 0.0)
	var to: Array = att.get_alive_models().map(func(m: ModelInstance) -> Vector3: return m.node.global_position + step)
	var row := {"unit": att.unit_id, "removed": [], "shaken": false, "alive": 9, "moved": true, "unknown": true,
		"positions": to, "stamps": {}}
	await CoreActivation.land_delta(_main, [row], start, {"0:%s:0" % att.unit_id: dead})
	var got: Array = att.get_alive_models().map(func(m: ModelInstance) -> Vector3: return m.node.global_position)
	assert_int(got.size()).is_equal(9)
	for i in got.size():
		assert_float(Vector2((got[i] as Vector3).x, (got[i] as Vector3).z).distance_to(
			Vector2((to[i] as Vector3).x, (to[i] as Vector3).z))).override_failure_message(
			"survivor %d stands on the core's spot: %s vs %s" % [i, got[i], to[i]]).is_less(0.001)
	_free(units)


## melee95: a core step of half a millimetre to a millimetre (the defender's last pile-in step, 0.0005 m is the table's own smallest move) is
## landed like any other. RED with the old millimetre tolerance: the model stays 0.7 mm short of the core's spot (0.02 in in the melee sweep).
func test_a_core_step_of_under_a_millimetre_is_still_landed() -> void:
	CoreActivation.reset_all(_main)
	var units := _pair()
	var att: GameUnit = units[0]
	var start := CoreActivation._start_models(_main)
	var to: Array = att.get_alive_models().map(func(m: ModelInstance) -> Vector3: return m.node.global_position)
	to[0] = (to[0] as Vector3) + Vector3(0.0007, 0.0, 0.0)
	var row := {"unit": att.unit_id, "removed": [], "shaken": false, "alive": to.size(), "moved": true, "unknown": true,
		"positions": to, "stamps": {}}
	await CoreActivation.land_delta(_main, [row], start, {})
	var now: Vector3 = (att.get_alive_models()[0] as ModelInstance).node.global_position
	assert_float(Vector2(now.x, now.z).distance_to(Vector2((to[0] as Vector3).x, (to[0] as Vector3).z))).override_failure_message(
		"the 0.7 mm step landed: %s vs %s" % [now, to[0]]).is_less(0.0001)
	_free(units)


## meleefix: the 1 in separation can end a model 0.36 mm from the spot the board holds (sweep row Snipers -> Steam-Suits, seed 2: landed,
## snapped, stepped back to just short of its landing spot). Any step above float noise is landed. RED with the 0.0005 m dead zone: the
## model stays 0.014 in off the core's own end state.
func test_a_core_step_of_a_third_of_a_millimetre_is_still_landed() -> void:
	CoreActivation.reset_all(_main)
	var units := _pair()
	var att: GameUnit = units[0]
	var start := CoreActivation._start_models(_main)
	var to: Array = att.get_alive_models().map(func(m: ModelInstance) -> Vector3: return m.node.global_position)
	to[0] = (to[0] as Vector3) + Vector3(0.00036, 0.0, 0.0)
	var row := {"unit": att.unit_id, "removed": [], "shaken": false, "alive": to.size(), "moved": true, "unknown": true,
		"positions": to, "stamps": {}}
	await CoreActivation.land_delta(_main, [row], start, {})
	var now: Vector3 = (att.get_alive_models()[0] as ModelInstance).node.global_position
	assert_float(Vector2(now.x, now.z).distance_to(Vector2((to[0] as Vector3).x, (to[0] as Vector3).z))).override_failure_message(
		"the 0.36 mm step landed: %s vs %s" % [now, to[0]]).is_less(0.00002)
	_free(units)
