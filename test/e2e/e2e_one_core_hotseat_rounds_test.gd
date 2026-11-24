extends GdUnitTestSuite
## P4.D-43d: the gate for turning the hotseat switch on. A three-round hotseat Automatic game (two local human sides,
## no AI seat) ends in the SAME rules state with NML_ONE_CORE_HOTSEAT on and off: the core resolves the two sides'
## moves and volleys, the table resolved them before, and the state digest must not notice the difference.
##
## Driven through the doors a player uses on each side of the switch: with the switch on a unit's Start opens the core
## session, the drag is its move, the volley is its intent and ends the activation; with it off the drag is free and the
## volley ends the activation on the table. Both sides' activations pass the turn, both sides spent ends the round, three
## rounds end the game. The digest is SoloController.state_digest (the same fingerprint the arena compares).
## Real: the main scene, NmlCore, the drag machine, the radial doors, the battle log, the hotseat round end.
## Constructed: four plain units per table (two per side), their kit and their spots.
##
## RED (planted fault, `_nudge`): one model moved on the core path after the last activation - the digests must differ.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")
const INCH := 0.0254
const SEEDS := [3, 7, 11]
const ROUNDS := 3
const SIDE := {"quality": 4, "defense": 4, "tough": 1, "models": 5, "z_step_in": 1.2, "game_system": "gf",
	"faction_folder": "robot_legions", "rules": []}
const RIFLE := {"name": "Rifle", "range_in": 24, "attacks": 1, "count": 5, "rules": []}
## The table's furniture: [side, name, x_in, z_in]. Two plain units a side, inside rifle range of each other.
const UNITS := [[1, "Rifles", -6.0, 0.0], [2, "Guards", 6.0, 0.0],
	[1, "Scouts", -9.0, 5.0], [2, "Raiders", 9.0, 5.0]]

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _sessions := 0   # Start presses that opened a core session (only on the switch-on path)
var _volleys := 0    # volleys resolved in the game


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {}   # two local human sides: no AI seat
	_main.opr_army_manager.rules_automation = RulesAutomation.Level.AUTOMATIC
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	SoloHarness.instant(_main)
	SoloHarness.fast(_main)
	SoloHarness.auto_saves(_main)
	_main._autosave_controller.set_lesson_paused(true)
	SoloHarness.controller(_main)
	_main.solo_controller.game_rounds = ROUNDS
	CoreActivation._env = 1


func after_test() -> void:
	CoreActivation.reset_all(_main)
	CoreActivation._env = -1
	CoreActivation._hotseat_env = -1
	SoloController.mission_scoring = "end"
	SoloController.mission_markers = []
	SoloController.mission_vp = [0, 0]
	SoloController.mission_vp_memo = {}
	SoloController.mission_vp_flavour = {}
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _clear_units() -> void:
	for u in _main.opr_army_manager.game_units.values():
		for m in (u as GameUnit).models:
			(m as ModelInstance).node.queue_free()
	_main.opr_army_manager.game_units.clear()


## A clean table for `seed` with the switch as asked: fresh units, round 1, the same RNG seeds, no leftover turn,
## mission or session state. Only the switch and the seed may differ between the two runs of a digest compare.
func _reset(seed: int, switch_on: bool) -> void:
	CoreActivation.reset_all(_main)
	CoreActivation._env = 1
	CoreActivation._hotseat_env = 1 if switch_on else 0
	_sessions = 0
	_volleys = 0
	_clear_units()
	_main._hotseat_turn = null
	_main._solo_game_finished = false
	_main.opr_army_manager.current_round = 1
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	SoloHarness.controller(_main)
	_main.solo_controller.game_rounds = ROUNDS
	_main.solo_controller._rng.seed = seed
	_main.seed_tray_rng(seed)
	SoloController.mission_scoring = "end"
	SoloController.mission_markers = []
	SoloController.mission_vp = [0, 0]
	SoloController.mission_vp_memo = {}
	SoloController.mission_vp_flavour = {}
	_build()


func _build() -> void:
	for spec in UNITS:
		var u := ParityTable._make_unit(_main, SIDE.merged({"player": int(spec[0]), "name": str(spec[1]),
			"x_in": float(spec[2])}), RIFLE)
		for m in u.models:
			(m as ModelInstance).node.global_position.z += float(spec[3]) * INCH


func _screen(wx: float, wz: float) -> Vector2:
	return _main.get_viewport().get_camera_3d().unproject_position(Vector3(wx, 0.0, wz))


