extends GdUnitTestSuite
## E2E — wave 5: the "Pass Turn" primitive and its first user, Delayed Action, driven on the REAL
## scenes/main.tscn.
##
## THE RULE (word-identical in all 21 army books that carry it, 73 occurrences across all five game
## systems — the largest single open rule):
##   "Once per round, if your opponent has more units left to activate than you, then this model's
##    unit may pass its turn instead of activating (may still be activated later)."
##
## WHY THIS SUITE EXISTS AT THE E2E LEVEL. The rule is the first thing in the game that advances the
## ALTERNATION without spending an activation, so every claim about it is a claim about main.gd's own
## pump (_solo_pump / _solo_pending_replies / _solo_after_activation) — precisely the layer unit tests
## do not load. A pure test can prove the condition; only this layer can prove the round still ends.
##
## THE TWO TERMINATION GUARDS, each with its ROT flip documented in the PR:
##   (a) strictly MORE — antisymmetric, so it can never stand for both sides at once (a mutual pass
##       would never terminate). Turning it into ">=" makes test 3 and test 6 go red.
##   (b) a per-carrier round stamp — one carrier cannot pass the same round twice. Removing the
##       stamp makes test 2 go red.
##
## MAINTAINER RULINGS under test: reserve units do NOT count as "units left to activate" (test 6),
## the once-per-round limit binds the CARRIER, not the army (test 2), and an entry that cannot be
## used right now is REFUSED with its reason instead of being hidden (tests 2, 3, 6, 7).
##
## WHAT IS REAL vs CONSTRUCTED. Real: main.tscn with its real _ready(), the real OPRArmyManager and
## phase machine, the real SoloController, the real alternation pump, the real battle log, the real
## radial-menu item builder. Constructed: the GameUnits and their model nodes (importing a real Army
## Forge list needs the network; spawning needs R2 assets) — placed at genuine table coordinates.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")

## Well inside the real 6x4 ft table rect (±0.914 x ±0.610 m).
const HUMAN_LINE := Vector3(-0.30, 0.0, 0.20)
const AI_LINE := Vector3(0.30, 0.0, -0.20)
const TRAY := Vector3(3.0, 0.0, 0.0)   # strictly outside the rect — where a reserve waits

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
## Every AI activation this test saw, in order — the alternation's own witness.
var _ai_acted: PackedStringArray = []


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {2: true}          # player 2 = NACHTMAHR
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	_main._solo_batch = true                 # no dialogs, no per-unit frame yield in a headless sweep
	_ai_acted = PackedStringArray()
	_main.solo_controller.ai_unit_activated.connect(func(gu: GameUnit) -> void:
		_ai_acted.append(gu.get_name()))


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


# === fixture helpers ==========================================================================

func _register(pid: int, unit_name: String, at: Vector3, models: int = 2) -> GameUnit:
	var positions: Array = []
	for i in range(models):
		positions.append(at + Vector3(0.03 * i, 0.0, 0.0))
	var u := E2EBoot.make_unit(_main, pid, unit_name, positions)
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## A Delayed Action carrier on `pid`'s side.
func _carrier(pid: int, unit_name: String, at: Vector3) -> GameUnit:
	var u := _register(pid, unit_name, at)
	u.unit_properties["special_rules"] = ["Delayed Action"]
	return u


## A row of plain units, spread along the line so nothing overlaps.
func _row(pid: int, prefix: String, count: int, at: Vector3) -> Array:
	var out: Array = []
	for i in range(count):
		out.append(_register(pid, "%s%d" % [prefix, i + 1], at + Vector3(0.0, 0.0, 0.12 * (i + 1))))
	return out


func _log_text() -> String:
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


func _count(needle: String) -> int:
	var n := 0
	for e in _main.battle_log.entries():
		if str((e as Dictionary)["text"]).contains(needle):
			n += 1
	return n


func _eligible(pid: int) -> int:
	return _main.solo_controller.eligible_units_for(pid).size()


# === 1. the human passes — the turn moves, the unit does not ==================================

