class_name AiShooting
extends RefCounted
## Solo-AI M2 (goal 001 P3) — pure shooting-plan logic. Given a unit's weapons and the distance to the
## chosen target, build the list of RANGED profiles that can fire: one entry per weapon profile with its
## total attack count (attacks × count) and its AP value. The resolution loop rolls each profile as one
## batch (to-hit at the unit's Quality, then the defender saves at Defense + that profile's AP) — the
## OPR-legal grouping of identical weapons. Melee weapons (range 0) never shoot. Headless-testable.


## Ranged weapon profiles able to reach `dist_in`: [{name: String, attacks: int, ap: int}].
## Accepts OPRWeapon objects or plain {range_value, attacks, count, special_rules} dicts.
static func profiles_in_range(weapons: Array, dist_in: float) -> Array:
	var out: Array = []
	for w in weapons:
		var rng_in: int = _field_i(w, "range_value", 0)
		if rng_in <= 0 or float(rng_in) < dist_in:
			continue
		var attacks: int = maxi(_field_i(w, "attacks", 1), 0) * maxi(_field_i(w, "count", 1), 1)
		if attacks <= 0:
			continue
		out.append({
			"name": _field_s(w, "name", "Weapon"),
			"attacks": attacks,
			"ap": _ap_of(w),
		})
	return out


## Total dice a shooting activation would roll (quick eligibility check for the decision tree).
static func total_attacks(profiles: Array) -> int:
	var n := 0
	for p in profiles:
		n += int((p as Dictionary).get("attacks", 0))
	return n


# === Field access (OPRWeapon object OR dict) ===

static func _ap_of(w: Variant) -> int:
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
