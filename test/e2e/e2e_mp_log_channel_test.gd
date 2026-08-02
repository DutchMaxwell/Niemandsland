extends GdUnitTestSuite
## E2E — NML-946: rule events had no channel, so a correctly applied rule read as a missing one.
##
## THE DEFECT. Exactly one battle-log line travelled: sync_move_log, and only because the drag stream
## is unreliable so the peer could not tell when a drop happened. Everything else the rules engine
## writes — a pass, a Coordinate hand-off, an Ambush arrival, an Extended Buff Range refusal — was
## written into the local log and stopped there. On the other screen those rules were simply silent.
## Nothing is more direct a contradiction of "every applied rule owes a log line" than a log that
## drops the line at the network card.
##
## The pass is the purest case: _solo_pass_turn only moves a reply counter. It activates nothing,
## moves nothing and broadcasts nothing, so the line IS the entire event. Today the opponent's log
## shows the AI answering an activation that, as far as their log is concerned, never happened.
##
## THE FIX UNDER TEST. broadcast_log_event / sync_log_event beside the move pair (not a rename of it:
## renaming would have silently dropped every movement line on any peer that predates the rename),
## and main._log_rule_event as the one door a routed line goes through.
##
## THE SELECTION — the actual work, and what this suite pins. A line travels iff it names a rule
## APPLIED or REFUSED at a point the opponent cannot observe. Three exclusions:
##   1. already carried by another channel (movement summaries, activations, dice, the round,
##      casualties) — routing those prints them twice;
##   2. diagnosis rather than an event (AI decision records, rule-inventory dumps, the hit-modifier
##      notes folded into a dice line the peer already receives);
##   3. instructions to the player currently giving input (the Coordinate offer prompt, a mis-click
##      correction, "place the whole unit first") — meaningless to anyone not holding the mouse.
## Tests 5 and 6 below are exclusions 1 and 3 respectively.
##
## REACHABILITY, honestly: the rules engine runs wherever solo_controller exists, which in a
## networked room means a room with an explicitly designated AI slot (_ensure_solo_controller,
## main.gd:2021). Two routed lines reach a plain human-vs-human room as well — the reform
## honour-system notice and the move-undo line.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")

const HUMAN_LINE := Vector3(-0.30, 0.0, 0.20)
const AI_LINE := Vector3(0.30, 0.0, -0.20)


## The REAL NetworkManager with only its transport swapped out, so the actual broadcast_log_event
## body runs and this records the exact wire frames it produces.
class FakeNet extends "res://scripts/network_manager.gd":
	var active: bool = true
	var sent: Array = []
	func is_multiplayer_active() -> bool:
		return active
	func _validate_rpc_ready(_context: String = "") -> bool:
		return active
	func _remote_call(method: String, args: Array, _target_peer: int = 0) -> void:
		sent.append({"m": method, "a": args})
	func slot_has_human_peer(_slot: int) -> bool:
		return false

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
	_main.opr_army_manager.current_round = 1
	_main._solo_batch = true
	_real_net = _main.network_manager
	_fake = auto_free(FakeNet.new())
	_fake.army_manager = _main.opr_army_manager
	_main.network_manager = _fake


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null
	_fake = null
	_real_net = null


# === fixture helpers ==========================================================================

func _register(pid: int, unit_name: String, at: Vector3, models: int = 2) -> GameUnit:
	var positions: Array = []
	for i in range(models):
		positions.append(at + Vector3(0.03 * i, 0.0, 0.0))
	var u := E2EBoot.make_unit(_main, pid, unit_name, positions)
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func _row(pid: int, prefix: String, count: int, at: Vector3) -> Array:
	var out: Array = []
	for i in range(count):
		out.append(_register(pid, "%s%d" % [prefix, i + 1], at + Vector3(0.0, 0.0, 0.12 * (i + 1))))
	return out


