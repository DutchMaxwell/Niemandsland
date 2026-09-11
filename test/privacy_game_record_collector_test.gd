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
