extends GdUnitTestSuite
## E2E — NML-949/950: rule state that outlives the objects that compute it, proven on the REAL
## scenes/main.tscn. Five once-per-game / per-round values live only in RAM today — a save/load
## (or, for the AI-slot-gated pair, an MP rejoin) hands them back at their class defaults. THE
## CORE PROOF the maintainer asked for by name is B4: a round-duration spell buff granted, then
## reloaded, then round-ended — the mechanical record and the visible token must BOTH die with
## the round, and today neither does (for opposite reasons).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _log_text() -> String:
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


## A real reload. The units go out through GameUnit.to_dict, through JSON (a save is a JSON file,
## and JSON has no integer dictionary keys) and back in through GameUnit.from_dict; the match state
## goes through save_manager's own serializer/deserializer; then the real post-load hooks run.
##
## The one thing a test cannot do cheaply is build a SECOND Main, so the wipe below models one: after
## the wire image is taken, every piece of rule bookkeeping that lives on this node is put back to the
## value a freshly constructed Main would have. Without that the test proves nothing at all — the same
## Main instance simply keeps its variables across the "reload" and every assertion passes for free.
## The defaults here are quoted from their declarations in scripts/main.gd, so if one of them ever
## changes, this helper is wrong in an obvious way rather than a silent one.
func _wipe_to_fresh_process() -> void:
	_main._solo_ai_took_last_activation = true   # main.gd:297 — round 1 opens with the human
	_main._solo_pending_replies = 0              # main.gd:293
	_main._solo_replied_ids.clear()              # main.gd:294
	_main._solo_rapid_round_one_done = false     # main.gd:1067
	_main._solo_spell_mods.clear()               # main.gd:321
	_main._solo_spell_tokens_active.clear()      # main.gd:320


func _reload(units: Array) -> Array:
	var sm = _main.save_manager
	var wire_state: Dictionary = JSON.parse_string(JSON.stringify(sm._serialize_game_state()))
	var wire_units: Array = []
	for u in units:
		wire_units.append(JSON.parse_string(JSON.stringify((u as GameUnit).to_dict())))
	_wipe_to_fresh_process()
	var out: Array = []
	for w in wire_units:
		var nu := GameUnit.from_dict(w)
		_main.opr_army_manager.game_units[nu.unit_id] = nu
		out.append(nu)
	sm._deserialize_game_state(wire_state)
	sm._restore_hero_attachments_after_load()
	_main._on_load_completed(0)
	return out


# === B1 — the round opener [state 3] ============================================================

func test_the_round_opener_survives_a_reload(timeout := 120000) -> void:
	_main._solo_ai_took_last_activation = false   # the human took the last activation
	_reload([])
	assert_bool(_main._solo_ai_took_last_activation) \
		.override_failure_message("who opens the next round is an official rule (the side that did NOT take the last activation). A reload drops it to the class default true and hands the opening to the wrong side — save just before the round ends and you pick your opener.") \
		.is_false()


# === B2 — the alternation debt [state 5] ========================================================
#
# Course correction (peer review, NML-949): driving the full `_on_solo_human_activated` ->
# `_solo_pump` -> reload -> fresh-controller chain risks a hang/side-effect cascade for no extra
# proof. The defect is provable directly and unambiguously: `_solo_replied_ids` is written keyed
# by `gu.get_instance_id()` (main.gd:1329) — an id `GameUnit.from_dict()` can never reproduce, so
# a reload can never find the mark again by anything that only knows the unit_id (the one thing
# that DOES survive a reload). Proving the key is wrong is proving the persistence is impossible.
func test_the_alternation_debt_survives_a_reload(timeout := 120000) -> void:
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	_main._solo_batch = true   # no dialogs, no per-unit frame yield in a headless run

	var u1 := E2EBoot.make_unit(_main, 1, "Wachtturm", [Vector3(-0.2, 0, 0.2)])
	var u2 := E2EBoot.make_unit(_main, 1, "Reserve", [Vector3(-0.2, 0, 0.3)])
	_main.opr_army_manager.game_units[u1.unit_id] = u1
	_main.opr_army_manager.game_units[u2.unit_id] = u2

	# Drive the REAL production write (main.gd:1326-1329) rather than poking the dict directly.
	u1.activate(_main.opr_army_manager.current_round)
	await _main._on_solo_human_activated(u1)

	assert_bool(_main._solo_replied_ids.has(u1.unit_id)) \
		.override_failure_message("the AI's owed-reply bookkeeping is keyed by instance id, which means nothing after a reload — the same unit can earn a second answer, or lose the one it earned.") \
		.is_true()
	await E2EBoot.settle(get_tree())


