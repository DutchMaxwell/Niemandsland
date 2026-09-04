extends GdUnitTestSuite
## E2E — audit row 17: round-duration spell tokens expire at round end in MULTIPLAYER too.
##
## `_solo_expire_spell_tokens` is fully wired for the wire (it broadcasts the emptied record list
## via `_broadcast_spell_mods` and clears the mechanical stamps via `_sync_unit_property`) — but it
## is called from `_on_solo_round_advanced` BEHIND the `solo_ai_slots.is_empty()` gate, so in a
## plain human-vs-human room (no AI slot anywhere) the early return never reaches it: the placed
## token sits on the table and the peer keeps the modifier forever.
##
## THE FIX UNDER TEST: the expiry call moves ABOVE the gate. In a real solo game `solo_ai_slots`
## is never empty (that dict is what makes it "solo"), so the gate never blocked expiry there and
## the move changes nothing observable for solo — it only unblocks multiplayer.
##
## The seam driven here is the audited one: `_on_solo_round_advanced` is connected UNCONDITIONALLY
## to `opr_army_manager.round_advanced` (main.gd:12061), and `NetworkManager.sync_round_advance()`
## also calls `army_manager.advance_round()` on the receiving peer — so this one handler is the
## round boundary on BOTH clients. The sibling fatigue-clear PR (row 36) shares the same function;
## this suite deliberately leaves the fatigue path alone.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")


## Stands in for NetworkManager at main's seam: a live session that records every outbound frame.
## Same recorder shape as e2e_mp_utility_buffs_test.gd — the expiry produces both frame kinds
## (the record-list full replace and the mechanical stamp cleanup).
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
	# PLAIN MP room: `solo_ai_slots` stays EMPTY — exactly the configuration the gate blocks
	# today (the utility-buffs suite uses {2: true} for co-op; that is NOT this room).
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


## A human-side unit carrying a round-scoped spell token, placed through the REAL production
## entry point (same call shape as e2e_rule_state_reload_test.gd / e2e_cast_split_ux_test.gd).
func _seed_round_token(u_name: String) -> GameUnit:
	var tgt := E2EBoot.make_unit(_main, 1, u_name, [Vector3.ZERO])
	_main.opr_army_manager.game_units[tgt.unit_id] = tgt
	_main._solo_place_spell_tokens("Round Buff", [tgt],
		{"grants_rule": "Poison", "once": false, "duration": "round",
		"modifier": {"def_mod": 1, "advance_in": 4, "rush_in": 4}})
	return tgt


func _tokens_for(u: GameUnit) -> Array:
	var out: Array = []
	for e in _main._solo_spell_tokens_active:
		var tu: GameUnit = (e as Dictionary).get("unit")
		if tu == u:
			out.append(e)
	return out


func _records_for(u: GameUnit) -> Array:
	return _main._solo_spell_mods.get(u.get_instance_id(), [])


## Outbound record-list frames only (the stamp cleanup shares the recorder).
func _mod_frames(u: GameUnit) -> Array:
	var out: Array = []
	for e in _fake.sent:
		var d := e as Dictionary
		if str(d["kind"]) == "mods" and str(d["unit"]) == u.unit_id:
			out.append(d)
	return out


# === 1. THE GATE ================================================================================

## THE CLAIM: the audited seam fires the round boundary in a plain MP room, and the expiry —
## token off the table, record list emptied and REPLACED on the wire, mechanical stamps cleared —
## runs on this client instead of dying behind the solo gate.
func test_a_round_token_expires_at_the_round_boundary_in_a_plain_mp_room(timeout := 120000) -> void:
	var tgt := _seed_round_token("Blessed")
	# Fixture checks: the token really is on the table, the record really is in the store —
	# a failure below must not be a seeding artefact.
	assert_int(_tokens_for(tgt).size()) \
		.override_failure_message("fixture check: the round-duration token was never placed") \
		.is_equal(1)
	assert_int(_records_for(tgt).size()) \
		.override_failure_message("fixture check: the mechanical record was never registered") \
		.is_equal(1)
	assert_bool((tgt.unit_properties.get("special_rules", []) as Array).has("Poison (spell)")) \
		.override_failure_message("fixture check: the grant never landed on the unit") \
		.is_true()
	_fake.sent.clear()   # the placement itself already travelled; only the expiry is under test

	# The audited seam: `round_advanced` fires this on BOTH peers (locally on advance, and on the
	# other peer through NetworkManager.sync_round_advance -> army_manager.advance_round()).
	_main._on_solo_round_advanced(2)

	assert_array(_tokens_for(tgt)) \
		.override_failure_message("the round-scoped token survived the round boundary in a plain MP room — the expiry is still gated behind solo_ai_slots") \
		.is_empty()
	assert_array(_records_for(tgt)) \
		.override_failure_message("the modifier record survived the round boundary in a plain MP room") \
		.is_empty()
	assert_bool((tgt.unit_properties.get("special_rules", []) as Array).has("Poison (spell)")) \
		.override_failure_message("the granted rule stayed on the unit after the round boundary in a plain MP room") \
		.is_false()
	# …and the emptied list went on the wire, so the peer drops its copy of the modifier too.
	var frames := _mod_frames(tgt)
	assert_int(frames.size()) \
		.override_failure_message("the expiry never left this client — the peer holds a modifier for a round that has ended (sent: %s)" % str(_fake.sent)) \
		.is_greater_equal(1)
	var wire: Array = (frames[frames.size() - 1] as Dictionary).get("records", []) if not frames.is_empty() else []
	assert_array(wire) \
		.override_failure_message("the frame must hand over an EMPTY list — that is what clears the peer") \
		.is_empty()
	# The mechanical stamp cleanup travelled as well (NML-927's property channel).
	var stamp_synced := false
	for e in _fake.sent:
		var d := e as Dictionary
		if str(d["kind"]) == "property" and str(d["unit"]) == tgt.unit_id and str(d["key"]) == "spell_move_mod":
			stamp_synced = true
	assert_bool(stamp_synced) \
		.override_failure_message("the speed stamp was erased locally but never synced — the peer keeps the movement modifier (sent: %s)" % str(_fake.sent)) \
		.is_true()


# === 2. THE SOLO PATH IS UNTOUCHED ==============================================================

## CONTROL: in a real solo game `solo_ai_slots` is never empty, so the gate never blocked expiry
## there — moving the call above it must keep the solo behaviour exactly as it was.
func test_the_solo_path_still_expires_the_token(timeout := 120000) -> void:
	_main.solo_ai_slots = {2: true}   # co-op: an AI-held slot = the solo configuration
	var tgt := _seed_round_token("Blessed")
	assert_int(_tokens_for(tgt).size()) \
		.override_failure_message("fixture check: the round-duration token was never placed") \
		.is_equal(1)
	_fake.sent.clear()

	_main._on_solo_round_advanced(2)

	assert_array(_tokens_for(tgt)) \
		.override_failure_message("the solo path lost its round-end token expiry with the gate move") \
		.is_empty()
	assert_array(_records_for(tgt)) \
		.override_failure_message("the solo path lost its round-end record expiry with the gate move") \
		.is_empty()