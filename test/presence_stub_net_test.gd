extends GdUnitTestSuite
## Every test FakeNet that stands in for NetworkManager answers main._broadcast_presence's three calls, so no suite
## crashes when the 15 Hz presence timer fires during a long run (the e2e_mp_transport_activation_economy_test crash).
## The guard scans test/ for FakeNet classes, so a new one that extends Node again turns this red.

const PRESENCE := ["broadcast_cursor_position", "broadcast_camera_direction", "broadcast_camera_position"]


func _fake_net_suites(dir: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".gd") and FileAccess.get_file_as_string(dir.path_join(f)).contains("\nclass FakeNet extends"):
			out.append(dir.path_join(f))
	for sub in d.get_directories():
		out.append_array(_fake_net_suites(dir.path_join(sub)))
	return out


func test_every_fake_net_answers_the_presence_calls() -> void:
	var suites := _fake_net_suites("res://test")
	assert_int(suites.size()).override_failure_message("no FakeNet found - the scan is blind").is_greater(10)
	var missing: Array = []
	for path in suites:
		var fake: Node = (load(path).get("FakeNet") as GDScript).new()
		for m in PRESENCE:
			if not fake.has_method(m):
				missing.append("%s: %s" % [path, m])
		fake.free()
	assert_array(missing).override_failure_message("FakeNets without the presence calls:\n%s" % "\n".join(missing)).is_empty()
