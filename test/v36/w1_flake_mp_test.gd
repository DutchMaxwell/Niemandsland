extends GdUnitTestSuite
## W1.FLAKE-MP (0.3.15, #1958): the two-instance multiplayer harness records every network status the game
## sets, in order. On a fast rejoin the game can set the hiccup notice, then "Reconnected", then the online
## status inside ONE frame. A once-per-frame look at the status label saw only the last text, so the
## runner's "hiccup notice followed by Reconnected" check failed now and then although the game set both.

const HARNESS := "res://test/mp/mp_two_instance_harness.gd"
const HICCUP := "Connection hiccup — reconnecting…"


## Stands in for main.gd: the harness only reads its network status label.
class FakeMain extends Node:
	var network_status_label := Label.new()

	func _init() -> void:
		add_child(network_status_label)


## A harness around a FakeMain, listening the way it does once it has built main. Without the
## listener (the harness before #1958) only the per-frame sample records statuses.
func _harness() -> Node:
	var harness: Node = auto_free(load(HARNESS).new())
	harness.set("_main", auto_free(FakeMain.new()))
	harness.set("_started_ms", Time.get_ticks_msec())   # no connect timeout inside the test
	if harness.has_method("_listen_net_status"):
		harness.call("_listen_net_status")
	return harness


func _label(harness: Node) -> Label:
	return (harness.get("_main") as FakeMain).network_status_label


## The flake itself: three statuses set inside one frame, then the harness's per-frame step. Every one is
## recorded, in order, and the frame sample adds no second "Online (Peer 2)".
func test_statuses_set_in_one_frame_are_all_recorded() -> void:
	var harness := _harness()
	var label := _label(harness)
	GameMenu.set_status(label, HICCUP, HouseStyle.TONE_WARN)
	GameMenu.set_status(label, "Reconnected", HouseStyle.TONE_OK)
	GameMenu.set_status(label, "Online (Peer 2)", HouseStyle.TONE_OK)
	harness.call("_process", 0.0)
	assert_array(harness.get("_net_status_seen")).contains_exactly([HICCUP, "Reconnected", "Online (Peer 2)"])


## main.gd writes a few texts straight to the label ("Hosting …"); the per-frame sample still records
## those, once, after the status set earlier in the same frame. Another status line is never recorded.
func test_direct_label_write_after_a_set_is_sampled_once() -> void:
	var harness := _harness()
	var label := _label(harness)
	GameMenu.set_status(label, "Online: ABC-123", HouseStyle.TONE_OK)
	label.text = "Hosting (peer 2 joined)"
	GameMenu.set_status(auto_free(Label.new()), "Some other status line", HouseStyle.TONE_OK)
	harness.call("_process", 0.0)
	harness.call("_process", 0.0)
	assert_array(harness.get("_net_status_seen")).contains_exactly(["Online: ABC-123", "Hosting (peer 2 joined)"])
