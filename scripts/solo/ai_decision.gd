class_name AiDecision
extends RefCounted
## Solo-AI M2 — the per-unit action decision from OPR Solo & Co-Op v3.5.0, branched by archetype
## (AiArchetype). M2 implements the NO-OBJECTIVE branches of the official trees (objectives influence
## decisions in M3 per bus 038); the objective steps are marked below. Pure + deterministic; the caller
## (SoloController) supplies distances in INCHES and executes the chosen action.
##
## Official tree, no-objective branches:
##   MELEE:    enemy in charge range → CHARGE, else → RUSH toward enemy (melee never merely advances).
##   SHOOTING: already in shooting range → KITE (the "Advancing" basic concept: move away from the
##             closest enemy just enough to STAY in range) and shoot; else if advancing would bring the
##             enemy into range → ADVANCE toward enemy and shoot; else → RUSH toward enemy.
##   HYBRID:   enemy in charge range → CHARGE; else advance-and-shoot if that reaches range; else RUSH.
## HOLD is reserved for the M3 overlays (Artillery / Indirect / Relentless use Hold+shoot).

enum Action { HOLD, ADVANCE, RUSH, CHARGE, KITE }


## Decide the action toward the nearest valid target (no objectives on the decision yet — M3).
##   archetype       : AiArchetype.Type
##   dist_in         : inches to the target
##   advance_in      : Advance distance (6" ± modifiers)
##   charge_in       : Rush/Charge distance (12" ± modifiers)
##   shoot_range_in  : longest weapon range in inches (0 = melee-only)
##   in_shoot_range  : target within weapon range AND line of sight right now
static func decide(archetype: int, dist_in: float, advance_in: float, charge_in: float, shoot_range_in: float, in_shoot_range: bool) -> Action:
	match archetype:
		AiArchetype.Type.MELEE:
			return Action.CHARGE if dist_in <= charge_in else Action.RUSH
		AiArchetype.Type.SHOOTING:
			if in_shoot_range:
				return Action.KITE
			if dist_in - advance_in <= shoot_range_in:
				return Action.ADVANCE
			return Action.RUSH
		_:  # HYBRID
			if dist_in <= charge_in:
				return Action.CHARGE
			if in_shoot_range or dist_in - advance_in <= shoot_range_in:
				return Action.ADVANCE
			return Action.RUSH


## Human-readable verb for the battle log.
static func action_name(action: int) -> String:
	match action:
		Action.HOLD: return "holds"
		Action.ADVANCE: return "advances"
		Action.RUSH: return "rushes"
		Action.CHARGE: return "charges"
		Action.KITE: return "falls back"
	return "?"


enum Toward { ENEMY, OBJECTIVE }

## The FULL official Solo & Co-Op decision trees (GF/AoF Advanced Rules v3.5.1, p.57) — objective-driven,
## which the legacy `decide` above is not. There is NO kite/retreat in the official rules: the AI always
## Advances/Rushes/Charges toward an objective (if any uncontrolled one exists) or else the enemy. Pure +
## deterministic. Returns {"action": Action, "toward": Toward, "shoot": bool}.
##   ctx keys (all bool unless noted):
##     arch                : AiArchetype.Type (int)
##     objective           : an uncontrolled objective exists
##     in_way              : enemies are in the way to that objective (within 6" of the path)
##     obj_in_advance      : the objective is reachable with an Advance move
##     obj_in_rush         : the objective is reachable with a Rush move
##     enemy_in_charge     : an enemy is in Charge range
##     shoot_after_advance : after an Advance, an enemy would be in shooting range
static func decide_solo(ctx: Dictionary) -> Dictionary:
	var arch: int = int(ctx.get("arch", AiArchetype.Type.MELEE))
	var obj: bool = bool(ctx.get("objective", false))
	var in_way: bool = bool(ctx.get("in_way", false))
	var enemy_charge: bool = bool(ctx.get("enemy_in_charge", false))
	var shoot_adv: bool = bool(ctx.get("shoot_after_advance", false))
	match arch:
		AiArchetype.Type.MELEE:
			if obj:
				if in_way and enemy_charge:
					return _r(Action.CHARGE, Toward.ENEMY, false)
				return _r(Action.RUSH, Toward.OBJECTIVE, false)
			return _r(Action.CHARGE, Toward.ENEMY, false) if enemy_charge else _r(Action.RUSH, Toward.ENEMY, false)
		AiArchetype.Type.SHOOTING:
			if obj:
				return _r(Action.ADVANCE, Toward.OBJECTIVE, true) if shoot_adv else _r(Action.RUSH, Toward.OBJECTIVE, false)
			return _r(Action.ADVANCE, Toward.ENEMY, true) if shoot_adv else _r(Action.RUSH, Toward.ENEMY, false)
		_:  # HYBRID
			if obj:
				if in_way:
					if enemy_charge:
						return _r(Action.CHARGE, Toward.ENEMY, false)
					return _r(Action.ADVANCE, Toward.OBJECTIVE, true) if shoot_adv else _r(Action.RUSH, Toward.OBJECTIVE, false)
				if bool(ctx.get("obj_in_rush", false)) and not bool(ctx.get("obj_in_advance", false)):
					return _r(Action.RUSH, Toward.OBJECTIVE, false)
				return _r(Action.ADVANCE, Toward.OBJECTIVE, true) if shoot_adv else _r(Action.RUSH, Toward.OBJECTIVE, false)
			if enemy_charge:
				return _r(Action.CHARGE, Toward.ENEMY, false)
			return _r(Action.ADVANCE, Toward.ENEMY, true) if shoot_adv else _r(Action.RUSH, Toward.ENEMY, false)


static func _r(action: int, toward: int, shoot: bool) -> Dictionary:
	return {"action": action, "toward": toward, "shoot": shoot}