## The second half of the alternation debt: the COUNT of answers the AI still owes. A reload that
## drops it to zero lets the human play out the rest of the round with no reply at all (it heals at
## the round boundary, which is why this is the mildest of the five — but it is still a rule).
func test_the_owed_reply_count_survives_a_reload(timeout := 120000) -> void:
	var u1 := E2EBoot.make_unit(_main, 1, "Wachtturm", [Vector3(-0.2, 0, 0.2)])
	_main.opr_army_manager.game_units[u1.unit_id] = u1
	_main._solo_pending_replies = 2
	_main._solo_replied_ids[u1.unit_id] = true

	var back: Array = _reload([u1])

	assert_int(_main._solo_pending_replies) \
		.override_failure_message("the alternation debt is zeroed by a reload — the human activates the rest of this round with no answer from the AI.") \
		.is_equal(2)
	assert_bool(_main._solo_replied_ids.has((back[0] as GameUnit).unit_id)) \
		.override_failure_message("the per-unit 'already answered this round' mark did not survive the reload, so the AI owes this unit a second answer it has already given.") \
		.is_true()


# === B3 — round-1 Rapid Ambush beat [precautionary] =============================================

func test_rapid_ambush_round_one_stays_done_after_a_reload(timeout := 120000) -> void:
	_main._solo_rapid_round_one_done = true
	_reload([])
	assert_bool(_main._solo_rapid_round_one_done) \
		.override_failure_message("the round-1 Rapid Ambush beat is once per game; today only a foreign game_phase gate hides the reset (NML-950).") \
		.is_true()


# === B4 — a round-duration spell token still expires after a reload [state 1] ** CORE PROOF ** =
#
# Course correction (peer review, NML-949): built on the REAL production entry point
# `_main._solo_place_spell_tokens(spell_name, targets, effect)` (main.gd:3234) instead of hand-
# assembling the token-library-define + apply_library_token + _solo_record_spell_mod sequence —
# see test/e2e/e2e_cast_split_ux_test.gd:41-62, the closest sibling, for the same call shape.
func test_a_spell_token_still_expires_after_a_reload(timeout := 120000) -> void:
	var tgt := E2EBoot.make_unit(_main, 1, "Blessed", [Vector3.ZERO])
	_main.opr_army_manager.game_units[tgt.unit_id] = tgt

	_main._solo_place_spell_tokens("Round Buff", [tgt],
		{"grants_rule": "Poison", "once": false, "duration": "round", "modifier": {"def_mod": 1}})

	# Sanity BEFORE the reload, via the battle log (easier red to read than a bare dictionary diff).
	var pre := _log_text()
	assert_str(pre) \
		.override_failure_message("fixture: the round-duration token was never placed:\n%s" % pre) \
		.contains("\"Round Buff\" token placed on Blessed (expires at the end of the round)")
	assert_bool((tgt.unit_properties.get("special_rules", []) as Array).has("Poison (spell)")) \
		.override_failure_message("fixture: the grant never landed on the unit before the reload") \
		.is_true()
	assert_bool((tgt.models[0] as ModelInstance).markers.has("Round Buff")) \
		.override_failure_message("fixture: the token marker never landed on model 0 before the reload") \
		.is_true()

	var back: Array = _reload([tgt])
	var t2 := back[0] as GameUnit

	# Round end.
	_main._solo_expire_spell_tokens()

	assert_bool((t2.unit_properties.get("special_rules", []) as Array).has("Poison (spell)")) \
		.override_failure_message("a round-duration spell must end with the round. After a reload the expiry loop has an empty work set, so the grant is never revoked.") \
		.is_false()
	assert_bool((t2.models[0] as ModelInstance).markers.has("Round Buff")) \
		.override_failure_message("the spell token survives the save (it lives on the model) but the bookkeeping that removes it does not — after a reload the token sits on the table forever, decoration for an effect that no longer exists.") \
		.is_false()


