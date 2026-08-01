extends GdUnitTestSuite
## E2E — the wave-4 army-book rules, driven on the REAL main.tscn:
##
##   • Extended Buff Range  "If this unit is within 24" of another friendly unit with this rule that
##                           has a Hero in it, then that Hero may use special rules that allow it to
##                           pick friendly units within 12" (except for spells) on this unit as if it
##                           was in range."
##   • Coordinate           "At the end of this unit's activation, another friendly unit within 12"
##                           that hasn't activated yet may be activated immediately. May not be used
##                           if this unit was activated via Coordinate."
##
## MAINTAINER RULINGS under test: one living carrier model is enough to relay; a bearer that died
## during its own activation hands nothing off; reserve units are invisible to the hand-off; the
## relay is exactly ONE hop and Coordinate never chains past two activations.
##
## It also covers the wave's side finding: the whole Utility-Buff GIVER family was AI-only, so a
## human player's buff simply never happened. The human path is asserted here too.
##
## Every core claim carries its ROT case — the same machinery must REFUSE one step away (no Hero in
## the relay, a spell instead of a buff, an already-activated receiver, a dead bearer). No assertion
## sits behind a dice roll: relay reach, hand-off legality and the reply bookkeeping are all
## deterministic state code.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main._solo_batch = true   # no dialogs, no physics tray in a headless sweep


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## Register a fixture unit with the army manager and stamp the book that actually FIELDS the wave-4
## rules — the registry gate is system-scoped, so an unstamped unit resolves no primitive at all.
func _reg(u: GameUnit, rules: Array) -> GameUnit:
	u.unit_properties["game_system"] = "gf"
	u.unit_properties["faction_folder"] = "human_defense_force"
	u.unit_properties["special_rules"] = rules
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func _at(inches_x: float) -> Vector3:
	return Vector3(inches_x * INCH, 0.0, 0.0)


## A three-model line at `inches_x`. The buff's value proxy picks the BIGGEST unit, so the relay
## target has to out-value the one-model Hero that is buffing (a hero may legally buff itself).
func _line(inches_x: float) -> Array:
	return [_at(inches_x), _at(inches_x + 1.2), _at(inches_x + 2.4)]


func _log_text() -> String:
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


func _mods_on(u: GameUnit) -> Array:
	return _main._solo_spell_mods.get(u.get_instance_id(), [])


# === 1. Extended Buff Range ======================================================================

## The relay itself: a Hero's 12" Precision Shooter Buff lands on a friendly carrier standing 20"
## away, because the Hero's own unit carries the rule too — and the applied waiver writes its line.
func test_ebr_relays_a_twelve_inch_buff_onto_a_carrier_twenty_inches_out() -> void:
	# The Hero IS the buffing unit and IS the relay ("that Hero", inside a unit with the rule).
	var hero := _reg(E2EBoot.make_unit(_main, 2, "Field Commander", [_at(0.0)]),
		["Hero", "Precision Shooter Buff", "Extended Buff Range"])
	var far := _reg(E2EBoot.make_unit(_main, 2, "Forward Riflemen", _line(20.0)),
		["Extended Buff Range"])

	_main._solo_apply_utility_buffs(hero)

	assert_int(_mods_on(far).size()) \
		.override_failure_message("the relayed buff must land as a real once-mod record, not just a log line") \
		.is_equal(1)
	var rec: Dictionary = (_mods_on(far)[0] as Dictionary) if not _mods_on(far).is_empty() else {}
	assert_int(int(rec.get("hit_mod", 0))).is_equal(1)
	var text := _log_text()
	assert_str(text) \
		.override_failure_message("rules-must-log: the applied relay needs its own line\n%s" % text) \
		.contains("Extended Buff Range: Field Commander reaches Forward Riflemen at")
	assert_str(text).contains("relayed via Field Commander (24\" link, the 12\" pick is waived)")


