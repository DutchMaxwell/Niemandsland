extends GdUnitTestSuite
## A regiment tray must keep its MP network_id across save/load (bus 036): Regiment.to_dict serializes it,
## and restore feeds it back so the tray rebinds instead of minting a fresh id (like units already do).


func test_to_dict_includes_tray_network_id() -> void:
	var tray := RegimentTray.new()
	add_child(tray)
	auto_free(tray)
	tray.set_meta("network_id", 5007)
	var reg := Regiment.new()
	reg.tray = tray
	reg.frontage = 5
	var d := reg.to_dict()
	assert_bool(d.has("network_id")).is_true()
	assert_int(int(d["network_id"])).is_equal(5007)
