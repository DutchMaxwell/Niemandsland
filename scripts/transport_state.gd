class_name TransportState
extends RefCounted
## Transport(X) — the PURE capacity/eligibility core of the transport wave (NML-105 S1,
## design settled with the maintainer 2026-07-22). Implements the GF/AoF Advanced Rules
## v3.5.1 wording exactly (PDF-verified):
##
##   "May transport up to X models or Heroes with up to Tough(6), and non-Heroes with up to
##    Tough(3) which occupy 3 spaces each. [...] Regular models and Heroes with Tough(3) or
##    Tough(6) occupy 1 space, Tough(3) models occupy 3 spaces, and models with Tough(6) or
##    higher can't be transported."
##
## Space math per MODEL (from the rule + its example):
##   - Hero, Tough ≤ 6            → 1 space
##   - Hero, Tough > 6            → untransportable
##   - non-Hero, no Tough         → 1 space (a "regular model")
##   - non-Hero, Tough 2..5       → 3 spaces (the book names Tough(3); 2..5 read "up to Tough(3)"-class,
##                                  matching Army Forge data where such profiles are always Tough(3))
##   - non-Hero, Tough ≥ 6        → untransportable
##
## Everything here is static + side-effect free: callers describe models as plain Dictionaries
## {"hero": bool, "tough": int} so the math is unit-testable without scene plumbing. The live
## GameUnit adapters live with the embark state wiring, not here.

const UNTRANSPORTABLE := -1   # spaces_of() sentinel: this model may never embark

## Spaces one model occupies inside a transport, or UNTRANSPORTABLE.
## `tough` = the model's Tough rating (0 or 1 = no meaningful Tough — a regular 1-wound model).
static func spaces_of(hero: bool, tough: int) -> int:
	var t := maxi(tough, 0)
	if hero:
		return 1 if t <= 6 else UNTRANSPORTABLE
	if t >= 6:
		return UNTRANSPORTABLE
	if t >= 2:
		return 3
	return 1


## Total spaces a model list occupies, or UNTRANSPORTABLE if ANY model can never embark
## (the unit embarks as a whole — one untransportable model keeps the whole unit out).
## models = [{"hero": bool, "tough": int}, ...]
static func spaces_of_models(models: Array) -> int:
	var total := 0
	for m in models:
		var md := m as Dictionary
		var s := spaces_of(bool(md.get("hero", false)), int(md.get("tough", 0)))
		if s == UNTRANSPORTABLE:
			return UNTRANSPORTABLE
		total += s
	return total


## Whether a unit (as model dicts) fits into `capacity` spaces of which `used` are already taken.
static func fits(models: Array, capacity: int, used: int = 0) -> bool:
	var need := spaces_of_models(models)
	if need == UNTRANSPORTABLE:
		return false
	return used + need <= capacity


## Parse the X of a "Transport(X)" rule string list; 0 when the unit is no transport.
## Accepts the raw special_rules array (strings or {"name": ...} dicts — both shapes exist in
## imported unit_properties).
static func capacity_of_rules(rules: Array) -> int:
	for r in rules:
		var s := ""
		if r is String:
			s = r
		elif r is Dictionary:
			s = str((r as Dictionary).get("name", ""))
		s = s.strip_edges()
		if s.begins_with("Transport"):
			var open := s.find("(")
			var close := s.find(")")
			if open >= 0 and close > open:
				return maxi(0, int(s.substr(open + 1, close - open - 1)))
	return 0


## Parse a model's Tough rating out of its special_rules-style array ("Tough(3)" → 3; 0 without).
static func tough_of_rules(rules: Array) -> int:
	for r in rules:
		var s := ""
		if r is String:
			s = r
		elif r is Dictionary:
			s = str((r as Dictionary).get("name", ""))
		s = s.strip_edges()
		if s.begins_with("Tough"):
			var open := s.find("(")
			var close := s.find(")")
			if open >= 0 and close > open:
				return maxi(0, int(s.substr(open + 1, close - open - 1)))
	return 0
