extends GdUnitTestSuite
## The cast/attack announce markers are queue_free()d by whichever path ends first (a concurrent
## activation sweep, the caller's own cleanup), so `_solo_clear_announce` meets members that are
## already freed. `n is Node` on a freed instance raises "Left operand of 'is' is a previously freed
## instance" and aborts the loop, leaving the remaining markers alive and the sweep list stale.
## The cases hand it a freed node, a live node AFTER it and a non-node value, so an abort is visible
## in the outcome (the live node is never queued) and not only in the engine log.

class Probe extends "res://scripts/main.gd":
	pass


func _probe() -> Probe:
	var main: Probe = auto_free(Probe.new())
	main.battle_log = auto_free(BattleLog.new())
	return main


func test_freed_marker_does_not_abort_the_cleanup() -> void:
	var main := _probe()
	var dead := Node.new()
	dead.free()
	var live := Node.new()
	var nodes: Array = [dead, live, "not a node"]
	main._solo_live_announce = nodes
	main._solo_clear_announce(nodes)
	assert_bool(is_instance_valid(live) and live.is_queued_for_deletion()) \
		.override_failure_message("the live marker behind a freed one was never queued for deletion") \
		.is_true()
	assert_int(main._solo_live_announce.size()) \
		.override_failure_message("the sweep list was not emptied after the cleanup") \
		.is_equal(0)
	if is_instance_valid(live):
		live.free()


func test_live_markers_still_queued_and_list_emptied() -> void:
	var main := _probe()
	var a := Node.new()
	var b := Node.new()
	var nodes: Array = [a, b]
	main._solo_live_announce = nodes
	main._solo_clear_announce(nodes)
	assert_bool(a.is_queued_for_deletion() and b.is_queued_for_deletion()).is_true()
	assert_int(main._solo_live_announce.size()).is_equal(0)
	a.free()
	b.free()
