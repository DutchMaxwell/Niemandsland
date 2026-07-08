class_name SoloSim
extends RefCounted
## Headless AI-vs-AI game simulator (goal 003 — self-play stage 0). Plays a whole game with NO UI: no
## dice tray, no prompts, no camera — dice come from a SEEDED RNG and every combat/decision uses the SAME
## pure modules the real game uses (AiArchetype, AiDecision, AiShooting, AiCombatMath). That shared logic
## IS the correctness link to the real game: given the same board + the same dice faces, the outcome is
## identical (the modules are unit-tested). What differs is only the dice SOURCE (RNG vs physics tray) and
## the board model — v1 is 1D (an open approach axis), no terrain/objectives yet (those drive stage 2+).
##
## A unit is a plain Dictionary (see make_unit). Deterministic: same seed → same game.

const TABLE_IN := 48.0        # 4 ft approach axis
const DEPLOY_IN := 12.0       # deploy zones sit 12" from each edge
const CONTACT_IN := 2.0       # melee contact tolerance (matches the game's charge contact)
const DEFAULT_ROUNDS := 4     # OPR standard game length


## Build a sim unit. weapons: Array of dicts shaped like OPR weapons
## ({name, range_value, attacks, count, special_rules:["AP(1)"]}). Melee weapons use range_value 0.
static func make_unit(name: String, player: int, quality: int, defense: int, models: int, weapons: Array,
		tough: int = 1, rules: Array = [], advance_in: float = 6.0, rush_in: float = 12.0) -> Dictionary:
	return {
		"name": name, "player": player, "quality": quality, "defense": defense,
		"tough": maxi(tough, 1), "max_models": models, "wounds_pool": 0,
		"weapons": weapons, "rules": rules,
		"pos": DEPLOY_IN if player == 0 else (TABLE_IN - DEPLOY_IN),
		"advance_in": advance_in, "rush_in": rush_in,
		"activated": false, "shaken": false, "fatigued": false,
	}


static func alive_models(u: Dictionary) -> int:
	return maxi(0, int(u["max_models"]) - int(u["wounds_pool"]) / int(u["tough"]))


static func is_alive(u: Dictionary) -> bool:
	return alive_models(u) > 0


## Play one full game. Returns a result Dictionary; if `log_lines` is given, human-readable events are
## appended to it (used by the runner). Deterministic in `seed_value`.
static func simulate_game(army_a: Array, army_b: Array, seed_value: int, max_rounds: int = DEFAULT_ROUNDS,
		log_lines: Array = []) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var units: Array = []
	for u in army_a:
		units.append((u as Dictionary).duplicate(true))
	for u in army_b:
		units.append((u as Dictionary).duplicate(true))
	var a_start := _side_models(units, 0)
	var b_start := _side_models(units, 1)
	var activations := 0
	var end_reason := "round_limit"
	var round_no := 0
	for r in range(1, max_rounds + 1):
		round_no = r
		for u in units:
			u["activated"] = false
		log_lines.append("── Round %d ──" % r)
		# Alternating activations: side 0 acts one unit, then side 1, … until both are out of units.
		var side := 0
		while _has_unactivated(units, 0) or _has_unactivated(units, 1):
			if _has_unactivated(units, side):
				var actor: Variant = _next_unactivated(units, side)
				if actor != null:
					activations += 1
					_activate(actor, units, rng, log_lines)
			side = 1 - side
		# End of round: OPR fatigue lasts only until the round ends.
		for u in units:
			u["fatigued"] = false
		if _side_models(units, 0) == 0 or _side_models(units, 1) == 0:
			end_reason = "wipe"
			break
	var a_alive := _side_models(units, 0)
	var b_alive := _side_models(units, 1)
	var winner := -1
	if a_alive > b_alive:
		winner = 0
	elif b_alive > a_alive:
		winner = 1
	return {
		"winner": winner, "rounds": round_no, "end_reason": end_reason,
		"a_alive": a_alive, "b_alive": b_alive, "a_start": a_start, "b_start": b_start,
		"a_losses": a_start - a_alive, "b_losses": b_start - b_alive, "activations": activations,
	}