## ROT for the whole relay: the same board with no Hero in the relay unit refuses the reach and says
## which clause failed. (The wording is "another friendly unit with this rule THAT HAS A HERO IN IT".)
func test_ebr_without_a_hero_in_the_relay_unit_refuses_and_says_why() -> void:
	var giver := _reg(E2EBoot.make_unit(_main, 2, "Signal Squad", [_at(0.0)]),
		["Precision Shooter Buff", "Extended Buff Range"])   # no "Hero"
	var far := _reg(E2EBoot.make_unit(_main, 2, "Forward Riflemen", _line(20.0)),
		["Extended Buff Range"])

	_main._solo_apply_utility_buffs(giver)

	assert_int(_mods_on(far).size()) \
		.override_failure_message("no Hero in the relay unit — nothing may be relayed") \
		.is_equal(0)
	var text := _log_text()
	assert_str(text) \
		.override_failure_message("a silent refusal reads like a broken rule\n%s" % text) \
		.contains("Extended Buff Range: Signal Squad cannot reach Forward Riflemen — no living Hero in Signal Squad")
	assert_str(text).contains("(no relay, the 12\" pick stands)")
	# CONTROL: the resolver itself still ran — the buff landed on the one target that WAS in the
	# printed 12" (a unit may buff itself). Only the relayed reach was refused.
	assert_int(_mods_on(giver).size()).is_equal(1)


## ROT 2: the target must carry the rule itself ("If THIS UNIT is within 24\" …"). A friend without
## it stays out of reach even with a perfect relay standing right there.
func test_ebr_does_not_extend_onto_a_friend_without_the_rule() -> void:
	var hero := _reg(E2EBoot.make_unit(_main, 2, "Field Commander", [_at(0.0)]),
		["Hero", "Precision Shooter Buff", "Extended Buff Range"])
	var far := _reg(E2EBoot.make_unit(_main, 2, "Plain Riflemen", _line(20.0)), [])   # no rule

	_main._solo_apply_utility_buffs(hero)

	assert_int(_mods_on(far).size()) \
		.override_failure_message("the relay is not an aura — the TARGET has to carry the rule") \
		.is_equal(0)
	# CONTROL: the buff still resolved, onto the only unit inside the printed 12" (the Hero itself).
	assert_int(_mods_on(hero).size()).is_equal(1)
	assert_str(_log_text()).not_contains("relayed via")


## "(except for spells)" — the relay explicitly does NOT extend a spell. The same 20" carrier that
## the buff reached stays an illegal spell target, and the exclusion gets its own line.
func test_ebr_never_extends_a_spell_and_says_so() -> void:
	var hero := _reg(E2EBoot.make_unit(_main, 2, "Field Commander", [_at(0.0)]),
		["Hero", "Precision Shooter Buff", "Extended Buff Range"])
	var far := _reg(E2EBoot.make_unit(_main, 2, "Forward Riflemen", _line(20.0)),
		["Extended Buff Range"])
	var solo = _main.solo_controller

	# Green control: the BUFF does reach it (same board, same distance).
	_main._solo_apply_utility_buffs(hero)
	assert_int(_mods_on(far).size()) \
		.override_failure_message("control: without a reaching buff the spell claim proves nothing") \
		.is_equal(1)

	# The spell keeps its own printed 12" — the relay is not in that path at all.
	var entry := {"name": "Blessing", "range_in": 12, "target": {"side": "friendly"}}
	var cands: Array = solo.spell_candidates(hero, entry, solo.ai_slot, solo.human_slot)
	assert_bool(cands.has(far)) \
		.override_failure_message("a spell must NOT inherit the 24\" relay — the rule excludes spells") \
		.is_false()
	# ROT for the candidate machinery itself: a friend INSIDE 12" is a legal spell target, so the
	# assertion above is about the relay and not about a spell list that is empty for other reasons.
	var near := _reg(E2EBoot.make_unit(_main, 2, "Close Riflemen", _line(6.0)), [])
	cands = solo.spell_candidates(hero, entry, solo.ai_slot, solo.human_slot)
	assert_bool(cands.has(near)).is_true()

	_main._solo_log_ebr_spell_exclusion(hero, "Blessing", 12.0, cands)
	var text := _log_text()
	assert_str(text) \
		.override_failure_message("rules-must-log: the spell exclusion is exactly the thing a player would call a bug\n%s" % text) \
		.contains("Extended Buff Range: Forward Riflemen stays out of reach for Blessing — the relay excludes spells")


# === 2. Coordinate ===============================================================================

