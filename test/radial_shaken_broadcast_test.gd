extends GdUnitTestSuite
## Shaken set or cleared through RadialMenuController._toggle_shaken reaches the other peers: it broadcasts the ShakenMarker
## exactly once per toggle (as _toggle_fatigued does for FatiguedMarker). Before this the broadcast tail sat at the end of
## _log_manual_revive (moved there by the manual-corrections change), so a failed morale on the resolving table, an automatic
## Shaken and a manual Shaken toggle never left that table - the digest check reported "tables disagreed" and the correction
## repaired it - and a manual revive broadcast a Shaken nobody had toggled.


## A NetworkManager stand-in that only records the marker broadcasts.
class FakeNet extends "res://test/support/presence_stub_net.gd":
	var markers: Array = []

	func broadcast_unit_marker(game_unit: GameUnit, marker_name: String, add: bool, _color: Color = Color.WHITE, _value: int = -1) -> void:
		markers.append([game_unit, marker_name, add])


func _controller() -> RadialMenuController:
	var rc: RadialMenuController = auto_free(RadialMenuController.new())
	add_child(rc)   # in the tree: the manual path looks the table's Main node up by its absolute path
	rc.network_manager = auto_free(FakeNet.new())
	return rc


func test_a_shaken_toggle_broadcasts_the_marker_once() -> void:
	var rc := _controller()
	var unit := GameUnit.new()
	rc.card_toggle_shaken(unit)
	assert_bool(unit.is_shaken).is_true()
	assert_array((rc.network_manager as FakeNet).markers).override_failure_message("a Shaken set did not leave this table").is_equal([[unit, "ShakenMarker", true]])
	rc.card_toggle_shaken(unit)
	assert_bool(unit.is_shaken).is_false()
	assert_array((rc.network_manager as FakeNet).markers).is_equal([[unit, "ShakenMarker", true], [unit, "ShakenMarker", false]])


func test_the_manual_shaken_toggle_broadcasts_the_marker_once() -> void:
	var rc := _controller()
	var unit := GameUnit.new()
	rc.card_toggle_shaken(unit, true)
	assert_array((rc.network_manager as FakeNet).markers).is_equal([[unit, "ShakenMarker", true]])


func test_a_manual_revive_broadcasts_no_shaken_marker() -> void:
	var rc := _controller()
	var unit := GameUnit.new()
	rc._log_manual_revive(unit, "")
	assert_array((rc.network_manager as FakeNet).markers).override_failure_message("a revive broadcast a Shaken nobody toggled").is_empty()