# === Activation (mirrors SoloController._act on a 1D board) ===

static func _activate(unit: Dictionary, units: Array, rng: RandomNumberGenerator, log_lines: Array) -> void:
	unit["activated"] = true
	# OPR: a Shaken unit that activates must stay Idle and stops being Shaken.
	if unit["shaken"]:
		unit["shaken"] = false
		log_lines.append("%s recovers from Shaken (idle)" % unit["name"])
		return
	var target: Variant = _nearest_enemy(unit, units)
	if target == null:
		return
	var weapons: Array = unit["weapons"]
	var archetype: int = AiArchetype.classify(weapons)
	var shoot_range: int = AiArchetype.max_range_inches(weapons)
	var dist: float = absf(float(unit["pos"]) - float(target["pos"]))
	var in_range: bool = shoot_range > 0 and dist <= float(shoot_range)   # 1D open field: LOS always clear
	var action: int = AiDecision.decide(archetype, dist, float(unit["advance_in"]),
		float(unit["rush_in"]), float(shoot_range), in_range)
	log_lines.append("%s: %s (%.0f\" to %s)" % [unit["name"], AiDecision.action_name(action), dist, target["name"]])
	var dir: float = signf(float(target["pos"]) - float(unit["pos"]))
	match action:
		AiDecision.Action.ADVANCE:
			_move(unit, dir * float(unit["advance_in"]))
		AiDecision.Action.RUSH:
			_move(unit, dir * float(unit["rush_in"]))
		AiDecision.Action.CHARGE:
			# Charge into contact: never overshoot the enemy.
			_move(unit, dir * minf(float(unit["rush_in"]), maxf(dist - CONTACT_IN, 0.0)))
		AiDecision.Action.KITE:
			var room: float = maxf(float(shoot_range) - dist, 0.0)
			_move(unit, -dir * minf(float(unit["advance_in"]), room))
		_:
			pass   # HOLD
	dist = absf(float(unit["pos"]) - float(target["pos"]))
	if action == AiDecision.Action.CHARGE and dist <= CONTACT_IN + 0.001:
		_resolve_melee(unit, target, rng, log_lines)
	elif action in [AiDecision.Action.ADVANCE, AiDecision.Action.KITE, AiDecision.Action.HOLD] \
			and shoot_range > 0 and dist <= float(shoot_range):
		_resolve_shooting(unit, target, dist, rng, log_lines)


# === Combat resolution (uses AiShooting + AiCombatMath, dice from the seeded RNG) ===

static func _resolve_shooting(attacker: Dictionary, target: Dictionary, dist: float,
		rng: RandomNumberGenerator, log_lines: Array) -> void:
	var profiles: Array = AiShooting.profiles_in_range(attacker["weapons"], dist)
	if profiles.is_empty():
		return
	var alive_before := alive_models(target)
	var quality: int = int(attacker["quality"])
	var total := 0
	for p in profiles:
		var profile := p as Dictionary
		var faces := _roll(rng, int(profile["attacks"]))
		var hits := AiCombatMath.count_hits(faces, quality)
		if hits <= 0:
			continue
		var save_faces := _roll(rng, hits)
		total += AiCombatMath.wounds(hits, save_faces, int(target["defense"]), int(profile["ap"]))
	if total > 0:
		_apply_wounds(target, total)
		log_lines.append("%s shoots %s → %d wound(s)" % [attacker["name"], target["name"], total])
	# Post-shooting morale: casualties AND now at/below half.
	if AiCombatMath.should_test_shooting_morale(alive_before, alive_models(target), int(target["max_models"])):
		_morale(target, rng, log_lines)


