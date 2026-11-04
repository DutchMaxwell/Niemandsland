extends GdUnitTestSuite
## AI-G4 row F-H1a (rules 3.6, EPOCH_73_V36): the recorder names the LEG of every tray roll.
##
## The table's activation is [movement] -> dangerous-terrain test -> spell cast (the cast die, then the
## spell's own saves and morale) -> volley. The core prices a cast as an expectation and rolls no cast
## die, so the replay gates must CUT the cast and spell legs. Until now they found the legs by
## re-parsing the battle log. From EPOCH_73_V36 dice.jsonl stamps `leg` (cast / spell / dangerous /
## main) on every roll, and acts.jsonl gets a `kind:"pre"` line joined by `act` (the act line itself is
## flushed before the activation runs) with the units the cast leg changed: {uid: {alive, shaken}}.
## Below 73 nothing is written, byte-identical. Every test drives the live resolvers over main.tscn.

const Boot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254
const _DUMP_DIR := "user://g4_h1a_test_tmp"

var _runner: GdUnitSceneRunner
var _main: Node
var _roots: Array
var _epoch0: int


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	Boot.arm_harness_mode()
	_roots = Boot.root_children(get_tree())
	_runner = scene_runner(Boot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {1: true, 2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main._solo_batch = true
	DirAccess.make_dir_recursive_absolute(_DUMP_DIR)
	# Both recorders cache their env check + stream in statics — reset per test (the idiom of
	# e2e_dice_recorder_roll_kind_test.gd and ai_planner_act_recorder_test.gd).
	AiDiceRecorder._checked = false
	AiDiceRecorder._stream = null
	AiDiceRecorder._count = 0
	AiActRecorder._checked = false
	AiActRecorder._stream = null
	AiActRecorder._header_written = false
	AiActRecorder._count = 0
	OS.set_environment("NML_DICE_DUMP", ProjectSettings.globalize_path(_DUMP_DIR))
	OS.set_environment("NML_ACT_DUMP", ProjectSettings.globalize_path(_DUMP_DIR))


func after_test() -> void:
	AiDiceRecorder.close()
	AiActRecorder.close()
	OS.set_environment("NML_DICE_DUMP", "")
	OS.set_environment("NML_ACT_DUMP", "")
	AiActRecorder.rules_epoch = _epoch0   # statics leak across gdUnit tests - restore
	var d := DirAccess.open(_DUMP_DIR)
	if d != null:
		for f in d.get_files():
			d.remove(f)
	DirAccess.remove_absolute(_DUMP_DIR)
	Boot.free_stray_root_nodes(get_tree(), _roots)
	_main = null
	_runner = null


func _lines(file: String) -> Array:
	var out: Array = []
	var f := FileAccess.open(_DUMP_DIR.path_join(file), FileAccess.READ)
	if f == null:
		return out
	while not f.eof_reached():
		var line := f.get_line()
		if line != "":
			out.append(JSON.parse_string(line))
	f.close()
	return out


func _legs() -> Array:
	var legs: Array = []
	for rec in _lines("dice.jsonl"):
		legs.append(str((rec as Dictionary).get("leg", "<none>")))
	return legs


func _pre_lines() -> Array:
	return _lines("acts.jsonl").filter(func(l: Variant) -> bool: return str((l as Dictionary).get("kind", "")) == "pre")


func _caster() -> GameUnit:
	var c := Boot.make_unit(_main, 1, "Mystic", [Vector3.ZERO])
	var opr := OPRApiClient.OPRUnit.new()
	var ws: Array[OPRApiClient.OPRWeapon] = []
	opr.weapons = ws
	c.source_type = "opr"
	c.source_data = opr
	_main.opr_army_manager.game_units[c.unit_id] = c
	return c


func _foe() -> GameUnit:
	var positions: Array = []
	for i in range(5):
		positions.append(Vector3(6.0 * INCH, 0, 0.03 * i))
	var u := Boot.make_unit(_main, 2, "Brutes", positions)
	var opr := OPRApiClient.OPRUnit.new()
	var ws: Array[OPRApiClient.OPRWeapon] = []
	opr.weapons = ws
	u.source_type = "opr"
	u.source_data = opr
	for m in u.models:
		(m as ModelInstance).wounds_max = 1
		(m as ModelInstance).wounds_current = 1
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## A real damage spell entry (the shape the planner hands the resolver): ten fixed hits at AP(4)
## against Defense 4+, so only natural 6s save and the five-model unit falls.
func _cast(caster: GameUnit, foe: GameUnit) -> Dictionary:
	return {"caster": caster, "caster_unit": caster, "name": "Test Bolt", "targets": [foe], "boost": 0,
		"interference": 0, "base_target": 2, "threshold": 1, "owner_label": "AI (Mystic)",
		"spell": {"range_in": 12, "effect": {"kind": "damage", "hits": 10, "weapon_rules": ["AP(4)"]},
			"target": {"kind": "unit", "side": "enemy"}}}


## A tray seed whose FIRST die passes the 2+ cast (a natural 1 always fails, and a failed cast has no
## spell leg to record).
func _seed_where_the_cast_passes() -> int:
	var rng := RandomNumberGenerator.new()
	for s in range(1, 200):
		rng.seed = s
		if rng.randi_range(1, 6) >= 2:
			return s
	return 1


## The activation's act line + header, written the way the planner pick writes them (live capture).
func _open_act(caster: GameUnit) -> void:
	var state: Dictionary = _main.solo_controller.capture_board()
	var pending := AiActRecorder.begin(state, 1, [caster], Callable())
	AiActRecorder.finish(pending, {"used": true, "unit_key": caster.unit_id,
		"action": {"unit": caster.unit_id, "kind": 0, "dest": [0.0, 0.0, 0.0]}})


func test_a_cast_act_writes_the_legs_cast_spell_main() -> void:
	var caster := _caster()
	var foe := _foe()
	_open_act(caster)
	_main.seed_tray_rng(_seed_where_the_cast_passes())
	await _main._solo_resolve_ai_casts({"casts": [_cast(caster, foe)]})
	await _main._solo_tray_roll(4, 4, "AI (Mystic)")   # the volley that follows the cast leg
	var legs := _legs()
	assert_array(legs).override_failure_message("legs: %s" % str(legs)).is_not_empty()
	assert_str(str(legs[0])).override_failure_message("legs: %s" % str(legs)).is_equal("cast")
	assert_str(str(legs[legs.size() - 1])).override_failure_message("legs: %s" % str(legs)).is_equal("main")
	assert_int(legs.size()).override_failure_message("a passed cast rolls saves: %s" % str(legs)).is_greater(2)
	for i in range(1, legs.size() - 1):
		assert_str(str(legs[i])).override_failure_message("legs: %s" % str(legs)).is_equal("spell")


func test_a_dangerous_terrain_test_is_its_own_leg() -> void:
	var u := _foe()
	await _main._run_ai_dangerous(u, 3)
	assert_array(_legs()).is_equal(["dangerous"])


func test_the_act_carries_a_pre_block_with_the_cast_leg_casualties() -> void:
	var caster := _caster()
	var foe := _foe()
	_open_act(caster)
	_main.seed_tray_rng(_seed_where_the_cast_passes())
	await _main._solo_resolve_ai_casts({"casts": [_cast(caster, foe)]})
	assert_int(foe.get_alive_count()).override_failure_message("the fixture bolt must kill someone").is_less(5)
	var pre := _pre_lines()
	assert_int(pre.size()).override_failure_message("one pre line per cast leg").is_equal(1)
	if pre.is_empty():
		return
	var units: Dictionary = (pre[0] as Dictionary).get("units", {})
	assert_bool(units.has(foe.unit_id)).override_failure_message("pre: %s" % str(pre[0])).is_true()
	var rec: Dictionary = units[foe.unit_id]
	assert_int(int(rec.get("alive", -1))).is_equal(foe.get_alive_count())
	assert_bool(bool(rec.get("shaken", false))).is_equal(foe.is_shaken)
	assert_bool(units.has(caster.unit_id)).override_failure_message("an unchanged unit is not listed").is_false()


## AI-G4 row F-PRE-SURV (rules 3.6, EPOCH_73_V36): the pre block names WHICH models the cast leg left standing, not
## only how many. The gates kept the FIRST k models of the act-start list, but a spell kills whichever models the wound
## allocation picks (aof_1000_net_033 act 9: the table's spell killed other models than the gate's list dropped). `keep`
## = the positions, in the unit's act-start list of living models, that still stand; `of` = that list's length (the gate
## applies `keep` only to a per-model list of that size). Live path: the real spell resolver over a real five-model unit.
func test_the_pre_block_names_the_models_the_cast_leg_left_standing() -> void:
	var caster := _caster()
	var foe := _foe()
	_open_act(caster)
	var start: Array = foe.get_alive_models()
	var cast := _cast(caster, foe)
	((cast["spell"] as Dictionary)["effect"] as Dictionary)["hits"] = 3   # a bolt that thins the unit, not wipes it
	_main.seed_tray_rng(_seed_where_the_cast_passes())
	await _main._solo_resolve_ai_casts({"casts": [cast]})
	assert_int(foe.get_alive_count()).override_failure_message("the bolt must kill someone, and not everyone").is_between(1, 4)
	var want: Array = []
	for i in range(start.size()):
		if (start[i] as ModelInstance).is_alive:
			want.append(i)
	var units: Dictionary = (_pre_lines()[0] as Dictionary).get("units", {})
	var rec: Dictionary = units.get(foe.unit_id, {})
	assert_int(int(rec.get("of", -1))).override_failure_message("pre: %s" % str(rec)).is_equal(start.size())
	assert_array(rec.get("keep", []) as Array).override_failure_message("pre: %s" % str(rec)).is_equal(want)


func test_below_epoch_73_nothing_new_is_written() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36 - 1
	var caster := _caster()
	var foe := _foe()
	_open_act(caster)
	_main.seed_tray_rng(_seed_where_the_cast_passes())
	await _main._solo_resolve_ai_casts({"casts": [_cast(caster, foe)]})
	assert_array(_legs().filter(func(l: Variant) -> bool: return l != "<none>")).is_empty()
	assert_array(_pre_lines()).is_empty()
