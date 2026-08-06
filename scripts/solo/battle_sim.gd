class_name BattleSim
extends RefCounted
## Planner substrate, phase 1: a read-only snapshot of the live game as plain
## data. Static facts (profiles, rules) stay on the referenced GameUnit and are
## never mutated; dynamic facts (positions, wounds, flags, objective owners)
## are copied so expectation rollouts can edit them without touching the scene.
## Positions are metres, world space. Callable seams mirror SoloController's:
## objectives_provider() -> Array[Vector3], objective_owner_of(i) -> int.


const IN2M := 0.0254


## Deep-copies the DYNAMIC layers (positions/wounds/flags/objective owners);
## GameUnit refs stay shared — they are read-only by contract.
static func clone_state(state: Dictionary) -> Dictionary:
	var units := {}
	for key in state["units"]:
		var su: Dictionary = (state["units"][key] as Dictionary).duplicate()
		su["positions"] = (su["positions"] as Array).duplicate()
		su["wounds"] = (su["wounds"] as Array).duplicate()
		units[key] = su
	var objectives: Array = []
	for o in state["objectives"]:
		objectives.append((o as Dictionary).duplicate())
	return {"round": state["round"], "rounds_total": state["rounds_total"],
		"units": units, "objectives": objectives}


## Resolves one activation IN EXPECTATION on a cloned state and returns it.
## action: {"unit": key, "kind": AiDecision.Action, "dest": Vector3 (optional
## move goal for the unit centre)}. Movement v0 (plan D4): the whole unit
## translates toward dest, clamped by the official move band — no pathfinding.
static func resolve(state: Dictionary, action: Dictionary) -> Dictionary:
	var next := clone_state(state)
	var su: Dictionary = next["units"][action["unit"]]
	var kind: int = int(action.get("kind", AiDecision.Action.HOLD))
	var bands := SoloController.move_bands_for_unit(su["unit"], null)
	var band_in := 0.0
	if kind == AiDecision.Action.ADVANCE:
		band_in = float(bands.get("advance", 6))
	elif kind == AiDecision.Action.RUSH or kind == AiDecision.Action.CHARGE:
		band_in = float(bands.get("rush", 12))
	var positions: Array = su["positions"]
	if band_in > 0.0 and action.has("dest") and not positions.is_empty():
		var centre := Vector3.ZERO
		for p in positions:
			centre += p as Vector3
		centre /= positions.size()
		var delta: Vector3 = (action["dest"] as Vector3) - centre
		var reach_m := band_in * IN2M
		if delta.length() > reach_m:
			delta = delta.normalized() * reach_m
		for i in range(positions.size()):
			positions[i] = (positions[i] as Vector3) + delta
	su["activated"] = true
	return next


static func capture(army: OPRArmyManager, objectives_provider: Callable = Callable(),
		objective_owner_of: Callable = Callable(), round_no: int = 1,
		rounds_total: int = 4) -> Dictionary:
	var units := {}
	for uid in army.game_units:
		var u: GameUnit = army.game_units[uid]
		var positions: Array = []
		var wounds: Array = []
		for m in u.models:
			if m.is_alive and m.node != null:
				positions.append(m.node.global_position)
				wounds.append(m.wounds_current)
		units[uid] = {
			"unit": u,
			"player": int(u.unit_properties.get("player_id", 0)),
			"positions": positions,
			"alive": positions.size(),
			"wounds": wounds,
			"shaken": u.is_shaken,
			"fatigued": u.is_fatigued,
			"activated": u.is_activated,
			"casts": u.casts_current,
		}
	var objectives: Array = []
	if objectives_provider.is_valid():
		var objs: Variant = objectives_provider.call()
		for i in range(objs.size()):
			objectives.append({
				"pos": objs[i],
				"owner": int(objective_owner_of.call(i)) if objective_owner_of.is_valid() else 0,
			})
	return {
		"round": round_no,
		"rounds_total": rounds_total,
		"units": units,
		"objectives": objectives,
	}