static func _resolve_melee(attacker: Dictionary, target: Dictionary, rng: RandomNumberGenerator,
		log_lines: Array) -> void:
	var dealt := _strike(attacker, target, rng)
	if dealt > 0:
		_apply_wounds(target, dealt)
	var struck_back := 0
	if is_alive(target):
		struck_back = _strike(target, attacker, rng)
		if struck_back > 0:
			_apply_wounds(attacker, struck_back)
	attacker["fatigued"] = true
	target["fatigued"] = true
	log_lines.append("%s charges %s → %d dealt, %d back" % [attacker["name"], target["name"], dealt, struck_back])
	# The side that took MORE wounds tests morale.
	if dealt > struck_back and is_alive(target):
		_morale(target, rng, log_lines)
	elif struck_back > dealt and is_alive(attacker):
		_morale(attacker, rng, log_lines)


## One striker's melee output. OPR: a Fatigued unit hits only on 6s (to-hit 6), else its Quality.
static func _strike(striker: Dictionary, defender: Dictionary, rng: RandomNumberGenerator) -> int:
	var profiles: Array = AiShooting.melee_profiles(striker["weapons"])
	var to_hit: int = 6 if bool(striker["fatigued"]) else int(striker["quality"])
	var total := 0
	for p in profiles:
		var profile := p as Dictionary
		var faces := _roll(rng, int(profile["attacks"]))
		var hits := AiCombatMath.count_hits(faces, to_hit)
		if hits <= 0:
			continue
		var save_faces := _roll(rng, hits)
		total += AiCombatMath.wounds(hits, save_faces, int(defender["defense"]), int(profile["ap"]))
	return total


static func _morale(unit: Dictionary, rng: RandomNumberGenerator, log_lines: Array) -> void:
	var face: int = int(_roll(rng, 1)[0])
	var below := AiCombatMath.at_or_below_half(alive_models(unit), int(unit["max_models"]))
	var result: int = AiCombatMath.morale_result(face, int(unit["quality"]), below)
	match result:
		AiCombatMath.Morale.PASSED:
			log_lines.append("%s passes morale" % unit["name"])
		AiCombatMath.Morale.SHAKEN:
			unit["shaken"] = true
			log_lines.append("%s is Shaken" % unit["name"])
		AiCombatMath.Morale.ROUT:
			unit["wounds_pool"] = int(unit["max_models"]) * int(unit["tough"])   # wiped
			log_lines.append("%s ROUTS (destroyed)" % unit["name"])


static func _apply_wounds(unit: Dictionary, w: int) -> void:
	unit["wounds_pool"] = int(unit["wounds_pool"]) + maxi(w, 0)


# === Helpers ===

static func _roll(rng: RandomNumberGenerator, n: int) -> Array:
	var faces: Array = []
	for i in range(maxi(n, 0)):
		faces.append(rng.randi_range(1, 6))
	return faces


static func _move(unit: Dictionary, delta_in: float) -> void:
	unit["pos"] = clampf(float(unit["pos"]) + delta_in, 0.0, TABLE_IN)


static func _nearest_enemy(unit: Dictionary, units: Array) -> Variant:
	var best: Variant = null
	var best_d := INF
	for u in units:
		if u["player"] == unit["player"] or not is_alive(u):
			continue
		var d: float = absf(float(unit["pos"]) - float(u["pos"]))
		if d < best_d:
			best_d = d
			best = u
	return best


static func _side_models(units: Array, player: int) -> int:
	var n := 0
	for u in units:
		if u["player"] == player:
			n += alive_models(u)
	return n


static func _has_unactivated(units: Array, player: int) -> bool:
	for u in units:
		if u["player"] == player and is_alive(u) and not bool(u["activated"]):
			return true
	return false


static func _next_unactivated(units: Array, player: int) -> Variant:
	for u in units:
		if u["player"] == player and is_alive(u) and not bool(u["activated"]):
			return u
	return null