## Every log line this client put on the wire, in order.
func _sent_lines() -> PackedStringArray:
	var out: PackedStringArray = []
	for e in _fake.sent:
		var frame: Dictionary = e as Dictionary
		if str(frame.get("m", "")) == "sync_log_event":
			out.append(str((frame.get("a", []) as Array)[1]))
	return out


func _sent_containing(needle: String) -> int:
	var n := 0
	for line in _sent_lines():
		if line.contains(needle):
			n += 1
	return n


func _log_text() -> String:
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


func _logged_containing(needle: String) -> int:
	var n := 0
	for e in _main.battle_log.entries():
		if str((e as Dictionary)["text"]).contains(needle):
			n += 1
	return n


# === 1. THE RED PROOF: the pass line reaches the guest =========================================

## _solo_pass_turn moves a reply counter and nothing else — it activates nothing, moves nothing and
## broadcasts nothing. The line IS the whole event, so a guest whose log does not get it watches
## NACHTMAHR answer an activation that never appears in their record.
func test_the_pass_line_reaches_the_guest(timeout := 120000) -> void:
	var carrier := _register(1, "Wachtturm", HUMAN_LINE)
	carrier.unit_properties["special_rules"] = ["Delayed Action"]
	_row(1, "Grenzer", 1, HUMAN_LINE)
	_row(2, "Nachtzehrer", 3, AI_LINE)

	await _main.solo_begin_pass(carrier)

	assert_str(_log_text()) \
		.override_failure_message("fixture check: the pass must actually be applied locally:\n%s" % _log_text()) \
		.contains("Delayed Action: Wachtturm passes the turn")
	assert_int(_sent_containing("Delayed Action: Wachtturm passes the turn")) \
		.override_failure_message("the pass line never left this client — the opponent's log shows NACHTMAHR answering an activation that is not in their record (sent: %s)" % str(_sent_lines())) \
		.is_equal(1)


func test_a_refused_pass_says_so_on_both_screens(timeout := 120000) -> void:
	# Rules-must-log covers non-application: an opponent who only sees "nothing happened" cannot tell
	# a refused rule from a missing one. Here the carrier's side is NOT outnumbered, so the rule is
	# refused — with its reason.
	var carrier := _register(1, "Wachtturm", HUMAN_LINE)
	carrier.unit_properties["special_rules"] = ["Delayed Action"]
	_row(1, "Grenzer", 3, HUMAN_LINE)
	_row(2, "Nachtzehrer", 1, AI_LINE)

	await _main.solo_begin_pass(carrier)

	assert_str(_log_text()) \
		.override_failure_message("fixture check: the pass must be refused here:\n%s" % _log_text()) \
		.contains("Delayed Action: Wachtturm may not pass")
	assert_int(_sent_containing("Delayed Action: Wachtturm may not pass")) \
		.override_failure_message("the refusal stayed local — the opponent reads a refused rule as a missing one (sent: %s)" % str(_sent_lines())) \
		.is_equal(1)


func test_the_withdrawal_line_travels(timeout := 120000) -> void:
	# The Ambush family, second of the routed waves. The unit's disappearance is state (NML-945); the
	# reason it disappeared and the round it comes back are the line.
	var u := _register(1, "Raiders", HUMAN_LINE)
	u.unit_properties["special_rules"] = ["Ambush Re-Deployment"]
	_main.opr_army_manager.current_round = 2
	assert_bool(_main._solo_ambush_redeploy_execute(u)) \
		.override_failure_message("fixture check: the withdrawal must actually happen") \
		.is_true()
	assert_int(_sent_containing("Ambush Re-Deployment: Raiders leaves the table")) \
		.override_failure_message("the withdrawal line stayed local — the opponent's unit vanishes with no reason given (sent: %s)" % str(_sent_lines())) \
		.is_equal(1)