## NACHTMAHR's hand-off: the bearer ends its activation, names a friend within 12", and that friend
## activates in the SAME beat — stamped, so it cannot hand off again.
func test_coordinate_hands_the_activation_straight_to_a_friend() -> void:
	var bearer := _reg(E2EBoot.make_unit(_main, 2, "Comms Team", [_at(0.0)]), ["Coordinate"])
	var receiver := _reg(E2EBoot.make_unit(_main, 2, "Riflemen", [_at(8.0)]), [])
	_reg(E2EBoot.make_unit(_main, 1, "Raiders", [_at(30.0)]), [])   # something for the AI to look at
	bearer.activate(1)

	await _main._solo_try_coordinate_ai(bearer)

	assert_bool(receiver.is_activated) \
		.override_failure_message("\"may be activated immediately\" — the receiver acts inside the same beat") \
		.is_true()
	assert_bool(receiver.was_activated_via_coordinate()).is_true()
	var text := _log_text()
	assert_str(text) \
		.override_failure_message("rules-must-log: the hand-off needs its own line\n%s" % text) \
		.contains("Coordinate: Comms Team hands off to Riflemen")
	assert_str(text).contains("Riflemen activates immediately")
	await E2EBoot.settle(get_tree())


## The anti-chain clause: the receiver carries Coordinate too, and is refused a second hand-off.
func test_coordinate_stops_at_the_second_bearer() -> void:
	var bearer := _reg(E2EBoot.make_unit(_main, 2, "Comms Team", [_at(0.0)]), ["Coordinate"])
	var second := _reg(E2EBoot.make_unit(_main, 2, "Relay Team", [_at(8.0)]), ["Coordinate"])
	var third := _reg(E2EBoot.make_unit(_main, 2, "Riflemen", [_at(14.0)]), [])   # in 12" of the SECOND
	_reg(E2EBoot.make_unit(_main, 1, "Raiders", [_at(30.0)]), [])
	bearer.activate(1)

	await _main._solo_try_coordinate_ai(bearer)

	assert_bool(second.is_activated).is_true()
	assert_bool(third.is_activated) \
		.override_failure_message("a chain of three activations is exactly what the rule forbids") \
		.is_false()
	var text := _log_text()
	assert_str(text) \
		.override_failure_message("the stopped chain must be named, not silent\n%s" % text) \
		.contains("Coordinate: Relay Team was itself activated via Coordinate — the chain stops here")
	await E2EBoot.settle(get_tree())


## Maintainer ruling 2: a bearer wiped out during its own activation hands nothing off.
func test_coordinate_dead_bearer_hands_nothing_off() -> void:
	var bearer := _reg(E2EBoot.make_unit(_main, 2, "Comms Team", [_at(0.0)]), ["Coordinate"])
	var receiver := _reg(E2EBoot.make_unit(_main, 2, "Riflemen", [_at(8.0)]), [])
	bearer.activate(1)
	for m in bearer.models:
		(m as ModelInstance).is_alive = false

	await _main._solo_try_coordinate_ai(bearer)

	assert_bool(receiver.is_activated).is_false()
	assert_str(_log_text()).contains("Coordinate: Comms Team did not survive its own activation — no hand-off")


## Maintainer ruling 3: a unit still held in Ambush reserve is off the table and invisible to the
## hand-off — with nobody else in range the "may" lapses, and says so.
func test_coordinate_cannot_see_a_reserve_unit() -> void:
	var bearer := _reg(E2EBoot.make_unit(_main, 2, "Comms Team", [_at(0.0)]), ["Coordinate"])
	var hidden := _reg(E2EBoot.make_unit(_main, 2, "Infiltrators", [_at(8.0)]), ["Ambush"])
	hidden.unit_properties["ambush_reserve"] = true
	bearer.activate(1)

	await _main._solo_try_coordinate_ai(bearer)

	assert_bool(hidden.is_activated).is_false()
	assert_str(_log_text()).contains("Coordinate: Comms Team finds no un-activated friendly unit within 12\"")


