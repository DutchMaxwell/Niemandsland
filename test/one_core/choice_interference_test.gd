extends GdUnitTestSuite
## CC-14a: a foe's interference against an AI cast as a core choice (`interference:<seq>:<caster>:<slot>`) - the switch, the probes,
## the owner routing and the token landing. The REAL core resolves one cast-only activation (Infuse Bloodthirst: a debuff, so no save of the foe's remote owner is ever asked) of an AI caster;
## a human foe seat holds the pool (one Caster with 2 tokens). The foe's owner is a peer this test plays (a recording NetworkManager):
## it is asked over the owner-request path, its first answer applies once, a silent or absent owner is "no interference" with the
## table's own line. The switch `NML_ONE_CORE_CHOICE_INTERFERENCE` starts OFF: an open cast is then refused by the probe BEFORE any
## die and stays on the table (CC-13a's refused branch). CC-14b: the owner's answer is the table's own `InterferenceDialog` in collect
## mode (it asks, the driver spends), on the host's machine for a local human and on the owner's machine for a remote one.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")
const Harness := preload("res://test/one_core/golden_witness_harness.gd")
const GUEST_PEER := 42
const MYSTIC := {"key": "my", "player": 2, "name": "Mystic", "models": 1, "quality": 4, "defense": 4, "tough": 1,
	"x_in": 0.0, "z_step_in": 1.2, "base_radius_in": 0.63, "game_system": "gf", "faction_folder": "alien_hives", "rules": ["Caster"]}
const HELPER := {"key": "hp", "player": 1, "name": "Helper", "models": 1, "quality": 4, "defense": 4, "tough": 1,
	"x_in": -4.0, "z_step_in": 1.2, "base_radius_in": 0.63, "game_system": "gf", "faction_folder": "alien_hives", "rules": ["Caster"]}
const FOE := {"key": "foe", "player": 1, "name": "Foe", "models": 6, "quality": 4, "defense": 4, "tough": 1,
	"x_in": 8.0, "z_step_in": 1.3, "base_radius_in": 0.63, "game_system": "gf", "faction_folder": "alien_hives", "rules": []}
const STAFF := {"name": "Staff", "range_in": 0, "attacks": 1, "count": 1, "rules": []}
const BLOODTHIRST := {"name": "Infuse Bloodthirst", "threshold": 1, "range_in": 12,
	"target": {"side": "enemy", "count": 3, "kind": "unit"},
	"effect": {"kind": "debuff", "grants_rule": "Unpredictable Fighter", "duration": "once", "beneficiary": "attackers"}}


## A real NetworkManager with only the transport swapped out; every send is recorded. This machine sits in slot 2 (the AI's).
class FakeNet extends "res://scripts/network_manager.gd":
	var sent: Array = []
	var my_slot := 2

	func is_multiplayer_active() -> bool:
		return true

	func get_my_player_slot() -> int:
		return my_slot

	func _validate_rpc_ready(_context: String = "") -> bool:
		return true

	func slot_has_human_peer(_slot: int) -> bool:
		return false

	func send_command(type: String, payload: Variant = {}, target_peer: int = 0) -> bool:
		sent.append({"t": type, "p": payload, "to": target_peer})
		return true

	func broadcast_log_event(_category: int, _text: String, _ai: bool = false, _detail: String = "") -> void:
		pass


var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _real_net: Node
var _net: FakeNet


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_real_net = _main.network_manager
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.solo_controller.ai_slot = 2
	_main.solo_controller.human_slot = 1
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	_main._solo_batch = true
	_main._solo_fast = true
	_main._solo_auto_saves = true
	CoreActivation._env = 1
	CoreActivation._choice_on = {"interference": true}


func after_test() -> void:
	CoreActivation._choice_on = {}
	CoreActivation._env = -1
	if _main != null:
		CoreActivation.reset_all(_main)
		_main.network_manager = _real_net
		_main.solo_ai_slots = {}
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _session(peers: Dictionary) -> void:
	_net = auto_free(FakeNet.new())
	_net.army_manager = _main.opr_army_manager
	_net.peer_to_slot = peers
	_main.network_manager = _net
	_main.solo_ai_slots = {2: true}


func _requests() -> Array:
	return _net.sent.filter(func(f: Dictionary) -> bool: return str(f["t"]) == "request_roll") if _net != null else []