func test_an_offline_game_writes_the_line_and_sends_nothing(timeout := 120000) -> void:
	# Counter-proof: solo keeps working exactly as before.
	_fake.active = false
	var u := _register(1, "Raiders", HUMAN_LINE)
	u.unit_properties["special_rules"] = ["Ambush Re-Deployment"]
	_main.opr_army_manager.current_round = 2
	_main._solo_ambush_redeploy_execute(u)
	assert_str(_log_text()).contains("Ambush Re-Deployment: Raiders leaves the table")
	assert_array(_fake.sent) \
		.override_failure_message("an offline game put a log line on the wire") \
		.is_empty()


# === 5. EXCLUSION 1 — a line another channel already carries must not be routed =================

## Movement is the one thing that already travels, as per-unit DATA the receiver renders itself. If
## the rules channel carried the rendered line too, every move would appear twice in the opponent's
## log — which is precisely the failure main already learned from the dice hook.
func test_a_movement_summary_is_not_sent_twice(timeout := 120000) -> void:
	var walker := _register(1, "Walker", HUMAN_LINE)
	_main._on_battle_log_dropped([{"node": (walker.models[0] as ModelInstance).node, "arc_in": 5.0}])
	var move_frames := 0
	for e in _fake.sent:
		if str((e as Dictionary).get("m", "")) == "sync_move_log":
			move_frames += 1
	assert_int(move_frames) \
		.override_failure_message("fixture check: a drop must still ship its move summary (sent: %s)" % str(_fake.sent)) \
		.is_equal(1)
	assert_int(_sent_containing("Walker moves")) \
		.override_failure_message("the movement line was routed through the rules channel as well — the opponent would read every move twice (sent: %s)" % str(_sent_lines())) \
		.is_equal(0)


## The receiving half of the same guard: rendering an incoming move summary must not put anything
## back on the wire.
func test_rendering_a_received_move_summary_sends_nothing(timeout := 120000) -> void:
	var walker := _register(1, "Walker", HUMAN_LINE)
	_fake.sent.clear()
	_main._log_move_summaries([{"unit": walker.get_name(), "alive": 2, "count": 2, "max_in": 5.0, "whole": true}])
	assert_str(_log_text()) \
		.override_failure_message("fixture check: the received summary must still be rendered locally") \
		.contains("Walker")
	assert_array(_fake.sent) \
		.override_failure_message("rendering a peer's move summary put a line back on the wire (sent: %s)" % str(_fake.sent)) \
		.is_empty()


# === 6. EXCLUSION 3 — a prompt for the clicking player is not a rule event ======================

## The Coordinate mis-click correction answers the hand holding the mouse. It names no outcome and
## means nothing to anyone else, so it stays local by design — the selection is per call site, not
## "everything with a rule name in it".
func test_a_misclick_correction_stays_local(timeout := 120000) -> void:
	var bearer := _register(1, "Bearer", HUMAN_LINE)
	var stranger := _register(1, "Stranger", HUMAN_LINE + Vector3(0.0, 0.0, 0.4))
	_main._solo_target_mode = {"unit": bearer, "coordinate": true, "coord_valid": [], "cast_rings": []}
	await _main._solo_coordinate_click(stranger)
	assert_int(_logged_containing("cannot take the hand-off")) \
		.override_failure_message("fixture check: the mis-click must still be answered locally:\n%s" % _log_text()) \
		.is_equal(1)
	assert_int(_sent_containing("cannot take the hand-off")) \
		.override_failure_message("a prompt aimed at the clicking player was broadcast to the opponent (sent: %s)" % str(_sent_lines())) \
		.is_equal(0)


# === 7. the receiving half =====================================================================

func test_the_receiver_writes_the_line_and_does_not_echo(timeout := 120000) -> void:
	_main._on_remote_log_event(BattleLog.Category.GENERAL,
		"Delayed Action: Nachtzehrer1 passes the turn", true, "outnumbered")
	assert_int(_logged_containing("Nachtzehrer1 passes the turn")) \
		.override_failure_message("the peer's rules line never reached this log:\n%s" % _log_text()) \
		.is_equal(1)
	assert_array(_fake.sent) \
		.override_failure_message("the received line was sent straight back out (sent: %s)" % str(_fake.sent)) \
		.is_empty()