## The core claim: a pass hands the turn to NACHTMAHR, the passing unit stays UN-ACTIVATED, and it
## takes a normal turn later in the SAME round. That last half is what makes this a pass and not a
## skipped activation, and it is exactly what no existing seam could express.
func test_a_pass_hands_the_turn_over_and_keeps_the_unit_available(timeout := 120000) -> void:
	var carrier := _carrier(1, "Wachtturm", HUMAN_LINE)
	_row(1, "Grenzer", 1, HUMAN_LINE)   # a second unit of ours, so the round does not end here
	_row(2, "Nachtzehrer", 3, AI_LINE)
	assert_int(_eligible(1)).is_equal(2)
	assert_int(_eligible(2)).is_equal(3)

	await _main.solo_begin_pass(carrier)

	# The mandated line, with the counts the condition was measured on.
	assert_str(_log_text()) \
		.override_failure_message("rules-must-log: the applied pass needs its own line:\n%s" % _log_text()) \
		.contains("Delayed Action: Wachtturm passes the turn — the opponent has 3 units left to activate, you have 2 (Wachtturm may still be activated later)")
	# The unit did NOT spend its activation.
	assert_bool(carrier.is_activated) \
		.override_failure_message("the pass consumed the activation — 'may still be activated later' is broken") \
		.is_false()
	assert_int(_eligible(1)).is_equal(2)
	# The turn really moved: NACHTMAHR answered with EXACTLY one activation, then the pump waits.
	assert_int(_ai_acted.size()) \
		.override_failure_message("the AI answered %d times instead of once (alternation: one for one)" % _ai_acted.size()) \
		.is_equal(1)
	assert_int(_main._solo_pending_replies).is_equal(0)

	# …and later in the SAME round the very same unit takes a normal turn, answered once more.
	carrier.activate(_main.opr_army_manager.current_round)
	await _main._on_solo_human_activated(carrier)
	assert_int(_main.opr_army_manager.current_round) \
		.override_failure_message("fixture: the round must still be open, or the activation flags are read after a reset") \
		.is_equal(1)
	assert_bool(carrier.is_activated) \
		.override_failure_message("the delayed unit could not activate after its pass — 'may still be activated later' is broken") \
		.is_true()
	assert_int(_ai_acted.size()) \
		.override_failure_message("the delayed unit's real activation was not answered — the pass poisoned the alternation") \
		.is_equal(2)
	await E2EBoot.settle(get_tree())


# === 2. once per round, per carrier ===========================================================

## GUARD (b). The same carrier may not pass twice in one round — and the refusal SAYS so instead of
## the entry quietly disappearing. A second carrier is deliberately present: the maintainer ruling is
## that the limit binds the carrier, not the army, so its own pass must still be open.
func test_the_same_carrier_cannot_pass_twice_in_a_round(timeout := 120000) -> void:
	var first := _carrier(1, "Wachtturm", HUMAN_LINE)
	var second := _carrier(1, "Bollwerk", HUMAN_LINE + Vector3(0.0, 0.0, 0.15))
	_row(2, "Nachtzehrer", 5, AI_LINE)

	await _main.solo_begin_pass(first)
	assert_int(_count("Wachtturm passes the turn")).is_equal(1)
	var replies_after_first: int = _ai_acted.size()

	# The surplus still stands (5 - 1 = 4 AI units left vs our 2), so ONLY the stamp can refuse here.
	assert_bool(SoloController.delayed_action_surplus(_eligible(2), _eligible(1))) \
		.override_failure_message("fixture: the counts must still allow a pass, or this proves nothing") \
		.is_true()
	await _main.solo_begin_pass(first)

	assert_int(_count("Wachtturm passes the turn")) \
		.override_failure_message("guard (b) is gone: the carrier passed twice in one round") \
		.is_equal(1)
	assert_str(_log_text()).contains("Delayed Action: Wachtturm may not pass — it already passed a turn this round")
	assert_int(_ai_acted.size()) \
		.override_failure_message("a refused pass still moved the turn — the alternation ran ahead") \
		.is_equal(replies_after_first)
	# Ruling 2: no army-wide cap — the OTHER carrier's own once-per-round use is untouched.
	await _main.solo_begin_pass(second)
	assert_str(_log_text()).contains("Delayed Action: Bollwerk passes the turn")
	await E2EBoot.settle(get_tree())


# === 3. the condition itself ==================================================================

## GUARD (a). Equal counts refuse — and the refusal quotes the measured numbers, so "why not?" is
## answered in the log rather than in the forum.
func test_equal_counts_refuse_the_pass_and_name_the_numbers(timeout := 120000) -> void:
	var carrier := _carrier(1, "Wachtturm", HUMAN_LINE)
	_row(1, "Grenzer", 1, HUMAN_LINE)
	_row(2, "Nachtzehrer", 2, AI_LINE)
	assert_int(_eligible(1)).is_equal(2)
	assert_int(_eligible(2)).is_equal(2)

	await _main.solo_begin_pass(carrier)

	assert_str(_log_text()) \
		.override_failure_message("the refused pass must explain itself (#224):\n%s" % _log_text()) \
		.contains("Delayed Action: Wachtturm may not pass — your opponent has 2 units left to activate, you have 2 — the rule needs them to have MORE than you")
	assert_int(_count("passes the turn")).is_equal(0)
	assert_int(_ai_acted.size()) \
		.override_failure_message("a refused pass handed the turn over anyway") \
		.is_equal(0)
	assert_bool(carrier.is_activated).is_false()
	# The ROT direction of the same fixture: ONE more enemy and the identical call goes through.
	_row(2, "Spätling", 1, AI_LINE)
	await _main.solo_begin_pass(carrier)
	assert_str(_log_text()).contains("Delayed Action: Wachtturm passes the turn — the opponent has 3 units left to activate, you have 2")
	await E2EBoot.settle(get_tree())


