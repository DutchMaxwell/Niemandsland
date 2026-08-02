extends GdUnitTestSuite
## E2E — NML-929: the Utility-Buff giver family works in multiplayer.
##
## THE STARTING POINT. Wave 4 opened the whole buff-GIVER family (Precision Shooter Buff, Furious
## Buff, Entrenched Buff, No Retreat Buff, …) to human players — but with an explicit guard: in a
## live multiplayer game _solo_apply_utility_buffs bailed out. The reason was honest. The effect
## lands as an F4 once-mod RECORD (the same machinery spell tokens use), and those records did not
## ride the wire, so applying one would have put a modifier on ONE client's dice and not the other's.
## A silently one-sided modifier is worse than a rule that does nothing.
##
## Whose dice actually read a record decides this: the buffed unit's own attacks are rolled by its
## owner, but a defense record and an attackers-beneficiary record are read by the OPPONENT rolling
## into that unit — and the granted-rule overlay (grants_rule → special_rules) is read by every rule
## check on both sides.
##
## THE FIX UNDER TEST. The record list travels: main._broadcast_spell_mods pushes a unit's FULL list
## through NetworkManager.broadcast_spell_mods on every record, every consumption and every expiry —
## the same command channel NML-927's hidden-state deltas use, one more handler name in the existing
## envelope. With that in place the guard is gone.
##
## Full replace rather than add/remove deltas: the lists are tiny, one exchange can spend several
## records at once, and a replace is idempotent — a duplicated frame cannot leave the two tables
## holding different modifiers.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254


## Stands in for NetworkManager at main's seam: a live session that records every outbound frame.
## Both senders are here because the buff path produces both — the record list (this wave) and the
## hidden-state stamps (NML-927), and the suite has to be able to tell them apart.
class FakeNet extends Node:
	var active: bool = true
	var sent: Array = []
	func is_multiplayer_active() -> bool:
		return active
	func slot_has_human_peer(_slot: int) -> bool:
		return false
	func broadcast_unit_property(gu: GameUnit, key: String, value: Variant) -> void:
		sent.append({"kind": "property", "unit": gu.unit_id, "key": key, "value": value})
	func broadcast_spell_mods(gu: GameUnit, records: Array) -> void:
		sent.append({"kind": "mods", "unit": gu.unit_id, "records": records})

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
	# Slot 2 is NACHTMAHR's, slot 1 is the human's — the configuration the guard was written for:
	# a live session that ALSO has an AI army (co-op / an AI-held slot in a room).
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	_main._solo_batch = true
	_fake = auto_free(FakeNet.new())
	_main.network_manager = _fake


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null
	_fake = null


func _at(inches_x: float) -> Vector3:
	return Vector3(inches_x * INCH, 0.0, 0.0)


## A three-model line: the buff's value proxy picks the BIGGEST unit, so a receiver has to out-value
## the one-model Hero that is buffing (a hero may legally buff itself).
func _line(inches_x: float) -> Array:
	return [_at(inches_x), _at(inches_x + 1.2), _at(inches_x + 2.4)]


## Register a fixture unit and stamp the book that actually FIELDS these rules — the registry gate
## is system-scoped, so an unstamped unit resolves no primitive at all.
func _reg(pid: int, unit_name: String, positions: Array, rules: Array) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, positions)
	u.unit_properties["game_system"] = "gf"
	u.unit_properties["faction_folder"] = "human_defense_force"
	u.unit_properties["special_rules"] = rules
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func _mods_on(u: GameUnit) -> Array:
	return _main._solo_spell_mods.get(u.get_instance_id(), [])


## Outbound record-list frames only (the NML-927 stamp deltas share the recorder).
func _mod_frames(u: GameUnit = null) -> Array:
	var out: Array = []
	for e in _fake.sent:
		var d := e as Dictionary
		if str(d["kind"]) != "mods":
			continue
		if u != null and str(d["unit"]) != u.unit_id:
			continue
		out.append(d)
	return out


