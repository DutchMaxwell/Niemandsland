extends GdUnitTestSuite
## E2E — the SELF-PLAY ARENA alternation carries the pass step (Delayed Action / "Pass Turn").
##
## WHY THIS SUITE EXISTS. The game has TWO alternations. The human-facing one lives in `main._solo_pump`
## and runs on `_solo_pending_replies`; wave 5 (#269) taught it the pass step. The second one is
## `main._solo_run_both_ai_round` — the both-AI driver the rating ladder, the self-play harness and the
## tactic-audit runs actually play on. It knew nothing about the pass, so every ladder number was
## measured on an AI that was forbidden a rule the shipped game hands its players: the ladder measured
## NEXT TO the real game instead of in it.
##
## THE RULE (word-identical in all 21 army books that carry it):
##   "Once per round, if your opponent has more units left to activate than you, then this model's unit
##    may pass its turn instead of activating (may still be activated later)."
##
## WHAT IS REAL vs CONSTRUCTED. Real: `scenes/main.tscn` with its real `_ready()`, the real
## OPRArmyManager and phase machine, the real SoloController and its pass heuristic, the real both-AI
## driver, the real battle log. Constructed: the GameUnits and their model nodes (importing a real Army
## Forge list needs the network) — placed at genuine table coordinates.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")

## Well inside the real 6x4 ft table rect (±0.914 x ±0.610 m).
const P1_LINE := Vector3(-0.30, 0.0, 0.20)
const P2_LINE := Vector3(0.30, 0.0, -0.20)

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
## Every activation the driver made, in order — the alternation's own witness (both sides are AI here,
## so this signal sees the whole round).
var _acted: PackedStringArray = []


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {1: true, 2: true}   # BOTH sides on the AI — the arena/ladder configuration
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	_main._solo_batch = true                   # no dialogs, no per-unit frame yield in a headless sweep
	_acted = PackedStringArray()
	_main.solo_controller.ai_unit_activated.connect(func(gu: GameUnit) -> void:
		_acted.append(gu.get_name()))


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


# === 1. the pass fires inside the both-AI driver ===============================================

## The core claim. P2 fields one valuable carrier against three P1 units, one of them inside its reach
## and not yet committed — exactly the AI heuristic's trigger. The driver must offer the pass step, and
## the round must still play every unit out, the passer included: "may still be activated later" has to
## hold in this alternation too.
##
## ROT: without the pass step in `_solo_run_both_ai_round` the log line never appears (proven).
func test_the_both_ai_driver_offers_the_pass_step(timeout := 120000) -> void:
	var carrier := _carrier(2, "Wächter", P2_LINE)
	carrier.unit_properties["cost"] = 240      # the prize a pass is meant to protect
	var threat := _register(1, "Jäger", P2_LINE + Vector3(0.15, 0.0, 0.0))
	var row := _row(1, "Grenzer", 2, P1_LINE)
	assert_int(_eligible(1)).is_equal(3)
	assert_int(_eligible(2)).is_equal(1)

	var last_side: int = await _main._solo_run_both_ai_round(2)   # P2 opens — its turn, its pass

	assert_str(_log_text()) \
		.override_failure_message("the arena driver never offered the pass step:\n%s" % _log_text()) \
		.contains("Delayed Action: Wächter passes the turn — the opponent has 3 units left to activate, you have 1 (Wächter may still be activated later)")
	assert_int(_count("passes the turn")) \
		.override_failure_message("the carrier passed more than once in one round — the stamp does not bind here") \
		.is_equal(1)
	# The round still played everyone out, the passer included.
	for u in ([carrier, threat] + row):
		assert_bool((u as GameUnit).is_activated) \
			.override_failure_message("%s never activated — the pass swallowed an activation" % (u as GameUnit).get_name()) \
			.is_true()
	# A pass is not an activation: the next round's opener rule reads the last ACTIVATION, so the
	# returned side must be one that really acted.
	assert_bool(last_side == 1 or last_side == 2) \
		.override_failure_message("the round returned opener %d — a pass leaked into the last-activation record" % last_side) \
		.is_true()
	# The driver owns its own alternation — the human pump's reply counter must stay untouched, or a
	# session that later faces a human opponent inherits a phantom debt.
	assert_int(_main._solo_pending_replies) \
		.override_failure_message("the arena pass moved the human pump's reply counter") \
		.is_equal(0)
	await E2EBoot.settle(get_tree())


