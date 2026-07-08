class_name AiCombatMath
extends RefCounted
## Solo-AI M2 — pure OPR (Solo/Co-Op v3.5.0 core) combat resolution math. No dice are rolled here; these
## take the FACES that were physically rolled in the dice tray and turn them into hits / wounds / morale
## outcomes, so shooting, melee and morale share one tested rule core. Headless-testable.
##
## OPR core rules encoded:
##   - To-hit: roll one die per Attack; a result >= the attacker's Quality is a hit.
##   - Saves:  the defender rolls one die per hit; a result >= its Defense blocks the hit. AP(X) worsens
##             the save by X (the die must be X higher), i.e. the effective target is Defense + AP.
##   - Morale: roll one die; >= Quality passes. On a fail the unit is Shaken; a unit that fails while at
##             or below half strength Routs (is removed / flees).

enum Morale { PASSED, SHAKEN, ROUT }


## Hits from the attacker's to-hit roll: faces >= Quality (Quality is "better is lower", e.g. 3+).
static func count_hits(faces: Array, quality: int) -> int:
	return DiceRules.count_successes(_ints(faces), quality, 0)


## Coerce an untyped face array to the Array[int] DiceRules expects (callers pass plain [6,3,…] arrays).
static func _ints(faces: Array) -> Array[int]:
	var out: Array[int] = []
	for f in faces:
		out.append(int(f))
	return out


## The defender's save target after AP: a die must reach Defense + AP to block (higher AP = harder save).
static func save_target(defense: int, armor_piercing: int) -> int:
	return defense + maxi(armor_piercing, 0)


## Blocked hits from the defender's save roll: faces >= (Defense + AP).
static func count_blocks(save_faces: Array, defense: int, armor_piercing: int) -> int:
	return DiceRules.count_successes(_ints(save_faces), save_target(defense, armor_piercing), 0)


## Wounds that get through = hits the defender failed to save, never negative.
static func wounds(hit_count: int, save_faces: Array, defense: int, armor_piercing: int) -> int:
	return maxi(0, hit_count - count_blocks(save_faces, defense, armor_piercing))


## A unit is "at or below half" when its alive count has dropped to <= half its starting size (the OPR
## morale trigger threshold). Guards a zero/empty start.
static func at_or_below_half(alive: int, total: int) -> bool:
	if total <= 0:
		return true
	return alive * 2 <= total


## OPR rule gap (goal 003 P1): a unit tests morale after SHOOTING only if it took casualties this volley
## AND is now at half strength or less. Pure predicate behind the solo shooting-morale trigger. A wiped
## unit (alive_now <= 0) is gone, not routed here; no casualties (alive_now unchanged) → no test.
static func should_test_shooting_morale(alive_before: int, alive_now: int, total: int) -> bool:
	if alive_now <= 0 or alive_now >= alive_before:
		return false
	return at_or_below_half(alive_now, total)


## Resolve a morale test from the single rolled face. at_or_below_half decides Shaken vs Rout on a fail.
static func morale_result(face: int, quality: int, is_at_or_below_half: bool) -> Morale:
	if DiceRules.is_success(face, quality, 0):
		return Morale.PASSED
	return Morale.ROUT if is_at_or_below_half else Morale.SHAKEN