## Read defensively: with no frame at all every assertion must still FAIL cleanly rather than break
## the -d run into the debugger (which takes the whole headless process down).
func _last_records(u: GameUnit) -> Array:
	var frames := _mod_frames(u)
	return (frames[frames.size() - 1] as Dictionary).get("records", []) if not frames.is_empty() else []


## A human Hero with a shooting buff and a friend worth buffing.
func _human_giver_and_friend() -> Array:
	var giver := _reg(1, "Field Commander", [_at(0.0)], ["Hero", "Precision Shooter Buff"])
	var friend := _reg(1, "Riflemen", _line(6.0), [])
	return [giver, friend]


# === 1. The guard is gone ========================================================================

## THE CLAIM: a human player's buff giver now resolves in a LIVE multiplayer session. Before this
## wave the resolver returned at the door and the rule was dead data on the network.
func test_a_human_buff_lands_in_a_live_multiplayer_game(timeout := 120000) -> void:
	var gf := _human_giver_and_friend()
	assert_bool(_fake.is_multiplayer_active()) \
		.override_failure_message("fixture check: this test is only meaningful in a live session") \
		.is_true()

	_main._solo_apply_utility_buffs(gf[0])

	assert_int(_mods_on(gf[1]).size()) \
		.override_failure_message("the human's buff giver still does nothing in multiplayer") \
		.is_equal(1)
	var rec: Dictionary = (_mods_on(gf[1])[0] as Dictionary) if not _mods_on(gf[1]).is_empty() else {}
	assert_int(int(rec.get("hit_mod", 0))).is_equal(1)


# === 2. Setting the record =======================================================================

## …and the record it produced is on the wire, so the opponent's client holds the same modifier.
func test_the_record_rides_the_wire(timeout := 120000) -> void:
	var gf := _human_giver_and_friend()

	_main._solo_apply_utility_buffs(gf[0])

	var frames := _mod_frames(gf[1])
	assert_int(frames.size()) \
		.override_failure_message("the buff record never left this client — one client's dice carry a modifier the other's do not (sent: %s)" % str(_fake.sent)) \
		.is_greater_equal(1)
	var records := _last_records(gf[1])
	assert_int(records.size()) \
		.override_failure_message("the frame carried no record at all") \
		.is_equal(1)
	var wire: Dictionary = (records[0] as Dictionary) if not records.is_empty() else {}
	assert_int(int(wire.get("hit_mod", 0))).is_equal(1)
	assert_str(str(wire.get("duration", ""))).is_equal("once")
	assert_str(str(wire.get("scope", ""))) \
		.override_failure_message("the scope has to travel — a shooting-only buff that arrives scopeless applies in melee on the peer") \
		.is_equal("shooting")


## granted_to holds LOCAL instance ids. Sending them would be meaningless at best and would make the
## receiver revoke a grant off the wrong objects at worst — the receiver recomputes its own.
func test_the_local_grant_bookkeeping_never_leaves_this_client(timeout := 120000) -> void:
	# Entrenched Buff GRANTS a rule (the fixture's book fields it); Precision Shooter Buff only
	# carries a hit modifier, so it would never populate granted_to at all.
	var giver := _reg(1, "Field Commander", [_at(0.0)], ["Hero", "Entrenched Buff"])
	var friend := _reg(1, "Riflemen", _line(6.0), [])

	_main._solo_apply_utility_buffs(giver)

	var records := _last_records(friend)
	assert_int(records.size()) \
		.override_failure_message("fixture check: a grant-style buff must produce a record (sent: %s)" % str(_fake.sent)) \
		.is_equal(1)
	var wire: Dictionary = (records[0] as Dictionary) if not records.is_empty() else {}
	assert_bool(wire.has("granted_to")) \
		.override_failure_message("local instance ids went on the wire") \
		.is_false()
	# CONTROL: the record we KEPT does carry them, so the assertion above is about the wire copy and
	# not about a grant that never happened.
	var kept: Dictionary = (_mods_on(friend)[0] as Dictionary) if not _mods_on(friend).is_empty() else {}
	assert_bool(kept.has("granted_to")).is_true()


# === 3. Consuming the record =====================================================================

