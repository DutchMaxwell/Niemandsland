extends GdUnitTestSuite
## Unit-level guards for the PR B1 collector that do not need a booted game: the transport scan and
## the per-action cost, so a future edit cannot quietly add a network path or an expensive seam.

const COLLECTOR_PATH := "res://scripts/privacy/game_record_collector.gd"


func _collector():
	return load(COLLECTOR_PATH).new()


func test_collector_references_no_transport_apis() -> void:
	var source := FileAccess.get_file_as_string(COLLECTOR_PATH)
	for token: String in ["HTTP" + "Request", "HTTP" + "Client", "Stream" + "Peer", "Web" + "Socket", "ENet", "Network" + "Manager"]:
		assert_str(source).override_failure_message("collector references %s — it must stay local-only" % token).not_contains(token)


func test_collector_names_the_not_recorded_intents() -> void:
	var collector = _collector()
	var record: Dictionary = collector.build_record()
	assert_str(str(record["not_recorded"])).contains("charge declarations")
	assert_str(str(record["not_recorded"])).contains("human spell casts")
	collector.free()


## Negligible per action: measured over 2000 activations in this process; the bound is generous so a
## loaded CI box does not flake, while a real allocation-heavy regression still trips it.
## A real Table node off the world origin plus a bare main stub that answers the move seam.
func _table_fixture() -> Array:
	var table = load("res://scripts/table.gd").new()
	table.table_size = Vector2(6, 4)
	table.position = Vector3(1.5, 0.0, 0.75)
	var main_src := GDScript.new()
	main_src.source_code = "extends RefCounted\nvar table = null\nvar opr_army_manager = null\nvar terrain_overlay = null\nvar _solo_mission_id = \"\"\nvar unit = null\nfunc _trail_unit_of(_n):\n\treturn unit\n"
	main_src.reload()
	var main = main_src.new()
	main.table = table
	var gu := GameUnit.new()
	gu.unit_id = "corner-probe"
	gu.unit_properties = {"player_id": 1}
	main.unit = gu
	return [main, table]


## Fix 1: positions are recorded in table inches measured FROM the table corner (the
## example_record.json convention), never from the world origin. The two opposite corners must
## record as [0, 0] and [width_inches, height_inches] within 0.01 in, even though the table sits
## at a non-zero world position — proving the origin is read from the table node, not assumed.
func test_table_corners_record_in_inches_from_the_corner() -> void:
	var pair: Array = _table_fixture()
	var collector = _collector()
	collector.bind(pair[0])
	var table = pair[1]
	var half := Vector3(table.table_size.x * 0.3048 / 2.0, 0.0, table.table_size.y * 0.3048 / 2.0)
	collector.on_selection_dropped([{"node": null, "from": table.position - half, "to": table.position + half}])
	var record: Dictionary = collector.build_record()
	var actions: Array = record["actions"]
	assert_int(actions.size()).is_equal(1)
	var from: Array = actions[0]["from"]
	var to: Array = actions[0]["to"]
	assert_float(from[0]).override_failure_message("min corner x recorded %s, want 0.0" % from[0]).is_equal_approx(0.0, 0.01)
	assert_float(from[1]).override_failure_message("min corner z recorded %s, want 0.0" % from[1]).is_equal_approx(0.0, 0.01)
	assert_float(to[0]).override_failure_message("max corner x recorded %s, want 72.0" % to[0]).is_equal_approx(72.0, 0.01)
	assert_float(to[1]).override_failure_message("max corner z recorded %s, want 48.0" % to[1]).is_equal_approx(48.0, 0.01)
	collector.free()
	table.free()


func test_per_action_cost_is_negligible() -> void:
	var collector = _collector()
	var gu := GameUnit.new()
	gu.unit_id = "u1"
	gu.unit_properties = {"player_id": 1}
	var count := 2000
	var started := Time.get_ticks_usec()
	for _i in range(count):
		collector.on_unit_activated(gu)
	var elapsed := Time.get_ticks_usec() - started
	var per_action := float(elapsed) / float(count)
	assert_float(per_action).override_failure_message("measured %.2f us/action over %d actions" % [per_action, count]).is_less(250.0)
	collector.free()


## PR B2: main.gd hands the record to the menu and resets the collector; reset must leave no actions
## and no round counter behind for the next game.
func test_reset_clears_actions_and_round_counters() -> void:
	var collector = _collector()
	var gu := GameUnit.new()
	gu.unit_id = "u-reset"
	gu.unit_properties = {"player_id": 1}
	collector.on_unit_activated(gu)
	collector.on_round_advanced(4)
	assert_int(collector.action_count()).is_equal(1)
	collector.reset()
	assert_int(collector.action_count()).override_failure_message("reset() must empty the action list").is_equal(0)
	var record: Dictionary = collector.build_record()
	assert_int(int(record["rounds"])).is_equal(1)
	collector.free()
