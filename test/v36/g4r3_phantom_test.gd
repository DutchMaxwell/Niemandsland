extends GdUnitTestSuite
## G4R3 row F-PHANTOM (rules 3.6, EPOCH_73_V36): an act line is written when the planner PICKS, before the table decides
## to play the unit. gf_1000_net_004 act 20, gf_1000_net_009 act 25 and gf_1000_net_022 act 27 are picks the table never
## played (no battle-log line of the unit, no gate call, no dice; the game ended first), and the replay gate scored each
## as a core-longer silence. From EPOCH_73_V36 the recorder writes a `kind:"played"` line {act} when the activation
## actually RAN (the executor returned a unit), and the replay gate skips an act that has no marker.
## Every test drives the live AI activation over main.tscn with real units.

const Boot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254
const _DUMP_DIR := "user://g4r3_phantom_test_tmp"

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
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main._solo_batch = true
	DirAccess.make_dir_recursive_absolute(_DUMP_DIR)
	# The recorder caches its env check + stream in statics - reset per test (the idiom of g4_h1a_test.gd).
	AiActRecorder._checked = false
	AiActRecorder._stream = null
	AiActRecorder._header_written = false
	AiActRecorder._count = 0
	OS.set_environment("NML_ACT_DUMP", ProjectSettings.globalize_path(_DUMP_DIR))


func after_test() -> void:
	AiActRecorder.close()
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


func _played_lines() -> Array:
	var out: Array = []
	var f := FileAccess.open(_DUMP_DIR.path_join("acts.jsonl"), FileAccess.READ)
	if f == null:
		return out
	while not f.eof_reached():
		var line := f.get_line()
		if line != "":
			var rec: Variant = JSON.parse_string(line)
			if rec is Dictionary and str((rec as Dictionary).get("kind", "")) == "played":
				out.append(rec)
	f.close()
	return out


func _unit(pid: int, uid: String, at: Vector3) -> GameUnit:
	var u := Boot.make_unit(_main, pid, uid, [at])
	var opr := OPRApiClient.OPRUnit.new()
	var ws: Array[OPRApiClient.OPRWeapon] = []
	opr.weapons = ws
	u.source_type = "opr"
	u.source_data = opr
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## A human unit and the AI's unit on the table, and the recorder's header + act line for the AI's pick (the planner
## writes them at the pick; here the test stands in for it, as g4_h1a_test does).
func _table() -> GameUnit:
	_unit(1, "Human", Vector3.ZERO)
	var ai := _unit(2, "Machine", Vector3(10.0 * INCH, 0, 0))
	var state: Dictionary = _main.solo_controller.capture_board()
	AiActRecorder.finish(AiActRecorder.begin(state, 2, [ai], Callable()),
		{"used": true, "unit_key": ai.unit_id, "action": {"unit": ai.unit_id, "kind": AiDecision.Action.HOLD}})
	return ai


func test_an_activation_that_ran_writes_a_played_marker_joined_by_act() -> void:
	_table()
	var done: GameUnit = await _main._solo_activate_one_ai_body()
	assert_object(done).override_failure_message("the AI's unit must activate").is_not_null()
	var lines := _played_lines()
	assert_int(lines.size()).override_failure_message("one played line: %s" % str(lines)).is_equal(1)
	if lines.is_empty():
		return
	assert_int(int((lines[0] as Dictionary)["act"])).is_equal(_main.solo_controller.move_act_seq())


func test_a_pick_the_table_never_plays_leaves_no_played_marker() -> void:
	_table()
	var peeked: GameUnit = _main.solo_controller.peek_next_ai_unit()   # the pick exists; nobody activates it
	assert_object(peeked).is_not_null()
	assert_array(_played_lines()).is_empty()


func test_below_epoch_73_no_played_marker_is_written() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36 - 1
	_table()
	var done: GameUnit = await _main._solo_activate_one_ai_body()
	assert_object(done).is_not_null()
	assert_array(_played_lines()).is_empty()