## The other half of the deal: a "once" modifier is SPENT by the exchange it applies to. If only the
## setting travelled, the peer would keep applying a buff this client has already used up.
func test_the_consumption_rides_the_wire(timeout := 120000) -> void:
	var gf := _human_giver_and_friend()
	var enemy := _reg(2, "Raiders", [_at(20.0)], [])
	_main._solo_apply_utility_buffs(gf[0])
	assert_int(_mods_on(gf[1]).size()) \
		.override_failure_message("fixture check: there must be a record to spend") \
		.is_equal(1)
	_fake.sent.clear()

	_main._solo_consume_once_mods(gf[1], enemy, false)

	assert_int(_mods_on(gf[1]).size()) \
		.override_failure_message("fixture check: the exchange must actually spend the once-mod") \
		.is_equal(0)
	assert_int(_mod_frames(gf[1]).size()) \
		.override_failure_message("the consumption never left this client — the peer keeps applying a spent buff (sent: %s)" % str(_fake.sent)) \
		.is_greater_equal(1)
	assert_array(_last_records(gf[1])) \
		.override_failure_message("the frame must hand over an EMPTY list — that is what clears the peer") \
		.is_empty()


# === 4. The receiving side =======================================================================

## The peer's half, driven through the real handler: the frame reconstructs the modifier the dice
## read, and the granted rule lands on the live special_rules overlay.
func test_a_received_frame_reconstructs_the_record_and_the_grant(timeout := 120000) -> void:
	var giver := _reg(1, "Field Commander", [_at(0.0)], ["Hero", "Entrenched Buff"])
	var friend := _reg(1, "Riflemen", _line(6.0), [])
	_main._solo_apply_utility_buffs(giver)
	var wire := _last_records(friend)
	assert_int(wire.size()) \
		.override_failure_message("fixture check: nothing on the wire to replay (sent: %s)" % str(_fake.sent)) \
		.is_equal(1)
	var granted := str((wire[0] as Dictionary).get("grants_rule", "")) if not wire.is_empty() else ""
	assert_str(granted) \
		.override_failure_message("fixture check: this buff has to GRANT a rule for the overlay half to mean anything") \
		.is_not_empty()

	# Play the peer: wipe everything this client knows, then apply exactly what the wire carried.
	_main._solo_spell_mods.erase(friend.get_instance_id())
	friend.unit_properties["special_rules"] = []
	_main._on_remote_spell_mods_updated(friend, wire)

	assert_int(_mods_on(friend).size()) \
		.override_failure_message("replaying the wire did not install the record") \
		.is_equal(1)
	var adopted: Dictionary = (_mods_on(friend)[0] as Dictionary) if not _mods_on(friend).is_empty() else {}
	assert_str(str(adopted.get("grants_rule", ""))).is_equal(granted)
	var rules: Array = friend.unit_properties.get("special_rules", [])
	var has_overlay := false
	for r in rules:
		if str(r).begins_with(granted):
			has_overlay = true
	assert_bool(has_overlay) \
		.override_failure_message("the granted rule did not reach the peer's special_rules overlay (rules: %s)" % str(rules)) \
		.is_true()


## Adopting a peer's frame must not send anything back. The adoption runs the ordinary local writers
## (grant overlay, props stamps), and those broadcast — unguarded the frame bounces at its sender.
func test_adopting_a_frame_does_not_echo_it_back(timeout := 120000) -> void:
	var target := _reg(1, "Riflemen", _line(6.0), [])
	var wire: Array = [{
		"spell": "Quicken", "hit_mod": 0, "def_mod": 0, "casting_mod": 0, "morale_mod": 0,
		"range_in": 6, "advance_in": 4, "rush_in": 4, "grants_rule": "Fast",
		"scope": "", "beneficiary": "", "duration": "round",
	}]

	_main._on_remote_spell_mods_updated(target, wire)

	# The adoption really did do work — the stamps are there…
	assert_dict(target.unit_properties.get("spell_move_mod", {})).is_equal({"advance": 4, "rush": 4})
	assert_int(int(target.unit_properties.get("spell_range_mod", 0))).is_equal(6)
	# …and none of it went back out.
	assert_array(_fake.sent) \
		.override_failure_message("adopted state was echoed back at its sender") \
		.is_empty()


