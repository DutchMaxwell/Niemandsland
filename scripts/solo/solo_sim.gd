class_name SoloSim
extends RefCounted
## Headless AI-vs-AI game simulator (goal 003 — self-play). Plays a whole game with NO UI: no dice tray,
## no prompts, no camera — dice come from a SEEDED RNG and every combat/decision uses the SAME pure
## modules the real game uses (AiArchetype, AiDecision, AiShooting, AiCombatMath). That shared logic IS
## the correctness link to the real game.
##
## Board: 2D 4×4 ft table, 12" deployment zones, two mission objectives. NO terrain yet (open field, LOS
## always clear). Rules verified against the official GF Advanced Rules v3.5.1 rulebook (2026-07-08):
##  • Actions (p.7): Hold (no move, may shoot) / Advance (6", may shoot) / Rush (12", no shoot) /
##    Charge (12" into melee).
##  • Shooting (p.8) & Melee (p.9): sum attacks of models in range → roll to hit at Quality → defender
##    rolls to block at Defense → unblocked = wounds. Melee: defender may strike back; the loser (more
##    wounds taken) tests morale (p.10). Fatigue (p.9): after its first melee in a round a unit hits only
##    on unmodified 6s in melee.
##  • Shaken (p.10): a Shaken unit stays IDLE when activated (recovering at the end of that activation);
##    it may strike back COUNTING AS FATIGUED, ALWAYS fails morale tests, and can't seize or contest
##    objectives. (No stat penalty — an earlier web-sourced "-1 Q/D, half move" reading was wrong.)
##  • Morale (p.10): test at the end of an activation where wounds leave a unit at ≤ half; the melee loser
##    tests. Fail + ≤ half size → Rout (destroyed), else Shaken. There is NO end-of-round army morale.
##  • Mission (p.6): seize a marker at the END OF EACH ROUND with a unit within 3" and no enemy within 3";
##    a seized marker STAYS seized when the unit leaves; both sides within 3" → neutral. After 4 rounds
##    the player controlling most markers wins (you never win purely by wiping the enemy).
##
## A unit is a plain Dictionary (see make_unit). Deterministic: same seed → same game.

const BOARD_IN := 48.0
const DEPLOY_IN := 12.0
const CONTACT_IN := 2.0
const OBJECTIVE_CONTROL_IN := 3.0
const DEFAULT_ROUNDS := 4


static func default_objectives() -> Array:
	return [Vector2(BOARD_IN / 3.0, BOARD_IN / 2.0), Vector2(BOARD_IN * 2.0 / 3.0, BOARD_IN / 2.0)]


static func make_unit(name: String, player: int, quality: int, defense: int, models: int, weapons: Array,
		tough: int = 1, rules: Array = [], advance_in: float = 6.0, rush_in: float = 12.0) -> Dictionary:
	return {
		"name": name, "player": player, "quality": quality, "defense": defense,
		"tough": maxi(tough, 1), "max_models": models, "wounds_pool": 0,
		"weapons": weapons, "rules": rules,
		"pos": Vector2.ZERO,
		"advance_in": advance_in, "rush_in": rush_in,
		"activated": false, "shaken": false, "fatigued": false,
	}


static func units_from_opr_json(data: Dictionary, player: int) -> Array:
	var out: Array = []
	for u in data.get("units", []):
		var unit := u as Dictionary
		var rule_names: Array = []
		var tough := 1
		for r in unit.get("rules", []):
			var rn := str((r as Dictionary).get("name", ""))
			rule_names.append(rn)
			if rn == "Tough":
				tough = maxi(int((r as Dictionary).get("rating", 1)), 1)
		var weapons: Array = []
		for w in unit.get("loadout", []):
			var wd := w as Dictionary
			if not wd.has("attacks"):
				continue
			var ap := 0
			for sr in wd.get("specialRules", []):
				if str((sr as Dictionary).get("name", "")) == "AP":
					ap = int((sr as Dictionary).get("rating", 0))
			weapons.append({
				"name": str(wd.get("name", "Weapon")),
				"range_value": int(wd.get("range", 0)),
				"attacks": int(wd.get("attacks", 1)),
				"count": maxi(int(wd.get("count", 1)), 1),
				"special_rules": (["AP(%d)" % ap] if ap > 0 else []),
			})
		out.append(make_unit(str(unit.get("name", "Unit")), player, int(unit.get("quality", 4)),
			int(unit.get("defense", 4)), maxi(int(unit.get("size", 1)), 1), weapons, tough, rule_names))
	return out


static func alive_models(u: Dictionary) -> int:
	return maxi(0, int(u["max_models"]) - int(u["wounds_pool"]) / int(u["tough"]))


static func is_alive(u: Dictionary) -> bool:
	return alive_models(u) > 0