# === 4. the alternation does not tip ==========================================================

## The round still ENDS, nobody activates twice, and the round-opener bookkeeping survives a pass.
## This is the test the primitive exists for: a pass that leaked into _solo_pending_replies would
## either stall the round forever or hand the AI a free back-to-back turn.
func test_a_pass_leaves_the_round_able_to_end(timeout := 120000) -> void:
	var carrier := _carrier(1, "Wachtturm", HUMAN_LINE)
	_row(2, "Nachtzehrer", 2, AI_LINE)

	await _main.solo_begin_pass(carrier)
	assert_int(_ai_acted.size()).is_equal(1)
	assert_int(_main.opr_army_manager.current_round) \
		.override_failure_message("the round ended on a pass — impossible while the opponent has more units left") \
		.is_equal(1)

	# The human now takes its only real activation; the AI answers with its last unit and the round
	# closes on its own (both sides exhausted -> _solo_after_activation -> _solo_end_round).
	carrier.activate(_main.opr_army_manager.current_round)
	await _main._on_solo_human_activated(carrier)

	assert_int(_main.opr_army_manager.current_round) \
		.override_failure_message("the round never ended — the pass left an owed reply behind") \
		.is_equal(2)
	assert_int(_ai_acted.size()) \
		.override_failure_message("NACHTMAHR took %d activations for a 2-unit army: %s" % [_ai_acted.size(), str(_ai_acted)]) \
		.is_equal(2)
	# No AI unit acted twice — a pass must not buy anyone an extra turn.
	var seen := {}
	for n in _ai_acted:
		assert_bool(seen.has(n)) \
			.override_failure_message("%s activated twice in one round — the alternation tipped" % n) \
			.is_false()
		seen[n] = true
	await E2EBoot.settle(get_tree())


# === 5. the AI side ===========================================================================

## NACHTMAHR passes when the delay buys something: its most valuable un-activated unit stands inside
## the reach of a human unit that has NOT committed yet. The decision is taken in the CHOOSER (before
## a unit is picked) and carries its reasoning in the decision log.
func test_the_ai_passes_to_wait_out_an_uncommitted_threat(timeout := 120000) -> void:
	var guard := _carrier(2, "Wächter", AI_LINE)
	guard.unit_properties["cost"] = 240   # the prize a pass is meant to protect
	# Three human units, one of them well inside a standard 12" rush band of the prize.
	_register(1, "Jäger", AI_LINE + Vector3(0.15, 0.0, 0.0))
	_row(1, "Grenzer", 2, HUMAN_LINE)
	assert_int(_eligible(1)).is_equal(3)
	assert_int(_eligible(2)).is_equal(1)

	_main._solo_pending_replies = 1   # the AI owes exactly one answer
	await _main._solo_pump()

	assert_str(_log_text()) \
		.override_failure_message("the AI's pass needs the same line the human's gets:\n%s" % _log_text()) \
		.contains("Delayed Action: Wächter passes the turn — the opponent has 3 units left to activate, you have 1 (Wächter may still be activated later)")
	assert_int(_ai_acted.size()) \
		.override_failure_message("the AI passed AND activated — the pass must replace the activation") \
		.is_equal(0)
	assert_bool(guard.is_activated).is_false()
	assert_int(_main._solo_pending_replies) \
		.override_failure_message("the owed reply was not spent — the pump would offer it again") \
		.is_equal(0)
	# The reasoning is on the record (dev lane), not just in the outcome.
	var found := false
	for rec in _main.solo_controller.decision_log:
		var r := rec as Dictionary
		if str(r.get("chosen", "")) == "passes the turn" and str(r.get("unit", "")) == "Wächter":
			found = true
			assert_str(str(r.get("why", ""))).contains("waits out a threat")
			assert_str(str(r.get("rule", ""))).contains("more units left to activate")
			assert_str(str((r.get("data", {}) as Dictionary).get("threat", ""))).is_equal("Jäger")
	assert_bool(found) \
		.override_failure_message("the AI passed without a decision record — the dev lane cannot explain it") \
		.is_true()
	await E2EBoot.settle(get_tree())


