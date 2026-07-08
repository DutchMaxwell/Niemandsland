class_name SoloSim
extends RefCounted
## Headless AI-vs-AI game simulator (goal 003 — self-play). Plays a whole game with NO UI: no dice tray,
## no prompts, no camera — dice come from a SEEDED RNG and every combat/decision uses the SAME pure
## modules the real game uses (AiArchetype, AiDecision, AiShooting, AiCombatMath). That shared logic IS
## the correctness link to the real game.
##
## Board: 2D 4×4 ft table, 12" deployment zones, two mission objectives. NO terrain yet (open field, LOS
## always clear). Rules match OPR GF/AoF core v3.x (re-audited 2026-07-08):
##  • Shaken (post-Apr-2024): a Shaken unit still acts, but at −1 Quality and −1 Defense, HALF movement,
##    and it CANNOT seize objectives. (It could choose to idle-recover; the sim does not model that yet.)
##  • Objectives: seized at the END OF EACH ROUND by a non-Shaken unit within 3" with no enemy within 3";
##    a seized marker STAYS seized after the unit leaves; both sides within 3" → neutral again.
##  • Morale: the melee loser tests; a unit reduced to ≤ half by shooting tests; AND at each round end, an
##    army at ≤ half its starting UNIT count tests morale army-wide. Fail + (≤ half size OR already
##    Shaken) → Rout (destroyed), else Shaken.
##  • Winner: most objectives controlled after 4 rounds; surviving models as tiebreak.
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


## Shaken penalties (OPR post-Apr-2024): −1 to Quality and Defense rolls → the effective TARGET is one
## worse (a 4+ becomes a 5+). Half movement. Pure helpers so the effect is applied consistently.
static func _eff_quality(u: Dictionary) -> int:
	return int(u["quality"]) + (1 if bool(u["shaken"]) else 0)


static func _eff_defense(u: Dictionary) -> int:
	return int(u["defense"]) + (1 if bool(u["shaken"]) else 0)


static func _move_scale(u: Dictionary) -> float:
	return 0.5 if bool(u["shaken"]) else 1.0


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
	var a_start_units := _side_units(units, 0)
	var b_start_units := _side_units(units, 1)
	var activations := 0
	var end_reason := "round_limit"
	var round_no := 0
	for r in range(1, max_rounds + 1):
		round_no = r
		for u in units:
			u["activated"] = false
		log_lines.append("── Round %d ──" % r)
		# OPR: initiative is rolled off each round, then activations alternate (a fixed first player was a
		# systematic bias — the mirror test caught it).
		var side := rng.randi_range(0, 1)
		while _has_unactivated(units, 0) or _has_unactivated(units, 1):
			if _has_unactivated(units, side):
				var actor: Variant = _next_unactivated(units, side)
				if actor != null:
					activations += 1
					_activate(actor, units, rng, log_lines)
			side = 1 - side
		# End of round: fatigue clears; army-wide morale if an army is at half its starting units; then
		# objectives are (re)seized.
		for u in units:
			u["fatigued"] = false
		_army_morale(units, 0, a_start_units, rng, log_lines)
		_army_morale(units, 1, b_start_units, rng, log_lines)
		_seize_objectives(units, objs, obj_owner, log_lines)
		if _side_models(units, 0) == 0 or _side_models(units, 1) == 0:
			end_reason = "wipe"
			break
	var a_alive := _side_models(units, 0)
	var b_alive := _side_models(units, 1)
	var a_obj := obj_owner.count(0)
	var b_obj := obj_owner.count(1)
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
	var target: Variant = _nearest_enemy(unit, units)
	if target == null:
		return
	var upos: Vector2 = unit["pos"]
	var tpos: Vector2 = target["pos"]
	var weapons: Array = unit["weapons"]
	var archetype: int = AiArchetype.classify(weapons)
	var shoot_range: int = AiArchetype.max_range_inches(weapons)
	var move_scale: float = _move_scale(unit)   # Shaken → half movement
	var advance: float = float(unit["advance_in"]) * move_scale
	var rush: float = float(unit["rush_in"]) * move_scale
	var dist: float = upos.distance_to(tpos)
	var in_range: bool = shoot_range > 0 and dist <= float(shoot_range)   # open field: LOS always clear
	var action: int = AiDecision.decide(archetype, dist, advance, rush, float(shoot_range), in_range)
	log_lines.append("%s%s: %s (%.0f\" to %s)" % [unit["name"], (" [Shaken]" if bool(unit["shaken"]) else ""),
		AiDecision.action_name(action), dist, target["name"]])
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
	var quality := _eff_quality(attacker)
	var defense := _eff_defense(target)
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
	if dealt > struck_back and is_alive(target):
		_morale(target, rng, log_lines)
	elif struck_back > dealt and is_alive(attacker):
		_morale(attacker, rng, log_lines)