func _log_text(since: int) -> String:
	var text := ""
	var entries: Array = _main.battle_log.entries()
	for i in range(since, entries.size()):
		text += str((entries[i] as Dictionary)["text"]) + "\n"
	return text


## The AI caster (seat 2), the foe unit and the foe's token holder (seat 1, 2 tokens); one planned Infuse Bloodthirst with its
## interference OPEN and the holder as the pool. The planner has paid the 1-token threshold; the capture is the state before.
func _scenario(open := true) -> Dictionary:
	var caster := ParityTable._make_unit(_main, MYSTIC, STAFF)
	var helper := ParityTable._make_unit(_main, HELPER, STAFF)
	var foe := ParityTable._make_unit(_main, FOE, {})
	var pool_units: Array = [{"unit": helper, "tokens": 2}]
	var cast := {"caster": caster, "caster_unit": caster, "name": "Infuse Bloodthirst", "spell": BLOODTHIRST, "targets": [foe],
		"boost": 0, "interference": 0, "base_target": 4, "threshold": 1, "owner_label": "AI (Mystic)", "interference_open": open,
		"boost_sources": [], "interference_sources": [], "conduit": null, "conduit_shaken": [], "pools": [[1, pool_units]]}
	var report := {"action": AiDecision.Action.HOLD, "moved": false, "casts": [cast], "cast_door": true}
	_main._solo_spell_tokens_active.clear()
	caster.casts_current = 3
	helper.casts_current = 2
	var h := CoreActivation.capture(_main)   # the tokens BEFORE the plan's spend: the core pays them itself
	caster.spend_caster_points(1)
	_main._solo_act_flags = _main._solo_unit_flags()
	_main.seed_tray_rng(3)
	return {"caster": caster, "helper": helper, "foe": foe, "report": report, "h": h}


func _start(sc: Dictionary, out: Dictionary) -> void:
	var run := func() -> void:
		out["r"] = await CoreActivation.run_ai(_main, sc["caster"], sc["report"], null, int(sc["h"]), [], true)
	run.call()


func _until(cond: Callable, seconds := 20.0) -> void:
	var waited := 0.0
	while not cond.call() and waited < seconds:
		await get_tree().create_timer(0.05).timeout
		waited += 0.05


func _finish(sc: Dictionary, out: Dictionary) -> void:
	await _until(func() -> bool: return out.has("r"))
	assert_bool(out.has("r")).override_failure_message("the activation never ended").is_true()
	_main.solo_controller._core_node_ready().release(int(sc["h"]))
	await E2EBoot.settle(get_tree())


func _choice_frames() -> Array:
	return _requests().filter(func(f: Dictionary) -> bool:
		var ask: Dictionary = (f["p"] as Dictionary).get("ask", {})
		return ask.has("choice") and str((ask["choice"] as Dictionary)["id"]).begins_with("interference:"))


func test_the_switch_starts_off_and_the_environment_turns_it_on() -> void:
	var saved := OS.get_environment("NML_ONE_CORE_CHOICE_INTERFERENCE")
	OS.unset_environment("NML_ONE_CORE_CHOICE_INTERFERENCE")
	CoreActivation._choice_on = {}
	assert_bool(CoreActivation.choice_enabled("interference:0:a:1")).override_failure_message("ON by default").is_false()
	OS.set_environment("NML_ONE_CORE_CHOICE_INTERFERENCE", "1")
	CoreActivation._choice_on = {}
	assert_bool(CoreActivation.choice_enabled("interference:0:a:1")).is_true()
	assert_bool(CoreActivation.any_choice_enabled()).is_true()
	if saved.is_empty():
		OS.unset_environment("NML_ONE_CORE_CHOICE_INTERFERENCE")
	else:
		OS.set_environment("NML_ONE_CORE_CHOICE_INTERFERENCE", saved)
	CoreActivation._choice_on = {}


