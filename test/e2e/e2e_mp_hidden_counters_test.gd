extends GdUnitTestSuite
## E2E — NML-927: the HIDDEN rules numbers have to ride the wire.
##
## THE DEFECT. Three rules-relevant numbers live in unit_properties and never left the client that
## produced them:
##
##   • "spot_markers"    — Precision Spotter marks. Only the BOOLEAN "Spotted" token went through
##                          the marker channel (radial_menu_controller.apply/remove_library_token),
##                          so the peer knew THAT a unit was marked and never how OFTEN. Worse, a
##                          partial removal ("+2 to hit, one marker stays lying") leaves that token
##                          standing, so the marker channel carried nothing at all — the two tables
##                          then disagreed about a to-hit bonus that is still on the table.
##   • "spell_move_mod"  — the NET spell advance/rush delta the movement bands read.
##   • "spell_range_mod" — the NET spell shooting-range delta every volley/plan/ring site reads.
##
## All three are read by the OPPONENT's client too (it draws its own range rings, measures its own
## charge reach and rolls its own defense), so a number that stays local is a desync of the dice.
##
## THE FIX UNDER TEST. Every write to those keys goes through main._sync_unit_property, which writes
## AND pushes the delta through NetworkManager.broadcast_unit_property — the same command channel
## every other sync_* call uses, one more handler name in the existing envelope, no new protocol.
##
## The suite drives the REAL main.tscn resolvers and records what main hands to NetworkManager, then
## feeds those exact arguments into the REAL receiver to prove the delta reconstructs the number.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254


## Stands in for NetworkManager at main's seam: a live session that records every outbound hidden
## state delta in the order main sent them. `active` mirrors the real is_multiplayer_active() gate,
## which is what main tests before it broadcasts at all.
class FakeNet extends Node:
	var active: bool = true
	var sent: Array = []
	func is_multiplayer_active() -> bool:
		return active
	func slot_has_human_peer(_slot: int) -> bool:
		return false
	func broadcast_unit_property(gu: GameUnit, key: String, value: Variant) -> void:
		sent.append({"unit": gu.unit_id, "key": key, "value": value})

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _fake: FakeNet
var _real_net: Node


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main._solo_batch = true   # no dialogs, no physics tray, no floating text in a headless sweep
	_real_net = _main.network_manager   # kept for the receive-side proof (its handler is call_remote)
	_fake = auto_free(FakeNet.new())
	_main.network_manager = _fake


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null
	_fake = null
	_real_net = null


func _at(inches_x: float) -> Vector3:
	return Vector3(inches_x * INCH, 0.0, 0.0)


func _reg(pid: int, unit_name: String, positions: Array) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, positions)
	u.unit_properties["special_rules"] = []
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## Only the deltas for `key`, in the order main sent them.
func _sent(key: String) -> Array:
	var out: Array = []
	for e in _fake.sent:
		if str((e as Dictionary)["key"]) == key:
			out.append(e)
	return out


func _values(key: String) -> Array:
	var out: Array = []
	for e in _sent(key):
		out.append((e as Dictionary)["value"])
	return out


## Read defensively: with no message at all every assertion below must still FAIL cleanly — an
## out-of-bounds index would break gdUnit's -d run into the debugger instead (and, measured here,
## take the whole headless process down with signal 11).
func _first(key: String) -> Dictionary:
	var rows := _sent(key)
	return (rows[0] as Dictionary) if not rows.is_empty() else {}


# === 1. Precision Spotter marks ==================================================================

## Placing a mark sends its COUNT, and a second mark on the same unit sends the new count — the
## "Spotted" token is placed exactly once, so it can never carry this by itself.
func test_each_placed_spot_marker_sends_its_count(timeout := 120000) -> void:
	var spotter := _reg(2, "Scout Team", [_at(0.0)])
	var victim := _reg(1, "Riflemen", [_at(10.0), _at(11.0)])

	_main._solo_place_spot_marker(spotter, victim)
	_main._solo_place_spot_marker(spotter, victim)

	assert_int(int(victim.unit_properties.get("spot_markers", 0))) \
		.override_failure_message("fixture check: two marks must actually stack locally") \
		.is_equal(2)
	assert_array(_values("spot_markers")) \
		.override_failure_message("the mark COUNT never left this client — the peer sees a boolean token and guesses (sent: %s)" % str(_fake.sent)) \
		.is_equal([1, 2])
	assert_str(str(_first("spot_markers").get("unit", "<no message>"))).is_equal(victim.unit_id)


