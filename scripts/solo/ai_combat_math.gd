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

# ===== Constants (each cites its OPR source) =====

## The unmodified maximum d6 face — the trigger for the "on a 6" weapon rules (Surge / Furious / Rending),
## and the guaranteed-block face Bane forces the defender to re-roll (GF/AoF Advanced Rules v3.5.1: "rolls
## of 6 always succeed"). Named so the 6-face rules read the same constant.
const UNMODIFIED_SIX: int = 6

## Impact(X) hit target (GF/AoF Advanced Rules v3.5.1, p.13): "Roll X dice when attacking after charging,
## unless fatigued. For each 2+ the target takes one hit."
const IMPACT_HIT_TARGET: int = 2

## Fearless recovery target (GF/AoF Advanced Rules v3.5.1, p.13): "When a unit where all models have this
## rule fails a morale test, roll one die. On a 4+ it counts as passed instead."
const FEARLESS_RECOVER_TARGET: int = 4

## Rending armour-piercing bonus (GF/AoF Advanced Rules v3.5.1, p.14): "on unmodified results of 6 to hit,
## those hits get AP(+4)."
const RENDING_AP_BONUS: int = 4

## Thrust armour-piercing bonus (GF/AoF Advanced Rules v3.5.1, p.14): "When charging, gets +1 to hit rolls
## and AP(+1) in melee."
const THRUST_AP_BONUS: int = 1

## Thrust to-hit bonus (GF/AoF Advanced Rules v3.5.1, p.14): the "+1 to hit" a charging Thrust weapon gets.
const THRUST_TO_HIT_BONUS: int = 1

## Best achievable to-hit target after positive modifiers: a natural 1 always misses, so 2+ is the ceiling
## (GF/AoF Advanced Rules v3.5.1, p.1 "Modifiers": "rolls of 1 always fail").
const BEST_HIT_TARGET: int = 2


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


## Count of unmodified 6s among a to-hit roll — the shared trigger for Surge / Furious (extra hits) and
## Rending (AP upgrade). "Unmodified" means the raw die face, so this reads the faces as rolled.
static func unmodified_sixes(faces: Array) -> int:
	var n := 0
	for f in faces:
		if int(f) == UNMODIFIED_SIX:
			n += 1
	return n


## Extra hits Surge adds (GF/AoF Advanced Rules v3.5.1, p.14: "On unmodified results of 6 to hit, this
## weapon deals 1 extra hit."). Unlike Relentless there is NO range condition — it applies to shooting AND
## melee — so this needs only the faces. One extra hit per unmodified 6.
static func surge_bonus_hits(faces: Array) -> int:
	return unmodified_sixes(faces)


## Extra hits Furious adds (GF/AoF Advanced Rules v3.5.1, p.14: "When charging, unmodified results of 6 to
## hit in melee deal 1 extra hit."). Melee only, and only for the CHARGING unit — 0 when not charging.
static func furious_bonus_hits(faces: Array, is_charging: bool) -> int:
	return unmodified_sixes(faces) if is_charging else 0


## How many of a volley's hits Rending upgrades to AP(+4) (GF/AoF Advanced Rules v3.5.1, p.14: "on
## unmodified results of 6 to hit, those hits get AP(+4)."). One per unmodified 6, capped at the hits
## actually scored so a hit-reduction can never create phantom Rending hits. Every 6 is itself a hit, so
## without Blast this equals the count of 6s.
static func rending_ap_hits(faces: Array, total_hits: int) -> int:
	return mini(unmodified_sixes(faces), maxi(total_hits, 0))


## Impact hits (GF/AoF Advanced Rules v3.5.1, p.13: "Roll X dice when attacking after charging, unless
## fatigued. For each 2+ the target takes one hit."). Takes the X pre-rolled charge dice and scores 2+.
static func impact_hits(faces: Array) -> int:
	return count_hits(faces, IMPACT_HIT_TARGET)


## Charging to-hit target for a Thrust weapon (GF/AoF Advanced Rules v3.5.1, p.14: "+1 to hit rolls ... in
## melee" when charging). +1 to hit lowers the needed face by one, clamped at the 2+ ceiling; unchanged
## when not charging. Fatigue is handled by the caller (a fatigued unit hits only on unmodified 6s, so
## Thrust's modifier does not apply then).
static func thrust_to_hit(quality: int, is_charging: bool) -> int:
	return maxi(BEST_HIT_TARGET, quality - THRUST_TO_HIT_BONUS) if is_charging else quality


## Whether a Fearless re-roll rescues a FAILED morale test (GF/AoF Advanced Rules v3.5.1, p.13: on a failed
## test, "roll one die. On a 4+ it counts as passed instead."). True when the single re-roll die is a 4+.
static func fearless_recovers(reroll_face: int) -> bool:
	return DiceRules.is_success(reroll_face, FEARLESS_RECOVER_TARGET, 0)


## Fear(X) adjusted wound total for the who-won-melee check ONLY (GF/AoF Advanced Rules v3.5.1, p.13: "This
## model counts as having dealt +X wounds when checking who won melee."). Never changes the wounds actually
## applied — only the winner comparison. Returns caused + X (X floored at 0).
static func fear_adjusted_wounds(caused: int, fear_x: int) -> int:
	return maxi(caused, 0) + maxi(fear_x, 0)


## Number of unmodified Defense 6s in a save roll — the dice Bane forces the defender to re-roll (GF/AoF
## Advanced Rules v3.5.1, p.13: "the target must re-roll unmodified Defense results of 6.").
static func bane_reroll_count(save_faces: Array) -> int:
	return unmodified_sixes(save_faces)


## Blocked hits after the attacker's Bane forces the defender to re-roll unmodified Defense 6s (GF/AoF
## Advanced Rules v3.5.1, p.13). A natural 6 always blocks, so Bane strips those guaranteed saves: each save
## face of 6 is replaced by the next `reroll_faces` value (one per 6, in order). "A die roll may only be
## re-rolled once, so if another 6 is rolled after re-rolling Defense, then the hit is blocked." — a
## re-rolled 6 therefore stays a block. Returns the block count of the post-re-roll faces at Defense + AP.
## With no 6s (or no re-roll faces) this equals count_blocks(save_faces, defense, armor_piercing).
static func blocks_with_bane(save_faces: Array, reroll_faces: Array, defense: int, armor_piercing: int) -> int:
	var combined: Array = []
	var ri := 0
	for f in save_faces:
		if int(f) == UNMODIFIED_SIX:
			combined.append(int(reroll_faces[ri]) if ri < reroll_faces.size() else UNMODIFIED_SIX)
			ri += 1
		else:
			combined.append(int(f))
	return count_blocks(combined, defense, armor_piercing)


## Blast(X) hits (GF Advanced Rules v3.5.1: "Ignores cover, and after resolving other special rules, each
## hit is multiplied by X, where X is up to as many hits as models in the target unit." — the rulebook's
## example: 2 hits with Blast(3) vs 2 models → each hit ×2 → 4 hits). The multiplier is min(X, target
## models); the cover-ignore facet is the caller's side (it modifies the save target, not the hits).
static func blast_hits(hit_count: int, blast_x: int, target_models: int) -> int:
	if hit_count <= 0:
		return 0
	if blast_x <= 1:
		return hit_count
	return hit_count * clampi(blast_x, 1, maxi(target_models, 1))


## Reliable to-hit quality (GF Advanced Rules v3.5.1: the weapon "shoots at Quality 2+").
static func reliable_quality(quality: int, is_reliable: bool) -> int:
	return mini(quality, 2) if is_reliable else quality


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