## The probes: one id per pool slot that holds a token, in pool order; a cast with no token in any pool gets ONE covering id
## (its first pool's slot); a closed cast none; the switch OFF none. Pure.
func test_the_probes_are_one_id_per_slot_with_tokens_and_one_covering_id() -> void:
	var cast := func(seq: int, open: bool, pools: Array) -> Dictionary:
		return {"t": "cast", "seq": seq, "caster": "m", "open": open, "pools": pools}
	var t := [{"t": "begin"},
		cast.call(0, true, [[1, [["h1", 2]]], [3, [["h3", 0]]], [4, [["h4", 1]]]]),
		cast.call(1, true, [[3, [["h3", 0]]]]),
		cast.call(2, false, [[1, [["h1", 2]]]]),
		cast.call(3, true, [])]
	assert_array(CoreActivation.interference_probes(t)).is_equal(
		["interference:0:m:1", "interference:0:m:4", "interference:1:m:3", "interference:3:m:0"])
	CoreActivation._choice_on = {"interference": false}
	assert_array(CoreActivation.interference_probes(t)).override_failure_message("a switch that is off probed").is_empty()
	assert_str(CoreActivation.choice_purpose("interference:0:m:1")).is_equal("interference")
	assert_str(CoreActivation.choice_purpose("interference:0:m:1", [{"t": "cast", "caster": "m", "spell": "Infuse Bloodthirst"}])).is_equal("Infuse Bloodthirst")


## The probe at the body's cast slot: with the switch OFF the core refuses the OPEN cast before any die (the table keeps it,
## CC-13a); ON it is taken. Two human foe slots are refused either way (the planner's pools carry one slot).
func test_the_probe_takes_an_open_cast_only_with_the_switch_on_and_one_human_foe_slot() -> void:
	_session({GUEST_PEER: 1})
	var sc := _scenario()
	_main._solo_core_ai_h = int(sc["h"])   # the probe reads the body's AI capture
	var before := CoreActivation.cast_probe_refusals
	CoreActivation._choice_on = {"interference": false}
	assert_bool(CoreActivation.probe_casts(_main, sc["caster"], sc["report"])).override_failure_message("an open cast was taken with the switch off").is_false()
	assert_int(CoreActivation.cast_probe_refusals).is_equal(before + 1)
	assert_str(str(CoreActivation.cast_probe_reasons.back())).contains("cannot be asked yet")
	CoreActivation._choice_on = {"interference": true}
	assert_bool(CoreActivation.probe_casts(_main, sc["caster"], sc["report"])).override_failure_message(str(CoreActivation.cast_probe_reasons)).is_true()
	var second := ParityTable._make_unit(_main, HELPER.merged({"player": 3, "name": "Second", "x_in": -6.0}, true), STAFF)   # a second human seat
	assert_bool(CoreActivation.probe_casts(_main, sc["caster"], sc["report"])).override_failure_message("two human foe slots were taken").is_false()
	assert_str(str(CoreActivation.cast_probe_reasons.back())).contains("more than one human foe slot")
	_main._solo_core_ai_h = 0
	_main.solo_controller._core_node_ready().release(int(sc["h"]))
	assert_object(second).is_not_null()


## The remote owner is asked ONCE (the token holder's owner, with the pool as options), a stale second answer never overwrites the
## first, the core says the table's interference line, the tokens leave the holder once - no defect report from the delta.
func test_the_remote_foe_is_asked_once_and_its_tokens_are_spent_once(timeout := 120000) -> void:
	_session({GUEST_PEER: 1})
	var sc := _scenario()
	var out := {}
	var since: int = _main.battle_log.entries().size()
	await assert_error(func() -> void:
		_start(sc, out)
		await _until(func() -> bool: return not _requests().is_empty() or out.has("r"))
		var asked := _choice_frames()
		assert_int(asked.size()).override_failure_message("the foe was not asked exactly once: %s" % str(_net.sent)).is_equal(1)
		if asked.is_empty():
			return
		var p: Dictionary = asked[0]["p"]
		assert_int(_main._vfx_seq).override_failure_message("the foe was asked before the cast was shown (no seal yet)").is_greater(0)
		assert_int(int(asked[0]["to"])).override_failure_message("the host answered for a remote foe").is_equal(GUEST_PEER)
		assert_str(str(p["unit"])).is_equal((sc["helper"] as GameUnit).unit_id)
		assert_str(str((p["ask"]["choice"] as Dictionary)["id"])).is_equal("interference:0:%s:1" % (sc["caster"] as GameUnit).unit_id)
		assert_array((p["ask"]["choice"] as Dictionary)["options"]).is_equal(["0", "1", "2"])
		assert_str(str(p["purpose"])).is_equal("Infuse Bloodthirst")
		_main._rpc_roll_result(int(p["req"]), ["1"])
		_main._rpc_roll_result(int(p["req"]), ["2"])   # stale: the first answer is the answer
		await _finish(sc, out)).is_success()
	assert_bool(bool(out.get("r", false))).override_failure_message("the core did not take the activation").is_true()
	assert_int((sc["helper"] as GameUnit).casts_current).override_failure_message("the holder's tokens").is_equal(1)
	assert_int(_choice_frames().size()).override_failure_message("asked twice").is_equal(1)
	var text := _log_text(since)
	assert_str(text).contains("Waiting for")
	assert_str(text).contains("Interference: Helper ×1 spends 1 token — the cast roll worsens to 5+")
	assert_int(text.count("Infuse Bloodthirst: cast roll")).override_failure_message(text).is_equal(1)