## THE BOOKKEEPING CLAIM: a human hand-off is TWO activations riding ONE owed AI reply. Counting it
## twice would push _solo_pending_replies past the human's real activation count and
## SoloController.alternation_next would hand the AI two answers in a row.
func test_human_coordinate_books_exactly_one_reply_for_two_activations() -> void:
	var bearer := _reg(E2EBoot.make_unit(_main, 1, "Comms Team", [_at(0.0)]), ["Coordinate"])
	var receiver := _reg(E2EBoot.make_unit(_main, 1, "Riflemen", [_at(8.0)]), [])
	_reg(E2EBoot.make_unit(_main, 2, "Raiders", [_at(30.0)]), [])
	_main._solo_pending_replies = 0
	_main._solo_ai_busy = true   # freeze the pump: this test measures the LEDGER, not the AI's turn

	# The player takes the hand-off at the end of the bearer's activation.
	bearer.activate(1)
	await _main._solo_coordinate_pick(bearer, receiver)
	assert_int(_main._solo_pending_replies) \
		.override_failure_message("the bearer's own activation owes the AI exactly one reply") \
		.is_equal(1)
	assert_bool(receiver.was_activated_via_coordinate()).is_true()

	# …and the coordinated unit's own activation adds NOTHING.
	receiver.activate(1)
	await _main._solo_finish_human_activation(receiver)
	assert_int(_main._solo_pending_replies) \
		.override_failure_message("a coordinated activation must not book a SECOND reply — the alternation would flip") \
		.is_equal(1)

	# ROT: the same call for a unit that was NOT coordinated does book its reply.
	var plain := _reg(E2EBoot.make_unit(_main, 1, "Scouts", [_at(20.0)]), [])
	plain.activate(1)
	await _main._solo_finish_human_activation(plain)
	assert_int(_main._solo_pending_replies).is_equal(2)

	# The alternation state machine reads that ledger: with 1 reply owed the AI answers, with 0 it
	# waits for the human. Two bookings for one hand-off would have produced a double answer.
	assert_int(SoloController.alternation_next(1, 1, 1)).is_equal(SoloController.AltStep.REPLY)
	assert_int(SoloController.alternation_next(0, 1, 1)).is_equal(SoloController.AltStep.WAIT)
	_main._solo_ai_busy = false


## The hold: while a hand-off is open the AI's owed reply waits ("activated immediately" — nothing
## slips in between), and it releases itself the moment the receiver has acted.
func test_the_open_hand_off_holds_the_ai_reply_until_the_receiver_acts() -> void:
	var bearer := _reg(E2EBoot.make_unit(_main, 1, "Comms Team", [_at(0.0)]), ["Coordinate"])
	var receiver := _reg(E2EBoot.make_unit(_main, 1, "Riflemen", [_at(8.0)]), [])
	_main._solo_ai_busy = true
	bearer.activate(1)
	await _main._solo_coordinate_pick(bearer, receiver)
	_main._solo_ai_busy = false

	assert_bool(_main._solo_coordinate_hold_active()) \
		.override_failure_message("the AI must not answer between the two coordinated activations") \
		.is_true()
	# ROT: the hold is not a latch — the receiver acting releases it.
	receiver.activate(1)
	assert_bool(_main._solo_coordinate_hold_active()).is_false()


# === 3. The wave's side finding: the human never got the buff-GIVER family ========================

## Before this wave _solo_apply_utility_buffs bailed on `not _solo_is_ai_unit(unit)`, so a human
## player's Precision Shooter Buff was dead data. It now lands a real token and writes its line —
## and the round stamp keeps the two human doors (attack declaration / activation end) to ONE
## application per activation.
func test_a_human_buff_giver_lands_a_token_and_a_log_line_once() -> void:
	var giver := _reg(E2EBoot.make_unit(_main, 1, "Field Commander", [_at(0.0)]),
		["Hero", "Precision Shooter Buff"])
	var friend := _reg(E2EBoot.make_unit(_main, 1, "Riflemen", _line(6.0)), [])
	_main.opr_army_manager.current_round = 1

	_main._solo_apply_utility_buffs(giver)

	assert_int(_mods_on(friend).size()) \
		.override_failure_message("the human's buff giver must actually apply its buff") \
		.is_equal(1)
	assert_str(_log_text()).contains("Precision Shooter Buff: Field Commander → Riflemen")

	# The second door must not apply it again in the same activation.
	_main._solo_apply_utility_buffs(giver)
	assert_int(_mods_on(friend).size()) \
		.override_failure_message("\"once per activation\" — two doors, one application") \
		.is_equal(1)
	# ROT: a new round re-opens it.
	_main.opr_army_manager.current_round = 2
	_main._solo_apply_utility_buffs(giver)
	assert_int(_mods_on(friend).size()).is_equal(2)