## The ROT direction of test 5: the SAME condition, but with nothing of ours under threat the AI
## spends its turn instead of throwing tempo away — and says why it did not use the rule.
func test_the_ai_declines_the_pass_when_no_threat_is_waiting(timeout := 120000) -> void:
	var guard := _carrier(2, "Wächter", AI_LINE)
	guard.unit_properties["cost"] = 240
	# Every human unit is parked far away on the other side of the table: out of any reach band.
	_row(1, "Grenzer", 3, Vector3(-0.85, 0.0, 0.55))
	assert_int(_eligible(1)).is_equal(3)
	assert_int(_eligible(2)).is_equal(1)

	_main._solo_pending_replies = 1
	await _main._solo_pump()

	assert_int(_count("passes the turn")) \
		.override_failure_message("the AI passed with nothing to wait out — the heuristic is not gating") \
		.is_equal(0)
	assert_int(_ai_acted.size()) \
		.override_failure_message("the AI neither passed nor activated — the reply was swallowed") \
		.is_equal(1)
	await E2EBoot.settle(get_tree())


# === 6. reserve units do not count =============================================================

## MAINTAINER RULING 1: a unit still held in Ambush reserve is off the table and is NOT one of the
## "units left to activate" (the grundregel reading "left on the battlefield"). The fixture is exactly
## one unit away from a legal pass, and that one unit is the reserve — so the refusal proves the
## ruling rather than restating it. The ROT flip is the same call after the ambusher lands.
func test_a_reserve_unit_does_not_tip_the_balance(timeout := 120000) -> void:
	var carrier := _carrier(1, "Wachtturm", HUMAN_LINE)
	_row(1, "Grenzer", 1, HUMAN_LINE)
	_row(2, "Nachtzehrer", 2, AI_LINE)
	var ambusher := _register(2, "Schattenpirsch", TRAY)
	ambusher.unit_properties["special_rules"] = ["Ambush"]
	ambusher.unit_properties["ambush_reserve"] = true
	_main.solo_controller.ambush_reserve = [ambusher]

	assert_bool(SoloController.unit_in_reserve(ambusher)).is_true()
	assert_int(_eligible(2)) \
		.override_failure_message("the reserve leaked into the activation pool — the whole ruling rests on is_eligible") \
		.is_equal(2)

	await _main.solo_begin_pass(carrier)

	assert_str(_log_text()) \
		.override_failure_message("a reserve unit tipped the balance:\n%s" % _log_text()) \
		.contains("your opponent has 2 units left to activate, you have 2")
	assert_int(_count("passes the turn")).is_equal(0)
	# ROT flip: the SAME unit on the table is the third enemy, and the identical call goes through.
	ambusher.unit_properties.erase("ambush_reserve")
	E2EBoot.place_unit_at(ambusher, AI_LINE + Vector3(0.0, 0.0, 0.4))
	assert_int(_eligible(2)).is_equal(3)
	await _main.solo_begin_pass(carrier)
	assert_str(_log_text()).contains("Delayed Action: Wachtturm passes the turn — the opponent has 3 units left to activate, you have 2")
	await E2EBoot.settle(get_tree())


# === 7. the entry is offered, and an activated unit is still refused ===========================

## Transparency doctrine: the radial carries the entry for every carrier — it is NOT hidden when the
## condition happens to fail, because a rule that vanishes from the menu reads exactly like a missing
## rule. A unit that has already activated is refused with its own reason; that branch is also what
## makes "you have 0 units left" unreachable — with nothing left, the carrier is one of the activated.
func test_the_radial_offers_the_entry_and_an_activated_unit_is_refused(timeout := 120000) -> void:
	var carrier := _carrier(1, "Wachtturm", HUMAN_LINE)
	_row(2, "Nachtzehrer", 3, AI_LINE)

	var ids: PackedStringArray = []
	for item in RadialMenu.solo_combat_items(carrier):
		ids.append((item as RadialMenu.RadialMenuItem).id)
	assert_array(ids) \
		.override_failure_message("the carrier's radial has no Pass entry: %s" % str(ids)) \
		.contains(["solo_pass"])
	# A unit WITHOUT the rule never gets the entry (the gate is the rule, not the game mode).
	var plain := _register(1, "Grenzer", HUMAN_LINE + Vector3(0.0, 0.0, 0.3))
	var plain_ids: PackedStringArray = []
	for item in RadialMenu.solo_combat_items(plain):
		plain_ids.append((item as RadialMenu.RadialMenuItem).id)
	assert_array(plain_ids).not_contains(["solo_pass"])

	# Already activated → refused, and the unit is not un-activated behind the player's back.
	carrier.activate(1)
	await _main.solo_begin_pass(carrier)
	assert_str(_log_text()) \
		.override_failure_message("a spent unit passed a turn it no longer had:\n%s" % _log_text()) \
		.contains("Delayed Action: Wachtturm may not pass — it has already activated this round")
	assert_bool(carrier.is_activated).is_true()
	assert_int(_ai_acted.size()).is_equal(0)
	await E2EBoot.settle(get_tree())
