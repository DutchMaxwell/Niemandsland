class_name ActIntent
extends RefCounted
## Automodus A0 — the shared shape both feeders (the AI's `_act` and the player's `player_intent`,
## NML-202) hand to `SoloController.execute_intent()`. Nothing here executes anything; `make`
## assembles the dictionary, `validate` refuses the impossible ones before any dice are touched,
## `blank_report` is the empty report both feeders start from. Keeping this pure and file-local
## means the AI and the player share one seam with no second truth for the move/shoot gates.

## `unit`             : GameUnit acting this activation.
## `action`           : AiDecision.Action — HOLD/ADVANCE/RUSH/CHARGE/KITE.
## `target`           : GameUnit the move/shot is aimed at (null for a target-less HOLD).
## `goal`             : Vector3 world point the move steers toward.
## `band_in`          : inches available for an ADVANCE/RUSH this activation (0 for HOLD/CHARGE).
## `charge_band_in`   : the melee-shrouding-adjusted CHARGE reach (0 unless action == CHARGE).
## `shoot`            : whether the decided action opens the shooting gate at all.
## `shoot_range_in`   : longest weapon range in inches (0 = no ranged weapon).
## `quick_shot`       : true when the unit may shoot after a RUSH (army-book Quick Shot).
## `enemy_dist_in`    : pre-move centre-to-centre distance to `target`.
## `to_objective`     : the move steers at a marker, not the enemy (narration + seize bookkeeping).
## `to_flank`         : the move steers at a flank firing anchor (narration only).
## `source`           : "ai" | "player" — execute_intent skips the AI-only ledger for "player".
## `why`              : one line for the decision record / narration.
static func make(unit: GameUnit, action: int, target: GameUnit, goal: Vector3, band_in: float,
		shoot: bool, extra: Dictionary = {}) -> Dictionary:
	return {
		"unit": unit, "action": action, "target": target, "goal": goal, "band_in": band_in,
		"charge_band_in": float(extra.get("charge_band_in", 0.0)),
		"shoot": shoot, "shoot_range_in": float(extra.get("shoot_range_in", 0.0)),
		"quick_shot": bool(extra.get("quick_shot", false)),
		"enemy_dist_in": float(extra.get("enemy_dist_in", 0.0)),
		"to_objective": bool(extra.get("to_objective", false)),
		"to_flank": bool(extra.get("to_flank", false)),
		"source": str(extra.get("source", "ai")),
		"why": str(extra.get("why", "")),
	}


## "" = the intent may run. Anything else is the refusal reason (never executed, nothing moves).
static func validate(intent: Dictionary) -> String:
	var unit := intent.get("unit") as GameUnit
	if unit == null:
		return "no unit"
	var action: int = int(intent.get("action", -1))
	if not AiDecision.Action.values().has(action):
		return "unknown action"
	if action == AiDecision.Action.CHARGE and intent.get("target") == null:
		return "charge needs a target"
	if (action == AiDecision.Action.ADVANCE or action == AiDecision.Action.RUSH) \
			and float(intent.get("band_in", 0.0)) <= 0.0:
		return "no move band"
	return ""


## The empty report both `_act` and `player_intent` start from — identical to the dictionary
## `_act` used to build inline (solo_controller.gd:1709-1711) so the split changes no key, no
## default, no reader.
static func blank_report(unit: GameUnit) -> Dictionary:
	return {"unit": unit, "target": null, "action": AiDecision.Action.HOLD,
		"toward": AiDecision.Toward.ENEMY, "shoot": false, "can_shoot": false, "dist_in": INF,
		"dangerous_models": 0, "rule_notes": []}