static func simulate_game(army_a: Array, army_b: Array, seed_value: int, max_rounds: int = DEFAULT_ROUNDS,
		log_lines: Array = [], objectives: Array = []) -> Dictionary:
	var objs: Array = objectives if not objectives.is_empty() else default_objectives()
	var obj_owner: Array = []
	for _o in objs:
		obj_owner.append(-1)   # -1 = neutral / unseized
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var units: Array = []
	for u in army_a:
		units.append((u as Dictionary).duplicate(true))
	for u in army_b:
		units.append((u as Dictionary).duplicate(true))
	_deploy(units)
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
		# OPR: the deployment roll-off winner goes first on round 1, then the player who finished first
		# activates first each round. We roll off each round (a fixed first player was a systematic bias
		# the mirror test caught).
		var side := rng.randi_range(0, 1)
		while _has_unactivated(units, 0) or _has_unactivated(units, 1):
			if _has_unactivated(units, side):
				var actor: Variant = _next_unactivated(units, side)
				if actor != null:
					activations += 1
					_activate(actor, units, rng, log_lines)
			side = 1 - side
		# End of round: fatigue clears; then objectives are (re)seized.
		for u in units:
			u["fatigued"] = false
		_seize_objectives(units, objs, obj_owner, log_lines)
		if _side_models(units, 0) == 0 or _side_models(units, 1) == 0:
			end_reason = "wipe"
			break
	var a_alive := _side_models(units, 0)
	var b_alive := _side_models(units, 1)
	var a_obj := obj_owner.count(0)
	var b_obj := obj_owner.count(1)
	# Mission decides the winner (you never win purely by wiping); surviving models as the tiebreak.
	var winner := -1
	if a_obj != b_obj:
		winner = 0 if a_obj > b_obj else 1
	elif a_alive != b_alive:
		winner = 0 if a_alive > b_alive else 1
	return {
		"winner": winner, "rounds": round_no, "end_reason": end_reason,
		"a_alive": a_alive, "b_alive": b_alive, "a_start": a_start, "b_start": b_start,
		"a_losses": a_start - a_alive, "b_losses": b_start - b_alive, "activations": activations,
		"a_objectives": a_obj, "b_objectives": b_obj,
	}


static func _deploy(units: Array) -> void:
	for player in [0, 1]:
		var side: Array = []
		for u in units:
			if u["player"] == player:
				side.append(u)
		var z: float = DEPLOY_IN * 0.5 if player == 0 else (BOARD_IN - DEPLOY_IN * 0.5)
		for i in range(side.size()):
			var x: float = BOARD_IN * float(i + 1) / float(side.size() + 1)
			side[i]["pos"] = Vector2(x, z)


# === Activation (mirrors SoloController._act on the 2D board) ===

static func _activate(unit: Dictionary, units: Array, rng: RandomNumberGenerator, log_lines: Array) -> void:
	unit["activated"] = true
	# OPR (p.10): a Shaken unit spends its activation idle, which clears Shaken at the end of it.
	if unit["shaken"]:
		unit["shaken"] = false
		log_lines.append("%s spends its activation idle — recovers from Shaken" % unit["name"])
		return
	var target: Variant = _nearest_enemy(unit, units)
	if target == null:
		return
	var upos: Vector2 = unit["pos"]
	var tpos: Vector2 = target["pos"]
	var weapons: Array = unit["weapons"]
	var archetype: int = AiArchetype.classify(weapons)
	var shoot_range: int = AiArchetype.max_range_inches(weapons)
	var advance: float = float(unit["advance_in"])
	var rush: float = float(unit["rush_in"])
	var dist: float = upos.distance_to(tpos)
	var in_range: bool = shoot_range > 0 and dist <= float(shoot_range)   # open field: LOS always clear
	var action: int = AiDecision.decide(archetype, dist, advance, rush, float(shoot_range), in_range)
	log_lines.append("%s: %s (%.0f\" to %s)" % [unit["name"], AiDecision.action_name(action), dist, target["name"]])
	var dir: Vector2 = (tpos - upos).normalized() if dist > 0.0001 else Vector2.ZERO
	match action:
		AiDecision.Action.ADVANCE:
			_move(unit, dir * advance)
		AiDecision.Action.RUSH:
			_move(unit, dir * rush)
		AiDecision.Action.CHARGE:
			_move(unit, dir * minf(rush, maxf(dist - CONTACT_IN, 0.0)))
		AiDecision.Action.KITE:
			var room: float = maxf(float(shoot_range) - dist, 0.0)
			_move(unit, -dir * minf(advance, room))
		_:
			pass   # HOLD
	dist = (unit["pos"] as Vector2).distance_to(tpos)
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
	var defense: int = int(target["defense"])
	var total := 0
	for p in profiles:
		var profile := p as Dictionary
		var faces := _roll(rng, int(profile["attacks"]))
		var hits := AiCombatMath.count_hits(faces, quality)
		if hits <= 0:
			continue
		var save_faces := _roll(rng, hits)
		total += AiCombatMath.wounds(hits, save_faces, defense, int(profile["ap"]))
	if total > 0:
		_apply_wounds(target, total)
		log_lines.append("%s shoots %s → %d wound(s)" % [attacker["name"], target["name"], total])
	# General morale (p.10): a unit left at half or less by the wounds it just took must test.
	if AiCombatMath.should_test_shooting_morale(alive_before, alive_models(target), int(target["max_models"])):
		_morale(target, rng, log_lines)