## Spending ALL marks erases the key on the peer too. Erasure is the `null` payload — a 0 would
## leave a dead key lying in unit_properties on one side only.
func test_spending_every_marker_sends_the_erasure(timeout := 120000) -> void:
	var spotter := _reg(2, "Scout Team", [_at(0.0)])
	var victim := _reg(1, "Riflemen", [_at(10.0), _at(11.0)])
	_main._solo_place_spot_marker(spotter, victim)
	_main._solo_place_spot_marker(spotter, victim)
	_fake.sent.clear()

	var took: int = _main._solo_consume_spot_markers(victim)

	assert_int(took).override_failure_message("fixture check: the take-all path must take both").is_equal(2)
	assert_bool(victim.unit_properties.has("spot_markers")) \
		.override_failure_message("fixture check: a full consumption erases the key locally") \
		.is_false()
	assert_array(_values("spot_markers")) \
		.override_failure_message("the peer keeps two spent marks lying on the unit (sent: %s)" % str(_fake.sent)) \
		.is_equal([null])


## THE CASE NOTHING ELSE COVERS: a PARTIAL removal. The attacker takes one of three, the "Spotted"
## token stays on the table, so the marker channel is silent — this delta is the only message.
func test_a_partial_removal_sends_the_remainder(timeout := 120000) -> void:
	var spotter := _reg(2, "Scout Team", [_at(0.0)])
	var victim := _reg(1, "Riflemen", [_at(10.0), _at(11.0)])
	for _i in 3:
		_main._solo_place_spot_marker(spotter, victim)
	_fake.sent.clear()

	var took: int = _main._solo_consume_spot_markers(victim, 1)

	assert_int(took).is_equal(1)
	assert_int(int(victim.unit_properties.get("spot_markers", 0))) \
		.override_failure_message("fixture check: a partial take must leave the rest lying") \
		.is_equal(2)
	assert_array(_values("spot_markers")) \
		.override_failure_message("a partial removal is INVISIBLE on the marker channel — without this delta the peer still counts three (sent: %s)" % str(_fake.sent)) \
		.is_equal([2])


# === 2. The spell stamps =========================================================================

## A speed spell stamps {advance, rush} onto the unit — and the peer needs it to draw the same
## charge reach. Recording the mod is the production entry point (_solo_record_spell_mod).
func test_a_speed_stamp_rides_the_wire(timeout := 120000) -> void:
	var target := _reg(1, "Riflemen", [_at(10.0), _at(11.0)])

	_main._solo_record_spell_mod(target, "Quicken",
		{"modifier": {"advance_in": 4, "rush_in": 4}, "duration": "round"})

	assert_dict(target.unit_properties.get("spell_move_mod", {})) \
		.override_failure_message("fixture check: the stamp must land locally first") \
		.is_equal({"advance": 4, "rush": 4})
	assert_array(_values("spell_move_mod")) \
		.override_failure_message("the peer measures the unbuffed move — its charge reach and move rings disagree with ours (sent: %s)" % str(_fake.sent)) \
		.is_equal([{"advance": 4, "rush": 4}])
	# The range stamp stayed at zero, so nothing was sent for it: no traffic for a key that did
	# not change is part of the fix, not an omission.
	assert_array(_values("spell_range_mod")).is_empty()


## A range spell stamps an int, and the round-end expiry sends the erasure — otherwise the buff
## would be permanent on the peer's table.
func test_a_range_stamp_and_its_expiry_both_ride_the_wire(timeout := 120000) -> void:
	var target := _reg(1, "Riflemen", [_at(10.0), _at(11.0)])

	_main._solo_record_spell_mod(target, "Far Sight",
		{"modifier": {"range_in": 6}, "duration": "round"})
	assert_array(_values("spell_range_mod")) \
		.override_failure_message("the peer draws the unbuffed range ring (sent: %s)" % str(_fake.sent)) \
		.is_equal([6])

	_fake.sent.clear()
	_main._solo_expire_spell_tokens()

	assert_bool(target.unit_properties.has("spell_range_mod")) \
		.override_failure_message("fixture check: the round boundary must clear the stamp locally") \
		.is_false()
	assert_array(_values("spell_range_mod")) \
		.override_failure_message("the expiry never left this client — the buff is permanent on the peer (sent: %s)" % str(_fake.sent)) \
		.is_equal([null])


