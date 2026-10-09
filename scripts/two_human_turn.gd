class_name TwoHumanTurn
extends RefCounted
## Pure turn state for enforced alternation between two players (rules-automation plan 2.T1).
## One unit per side in turn; a side with no eligible unit is skipped and the other side keeps
## activating (the OPR TAIL); when neither side has an eligible unit the round is over; the side
## that did NOT take the round's last activation opens the next round (GF/AoF v3.5.1 "Rounds,
## Turns & Activations"). No scene access: the caller passes the eligible-unit counts as a
## Dictionary {slot: int}, read AFTER the activation being reported.
##
## Not wired into the game yet. TurnManager is dormant in solo and alternation_next is solo-only
## (one human, one AI), so neither is touched.

const NONE: int = -1

var slot_a: int = 1
var slot_b: int = 2
## The slot whose turn it is, or NONE before start_round() / after the round is over.
var side_on_turn: int = NONE

var _last_activator: int = NONE


func _init(p_slot_a: int = 1, p_slot_b: int = 2) -> void:
	slot_a = p_slot_a
	slot_b = p_slot_b


func other(slot: int) -> int:
	return slot_b if slot == slot_a else slot_a


## Begin a round. `opener` is given by the caller for round 1 and by next_round_opener() after
## that. A wiped opener yields to the other side; NONE when neither side has a unit.
func start_round(opener: int, eligible_counts: Dictionary) -> void:
	_last_activator = NONE
	if _count(eligible_counts, opener) > 0:
		side_on_turn = opener
	elif _count(eligible_counts, other(opener)) > 0:
		side_on_turn = other(opener)
	else:
		side_on_turn = NONE


## Only the side on turn may activate.
func can_activate(slot: int) -> bool:
	return side_on_turn != NONE and slot == side_on_turn


## Record that `slot` activated (counts are post-activation) and return the next side on turn:
## the other side if it has units, else `slot` again (TAIL), else NONE (round over). A refused
## out-of-turn call changes nothing and returns the unchanged side on turn.
func after_activation(slot: int, eligible_counts: Dictionary) -> int:
	if not can_activate(slot):
		return side_on_turn
	_last_activator = slot
	if _count(eligible_counts, other(slot)) > 0:
		side_on_turn = other(slot)
	elif _count(eligible_counts, slot) > 0:
		side_on_turn = slot
	else:
		side_on_turn = NONE
	return side_on_turn


func round_over(eligible_counts: Dictionary) -> bool:
	return _count(eligible_counts, slot_a) <= 0 and _count(eligible_counts, slot_b) <= 0


## The slot that opens the next round: the one that did NOT take this round's last activation
## (NONE if nobody activated).
func next_round_opener() -> int:
	return NONE if _last_activator == NONE else other(_last_activator)


func _count(eligible_counts: Dictionary, slot: int) -> int:
	return int(eligible_counts.get(slot, 0))