# === B5 — an apply-once spell is not silently scrubbed by a save [state 1, second half] ========

func test_an_apply_once_spell_is_not_silently_scrubbed_by_a_save(timeout := 120000) -> void:
	var tgt := E2EBoot.make_unit(_main, 1, "Blessed", [Vector3.ZERO])
	_main.opr_army_manager.game_units[tgt.unit_id] = tgt

	_main._solo_place_spell_tokens("Once Buff", [tgt],
		{"grants_rule": "Shred", "once": true, "duration": "once", "modifier": {"advance_in": 2, "rush_in": 4}})

	var pre := _log_text()
	assert_str(pre) \
		.override_failure_message("fixture: the apply-once token was never placed:\n%s" % pre) \
		.contains("\"Once Buff\" token placed on Blessed (persists until it applies)")
	assert_bool((tgt.unit_properties.get("special_rules", []) as Array).has("Shred (spell)")) \
		.override_failure_message("fixture: the grant never landed on the unit before the reload") \
		.is_true()
	assert_bool(tgt.unit_properties.has("spell_move_mod")) \
		.override_failure_message("fixture: the speed stamp never landed on the unit before the reload") \
		.is_true()

	var back: Array = _reload([tgt])
	var t2 := back[0] as GameUnit
	_main._solo_expire_spell_tokens()   # a round boundary must NOT consume an apply-once spell

	assert_bool((t2.unit_properties.get("special_rules", []) as Array).has("Shred (spell)")) \
		.override_failure_message("an apply-once spell persists until it applies (maintainer rules check 31.07.). The save path scrubbed it instead — the player's buff vanished in silence.") \
		.is_true()
	assert_bool(t2.unit_properties.has("spell_move_mod")) \
		.override_failure_message("an apply-once spell persists until it applies (maintainer rules check 31.07.). The save path scrubbed it instead — the player's buff vanished in silence.") \
		.is_true()


# === B6 — a record that arrived over the WIRE persists too [state 1, third half] ================
#
# The merge with main brings a FOURTH writer of `_solo_spell_mods` that neither branch had on its
# own: `_on_remote_spell_mods_updated` (main.gd:4802), the NML-929 receiver. It was written before
# the durable mirror existed, so it fills the in-memory store and stops there. On the peer that
# ADOPTED the records, a save therefore carries the granted rule but not the bookkeeping that takes
# it off again — B4's defect exactly, reached through multiplayer instead of through a local cast.
func test_a_wire_adopted_spell_record_still_expires_after_a_reload(timeout := 120000) -> void:
	var tgt := E2EBoot.make_unit(_main, 1, "Blessed", [Vector3.ZERO])
	_main.opr_army_manager.game_units[tgt.unit_id] = tgt

	# The REAL receive path, in the wire shape the sender produces (_broadcast_spell_mods strips
	# `granted_to` — it holds instance ids, which mean nothing on the receiving machine).
	_main._on_remote_spell_mods_updated(tgt, [{
		"spell": "Wire Buff", "grants_rule": "Poison", "duration": "round", "def_mod": 1}])

	assert_bool((tgt.unit_properties.get("special_rules", []) as Array).has("Poison (spell)")) \
		.override_failure_message("fixture: the adopted wire record never granted its rule, so this test would pass for the wrong reason") \
		.is_true()

	var back: Array = _reload([tgt])
	_main._solo_expire_spell_tokens()   # round end

	assert_bool(((back[0] as GameUnit).unit_properties.get("special_rules", []) as Array).has("Poison (spell)")) \
		.override_failure_message("a record that arrived over the wire is kept in RAM only: the peer that adopted it saves the granted rule but not the bookkeeping that removes it, so after a reload the buff never ends.") \
		.is_false()