## A real drag of the whole unit `dx_in` inches along x, landed (the drop tween done).
func _drag(u: GameUnit, dx_in: float) -> void:
	var om: Node3D = _main.object_manager
	om._deselect_all()
	for m in u.models:
		if (m as ModelInstance).is_alive:
			om._add_to_selection((m as ModelInstance).node)
	var a: Node3D = (u.models[0] as ModelInstance).node
	om._start_dragging(_screen(a.global_position.x, a.global_position.z))
	om._update_drag(_screen(a.global_position.x + dx_in * INCH, a.global_position.z))
	await _runner.simulate_frames(1)
	om._stop_dragging()
	await _runner.simulate_frames(3)
	await get_tree().create_timer(0.3).timeout   # a new drop id (a millisecond stamp) for the next drag


## One activation as a player drives it on this side of the switch: with the switch on the Start press opens the core
## session and the walk belongs to it; with it off the walk is free and the press comes after it. Then the volley that
## ends the activation (or the End press when there is nothing to shoot). Both paths end with the unit moved and spent.
func _activate(att: GameUnit, target: GameUnit) -> void:
	var dx: float = 2.0 if int(att.unit_properties.get("player_id", 1)) == 1 else -2.0
	if CoreActivation.hotseat_enabled():
		await _main.radial_menu_controller.card_start_activation(att)
		await E2EBoot.settle(get_tree())
		_sessions += 1 if CoreActivation.session_open(att.unit_id) else 0
	await _drag(att, dx)
	if target != null and target.get_alive_count() > 0 and _main._solo_volley_sighted(att, target) > 0:
		_volleys += 1
		await _main._run_human_attack(att, target, false)
	elif not att.is_activated:
		await _main.radial_menu_controller.card_end_activation(att)
	await E2EBoot.settle(get_tree())


## The next unit of `side` that may still activate this round (alive, unspent, not in reserve), or null.
func _next_unit(side: int) -> GameUnit:
	for u in _main.opr_army_manager.get_all_game_units():
		var gu: GameUnit = u
		if gu == null or int(gu.unit_properties.get("player_id", 0)) != side \
				or gu.get_alive_count() <= 0 or gu.is_activated or SoloController.unit_in_reserve(gu):
			continue
		return gu
	return null


## The nearest enemy of `att` that is alive, or null.
func _target_for(att: GameUnit) -> GameUnit:
	var best: GameUnit = null
	var best_d := INF
	for u in _main.opr_army_manager.get_all_game_units():
		var gu: GameUnit = u
		if gu == null or int(gu.unit_properties.get("player_id", 0)) == int(att.unit_properties.get("player_id", 0)) \
				or gu.get_alive_count() <= 0:
			continue
		var d: float = _main.solo_controller.unit_centre(att).distance_to(_main.solo_controller.unit_centre(gu))
		if d < best_d:
			best = gu
			best_d = d
	return best


## Every activation of every round, in the turn order the table enforces: whoever holds the token activates one unit,
## the round ends by itself when both sides are spent, the next round opens with the side the table names.
func _play() -> void:
	var guard := 0
	while _main.opr_army_manager.current_round <= ROUNDS and not _main._solo_game_finished and guard < 200:
		guard += 1
		var round_no: int = _main.opr_army_manager.current_round
		var att := _next_unit(_main._hotseat_side_on_turn())
		if att == null or _main._hotseat_round_spent():
			break
		await _activate(att, _target_for(att))
	assert_int(_main.opr_army_manager.current_round).override_failure_message(
		"the game did not run %d rounds: round is %d" % [ROUNDS, _main.opr_army_manager.current_round]).is_equal(ROUNDS)


## The planted fault: after the last activation one model stands one inch off where it stood on the table run.
func _nudge() -> void:
	for u in _main.opr_army_manager.get_all_game_units():
		for m in (u as GameUnit).models:
			var model: ModelInstance = m
			if model.is_alive and model.node != null:
				model.node.global_position.z += 1.0 * INCH
				return


func _digest() -> String:
	return _main.solo_controller.state_digest()


func _run(seed: int, switch_on: bool, fault := false) -> Dictionary:
	_reset(seed, switch_on)
	var legacy_before := int((CoreActivation.legacy.get("human_shoot", {}) as Dictionary).get("_all", 0))
	await _play()
	if fault:
		_nudge()
	return {"digest": _digest(), "fields": _fields(), "round": _main.opr_army_manager.current_round,
		"finished": bool(_main._solo_game_finished), "sessions": _sessions, "volleys": _volleys,
		"legacy": int((CoreActivation.legacy.get("human_shoot", {}) as Dictionary).get("_all", 0)) - legacy_before}


