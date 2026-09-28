extends GdUnitTestSuite
## NML-1010 wave C gate (C9.2) — the table's round-end referee record.
##
## The wave-C parity gate (core/nml-core-py/tools/mission_referee_gate.py) seats the
## core referee on the board the table had right BEFORE its round-end referee ran
## and must reach the ledger the table was left with. Both halves come from here:
## AiActRecorder.round_end writes one line per round into `rounds.jsonl`, a file
## of its own so no acts.jsonl reader ever meets a new line kind.

var _dir := ""


func before_test() -> void:
	AiActRecorder.close()
	_dir = OS.get_temp_dir().path_join("nml_round_end_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(_dir)
	OS.set_environment("NML_ACT_DUMP", _dir)


func after_test() -> void:
	AiActRecorder.close()
	OS.set_environment("NML_ACT_DUMP", "")
	SoloController.mission_reset("end", {}, [])


func _lines(name: String) -> Array:
	var out: Array = []
	if not FileAccess.file_exists(_dir.path_join(name)):
		return out
	for line in FileAccess.get_file_as_string(_dir.path_join(name)).split("\n", false):
		out.append(JSON.parse_string(line))
	return out


func _board(round_no: int) -> Dictionary:
	return {"round": round_no, "rounds_total": 4, "scoring": "round_vp", "units": {},
		"objectives": [{"pos": Vector3(0.1, 0, 0.2), "owner": 2}]}


func test_round_end_writes_the_board_before_and_the_ledger_after() -> void:
	SoloController.mission_reset("round_vp", {"majority": "end"},
		[{"carry": true, "carried_by": "u_carrier"}])
	SoloController.mission_vp[0] = 3
	SoloController.mission_vp[1] = 1
	AiActRecorder.round_end(2, _board(2), [1])
	var rounds := _lines("rounds.jsonl")
	assert_int(rounds.size()).is_equal(1)
	if rounds.size() != 1:
		return
	var rec: Dictionary = rounds[0]
	assert_int(int(rec["round"])).is_equal(2)
	# `pre` is the PLAIN board (arrays, not Vector3 strings), with the owner it had before.
	var obj: Dictionary = (rec["pre"]["objectives"] as Array)[0]
	assert_float(float((obj["pos"] as Array)[0])).is_equal_approx(0.1, 1e-6)
	assert_int(int(obj["owner"])).is_equal(2)
	var post: Dictionary = rec["post"]
	assert_array(post["owners"]).is_equal([1.0])
	assert_array(post["vp"]).is_equal([3.0, 1.0])
	assert_str(str((post["markers_meta"] as Array)[0]["carried_by"])).is_equal("u_carrier")
	assert_array(post["destroy_seq"]).is_equal([0.0])


func test_round_end_never_touches_the_acts_stream() -> void:
	AiActRecorder.round_end(1, _board(1), [0])
	AiActRecorder.round_end(2, _board(2), [0])
	assert_int(_lines("rounds.jsonl").size()).is_equal(2)
	assert_int(_lines("acts.jsonl").size()).is_equal(0)


func _armed(pid: int, positions: Array, uid: String) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = uid
	u.unit_properties = {"player_id": pid, "name": uid, "quality": 4, "defense": 4,
		"special_rules": []}
	for p in positions:
		var m := ModelInstance.new()
		m.is_alive = true
		m.wounds_current = 1
		m.unit = u
		var n := Node3D.new()
		add_child(n)
		n.global_position = p
		m.node = n
		u.models.append(m)
	var opr := OPRApiClient.OPRUnit.new()
	var ow := OPRApiClient.OPRWeapon.new()
	ow.name = "CCW"
	ow.attacks = 4
	ow.count = 1
	opr.weapons.append(ow)
	u.source_type = "opr"
	u.source_data = opr
	return u


## The live seam end to end: SoloController.capture_board() is the board main hands
## round_end() — a real capture of real units, in the planner's own unit order.
func test_capture_board_feeds_a_real_round_end_line() -> void:
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {"u_p1": _armed(1, [Vector3(-0.3, 0, 0)], "u_p1"),
		"u_p2": _armed(2, [Vector3(0.3, 0, 0)], "u_p2")}
	var solo: SoloController = auto_free(SoloController.new())
	add_child(solo)
	solo.setup(army, null, null, 1, 2)
	solo.round_provider = func() -> int: return 3
	solo.game_rounds = 4
	AiActRecorder.round_end(3, solo.capture_board(), [])
	var rounds := _lines("rounds.jsonl")
	assert_int(rounds.size()).is_equal(1)
	if rounds.size() != 1:
		return
	var pre: Dictionary = (rounds[0] as Dictionary)["pre"]
	assert_int(int(pre["round"])).is_equal(3)
	assert_array(pre["unit_order"]).is_equal(["u_p1", "u_p2"])
	assert_bool((pre["units"]["u_p2"] as Dictionary).has("prof")).is_true()


func test_round_end_is_silent_without_the_dump_env() -> void:
	AiActRecorder.close()
	OS.set_environment("NML_ACT_DUMP", "")
	AiActRecorder.round_end(1, _board(1), [0])
	assert_bool(FileAccess.file_exists(_dir.path_join("rounds.jsonl"))).is_false()
