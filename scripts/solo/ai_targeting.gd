class_name AiTargeting
extends RefCounted
## Solo-AI M2 — pure target-selection overlays from the official OPR Solo & Co-Op Rules v3.5.0 (p.2,
## "SPECIAL RULES"), verified verbatim against the PDF (GF - Solo & Co-Op Rules v3.5.0, 2026-07-09).
##
## Base rule (Solo p.2 "Shooting" / "Melee"): pick the NEAREST valid target, prioritising units that
## haven't activated yet; and for shooting, prefer a target in the OPEN over one in cover. Certain weapon
## special rules OVERRIDE which target is chosen FIRST:
##   • AP       — "always target enemies with the best defensive value first" → highest Defense.
##   • Deadly   — "always target single-model units with Tough first, and units with Tough second,
##                 prioritizing those with the lowest total remaining Tough."
##   • Takedown — "always target heroes first, and models with upgrades second, prioritizing those with
##                 the most expensive upgrade." (The sim has no per-model upgrade cost, so only the
##                 'heroes first' tier is modelled — flagged in docs/SOLO_AI_RULES_COVERAGE.md.)
##
## Different weapon TYPES may each pick their own target under their own overlay — that is exactly OPR
## split-fire (core rules p.8: "you may split a unit's attacks between different targets by weapon type").
## Pure + deterministic (headless-testable per the solo test conventions).

enum Overlay { NONE, AP, DEADLY, TAKEDOWN }


## The dominant targeting overlay implied by one weapon's special rules. A weapon can carry several (e.g.
## AP *and* Deadly); the Solo rules do not define precedence, so we pick the MOST SPECIFIC overlay —
## Takedown (snipe a model) > Deadly (finish Tough) > AP (crack armour). This ordering is a documented
## tie-break, NOT an official rule (see the coverage doc); most weapons carry only one of the three.
static func weapon_overlay(special_rules: Array) -> Overlay:
	var has_ap := false
	var has_deadly := false
	var has_takedown := false
	for r in special_rules:
		var s := str(r).strip_edges()
		if s.begins_with("Takedown"):
			has_takedown = true
		elif s.begins_with("Deadly"):
			has_deadly = true
		elif s.begins_with("AP"):
			has_ap = true
	if has_takedown:
		return Overlay.TAKEDOWN
	if has_deadly:
		return Overlay.DEADLY
	if has_ap:
		return Overlay.AP
	return Overlay.NONE


## Index of the preferred target in `candidates` under `overlay`, or -1 if empty. Each candidate is a
## descriptor Dictionary with these keys (all present):
##   dist            : float  — distance from the attacker (nearer = better, the base tie-break)
##   activated       : bool   — already activated this round (not-yet-activated is preferred)
##   in_cover        : bool   — the majority of its models sit in cover (open is preferred, shooting)
##   defense         : int    — Defense value (AP overlay: highest first)
##   is_hero         : bool   — carries the Hero rule (Takedown overlay: first)
##   has_upgrade     : bool   — carries a costed upgrade (Takedown overlay: second) [not modelled → false]
##   upgrade_cost    : int    — most-expensive upgrade cost (Takedown tie) [not modelled → 0]
##   single_tough    : bool   — single-model unit WITH Tough (Deadly overlay: first)
##   has_tough       : bool   — carries Tough (Deadly overlay: second)
##   remaining_tough : int    — total remaining Tough pool (Deadly tie: lowest first)
## Deterministic: on a full tie the earliest (lowest-index) candidate wins.
static func best_index(candidates: Array, overlay: int) -> int:
	if candidates.is_empty():
		return -1
	var best := 0
	var best_key: Array = _key(candidates[0] as Dictionary, overlay)
	for i in range(1, candidates.size()):
		var key: Array = _key(candidates[i] as Dictionary, overlay)
		if _less(key, best_key):
			best = i
			best_key = key
	return best


## Indices of every candidate whose official sort key EQUALS the best one's — a GENUINE tie, where the
## official rules would roll a die; the caller may rank the tied set by a utility metric instead (the
## hybrid policy, docs/SOLO_AI_PLAN.md). Additive API: best_index and the key ordering are unchanged
## (the sim's behaviour is untouched).
static func tied_with_best(candidates: Array, overlay: int, best_i: int) -> Array:
	if best_i < 0 or best_i >= candidates.size():
		return []
	var best_key: Array = _key(candidates[best_i] as Dictionary, overlay)
	var out: Array = []
	for i in range(candidates.size()):
		var k: Array = _key(candidates[i] as Dictionary, overlay)
		if not _less(k, best_key) and not _less(best_key, k):
			out.append(i)
	return out


## Sort key (an array of numbers, lower is better, compared lexicographically) for one candidate under an
## overlay. The last three entries are always the base tie-break: not-activated, in-the-open, then nearest.
static func _key(c: Dictionary, overlay: int) -> Array:
	var base: Array = [
		1.0 if bool(c.get("activated", false)) else 0.0,
		1.0 if bool(c.get("in_cover", false)) else 0.0,
		float(c.get("dist", 0.0)),
	]
	match overlay:
		Overlay.AP:
			return [-float(c.get("defense", 0))] + base   # highest Defense first
		Overlay.DEADLY:
			var cls := 0 if bool(c.get("single_tough", false)) else (1 if bool(c.get("has_tough", false)) else 2)
			var rt := float(c.get("remaining_tough", 0)) if bool(c.get("has_tough", false)) else 0.0
			return [float(cls), rt] + base   # single-Tough, then Tough (lowest remaining), then the rest
		Overlay.TAKEDOWN:
			var tier := 0 if bool(c.get("is_hero", false)) else (1 if bool(c.get("has_upgrade", false)) else 2)
			return [float(tier), -float(c.get("upgrade_cost", 0))] + base   # heroes, then costed upgrades
		_:
			return base


## Lexicographic "a is strictly better (lower) than b" over two equal-length numeric key arrays.
static func _less(a: Array, b: Array) -> bool:
	for i in range(mini(a.size(), b.size())):
		var av := float(a[i])
		var bv := float(b[i])
		if av < bv - 0.0000001:
			return true
		if av > bv + 0.0000001:
			return false
	return false