static func _resolve_melee(attacker: Dictionary, target: Dictionary, rng: RandomNumberGenerator,
		log_lines: Array) -> void:
	var dealt := _strike(attacker, target, rng)
	if dealt > 0:
		_apply_wounds(target, dealt)
	# The defender MAY strike back (Shaken units strike back as fatigued — handled in _strike).
	var struck_back := 0
	if is_alive(target):
		struck_back = _strike(target, attacker, rng)
		if struck_back > 0:
			_apply_wounds(attacker, struck_back)
	attacker["fatigued"] = true
	target["fatigued"] = true
	log_lines.append("%s charges %s → %d dealt, %d back" % [attacker["name"], target["name"], dealt, struck_back])
	# Melee morale (p.10): only the loser (more wounds taken) tests.
	if dealt > struck_back and is_alive(target):
		_morale(target, rng, log_lines)
	elif struck_back > dealt and is_alive(attacker):
		_morale(attacker, rng, log_lines)


## One striker's melee output. Fatigued OR Shaken → hits only on unmodified 6s; else its Quality.
static func _strike(striker: Dictionary, defender: Dictionary, rng: RandomNumberGenerator) -> int:
	var profiles: Array = AiShooting.melee_profiles(striker["weapons"])
	var to_hit: int = 6 if (bool(striker["fatigued"]) or bool(striker["shaken"])) else int(striker["quality"])
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


## OPR morale (p.10): roll 1 die vs Quality (a Shaken unit ALWAYS fails). Fail + ≤ half size → Rout
## (destroyed), else the unit becomes Shaken.
static func _morale(unit: Dictionary, rng: RandomNumberGenerator, log_lines: Array) -> void:
	var passed := false
	if not bool(unit["shaken"]):
		var face: int = int(_roll(rng, 1)[0])
		passed = DiceRules.is_success(face, int(unit["quality"]), 0)
	if passed:
		log_lines.append("%s passes morale" % unit["name"])
		return
	if AiCombatMath.at_or_below_half(alive_models(unit), int(unit["max_models"])):
		unit["wounds_pool"] = int(unit["max_models"]) * int(unit["tough"])   # wiped
		log_lines.append("%s ROUTS (destroyed)" % unit["name"])
	else:
		unit["shaken"] = true
		log_lines.append("%s is Shaken" % unit["name"])


## Seize objectives at round end (p.6): a marker is taken by the side with a non-Shaken unit within 3"
## and no enemy within 3". A seized marker STAYS with its owner if nobody is near; both sides near → it
## goes neutral. Shaken units can neither seize NOR contest. Mutates obj_owner in place.
static func _seize_objectives(units: Array, objectives: Array, obj_owner: Array, log_lines: Array) -> void:
	for i in range(objectives.size()):
		var near0 := false
		var near1 := false
		for u in units:
			if not is_alive(u) or bool(u["shaken"]):
				continue   # Shaken units can't seize or contest
			if (u["pos"] as Vector2).distance_to(objectives[i]) <= OBJECTIVE_CONTROL_IN:
				if u["player"] == 0:
					near0 = true
				else:
					near1 = true
		if near0 and near1:
			if obj_owner[i] != -1:
				log_lines.append("Objective %d contested → neutral" % i)
			obj_owner[i] = -1
		elif near0 and obj_owner[i] != 0:
			obj_owner[i] = 0
			log_lines.append("Objective %d seized by Army 0" % i)
		elif near1 and obj_owner[i] != 1:
			obj_owner[i] = 1
			log_lines.append("Objective %d seized by Army 1" % i)
		# nobody near → owner unchanged (persistent)


static func _apply_wounds(unit: Dictionary, w: int) -> void:
	unit["wounds_pool"] = int(unit["wounds_pool"]) + maxi(w, 0)


# === Helpers ===

static func _roll(rng: RandomNumberGenerator, n: int) -> Array:
	var faces: Array = []
	for i in range(maxi(n, 0)):
		faces.append(rng.randi_range(1, 6))
	return faces


static func _move(unit: Dictionary, delta: Vector2) -> void:
	var p: Vector2 = (unit["pos"] as Vector2) + delta
	unit["pos"] = Vector2(clampf(p.x, 0.0, BOARD_IN), clampf(p.y, 0.0, BOARD_IN))


static func _nearest_enemy(unit: Dictionary, units: Array) -> Variant:
	var best: Variant = null
	var best_d := INF
	for u in units:
		if u["player"] == unit["player"] or not is_alive(u):
			continue
		var d: float = (unit["pos"] as Vector2).distance_to(u["pos"])
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