# === 2. the turn really moves, and the round still ends ========================================

## THE PASS IS A HAND-OVER, not a skipped beat. The whole point of the step is that the OPPONENT acts
## next — an implementation that passed and then took the very next activation anyway would satisfy
## every "did it log a line" check while quietly handing the passing side two turns in a row. So: P1
## opens outnumbered 3 : 5 and passes; the FIRST unit to actually activate in the round must be one of
## P2's. On top of that the round still has to end with every unit on both sides activated exactly once
## — the claim the whole ladder rests on, because a self-play game that never ends produces no numbers.
##
## ROT: dropping the `side = other` hand-over in the driver's pass branch lets P1 activate first anyway
## (proven) — the log line is identical, only the alternation is wrong.
func test_the_arena_pass_hands_the_turn_over_and_the_round_still_ends(timeout := 120000) -> void:
	# The two carriers face each other inside a standard 12" rush band, so each is the other's threat:
	# that is what makes the pass condition live rather than academic.
	var p1_carrier := _carrier(1, "Wachtturm", P1_LINE)
	p1_carrier.unit_properties["cost"] = 240
	var p1_row := _row(1, "Grenzer", 2, P1_LINE)
	var p2_carrier := _carrier(2, "Wächter", P1_LINE + Vector3(0.15, 0.0, 0.0))
	p2_carrier.unit_properties["cost"] = 240
	var p2_row := _row(2, "Nachtzehrer", 4, P2_LINE)
	var everyone: Array = [p1_carrier, p2_carrier] + p1_row + p2_row
	assert_int(_eligible(1)).is_equal(3)
	assert_int(_eligible(2)).is_equal(5)

	await _main._solo_run_both_ai_round(1)   # P1 opens outnumbered 3 : 5 — its carrier may pass once

	assert_int(_count("passes the turn")) \
		.override_failure_message("%d passes in one round — the once-per-round stamp does not bind in this driver:\n%s" % [
			_count("passes the turn"), _log_text()]) \
		.is_equal(1)
	# The hand-over: P1 passed, so P2 owns the next activation.
	assert_bool(_acted.size() > 0).override_failure_message("nobody activated at all").is_true()
	var first: String = _acted[0]
	assert_bool(first == "Wächter" or first.begins_with("Nachtzehrer")) \
		.override_failure_message("P1 passed and then activated %s anyway — the pass did not hand the turn over (order: %s)" % [
			first, str(_acted)]) \
		.is_true()

	assert_int(_eligible(1)) \
		.override_failure_message("P1 still owes activations — the round did not play out") \
		.is_equal(0)
	assert_int(_eligible(2)) \
		.override_failure_message("P2 still owes activations — the round did not play out") \
		.is_equal(0)
	for u in everyone:
		assert_bool((u as GameUnit).is_activated) \
			.override_failure_message("%s never activated" % (u as GameUnit).get_name()).is_true()
	# Nobody bought a second turn out of a pass.
	var seen := {}
	for n in _acted:
		assert_bool(seen.has(n)) \
			.override_failure_message("%s activated twice in one round — a pass tipped the alternation" % n) \
			.is_false()
		seen[n] = true
	assert_int(_acted.size()) \
		.override_failure_message("%d activations for an 8-unit table: %s" % [_acted.size(), str(_acted)]) \
		.is_equal(8)
	await E2EBoot.settle(get_tree())
