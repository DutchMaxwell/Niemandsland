class_name AiArchetype
extends RefCounted
## Solo-AI M2 — classify a unit's fighting style from its weapons, the first input to the OPR Solo/Co-Op
## v3.5.0 per-unit decision trees. A weapon with range_value == 0 is melee, > 0 is ranged (opr_api_client
## OPRWeapon). We compare total ranged vs melee attack VOLUME so a unit's real threat, not just its weapon
## count, drives the choice. Pure + deterministic (headless-testable per the solo test conventions).

enum Type { MELEE, SHOOTING, HYBRID }

## Ratio at/above which one attack pool "dominates" the other → that single archetype instead of Hybrid.
const DOMINANCE := 2.0


## Classify from an array of weapons — each either an OPRWeapon or a {range_value, attacks} dict.
static func classify(weapons: Array) -> Type:
	var melee_attacks: int = 0
	var ranged_attacks: int = 0
	for w in weapons:
		var atk: int = maxi(_attacks(w), 0)
		if _range(w) <= 0:
			melee_attacks += atk
		else:
			ranged_attacks += atk
	if ranged_attacks <= 0:
		return Type.MELEE
	if melee_attacks <= 0:
		return Type.SHOOTING
	if float(ranged_attacks) >= float(melee_attacks) * DOMINANCE:
		return Type.SHOOTING
	if float(melee_attacks) >= float(ranged_attacks) * DOMINANCE:
		return Type.MELEE
	return Type.HYBRID


## Whether the unit has at least one ranged weapon (used by the decision tree to know it CAN shoot).
static func has_ranged(weapons: Array) -> bool:
	for w in weapons:
		if _range(w) > 0:
			return true
	return false


## The longest ranged weapon range in inches (0 if the unit is melee-only) — the shooting decision tree's
## "am I in range" threshold.
static func max_range_inches(weapons: Array) -> int:
	var best: int = 0
	for w in weapons:
		best = maxi(best, _range(w))
	return best


# === Weapon field access (OPRWeapon object OR plain dict) ===

static func _range(w: Variant) -> int:
	if w is Object and (w as Object).get("range_value") != null:
		return int((w as Object).range_value)
	if w is Dictionary:
		return int((w as Dictionary).get("range_value", 0))
	return 0


static func _attacks(w: Variant) -> int:
	if w is Object and (w as Object).get("attacks") != null:
		return int((w as Object).attacks)
	if w is Dictionary:
		return int((w as Dictionary).get("attacks", 1))
	return 1