func test_the_entry_keeps_its_ai_flag_and_detail(timeout := 120000) -> void:
	# The entry travels whole, so the receiving panel's AI filter and its expandable reasoning behave
	# exactly like the local one.
	_main._on_remote_log_event(BattleLog.Category.COMBAT, "NACHTMAHR holds its fire", true, "no line of sight")
	var found := {}
	for e in _main.battle_log.entries():
		if str((e as Dictionary)["text"]) == "NACHTMAHR holds its fire":
			found = e as Dictionary
	assert_bool(found.is_empty()) \
		.override_failure_message("the line did not arrive at all") \
		.is_false()
	assert_int(int(found.get("category", -1))).is_equal(BattleLog.Category.COMBAT)
	assert_bool(bool(found.get("ai", false))) \
		.override_failure_message("the AI flag was dropped — the receiving panel's AI filter would hide the line") \
		.is_true()
	assert_str(str(found.get("detail", ""))).is_equal("no line of sight")


## The REAL RPC handler, the one _on_raw_command calls by name when the frame arrives.
func test_the_real_rpc_handler_puts_the_line_in_the_log(timeout := 120000) -> void:
	_real_net.sync_log_event(BattleLog.Category.GENERAL, "Coordinate: Alpha hands off to Beta", false, "")
	assert_int(_logged_containing("Coordinate: Alpha hands off to Beta")) \
		.override_failure_message("the wire frame did not reach the log through the real handler:\n%s" % _log_text()) \
		.is_equal(1)


func test_an_empty_line_is_not_put_on_the_wire(timeout := 120000) -> void:
	_main._log_rule_event(BattleLog.Category.GENERAL, "")
	assert_array(_fake.sent) \
		.override_failure_message("an empty line was put on the wire") \
		.is_empty()
	var before: int = _main.battle_log.entries().size()
	_main._on_remote_log_event(BattleLog.Category.GENERAL, "", false, "")
	assert_int(_main.battle_log.entries().size()) \
		.override_failure_message("an empty frame from a peer added a blank row to the log") \
		.is_equal(before)


# === 8. NML-961 — the placement ghost could not end its own wait ===============================
#
# _reinforcement_human_ghost opened a PlacementGhost and then waited on a local `done` flag that its
# two callbacks set. A GDScript lambda captures locals BY VALUE, so both callbacks wrote to a copy
# and the loop `while not done: await get_tree().process_frame` never exited. The ghost is only
# opened for a HUMAN unit in a non-headless game (main.gd:9921), so in play the player placed or
# cancelled, the ghost freed itself, and the round never started — a silent freeze with no error
# line. These two cases were written as the log-channel proof for the two lines that stay local
# (exclusion 3, a prompt aimed at the hand holding the mouse) and hit gdUnit's 120 s timeout
# instead. They are the red-green proof for the fix: both must pass, and pass FAST — a case that
# takes the full timeout means the loop is still spinning.


## A REAL OPRUnit profile: a runtime unit is built from one. Same shape as
## e2e_reinforcement_test.gd::_profile.
func _profile(unit_name: String, size: int, rules: Array) -> OPRApiClient.OPRUnit:
	var u := OPRApiClient.OPRUnit.new()
	u.name = unit_name
	u.size = size
	u.quality = 4
	u.defense = 4
	u.cost = 130
	u.base_size_round = 25
	u.base_width_mm = 25
	u.base_depth_mm = 25
	u.game_system = "gf"
	for r in rules:
		u.special_rules.append(str(r))
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Rusty Blade"
	w.attacks = 2
	u.weapons.append(w)
	return u


