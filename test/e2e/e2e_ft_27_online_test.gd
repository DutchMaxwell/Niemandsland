extends GdUnitTestSuite
## Feature test FT-27: the turn token and the command picks online, Firefight (gff) and Skirmish (aofs). An agreed
## Automatic room, this table = the host on slot 1, the transport swapped for the recording WireNet (every frame in
## `net.wire`). FF36 p.7 l.487-507 (one unit per turn, alternating) and AS36 p.13 l.1186-1203 (command picks).
## - gff: the host activates and ends Hosts -> one `sync_turn_state` [2] goes out and the host's second unit is refused
##   ("It is P2's turn"); the host's off-turn drag of that unit snaps back with no fact on the wire; the guest's activation
##   fact arrives (the real receive door) -> the host hands the token back: `sync_turn_state` [1].
## - aofs: during deployment the host's Band (Banner) picks Xan and Yor -> the pick travels in the unit-property sync
##   frame `command_picks`. FINDING #3878 (R-FT2): it does not - `command_picks` is not a syncable unit property (the
##   manager refuses it with a warning); the case stays, skipped with that issue.
## Real: the main scene, the REAL NetworkManager (transport only swapped), the card's Activate / End, the real drag, the
## receive door `sync_unit_activation`, the pick door.

const INCH := 0.0254

var _t: SkirmishTable


func before_test() -> void:
	_t = await SkirmishTable.boot(self, "O")


func after_test() -> void:
	if _t != null:
		_t.teardown()
	_t = null


func _frames(method: String) -> Array:
	return _t.net.wire.filter(func(f: Dictionary) -> bool: return str(f["t"]) == "rpc" and str(f["p"]["m"]) == method)


func test_gff_the_token_alternates_with_the_guest(timeout := 120000) -> void:
	var h1 := _t.unit("gff", 1, "Hosts", 1, 1, -12.0, 0.0)
	var h2 := _t.unit("gff", 1, "Hosts2", 1, 1, -12.0, 8.0)
	var g1 := _t.unit("gff", 2, "Guests", 1, 1, 12.0, 0.0)
	_t.unit("gff", 2, "Guests2", 1, 1, 12.0, 8.0)
	assert_bool(await _t.start(h1)).is_true()
	await _t.end(h1)
	var tokens := _frames("sync_turn_state")
	assert_int(tokens.size()).override_failure_message("one token frame: %s" % [_t.net.wire]).is_equal(1)
	assert_array(tokens[0]["p"]["a"] if not tokens.is_empty() else []).is_equal([2])
	assert_bool(await _t.start(h2)).override_failure_message("the host's second unit is refused").is_false()
	assert_bool(_t.lines.any(func(l: String) -> bool: return l.find("It is P2's turn") != -1)).override_failure_message("%s" % [_t.lines]).is_true()
	var sent := _t.net.wire.size()
	var from: Vector3 = (h2.models[0] as ModelInstance).node.global_position
	await _t.walk(h2, 3.0, 0.0, CoreActivation.CAP_ADVANCE)
	assert_float(((h2.models[0] as ModelInstance).node.global_position - from).length() / INCH) \
		.override_failure_message("the off-turn drag snaps back: %s" % [_t.lines]).is_less(0.1)
	assert_bool(_t.net.wire.slice(sent).any(func(f: Dictionary) -> bool: return str(f["t"]) == "rpc" \
		and str(f["p"]["m"]) in ["sync_move_log", "sync_turn_state", "sync_unit_activation"])) \
		.override_failure_message("no fact on the wire: %s" % [_t.net.wire.slice(sent)]).is_false()
	_t.net.sync_unit_activation(g1.unit_id, true, 1)   # the guest's activation fact arrives
	await _t.runner.simulate_frames(4)
	tokens = _frames("sync_turn_state")
	assert_int(tokens.size()).override_failure_message("the host hands the token back: %s" % [_t.net.wire]).is_equal(2)
	assert_array(tokens[-1]["p"]["a"] if not tokens.is_empty() else []).is_equal([1])


@warning_ignore("unused_parameter")
func test_aofs_the_command_picks_travel_in_the_unit_property_sync(timeout := 120000, do_skip := true,
		skip_reason := "FINDING #3878: command_picks is not a syncable unit property - the pick never reaches the wire") -> void:
	_t.main.opr_army_manager.set_game_phase(OPRArmyManager.GamePhase.DEPLOYMENT)
	var band := _t.unit("aofs", 1, "Band", 1, 1, -20.0, 0.0, {}, ["Banner"])
	var x := _t.unit("aofs", 1, "Xan", 1, 1, -20.0, 5.0)
	var y := _t.unit("aofs", 1, "Yor", 1, 1, -20.0, 10.0)
	_t.unit("aofs", 2, "Guests", 1, 1, 20.0, 0.0)
	CommandPicks.toggle(_t.main, band, x)
	CommandPicks.toggle(_t.main, band, y)
	var picks := _frames("sync_unit_property").filter(func(f: Dictionary) -> bool: return str(f["p"]["a"][1]) == "command_picks")
	assert_int(picks.size()).override_failure_message("two pick frames: %s" % [_t.net.wire]).is_equal(2)
	if picks.size() == 2:
		assert_array(picks[-1]["p"]["a"][2]).is_equal([x.unit_id, y.unit_id])
