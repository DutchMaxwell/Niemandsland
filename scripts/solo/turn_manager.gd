class_name TurnManager
extends Node
## Solo/AI turn engine (Phase 0). Drives OnePageRules alternating activation: one unit per side
## in turn, and when a side runs out of eligible units the other side keeps activating until the
## round is exhausted, then the round advances. Two sides only for now — HUMAN (a player slot) and
## AI (the Solo opponent slot). This is the AUTHORITATIVE turn state for strict enforcement: the
## input layer asks `can_activate(unit)` before letting the human act, and the SoloController acts
## when `activation_required(AI)` fires.
##
## It is deliberately decoupled from GameUnit: all board access goes through an injected `delegate`
## (duck-typed) so the engine is pure, headless-testable logic. The production adapter wraps
## OPRArmyManager/GameUnit; tests pass a stub. The delegate must implement:
##   units() -> Array                  # all participating units (both sides)
##   slot_of(unit) -> int              # the unit's player slot
##   is_eligible(unit) -> bool         # alive AND not yet activated this round
##   mark_activated(unit) -> void      # record that the unit has activated
##   reset_round() -> void             # clear every unit's activation for a new round
##
## Engine-agnostic: no ruleset specifics live here (no archetypes, no combat). Phase 1 adds the
## OPR section-split unit selection and Shaken-last / Counter-after ordering on top.

# === Constants / enums ===

enum Side { HUMAN, AI }
enum State { IDLE, HUMAN_ACTIVATION, AI_ACTIVATION, ROUND_END, GAME_OVER }

# === Signals ===

## The active side changed (a new activation is expected from `side`).
signal turn_changed(side: int)
## `side` must now activate exactly one eligible unit (the SoloController listens for AI).
signal activation_required(side: int)
## A new round began (1-based).
signal round_advanced(round_number: int)
## No side has any eligible unit at round start — the game cannot continue.
signal game_over()

# === Public state ===

var current_round: int = 0

# === Private variables ===

var _delegate = null
var _human_slot: int = 1
var _ai_slot: int = 2
var _state: int = State.IDLE
var _active_side: int = Side.HUMAN
var _round_starting_side: int = Side.HUMAN

# === Public API ===

## Wire the engine to its board delegate and the two player slots. Call once before start_game().
func configure(human_slot: int, ai_slot: int, delegate) -> void:
	_human_slot = human_slot
	_ai_slot = ai_slot
	_delegate = delegate


## Begin the game at round 1 with the HUMAN side starting, and enter the first activation.
func start_game() -> void:
	assert(_delegate != null, "TurnManager.start_game() before configure()")
	current_round = 0
	_round_starting_side = Side.HUMAN
	_begin_round()


func active_side() -> int:
	return _active_side


func state() -> int:
	return _state


## True when `unit` is allowed to activate right now: we're in an activation state, the unit
## belongs to the active side's slot, and it is still eligible. The input layer gates on this.
func can_activate(unit) -> bool:
	if _state != State.HUMAN_ACTIVATION and _state != State.AI_ACTIVATION:
		return false
	if _delegate.slot_of(unit) != _slot_for_side(_active_side):
		return false
	return _delegate.is_eligible(unit)


## The eligible (alive, not-yet-activated) units belonging to `side`.
func eligible_units(side: int) -> Array:
	var slot: int = _slot_for_side(side)
	var result: Array = []
	for unit in _delegate.units():
		if _delegate.slot_of(unit) == slot and _delegate.is_eligible(unit):
			result.append(unit)
	return result


func has_eligible(side: int) -> bool:
	return not eligible_units(side).is_empty()


func is_round_over() -> bool:
	return not has_eligible(Side.HUMAN) and not has_eligible(Side.AI)


## Record that `unit` completed its activation and advance the turn. Strictly ignored if the unit
## isn't a legal activation right now (wrong side / already activated / not in an activation state),
## so an off-turn or duplicate call can't desync the engine.
func notify_activated(unit) -> void:
	if not can_activate(unit):
		return
	_delegate.mark_activated(unit)
	_advance()

# === Private ===

func _begin_round() -> void:
	_delegate.reset_round()
	current_round += 1
	round_advanced.emit(current_round)
	var starter: int = _round_starting_side
	if not has_eligible(starter):
		starter = _opposite(starter)
	if not has_eligible(starter):
		_state = State.GAME_OVER
		game_over.emit()
		return
	_enter_activation(starter)


func _enter_activation(side: int) -> void:
	_active_side = side
	_state = State.HUMAN_ACTIVATION if side == Side.HUMAN else State.AI_ACTIVATION
	turn_changed.emit(side)
	activation_required.emit(side)


func _advance() -> void:
	var other: int = _opposite(_active_side)
	if has_eligible(other):
		_enter_activation(other)            # normal alternation
	elif has_eligible(_active_side):
		_enter_activation(_active_side)     # other side exhausted — keep going
	else:
		_end_round()


func _end_round() -> void:
	_state = State.ROUND_END
	_round_starting_side = _opposite(_round_starting_side)  # alternate who starts next round
	_begin_round()


func _slot_for_side(side: int) -> int:
	return _human_slot if side == Side.HUMAN else _ai_slot


func _opposite(side: int) -> int:
	return Side.AI if side == Side.HUMAN else Side.HUMAN
