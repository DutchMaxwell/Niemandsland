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


## Probability a single d6 meets a success target (goal 003 P2 — the "expected damage" AI metric). OPR:
## a face >= target succeeds, but a 6 ALWAYS succeeds and a 1 ALWAYS fails, so the chance is bounded to
## [1/6, 5/6]: target <= 2 → 5/6 (only a 1 fails), target >= 6 → 1/6 (only a 6 saves the impossible-looking
## roll). = (7 - clamp(target, 2, 6)) / 6.
static func success_chance(target: int) -> float:
	return float(7 - clampi(target, 2, 6)) / 6.0


## Expected wounds one weapon profile deals to a target (goal 003 P2 metric): attacks × P(hit at Quality)
## × P(the save at Defense+AP fails). Deterministic, no dice — the AI sums this across its profiles per
## candidate target and picks the target that maximises it (the officially-undefined "better than" step,
## locked to expected damage).
static func expected_wounds(attacks: int, quality: int, defense: int, armor_piercing: int) -> float:
	if attacks <= 0:
		return 0.0
	var p_hit := success_chance(quality)
	var p_through := 1.0 - success_chance(save_target(defense, armor_piercing))
	return float(attacks) * p_hit * p_through


## Extra hits Relentless adds (GF Advanced Rules v3.5.1, p.14): "When this model shoots at enemies over 9"
## away, unmodified results of 6 to hit deal 1 extra hit." So each unmodified 6 among the to-hit faces adds
## one hit — but only when the shot is over 9". Returns 0 at 9" or closer. (Shooting only; not melee.)
static func relentless_bonus_hits(faces: Array, dist_in: float) -> int:
	if dist_in <= 9.0:
		return 0
	var sixes := 0
	for f in faces:
		if int(f) == 6:
			sixes += 1
	return sixes


## Damage multiplier for a Deadly(X) weapon against a target (GF Advanced Rules v3.5.1, p.13 + the "Deadly
## Weapons" clarification, p.10): each unsaved wound is multiplied by X and assigned to one model, but a
## Deadly weapon "may only deal up to as many wounds as the Tough value of the majority of models in the
## unit; if the majority don't have Tough, it only deals 1 wound." In the pooled sim every model of a unit
## shares one Tough, so the cap is that Tough (or 1 for a non-Tough unit). Returns >= 1.
static func deadly_multiplier(deadly_x: int, target_tough: int) -> int:
	var cap: int = maxi(target_tough, 1)
	return clampi(deadly_x, 1, cap)


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
