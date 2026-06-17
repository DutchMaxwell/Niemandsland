extends GdUnitTestSuite
## Sort Table now mirrors to remote peers (0.3.4.5). Previously object_manager.sort_table() reset
## every unit to its import state LOCALLY and broadcast nothing, so the other client never saw it.
## The fix broadcasts the command; the sync_sort_table RPC must emit remote_sort_table_received,
## which main.gd handles by re-running sort_table(broadcast=false) on the receiving peer.

const NetworkManagerScript = preload("res://scripts/network_manager.gd")


func test_sync_sort_table_emits_remote_signal() -> void:
	var nm: Node = auto_free(NetworkManagerScript.new())
	var hits := [0]
	nm.remote_sort_table_received.connect(func() -> void: hits[0] += 1)
	nm.sync_sort_table()
	assert_int(hits[0]).is_equal(1)
