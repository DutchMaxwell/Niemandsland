extends GdUnitTestSuite
## Heights B2 step 18 — the move corpus carries opts["ledges"] as [ax, ay, bx, by, dy_in] rows, and the
## recheck rebuilds them to the exact planner types (a call with ledges must replay the same plan).

func _ledges() -> Array:
	return [{"a": Vector2(12, 0), "b": Vector2(12, 20), "dy_in": 2.5}, {"a": Vector2(3, 4), "b": Vector2(9, 4), "dy_in": 1.0}]


func test_ledges_are_recorded_as_rows_through_json() -> void:
	var flat := MoveRecorder._flatten_opts({"clearance": 0.6, "ledges": _ledges()})
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(flat))
	assert_array(parsed["ledges"]).is_equal([[12.0, 0.0, 12.0, 20.0, 2.5], [3.0, 4.0, 9.0, 4.0, 1.0]])


func test_rows_rebuild_to_the_planner_types_and_the_same_climb_cost() -> void:
	var rows: Array = JSON.parse_string(JSON.stringify(MoveRecorder.ledge_rows(_ledges())))
	var rebuilt := MoveRecorder.ledges_from_rows(rows)
	assert_array(rebuilt).is_equal(_ledges())
	var a := Vector2(10, 10)
	var b := Vector2(16, 10)
	assert_float(MovementPlanner.ledge_cost(a, b, {"ledges": rebuilt})).is_equal(MovementPlanner.ledge_cost(a, b, {"ledges": _ledges()}))


func test_a_call_without_ledges_records_no_key() -> void:
	assert_bool(MoveRecorder._flatten_opts({"clearance": 0.6}).has("ledges")).is_false()
