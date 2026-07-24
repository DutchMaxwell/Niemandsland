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
		if _has_rule(w, "Strafing"):
			continue   # NML-002: "may only be used in this way" — fires via the move-through trigger only
		var attacks: int = maxi(_field_i(w, "attacks", 1), 0) * maxi(_field_i(w, "count", 1), 1)
		if attacks <= 0:
			continue
		out.append(_profile(w, attacks, rng_in))
	return out


## NML-002: the unit's Strafing weapon profiles (fired ONLY by the move-through trigger).
static func strafing_profiles(weapons: Array) -> Array:
	var out: Array = []
	for w in weapons:
		if not _has_rule(w, "Strafing"):
			continue
		var attacks: int = maxi(_field_i(w, "attacks", 1), 0) * maxi(_field_i(w, "count", 1), 1)
		if attacks <= 0:
			continue
		out.append(_profile(w, attacks, _field_i(w, "range_value", 0)))
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
		# X2: copies of this weapon in the unit — `attacks` is per-copy × count, and the strike scaler
		# needs the split to count LIVING bearers of special weapons (dead-bearer exploit, test game 2).
		"count": maxi(_field_i(w, "count", 1), 1),
		# Resolver wave A — Hazardous ("Gets AP(4), but this model's unit takes one wound on
		# unmodified rolls of 1 to hit"): the AP(4) grant folds into the profile AP here; the
		# self-wound half is counted at the hit-roll seams (each natural 1 wounds the firer's unit).
		"ap": maxi(_ap_of(w), 4) if _has_rule(w, "Hazardous") else _ap_of(w),
		"hazardous": _has_rule(w, "Hazardous"),
		"deadly": _rating_of(w, "Deadly"),
		"relentless": _has_rule(w, "Relentless"),
		"blast": _rating_of(w, "Blast"),
		"reliable": _has_rule(w, "Reliable"),
		# NML-002 Strafing (weapon rule): "This weapon may only be used in this way" — the flag
		# EXCLUDES it from every normal volley; the move-through trigger fires it separately.
		"strafing": _has_rule(w, "Strafing"),
		# Coverage wave: weapon-level cover negation ("Ignores Cover" / "… when Shooting") — the
		# save step then uses the uncovered Defense, like Blast/Indirect.
		"ignores_cover": _has_rule(w, "Ignores Cover"),
		"precise": _has_rule(w, "Precise"),   # army-book weapon rule: +1 to hit when attacking
		# Wave-2 weapon rules (GF/AoF Advanced Rules v3.5.1): Surge (+1 hit per unmodified 6, any range),
		# Rending (unmodified 6-to-hit → AP(+4) on those hits), Bane (defender re-rolls unmodified Defense
		# 6s), Thrust (charging melee → +1 to hit and AP(+1)). Pre-parsed here like the wave-1 facets so the
		# resolution helpers read booleans, not strings.
		"surge": _has_rule(w, "Surge"),
		"rending": _has_rule(w, "Rending"),
		# Bane (defender re-rolls unmodified Defense 6s). Lacerate (AoF Advanced v3.5.1) is worded
		# identically ("when attacking the target must re-roll unmodified Defense results of 6"), so it is
		# a straight data-alias of Bane — see special-rules-coverage-plan (alias table). AoF's most common
		# weapon rule (168×/10 factions), so aliasing it here is the single biggest coverage down-payment.
		"bane": _has_rule(w, "Bane") or _has_rule(w, "Lacerate"),
		"thrust": _has_rule(w, "Thrust"),
		# Wave-3 (GF/AoF v3.5.1 p.13): Counter — the weapon strikes first when its bearer is charged and
		# reduces the charger's Impact rolls; drives the strike-first phase + the Counter-last activation.
		"counter": _has_rule(w, "Counter"),
		# Wave-4 army-book weapon rule (Robot Legions / Mummified Undead — official Army Forge text:
		# "On unmodified results of 6 to hit, those hits get AP(+4)."). Identical to Rending's AP(+4) facet
		# but WITHOUT Rending's Regeneration-bypass — so Destructive wounds stay Regeneration-able.
		"destructive": _has_rule(w, "Destructive"),
		# Wave-5 weapon rules (parameter knobs live in the RulesRegistry mechanics maps; these facets
		# are the raw "the weapon carries it" flags): Shred (unmodified Defense 1 → +1 wound), Indirect
		# (-1 to hit when shooting after moving; ignores LOS + cover from sight obstructions; solo
		# overlay: hold & shoot), Limited (once per game — SoloController tracks the expenditure).
		"shred": _has_rule(w, "Shred"),
		"indirect": _has_rule(w, "Indirect"),
		"limited": _has_rule(w, "Limited"),
		# Takedown (GF v3.5.1 p.14): the model may pick ANY model in the target unit as its individual
		# target, resolved as a unit of [1], before other weapons (Bug 25). The flag routes its wounds
		# to a chosen model instead of the pooled defender-optimal removal.
		"takedown": _has_rule(w, "Takedown"),
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