## The payload is untrusted wire data. Each record is rebuilt field by field, so a peer cannot
## smuggle extra keys into the record dictionaries, and junk entries are dropped.
func test_a_received_frame_is_normalised(timeout := 120000) -> void:
	var target := _reg(1, "Riflemen", _line(6.0), [])
	var wire: Array = [
		"not a record",
		{"spell": "Blessing", "hit_mod": 1, "duration": "once", "trespass": "arbitrary payload"},
	]

	_main._on_remote_spell_mods_updated(target, wire)

	assert_int(_mods_on(target).size()) \
		.override_failure_message("the junk entry was installed as a record") \
		.is_equal(1)
	var rec: Dictionary = (_mods_on(target)[0] as Dictionary) if not _mods_on(target).is_empty() else {}
	assert_bool(rec.has("trespass")) \
		.override_failure_message("an arbitrary key from the wire landed inside a record the rules read") \
		.is_false()
	# The known fields survive, defaults fill the rest.
	assert_int(int(rec.get("hit_mod", 0))).is_equal(1)
	assert_str(str(rec.get("spell", ""))).is_equal("Blessing")
	assert_int(int(rec.get("def_mod", -1))).is_equal(0)
	# …and the normalised record is LIVE: the peer's own to-hit seam reads it.
	assert_int(int(_main._solo_spell_hit_mod(target, false).get("mod", 0))) \
		.override_failure_message("the adopted record is inert — the peer's dice do not read it") \
		.is_equal(1)


# === 5. Counter-proofs ===========================================================================

## Offline nothing is sent, and the buff still lands exactly as it did before this wave.
func test_solo_without_peers_sends_nothing_and_still_buffs(timeout := 120000) -> void:
	_fake.active = false
	var gf := _human_giver_and_friend()

	_main._solo_apply_utility_buffs(gf[0])

	assert_int(_mods_on(gf[1]).size()) \
		.override_failure_message("the solo behaviour changed with the MP wiring") \
		.is_equal(1)
	assert_array(_fake.sent) \
		.override_failure_message("an offline game broadcast buff records") \
		.is_empty()


## The once-per-activation stamp still binds in multiplayer: two doors (declaring an attack, ending
## an activation that never attacked) must not buy the buff twice — and must not send twice either.
func test_the_once_per_activation_stamp_still_binds(timeout := 120000) -> void:
	var gf := _human_giver_and_friend()

	_main._solo_apply_utility_buffs(gf[0])
	_fake.sent.clear()
	_main._solo_apply_utility_buffs(gf[0])

	assert_int(_mods_on(gf[1]).size()) \
		.override_failure_message("\"once per activation\" — two doors, one application") \
		.is_equal(1)
	assert_array(_mod_frames()) \
		.override_failure_message("the second door put a duplicate record on the wire") \
		.is_empty()

	# ROT: a new round re-opens it, and that one does travel.
	_main.opr_army_manager.current_round = 2
	_main._solo_apply_utility_buffs(gf[0])
	assert_int(_mods_on(gf[1]).size()).is_equal(2)
	assert_int(_mod_frames(gf[1]).size()).is_greater_equal(1)


## NACHTMAHR's own side is untouched by the guard removal — it never had one — and its records now
## travel through the same channel.
func test_the_ai_side_still_buffs_and_now_also_sends(timeout := 120000) -> void:
	var giver := _reg(2, "Field Commander", [_at(0.0)], ["Hero", "Precision Shooter Buff"])
	var friend := _reg(2, "Riflemen", _line(6.0), [])

	_main._solo_apply_utility_buffs(giver)

	assert_int(_mods_on(friend).size()) \
		.override_failure_message("the AI's buff giver stopped working") \
		.is_equal(1)
	assert_int(_mod_frames(friend).size()) \
		.override_failure_message("the AI's record stayed local (sent: %s)" % str(_fake.sent)) \
		.is_greater_equal(1)