## A carrier standing on the table, built through the runtime factory rather than the lightweight
## fixture above: only a factory-built unit carries the metas the rule's own code reads back.
func _carrier(unit_name: String, count: int, pid: int = 1) -> GameUnit:
	var positions: Array = []
	for i in count:
		positions.append(Vector3(float(i) * 1.2 * OPRArmyManager.INCHES_TO_METERS, 0.0, 0.0))
	var u: GameUnit = _main.opr_army_manager.create_runtime_unit({
		"opr_unit": _profile(unit_name, count, ["Tough(1)", "Reinforcement"]),
		"faction_folder": "ratmen_clans",
	}, pid, positions, "spawn")
	assert_object(u).override_failure_message("fixture check: the carrier was not built").is_not_null()
	return u


## EXCLUSION 3 — the placement ghost. Headless _reinforcement_pick_spots skips the ghost entirely
## (main.gd:9921), so the human half is driven directly, exactly as it runs in a windowed game. The
## cancel is armed on a tree timer BEFORE the coroutine is awaited: calling an async function
## without await drops gdUnit's -d run into an interactive debug prompt that never returns.
func _drive_placement_ghost(u: GameUnit) -> void:
	var trect: Rect2 = _main._table_rect()
	var margin_m: float = SoloController.REINFORCEMENT_EDGE_IN * OPRArmyManager.INCHES_TO_METERS
	var radii: Array = []
	for i in u.models.size():
		radii.append(_main._reinforcement_model_radius(u, i))
	var blockers: Array = _main._reinforcement_blockers(u)
	var prefer: Vector3 = _main._reinforcement_prefer_point(u, trect)
	var auto_spots: Array = SoloController.reinforcement_spots(radii, trect, margin_m, blockers,
		prefer, OPRArmyManager.INCHES_TO_METERS)
	assert_array(auto_spots) \
		.override_failure_message("fixture check: no automatic spot, so the ghost is never opened") \
		.is_not_empty()
	get_tree().create_timer(0.2).timeout.connect(_cancel_open_ghost)
	await _main._reinforcement_human_ghost(u, radii, trect, margin_m, blockers, auto_spots)


## What ESC does: PlacementGhost._finish(false) -> the cancel callable -> the awaiting loop ends.
func _cancel_open_ghost() -> void:
	for c in _main.get_children():
		if c is PlacementGhost:
			(c as PlacementGhost)._finish(false)
			return


## "R rotates, Esc drops it" names two keys on one keyboard. Broadcasting it would tell the opponent
## to press keys that do nothing on their machine.
func test_the_placement_prompt_stays_local(timeout := 120000) -> void:
	var u := _carrier("Clan Rats", 2)
	await _drive_placement_ghost(u)
	assert_int(_logged_containing("R rotates, Esc drops it")) \
		.override_failure_message("fixture check: the prompt must be written locally:\n%s" % _log_text()) \
		.is_equal(1)
	assert_int(_sent_containing("R rotates, Esc drops it")) \
		.override_failure_message("a keyboard prompt for the local hand was broadcast to the opponent (sent: %s)" % str(_sent_lines())) \
		.is_equal(0)
	await E2EBoot.settle(get_tree())


## The cancel answer to that same prompt: the copy still arrives, only at the automatic spot. It is
## the mis-click correction of exclusion 3, one screen wide.
func test_the_cancelled_placement_line_stays_local(timeout := 120000) -> void:
	var u := _carrier("Clan Rats", 2)
	await _drive_placement_ghost(u)
	assert_int(_logged_containing("placement cancelled")) \
		.override_failure_message("fixture check: the cancel must be answered locally:\n%s" % _log_text()) \
		.is_equal(1)
	assert_int(_sent_containing("placement cancelled")) \
		.override_failure_message("a mis-click correction aimed at the local hand was broadcast (sent: %s)" % str(_sent_lines())) \
		.is_equal(0)
	await E2EBoot.settle(get_tree())