## The traffic guard: restamping the SAME numbers must not put another frame on the wire. A second
## record with no speed/range component recomputes the identical stamp.
func test_an_unchanged_restamp_stays_off_the_wire(timeout := 120000) -> void:
	var target := _reg(1, "Riflemen", [_at(10.0), _at(11.0)])
	_main._solo_record_spell_mod(target, "Far Sight",
		{"modifier": {"range_in": 6}, "duration": "round"})
	_fake.sent.clear()

	_main._solo_record_spell_mod(target, "Blessing",
		{"modifier": {"hit_mod": 1}, "duration": "round"})

	assert_int(int(target.unit_properties.get("spell_range_mod", 0))) \
		.override_failure_message("fixture check: the second record must not change the range stamp") \
		.is_equal(6)
	assert_array(_fake.sent) \
		.override_failure_message("every restamp turned into a wire frame — the stamps are recomputed on every record, consumption and expiry") \
		.is_empty()


# === 3. Counter-proofs ===========================================================================

## Offline the whole thing must stay silent — a solo game keeps working exactly as before, with no
## message and no error on a NetworkManager that refuses to send.
func test_solo_without_peers_sends_nothing_and_still_counts(timeout := 120000) -> void:
	_fake.active = false
	var spotter := _reg(2, "Scout Team", [_at(0.0)])
	var victim := _reg(1, "Riflemen", [_at(10.0), _at(11.0)])

	_main._solo_place_spot_marker(spotter, victim)
	_main._solo_place_spot_marker(spotter, victim)
	_main._solo_consume_spot_markers(victim, 1)
	_main._solo_record_spell_mod(victim, "Quicken",
		{"modifier": {"advance_in": 4, "rush_in": 4}, "duration": "round"})

	assert_int(int(victim.unit_properties.get("spot_markers", 0))) \
		.override_failure_message("solo counting changed with the MP fix") \
		.is_equal(1)
	assert_dict(victim.unit_properties.get("spell_move_mod", {})).is_equal({"advance": 4, "rush": 4})
	assert_array(_fake.sent) \
		.override_failure_message("an offline game broadcast hidden state") \
		.is_empty()


## The receive side, on the REAL NetworkManager handler: the arguments main put on the wire
## reconstruct the number on a peer that never saw the roll.
func test_the_delta_reconstructs_the_number_on_the_receiving_peer(timeout := 120000) -> void:
	var spotter := _reg(2, "Scout Team", [_at(0.0)])
	var victim := _reg(1, "Riflemen", [_at(10.0), _at(11.0)])
	for _i in 3:
		_main._solo_place_spot_marker(spotter, victim)
	_main._solo_consume_spot_markers(victim, 1)
	var wire: Array = _sent("spot_markers")
	assert_int(wire.size()) \
		.override_failure_message("fixture check: four transitions, four deltas (sent: %s)" % str(_fake.sent)) \
		.is_equal(4)

	# Play the peer: wipe the local number, then apply exactly what the wire carried.
	victim.unit_properties.erase("spot_markers")
	for e in wire:
		var d := e as Dictionary
		_real_net.sync_unit_property(str(d["unit"]), str(d["key"]), d["value"])

	assert_int(int(victim.unit_properties.get("spot_markers", 0))) \
		.override_failure_message("replaying the wire did not reproduce the count") \
		.is_equal(2)

	# …and the erasure arrives as an erasure, not as a zero left lying in the bag.
	_real_net.sync_unit_property(victim.unit_id, "spot_markers", null)
	assert_bool(victim.unit_properties.has("spot_markers")).is_false()


## The allow-list is a security boundary, not a formality: unit_properties also carries ownership,
## the army list entry and the model spec. A frame naming any other key is dropped.
func test_the_receiver_refuses_an_unlisted_key(timeout := 120000) -> void:
	var victim := _reg(1, "Riflemen", [_at(10.0), _at(11.0)])
	assert_int(int(victim.unit_properties.get("player_id", 0))).is_equal(1)

	_real_net.sync_unit_property(victim.unit_id, "player_id", 2)
	assert_int(int(victim.unit_properties.get("player_id", 0))) \
		.override_failure_message("a peer rewrote unit OWNERSHIP through the hidden-state channel") \
		.is_equal(1)

	_real_net.sync_unit_property(victim.unit_id, "special_rules", ["Fearless"])
	assert_array(victim.unit_properties.get("special_rules", [])) \
		.override_failure_message("a peer wrote special rules through the hidden-state channel") \
		.is_empty()

	# CONTROL: the same handler, one listed key away, does apply — the refusals above are about the
	# allow-list and not about a handler that is broken for everything.
	_real_net.sync_unit_property(victim.unit_id, "spot_markers", 3)
	assert_int(int(victim.unit_properties.get("spot_markers", 0))).is_equal(3)
