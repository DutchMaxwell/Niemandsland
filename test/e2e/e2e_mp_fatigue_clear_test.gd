extends GdUnitTestSuite
## E2E — audit row 36: the round-start fatigue clear also runs in a PLAIN multiplayer room.
##
## THE GATE. main._on_solo_round_advanced bails out when solo_ai_slots is empty — i.e. in exactly
## the human-vs-human rooms where automation was assumed dead. The clear itself is already general
## and already synced: _solo_reset_all_fatigue walks EVERY unit of BOTH sides and clears through
## radial_menu_controller.card_toggle_fatigued, the same toggle the manual Fatigued button uses,
## which broadcasts FatiguedMarker to the peer. The handler is connected UNCONDITIONALLY to
## opr_army_manager.round_advanced (main.gd:12061), and that signal also fires locally on the
## REMOTE peer — NetworkManager.sync_round_advance calls army_manager.advance_round() on the
## receiver (network_manager.gd:896-899). So moving the clear in front of the gate automates both
## sides with zero new sync code.
##
## THE SEAM UNDER TEST. This suite calls _main._on_solo_round_advanced(2) directly — that IS the
## audited seam: every round-advance path (solo _solo_end_round, the plain-MP branch of
## _do_next_round, and the remote sync_round_advance RPC) lands here. Driving the button/RPC
## plumbing on top would test Godot, not the gate.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")


## Stands in for NetworkManager at main's seam: a live session that records every outbound frame.
class FakeNet extends Node:
	var active: bool = true
	var sent: Array = []
	func is_multiplayer_active() -> bool:
		return active
	func broadcast_unit_marker(gu: GameUnit, marker_name: String, add: bool, _color: Color = Color.WHITE, _value: int = -1) -> void:
		sent.append({"kind": "marker", "unit": gu.unit_id, "marker": marker_name, "add": add})

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _fake: FakeNet


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	# PLAIN multiplayer room: NO AI slot at all. This is the configuration the gate bites on —
	# the co-op suites ({2: true}) can never see it, because the gate only blocks empty rooms.
	assert_array(_main.solo_ai_slots.keys()) \
		.override_failure_message("fixture check: this suite tests the PLAIN mp room — solo_ai_slots must be empty") \
		.is_empty()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	_fake = auto_free(FakeNet.new())
	_main.network_manager = _fake
	# The toggle path holds its own reference (main.gd:15986 stamps it at boot) — point it at the
	# recorder so the suite can watch the FatiguedMarker frames the clear is supposed to ride.
	_main.radial_menu_controller.network_manager = _fake


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null
	_fake = null


## Register a fixture unit owned by `pid` in the army manager's registry — the set
## _solo_reset_all_fatigue walks (get_all_game_units reads exactly this dict).
func _reg(pid: int, unit_name: String) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, [Vector3.ZERO])
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## Fatigued markers a unit sent to the peer (add=false = "marker removed" = cleared).
func _marker_frames(u: GameUnit) -> Array:
	var out: Array = []
	for e in _fake.sent:
		var d := e as Dictionary
		if str(d["kind"]) == "marker" and str(d["unit"]) == u.unit_id:
			out.append(d)
	return out


## THE CLAIM: in a plain human-vs-human room, one round advance clears fatigue on BOTH sides —
## each through the real toggle path (is_fatigued flipped via card_toggle_fatigued) and each
## announced to the peer (a FatiguedMarker add=false frame on the wire), with no new sync code.
func test_round_start_clears_fatigue_on_both_sides_in_plain_mp(timeout := 120000) -> void:
	var mine := _reg(1, "Riflemen")
	var theirs := _reg(2, "Raiders")
	mine.is_fatigued = true
	theirs.is_fatigued = true
	assert_bool(_fake.is_multiplayer_active()) \
		.override_failure_message("fixture check: this test is only meaningful in a live session") \
		.is_true()

	_main._on_solo_round_advanced(2)

	assert_bool(mine.is_fatigued) \
		.override_failure_message("the human's fatigue survives the round change — the solo_ai_slots gate blocks the clear in plain multiplayer") \
		.is_false()
	assert_bool(theirs.is_fatigued) \
		.override_failure_message("the opponent's fatigue survives too — the gate returns before any reset runs") \
		.is_false()
	for u: GameUnit in [mine, theirs]:
		# Read defensively (see e2e_mp_utility_buffs_test._last_records): when the gate blocks,
		# there is no frame at all — the asserts below must FAIL cleanly, not index [-1].
		var frames := _marker_frames(u)
		assert_int(frames.size()) \
			.override_failure_message("the clear of %s never left this client — the peer's markers would stay Fatigued (sent: %s)" % [u.unit_id, str(_fake.sent)]) \
			.is_greater_equal(1)
		var last: Dictionary = (frames[frames.size() - 1] as Dictionary) if not frames.is_empty() else {}
		assert_bool(bool(last.get("add", true))) \
			.override_failure_message("%s's last FatiguedMarker frame was an add — the wire would RE-fatigue the peer" % u.unit_id) \
			.is_false()


## Offline solo is untouched by the re-ordering: with slots present the clear still runs, and it
## still logs. (In solo the gate never actually blocked it — the dict is what MAKES it solo — so
## this is the byte-identical-behaviour control.)
func test_solo_room_still_clears_fatigue(timeout := 120000) -> void:
	_main.solo_ai_slots = {2: true}
	var mine := _reg(1, "Riflemen")
	mine.is_fatigued = true

	_main._on_solo_round_advanced(2)

	assert_bool(mine.is_fatigued) \
		.override_failure_message("the solo room lost its round-start fatigue clear") \
		.is_false()