## One striker's melee output. Fatigued → hits only on 6s; else effective Quality (Shaken = −1). The
## defender saves at its effective Defense (Shaken = −1).
static func _strike(striker: Dictionary, defender: Dictionary, rng: RandomNumberGenerator) -> int:
	var profiles: Array = AiShooting.melee_profiles(striker["weapons"])
	var to_hit: int = 6 if bool(striker["fatigued"]) else _eff_quality(striker)
	var defense := _eff_defense(defender)
	var total := 0
	for p in profiles:
		var profile := p as Dictionary
		var faces := _roll(rng, int(profile["attacks"]))
		var hits := AiCombatMath.count_hits(faces, to_hit)
		if hits <= 0:
			continue
		var save_faces := _roll(rng, hits)
		total += AiCombatMath.wounds(hits, save_faces, defense, int(profile["ap"]))
	return total


## OPR morale: roll 1 die vs Quality. Fail + (≤ half size OR ALREADY Shaken) → Rout (destroyed); else
## becomes Shaken. (An already-Shaken unit that fails is removed — that is how Shaken units die off.)
static func _morale(unit: Dictionary, rng: RandomNumberGenerator, log_lines: Array) -> void:
	var face: int = int(_roll(rng, 1)[0])
	if DiceRules.is_success(face, int(unit["quality"]), 0):
		log_lines.append("%s passes morale" % unit["name"])
		return
	var below := AiCombatMath.at_or_below_half(alive_models(unit), int(unit["max_models"]))
	if below or bool(unit["shaken"]):
		unit["wounds_pool"] = int(unit["max_models"]) * int(unit["tough"])   # wiped
		log_lines.append("%s ROUTS (destroyed)" % unit["name"])
	else:
		unit["shaken"] = true
		log_lines.append("%s is Shaken" % unit["name"])


## OPR end-of-round army morale: if a side is at half or LESS of its starting UNIT count, every one of
## its still-alive units must test morale.
static func _army_morale(units: Array, player: int, start_units: int, rng: RandomNumberGenerator,
		log_lines: Array) -> void:
	if start_units <= 0:
		return
	if _side_units(units, player) * 2 > start_units:
		return   # still above half strength as an army
	log_lines.append("Army %d is at half strength — army-wide morale" % player)
	for u in units:
		if u["player"] == player and is_alive(u):
			_morale(u, rng, log_lines)


## Seize objectives at round end (OPR): a marker is taken by the side with a NON-Shaken unit within 3"
## and no enemy within 3". A seized marker STAYS with its owner if nobody is near; both sides near → it
## goes neutral. Mutates obj_owner in place.
static func _seize_objectives(units: Array, objectives: Array, obj_owner: Array, log_lines: Array) -> void:
	for i in range(objectives.size()):
		var near0 := false
		var near1 := false
		for u in units:
			if not is_alive(u) or bool(u["shaken"]):
				continue   # Shaken units cannot seize
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


static func _side_units(units: Array, player: int) -> int:
	var n := 0
	for u in units:
		if u["player"] == player and is_alive(u):
			n += 1
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
