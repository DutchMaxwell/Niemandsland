class_name DiceRules
extends RefCounted
## OPR success evaluation and reroll selection for the dice tray — a display-only
## aid: the tool counts successes and picks which dice a chosen reroll affects,
## the players decide whether a rule entitles them to it.
##
## OPR GF/AoF Core Rules v3.5.1, p.1 "Quality Tests": "Roll one six-sided die,
## and if you score the model's quality value or higher, then it counts as a
## success." Defense rolls work the same way against the Defense value (p.1
## "Shooting"). Pure/static so it is trivially testable (see LosRules).

# === Constants ===

## No success target selected — rolls are shown without success evaluation.
const TARGET_NONE := 0
## Valid success targets ("2+" .. "6+"), matching the Quality/Defense stat range.
const TARGET_MIN := 2
const TARGET_MAX := 6
## UI bounds for the roll modifier. OPR itself has NO modifier cap (AP(4),
## Artillery -2 and stacking spell tokens all exceed +/-1; the natural-6/1 rule
## is the only safety valve), but beyond +/-5 every die is decided by that rule
## anyway, so the selector does not need a wider range.
const MODIFIER_MIN := -5
const MODIFIER_MAX := 5
## D6 face range; the natural extremes carry rule meaning (see is_success).
const FACE_MIN := 1
const FACE_MAX := 6

## Which dice of the previous roll a reroll re-tosses. FAILURES needs a success
## target; SIXES covers forced rerolls of unmodified 6s (OPR GF Core Rules
## v3.5.1, p.2 "Bane": "...when attacking the target must re-roll unmodified
## Defense rolls of 6." — named "Poison" up to v3.4.x).
enum RerollMode { FAILURES, ONES, SIXES, ALL }

## Marks a roll that is not a reroll in roll-context dictionaries.
const REROLL_NONE := -1

## Keys of the roll-context Dictionary shared between the local evaluation,
## the dice log and the multiplayer broadcast.
const CTX_TARGET := "target"
const CTX_MODIFIER := "modifier"
const CTX_REROLL_MODE := "reroll_mode"
const CTX_REROLL_COUNT := "reroll_count"

# === Public (static) ===


## True if a die face passes the success target under a modifier.
## OPR GF/AoF Core Rules v3.5.1, p.1 "Modifiers": "Regardless of modifiers,
## rolls of 6 always succeed, and rolls of 1 always fail."
static func is_success(face: int, target: int, modifier: int) -> bool:
	if target == TARGET_NONE:
		return false
	if face >= FACE_MAX:
		return true
	if face <= FACE_MIN:
		return false
	return face + modifier >= target


## Number of successes in a roll (0 when no target is selected).
static func count_successes(faces: Array[int], target: int, modifier: int) -> int:
	var successes := 0
	for face: int in faces:
		if is_success(face, target, modifier):
			successes += 1
	return successes


## Indices of the dice a reroll mode re-tosses, given the previous faces.
## FAILURES without a selected target returns no indices (nothing is a
## "failure" while nothing is being tested).
static func reroll_indices(faces: Array[int], mode: RerollMode, target: int, modifier: int) -> Array[int]:
	var indices: Array[int] = []
	for i: int in faces.size():
		var face: int = faces[i]
		var picked := false
		match mode:
			RerollMode.FAILURES:
				picked = target != TARGET_NONE and not is_success(face, target, modifier)
			RerollMode.ONES:
				picked = face <= FACE_MIN
			RerollMode.SIXES:
				picked = face >= FACE_MAX
			RerollMode.ALL:
				picked = true
		if picked:
			indices.append(i)
	return indices


## Short log tag for a reroll mode ("fails", "1s", "6s", "all").
static func reroll_mode_label(mode: int) -> String:
	match mode:
		RerollMode.FAILURES:
			return "fails"
		RerollMode.ONES:
			return "1s"
		RerollMode.SIXES:
			return "6s"
		RerollMode.ALL:
			return "all"
	return ""