## Nobody answers in time / nobody sits in the seat: no interference, the cast goes on, and the table's own line says why.
func test_a_foe_nobody_answers_is_no_interference_with_the_tables_line(timeout := 120000) -> void:
	for seat in [{GUEST_PEER: 1}, {}]:
		_session(seat)
		_main._owner_roll_timeout_s = 0.2
		var sc := _scenario()
		var since: int = _main.battle_log.entries().size()
		var out := {}
		_start(sc, out)
		await _finish(sc, out)
		var text := _log_text(since)
		assert_bool(bool(out.get("r", false))).override_failure_message("seat %s: not taken" % [seat]).is_true()
		assert_int((sc["helper"] as GameUnit).casts_current).override_failure_message("seat %s: tokens moved" % [seat]).is_equal(2)
		assert_str(text).override_failure_message(text).contains(("Infuse Bloodthirst: player 1's seat is empty — no interference" if seat.is_empty()
			else "Infuse Bloodthirst: no answer from player 1 — no interference"))
		assert_int(text.count("no interference")).override_failure_message(text).is_equal(1)
		assert_int(text.count("Infuse Bloodthirst: cast roll")).override_failure_message("the cast die was not thrown: %s" % text).is_equal(1)
		CoreActivation.reset_all(_main)
		_main._solo_spell_mods.clear()
		Harness._free_units(_main, [sc["caster"], sc["helper"], sc["foe"]])
		await get_tree().process_frame


func _card() -> PromptCard:
	for n in _main.get_children():
		if n is InterferenceDialog:
			for c in n.get_children():
				if c is PromptCard and (c as PromptCard).title == "Enemy spell!":
					return c
	return null


## A human on THIS machine is asked with the table's tableau (a card on this screen, nothing on the wire): the count they pick
## is the answer, the core spends it - the same lines and tokens as the remote case.
func test_a_local_human_foe_answers_on_the_dialog(timeout := 120000) -> void:
	_session({GUEST_PEER: 1})
	_net.my_slot = 1
	_main._solo_batch = false
	var sc := _scenario()
	var since: int = _main.battle_log.entries().size()
	var out := {}
	_start(sc, out)
	await _until(func() -> bool: return _card() != null or out.has("r"))
	var card := _card()
	assert_object(card).override_failure_message("no dialog opened for the local foe: %s" % _log_text(since)).is_not_null()
	if card != null:
		card.resolve(2)
	await _finish(sc, out)
	assert_array(_requests()).override_failure_message("a local foe was asked over the wire").is_empty()
	assert_bool(bool(out.get("r", false))).is_true()
	assert_int((sc["helper"] as GameUnit).casts_current).is_equal(0)
	assert_str(_log_text(since)).contains("Interference: Helper \u00d72 spends 2 tokens \u2014 the cast roll worsens to 6+")