## The gate: the same three-round game, the switch on and off, the same end state for every seed. The switch-on run is
## proven to be the core's: every Start opened a session and no volley fell back to the table.
func test_three_hotseat_rounds_end_in_the_same_state_digest(timeout := 900000) -> void:
	var bad: Array = []
	var volleys: Array = []
	for seed in SEEDS:
		var table := await _run(int(seed), false)
		var core := await _run(int(seed), true)
		volleys.append(int(core["volleys"]))
		if table["digest"] != core["digest"]:
			bad.append("seed %d: %s" % [int(seed), _first_diff(table["fields"], core["fields"])])
		if table["round"] != ROUNDS or core["round"] != ROUNDS:
			bad.append("seed %d: rounds %s / %s" % [int(seed), table["round"], core["round"]])
		if int(table["volleys"]) < 1 or int(core["volleys"]) != int(table["volleys"]):
			bad.append("seed %d: volleys %s / %s" % [int(seed), table["volleys"], core["volleys"]])
		if int(core["sessions"]) < 1 or int(core["sessions"]) < int(core["volleys"]):
			bad.append("seed %d: only %d core sessions for %d volleys" % [int(seed), core["sessions"], core["volleys"]])
		if int(core["legacy"]) != 0:
			bad.append("seed %d: %d volleys fell back to the table" % [int(seed), int(core["legacy"])])
	print("hotseat rounds gate: %d of %d seeds differ; volleys %s" % [bad.size(), SEEDS.size(), volleys])
	assert_array(bad).is_empty()


## The gate is not blind: a model one inch off after the last activation turns it red.
func test_one_model_moved_after_the_last_activation_turns_the_gate_red(timeout := 600000) -> void:
	var table := await _run(int(SEEDS[0]), false)
	var faulted := await _run(int(SEEDS[0]), true, true)
	assert_str(str(faulted["digest"])).override_failure_message(
		"the gate did not see a model moved after the last activation").is_not_equal(str(table["digest"]))


## state_digest hashes exactly this field list, rebuilt here only to NAME the first differing field when the gate is
## red (the gate itself compares the digest).
func _fields() -> Array[String]:
	var sc: SoloController = _main.solo_controller
	var parts: Array[String] = []
	parts.append("round=%d|seq=%d" % [int(_main.opr_army_manager.current_round), sc._activation_seq])
	var keyed: Array = []
	for u in _main.opr_army_manager.get_all_game_units():
		keyed.append({"key": sc._digest_unit_key(u), "unit": u})
	keyed.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.key < b.key)
	for entry in keyed:
		var u: GameUnit = entry.unit
		parts.append("u:%s|sh=%d|fa=%d|ac=%d|ca=%d" % [entry.key, int(u.is_shaken), int(u.is_fatigued),
			int(u.is_activated), u.casts_current])
		for m in u.models:
			var model: ModelInstance = m
			var pos: Vector3 = model.node.global_position \
				if model.node and is_instance_valid(model.node) else Vector3.ZERO
			var mk: Array[String] = model.markers.duplicate()
			mk.sort()
			parts.append("  m:al=%d|wo=%d|mk=%s|x=%.2f|y=%.3f|z=%.2f" % [int(model.is_alive),
				model.wounds_current, ", ".join(mk), pos.x, pos.y, pos.z])
	if sc.objectives_provider.is_valid():
		var objs: Variant = sc.objectives_provider.call()
		if objs is Array:
			for i in range((objs as Array).size()):
				var owner: int = int(sc.objective_owner_of.call(i)) if sc.objective_owner_of.is_valid() else 0
				parts.append("o:%d|ow=%d" % [i, owner])
	return parts


## The first field line the two runs disagree on, plus the counts (the digest alone is a hash).
func _first_diff(a: Array[String], b: Array[String]) -> String:
	for i in range(mini(a.size(), b.size())):
		if a[i] != b[i]:
			return "first differing field (line %d):\n  table %s\n  core  %s" % [i, a[i], b[i]]
	if a.size() != b.size():
		return "field counts differ: table %d, core %d" % [a.size(), b.size()]
	return "the digests differ but no field line does"

