class_name AiShooting
extends RefCounted
## Solo-AI M2 (goal 001 P3) — pure shooting-plan logic. Given a unit's weapons and the distance to the
## chosen target, build the list of RANGED profiles that can fire: one entry per weapon profile with its
## total attack count (attacks × count) and its AP value. The resolution loop rolls each profile as one
## batch (to-hit at the unit's Quality, then the defender saves at Defense + that profile's AP) — the
## OPR-legal grouping of identical weapons. Melee weapons (range 0) never shoot. Headless-testable.


## Ranged weapon profiles able to reach `dist_in`: one entry per weapon type carrying its total attacks and
## the special-rule facets the combat/targeting layers need. Accepts OPRWeapon objects or plain
## {range_value, attacks, count, special_rules} dicts.
##   {name, attacks, ap, deadly (X, 0 = none), relentless (bool), range (inches), rules (raw special_rules)}
static func profiles_in_range(weapons: Array, dist_in: float) -> Array:
	var out: Array = []
	for w in weapons:
		var rng_in: int = _field_i(w, "range_value", 0)
		if rng_in <= 0 or float(rng_in) < dist_in:
			continue
		var attacks: int = maxi(_field_i(w, "attacks", 1), 0) * maxi(_field_i(w, "count", 1), 1)
		if attacks <= 0:
			continue
		out.append(_profile(w, attacks, rng_in))
	return out


## MELEE weapon profiles (range 0) — same shape as profiles_in_range (range 0, never Relentless), for the
## melee resolution: each profile rolls as one batch; the defender saves at Defense + that profile's AP.
static func melee_profiles(weapons: Array) -> Array:
	var out: Array = []
	for w in weapons:
		if _field_i(w, "range_value", 0) > 0:
			continue
		var attacks: int = maxi(_field_i(w, "attacks", 1), 0) * maxi(_field_i(w, "count", 1), 1)
		if attacks <= 0:
			continue
		out.append(_profile(w, attacks, 0))
	return out


## Build one profile dict from a weapon, its resolved total attacks, and its range (inches).
static func _profile(w: Variant, attacks: int, range_in: int) -> Dictionary:
	return {
		"name": _field_s(w, "name", "Weapon"),
		"attacks": attacks,
		"ap": _ap_of(w),
		"deadly": _rating_of(w, "Deadly"),
		"relentless": _has_rule(w, "Relentless"),
		"blast": _rating_of(w, "Blast"),
		"reliable": _has_rule(w, "Reliable"),
		"range": range_in,
		"rules": _rules_of(w),
	}


## Total dice a shooting activation would roll (quick eligibility check for the decision tree).
static func total_attacks(profiles: Array) -> int:
	var n := 0
	for p in profiles:
		n += int((p as Dictionary).get("attacks", 0))
	return n


# === Field access (OPRWeapon object OR dict) ===

## Raw special-rule strings of a weapon (e.g. ["AP(1)", "Deadly(3)", "Relentless"]).
static func _rules_of(w: Variant) -> Array:
	if w is Object and (w as Object).get("special_rules") != null:
		return (w as Object).special_rules
	if w is Dictionary:
		return (w as Dictionary).get("special_rules", [])
	return []


static func _ap_of(w: Variant) -> int:
	return _rating_of(w, "AP")


## Rating X of a "Name(X)" special rule (0 if the rule is absent; the leading + of "Deadly(+3)" is stripped).
static func _rating_of(w: Variant, rule_name: String) -> int:
	var prefix := rule_name + "("
	for r in _rules_of(w):
		var s := str(r).strip_edges()
		if s.begins_with(prefix) and s.ends_with(")"):
			return int(s.substr(prefix.length(), s.length() - prefix.length() - 1).replace("+", ""))
	return 0


## Whether a weapon carries a flag-style special rule (no rating), e.g. "Relentless" / "Takedown".
static func _has_rule(w: Variant, rule_name: String) -> bool:
	for r in _rules_of(w):
		if str(r).strip_edges().begins_with(rule_name):
			return true
	return false


static func _field_i(w: Variant, field: String, fallback: int) -> int:
	if w is Object and (w as Object).get(field) != null:
		return int((w as Object).get(field))
	if w is Dictionary:
		return int((w as Dictionary).get(field, fallback))
	return fallback


static func _field_s(w: Variant, field: String, fallback: String) -> String:
	if w is Object and (w as Object).get(field) != null:
		return str((w as Object).get(field))
	if w is Dictionary:
		return str((w as Dictionary).get(field, fallback))
	return fallback
