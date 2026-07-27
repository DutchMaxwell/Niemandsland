extends GdUnitTestSuite
## Solo/AI turn engine (Phase 0): alternating activation, side-exhaustion, strict can_activate
## gating, round reset, and starting-side alternation. Pure logic over a stub delegate — no
## GameUnit, no rendering.

const TMScript := preload("res://scripts/solo/turn_manager.gd")


## A minimal board unit for the engine: a slot + alive/activated flags.
class FakeUnit:
	extends RefCounted
	var id: String
	var slot: int
	var alive: bool = true
	var activated: bool = false
	func _init(p_id: String, p_slot: int) -> void:
		id = p_id
		slot = p_slot


## Stub board delegate over a flat list of FakeUnits.
class StubDelegate:
	extends RefCounted
	var units_arr: Array = []
	func units() -> Array:
		return units_arr
	func slot_of(unit) -> int:
		return unit.slot
	func is_eligible(unit) -> bool:
		return unit.alive and not unit.activated
	func mark_activated(unit) -> void:
		unit.activated = true
	func reset_round() -> void:
		for unit in units_arr:
			unit.activated = false


func _mk(id: String, slot: int) -> FakeUnit:
	return FakeUnit.new(id, slot)


func _tm(delegate) -> TurnManager:
	var tm: TurnManager = auto_free(TMScript.new())
	add_child(tm)
	tm.configure(1, 2, delegate)
	return tm


## Activate the first eligible unit of the currently active side; returns it.
func _activate_active(tm: TurnManager) -> FakeUnit:
	var units: Array = tm.eligible_units(tm.active_side())
	var unit: FakeUnit = units[0]
	tm.notify_activated(unit)
	return unit


# === alternation ===

func test_even_sides_alternate_then_round_advances() -> void:
	var d := StubDelegate.new()
	d.units_arr = [_mk("h1", 1), _mk("h2", 1), _mk("a1", 2), _mk("a2", 2)]
	var tm := _tm(d)
	tm.start_game()
	assert_int(tm.current_round).is_equal(1)
	var seq: Array = []
	var guard := 0
	while tm.current_round == 1 and guard < 20:
		seq.append(tm.active_side())
		_activate_active(tm)
		guard += 1
	# 2 per side, strictly alternating, then the round rolls over to 2.
	assert_array(seq).is_equal([TurnManager.Side.HUMAN, TurnManager.Side.AI,
		TurnManager.Side.HUMAN, TurnManager.Side.AI])
	assert_int(tm.current_round).is_equal(2)


func test_uneven_sides_exhausted_side_yields() -> void:
	var d := StubDelegate.new()
	# 1 human, 3 AI: after H,A the human is spent, so the AI continues alone.
	d.units_arr = [_mk("h1", 1), _mk("a1", 2), _mk("a2", 2), _mk("a3", 2)]
	var tm := _tm(d)
	tm.start_game()
	var seq: Array = []
	var guard := 0
	while tm.current_round == 1 and guard < 20:
		seq.append(tm.active_side())
		_activate_active(tm)
		guard += 1
	assert_array(seq).is_equal([TurnManager.Side.HUMAN, TurnManager.Side.AI,
		TurnManager.Side.AI, TurnManager.Side.AI])


# === strict can_activate gate ===

func test_can_activate_only_active_side_and_eligible() -> void:
	var d := StubDelegate.new()
	var h1 := _mk("h1", 1)
	var a1 := _mk("a1", 2)
	d.units_arr = [h1, a1]
	var tm := _tm(d)
	tm.start_game()  # HUMAN starts
	assert_bool(tm.can_activate(h1)).is_true()    # active side, eligible
	assert_bool(tm.can_activate(a1)).is_false()   # off-turn (AI)
	tm.notify_activated(h1)
	assert_bool(tm.can_activate(h1)).is_false()   # already activated
	assert_bool(tm.can_activate(a1)).is_true()    # now the AI's turn


func test_off_turn_notify_is_ignored() -> void:
	var d := StubDelegate.new()
	var h1 := _mk("h1", 1)
	var a1 := _mk("a1", 2)
	d.units_arr = [h1, a1]
	var tm := _tm(d)
	tm.start_game()
	tm.notify_activated(a1)  # AI unit on the human's turn — must be a no-op
	assert_bool(a1.activated).is_false()
	assert_int(tm.active_side()).is_equal(TurnManager.Side.HUMAN)


# === round reset & starting-side alternation ===

func test_round_resets_activation_and_alternates_starter() -> void:
	var d := StubDelegate.new()
	d.units_arr = [_mk("h1", 1), _mk("a1", 2)]
	var tm := _tm(d)
	tm.start_game()
	assert_int(tm.active_side()).is_equal(TurnManager.Side.HUMAN)  # round 1 starts HUMAN
	_activate_active(tm)  # human
	_activate_active(tm)  # ai -> round 2 begins
	assert_int(tm.current_round).is_equal(2)
	assert_int(tm.active_side()).is_equal(TurnManager.Side.AI)     # round 2 starts AI
	# Activations were reset for the new round.
	assert_bool(tm.has_eligible(TurnManager.Side.HUMAN)).is_true()
	assert_bool(tm.has_eligible(TurnManager.Side.AI)).is_true()


# === degenerate boards ===

func test_one_empty_side_runs_only_the_other() -> void:
	var d := StubDelegate.new()
	d.units_arr = [_mk("h1", 1), _mk("h2", 1)]  # no AI units at all
	var tm := _tm(d)
	tm.start_game()
	var seq: Array = []
	var guard := 0
	while tm.current_round == 1 and guard < 20:
		seq.append(tm.active_side())
		_activate_active(tm)
		guard += 1
	assert_array(seq).is_equal([TurnManager.Side.HUMAN, TurnManager.Side.HUMAN])


func test_no_units_is_game_over() -> void:
	var d := StubDelegate.new()
	d.units_arr = []
	var tm := _tm(d)
	var fired := [false]
	tm.game_over.connect(func() -> void: fired[0] = true)
	tm.start_game()
	assert_bool(fired[0]).is_true()
	assert_int(tm.state()).is_equal(TurnManager.State.GAME_OVER)