## The remote owner's MACHINE: the host's request carries the cast's facts (`ask.choice.ctx`); the owner's machine opens the
## dialog from them, answers with the count, and the host spends it once. The facts are the dialog's own arguments.
func test_the_owners_machine_opens_the_dialog_from_the_hosts_facts(timeout := 120000) -> void:
	_session({GUEST_PEER: 1})
	_main._solo_batch = false
	var sc := _scenario()
	var since: int = _main.battle_log.entries().size()
	var out := {}
	_start(sc, out)
	await _until(func() -> bool: return not _requests().is_empty() or out.has("r"))
	var asked := _choice_frames()
	assert_int(asked.size()).override_failure_message("not asked: %s" % _log_text(since)).is_equal(1)
	if asked.is_empty():
		return
	var rq: Dictionary = asked[0]["p"]
	assert_dict((rq["ask"]["choice"] as Dictionary)["ctx"]).is_equal({"caster": "Mystic", "spell": "Infuse Bloodthirst", "targets": "Foe", "base": 4, "boost": 0})
	assert_object(_card()).override_failure_message("the host's screen opened the foe's dialog").is_null()
	_net.sent.clear()
	_net.my_slot = 1   # the owner's machine
	(func() -> void: await _main._rpc_request_roll(rq, 7)).call()
	await _until(func() -> bool: return _card() != null)
	var card := _card()
	assert_object(card).override_failure_message("the owner's machine showed no dialog").is_not_null()
	if card != null:
		card.resolve(1)
	await _until(func() -> bool: return not _net.sent.filter(func(f: Dictionary) -> bool: return str(f["t"]) == "roll_result").is_empty())
	var replies := _net.sent.filter(func(f: Dictionary) -> bool: return str(f["t"]) == "roll_result")
	assert_int(replies.size()).override_failure_message("the owner's machine did not answer: %s" % str(_net.sent)).is_equal(1)
	_net.my_slot = 2   # back on the host
	if not replies.is_empty():
		_main._rpc_roll_result(int((replies[0]["p"] as Dictionary)["req"]), (replies[0]["p"] as Dictionary)["faces"])
	await _finish(sc, out)
	assert_int((sc["helper"] as GameUnit).casts_current).is_equal(1)
	assert_str(_log_text(since)).contains("Interference: Helper \u00d71 spends 1 token \u2014 the cast roll worsens to 5+")


## No facts (an older host) or no pool: nothing to ask, so no answer (the host reads it as no interference).
func test_no_context_or_no_pool_asks_nobody() -> void:
	assert_str(await _main._solo_pick_interference(["0", "1"], {})).is_empty()
	assert_str(await _main._solo_pick_interference(["0"], {"caster": "a", "spell": "b", "targets": "c", "base": 4, "boost": 0})).is_empty()
	assert_object(_card()).is_null()


## The landing alone: 3 tokens against two holders (2 + 5): the nearest gives 2, the next 1; the rest of the pool is untouched;
## a spend dims the seal on the stage, a zero does not.
func test_the_spend_leaves_the_pool_nearest_first() -> void:
	_session({GUEST_PEER: 1})
	var a := ParityTable._make_unit(_main, HELPER, STAFF)
	var b := ParityTable._make_unit(_main, HELPER.merged({"name": "Second", "x_in": -6.0}, true), STAFF)
	a.casts_current = 2
	b.casts_current = 5
	var t := [{"t": "cast", "seq": 0, "caster": "m", "open": true, "pools": [[1, [[a.unit_id, 2], [b.unit_id, 5]]]]}]
	CoreActivation._land_interference(_main, {}, t, "interference:0:m:1", 3)
	assert_array([a.casts_current, b.casts_current]).is_equal([0, 4])
	CoreActivation._land_interference(_main, {}, t, "interference:0:m:1", 0)
	assert_array([a.casts_current, b.casts_current]).override_failure_message("0 spent something").is_equal([0, 4])
	var c := ParityTable._make_unit(_main, HELPER.merged({"name": "Third", "x_in": -8.0}, true), STAFF)
	c.casts_current = 3
	var t2 := [{"t": "cast", "seq": 0, "caster": "m", "open": true, "pools": [[1, [[c.unit_id, 3]]]]}]
	var seq: int = _main._vfx_seq
	CoreActivation._land_interference(_main, {"cur": {"seal": 7}}, t2, "interference:0:m:1", 0)
	assert_int(_main._vfx_seq).override_failure_message("a zero spend dimmed the seal").is_equal(seq)
	CoreActivation._land_interference(_main, {"cur": {"seal": 7}}, t2, "interference:0:m:1", 1)
	assert_int(_main._vfx_seq).override_failure_message("a spend did not dim the seal").is_equal(seq + 1)
	assert_int(c.casts_current).is_equal(2)
	var casts_frames := _net.sent.filter(func(f: Dictionary) -> bool: return str(f["t"]) == "rpc" and str((f["p"] as Dictionary).get("m", "")) == "sync_unit_casts")
	assert_int(casts_frames.size()).override_failure_message("every payer is broadcast: %s" % str(_net.sent)).is_equal(3)   # a, b, then c
