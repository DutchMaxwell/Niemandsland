class_name AiDecision
extends RefCounted
## Solo-AI M2 — the per-unit action decision tree from OPR Solo/Co-Op v3.5.0, branched by archetype
## (AiArchetype). Given a unit's move bands + the tactical situation toward its chosen target, pick ONE
## action. Pure + deterministic (no RNG here — ties are resolved by the fixed branch order); headless-
## testable. The caller (SoloController) supplies distances in INCHES and executes the chosen action via
## the existing move/charge/shoot seams.

enum Action { HOLD, ADVANCE, RUSH, CHARGE }


## Decide the action toward the nearest valid target.
##   archetype       : AiArchetype.Type
##   dist_in         : inches from this unit to the target (edge-to-edge)
##   advance_in      : this unit's Advance distance (OPR 6" ± modifiers)
##   charge_in       : this unit's Rush/Charge distance (OPR 12" ± modifiers)
##   shoot_range_in  : the unit's longest weapon range in inches (0 = melee-only)
##   in_shoot_range  : target is within a weapon's range AND has line of sight right now
static func decide(archetype: int, dist_in: float, advance_in: float, charge_in: float, shoot_range_in: float, in_shoot_range: bool) -> Action:
	match archetype:
		AiArchetype.Type.MELEE:
			# Melee wants contact: charge if reachable, otherwise close the gap as fast as possible.
			if dist_in <= charge_in:
				return Action.CHARGE
			if dist_in <= charge_in + advance_in:
				return Action.RUSH
			return Action.ADVANCE
		AiArchetype.Type.SHOOTING:
			# Shooters hold and fire when able; else advance into range (Advance still allows shooting),
			# or rush to close the range faster when advancing alone can't bring the target in range.
			if in_shoot_range:
				return Action.HOLD
			if dist_in - advance_in <= shoot_range_in:
				return Action.ADVANCE
			return Action.RUSH
		_:  # HYBRID
			# Get stuck in if a charge lands; otherwise shoot when able; otherwise advance to do both soon.
			if dist_in <= charge_in:
				return Action.CHARGE
			if in_shoot_range:
				return Action.HOLD
			return Action.ADVANCE


## Human-readable action name for the battle log ("Grave Wardens advances / charges …").
static func action_name(action: int) -> String:
	match action:
		Action.HOLD: return "holds"
		Action.ADVANCE: return "advances"
		Action.RUSH: return "rushes"
		Action.CHARGE: return "charges"
	return "?"
