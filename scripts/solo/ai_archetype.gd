class_name AiArchetype
extends RefCounted
## Solo-AI M2 — classify a unit's fighting style from its weapons, the first input to the OPR Solo/Co-Op
## v3.5.0 per-unit decision trees. A weapon with range_value == 0 is melee, > 0 is ranged (opr_api_client
## OPRWeapon). We compare total ranged vs melee attack VOLUME so a unit's real threat, not just its weapon
## count, drives the choice. Pure + deterministic (headless-testable per the solo test conventions).

enum Type { MELEE, SHOOTING, HYBRID }


## Classify from an array of weapons per the OPR Solo & Co-Op rules (p.1 "Unit Types"): MELEE = no ranged
## weapon at all; otherwise HYBRID if the best MELEE weapon is "better than" the best RANGED weapon, else
## SHOOTING. "Better than" is left undefined by the rules — we score a weapon by attacks × (1 + AP), taking
## the strongest weapon on each side; a tie goes to SHOOTING (a ranged weapon also has reach). This fixes
## the old attack-VOLUME heuristic that wrongly called a rifle-and-basic-CCW squad "Hybrid".
static func classify(weapons: Array) -> Type:
	var best_ranged: float = -1.0
	var best_melee: float = -1.0
	for w in weapons:
		var s: float = _weapon_strength(w)
		if _range(w) > 0:
			best_ranged = maxf(best_ranged, s)
		else:
			best_melee = maxf(best_melee, s)
	if best_ranged < 0.0:
		return Type.MELEE          # no ranged weapon
	if best_melee < 0.0:
		return Type.SHOOTING       # no melee weapon
	return Type.HYBRID if best_melee > best_ranged else Type.SHOOTING


## A weapon's "better than" score: attacks × (1 + AP). Higher AP and more attacks = stronger.
static func _weapon_strength(w: Variant) -> float:
	return float(maxi(_attacks(w), 0)) * (1.0 + float(_ap(w)))


static func _ap(w: Variant) -> int:
	var rules: Array = []
	if w is Object and (w as Object).get("special_rules") != null:
		rules = (w as Object).special_rules
	elif w is Dictionary:
		rules = (w as Dictionary).get("special_rules", [])
	for r in rules:
		var s := str(r).strip_edges()
		if s.begins_with("AP(") and s.ends_with(")"):
			return int(s.substr(3, s.length() - 4).replace("+", ""))
	return 0


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
