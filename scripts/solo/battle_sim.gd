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
	var out := {"round": state["round"], "rounds_total": state["rounds_total"],
		"units": units, "objectives": objectives}
	if state.has("terrain_at"):
		out["terrain_at"] = state["terrain_at"]
	return out


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
		var terrain_at: Callable = next.get("terrain_at", Callable())
		if terrain_at.is_valid():   # T2b: the mover's cover follows it (unit-centre probe, v0)
			su["in_cover"] = TerrainRules.gives_cover(int(terrain_at.call(centre + delta)))
	var shoot_key := str(action.get("shoot", ""))
	if shoot_key != "" and next["units"].has(shoot_key) and sees(su, shoot_key) \
			and (kind == AiDecision.Action.HOLD or kind == AiDecision.Action.ADVANCE):
		var tu: Dictionary = next["units"][shoot_key]
		var d := dist_in(positions, tu["positions"])
		_apply_expected_wounds(tu, AiEv.shoot_ev(_profiles_of(su, false, d),
			_ctx_of(su), _ctx_of(tu), d))
	var charge_key := str(action.get("charge", ""))
	if kind == AiDecision.Action.CHARGE and charge_key != "" and next["units"].has(charge_key):
		var tu: Dictionary = next["units"][charge_key]
		if dist_in(positions, tu["positions"]) <= CONTACT_IN:
			_apply_expected_wounds(tu, AiEv.melee_ev(_profiles_of(su, true),
				_ctx_of(su), _ctx_of(tu), true))
			su["fatigued"] = true
			if int(tu["alive"]) > 0:   # survivors strike back, already survivor-scaled
				_apply_expected_wounds(su, AiEv.melee_ev(_profiles_of(tu, true),
					_ctx_of(tu), _ctx_of(su), false))
	su["activated"] = true
	return next


const CONTACT_IN := 1.0

## Snapshot LOS: no matrix (no los_of wired at capture) = everyone sees
## everyone, byte-identical to pre-T2. V0 approximation, documented: the
## matrix is CAPTURE-TIME — a unit moved during a rollout keeps its captured
## sight lines (exact for hold+shoot, approximate after moves).
static func sees(su: Dictionary, other_key: String) -> bool:
	if not su.has("los"):
		return true
	return bool((su["los"] as Dictionary).get(other_key, true))

## Nearest-model gap between two snapshot position arrays, inches.
static func dist_in(a: Array, b: Array) -> float:
	var best := INF
	for pa in a:
		for pb in b:
			best = minf(best, ((pa as Vector3) - (pb as Vector3)).length())
	return best / IN2M


## AiEv context sourced from the SNAPSHOT's dynamic layer, not the live models.
static func _ctx_of(su: Dictionary) -> Dictionary:
	var ctx := AiEv.ctx_for(su["unit"], bool(su.get("in_cover", false)))
	ctx["models"] = int(su["alive"])
	return ctx


## Weapon profiles with attacks scaled to the snapshot's survivors (dead models
## stop attacking — mirrors effective_attacks in the real path). Limited-weapon
## usage tracking is NOT modelled yet (v0; noted for the parity wave).
static func _profiles_of(su: Dictionary, melee: bool, d := 0.0) -> Array:
	var u: GameUnit = su["unit"]
	var weapons: Array = []
	if u.source_type == "opr" and u.source_data is OPRApiClient.OPRUnit:
		weapons = (u.source_data as OPRApiClient.OPRUnit).weapons
	var profiles: Array = AiShooting.melee_profiles(weapons) if melee \
		else AiShooting.profiles_in_range(weapons, d)
	var out: Array = []
	for p in AiEv.stamp_sergeant(profiles, u):
		var q := (p as Dictionary).duplicate()
		q["attacks"] = SoloController.effective_attacks(int(q.get("attacks", 0)),
			int(su["alive"]), u.models.size())
		out.append(q)
	return out


## Expected unsaved wounds land on the snapshot: floored to whole wounds, then
## filled model by model in array order (v0 — casualty_order parity is step 3).
static func _apply_expected_wounds(tu: Dictionary, ev: float) -> void:
	var left := int(floor(ev))
	var wounds: Array = tu["wounds"]
	var positions: Array = tu["positions"]
	while left > 0 and not wounds.is_empty():
		var take: int = mini(left, int(wounds[0]))
		wounds[0] = int(wounds[0]) - take
		left -= take
		if int(wounds[0]) <= 0:
			wounds.remove_at(0)
			positions.remove_at(0)
	tu["alive"] = positions.size()


static func capture(army: OPRArmyManager, objectives_provider: Callable = Callable(),
		objective_owner_of: Callable = Callable(), round_no: int = 1,
		rounds_total: int = 4, cover_of: Callable = Callable(),
		los_of: Callable = Callable(), terrain_at: Callable = Callable()) -> Dictionary:
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
			"in_cover": bool(cover_of.call(u)) if cover_of.is_valid() else false,
			"shaken": u.is_shaken,
			"fatigued": u.is_fatigued,
			"activated": u.is_activated,
			"casts": u.casts_current,
		}
	if los_of.is_valid():
		for k in units:
			var su: Dictionary = units[k]
			var matrix := {}
			for ok in units:
				var other: Dictionary = units[ok]
				if int(other["player"]) != int(su["player"]):
					matrix[ok] = bool(los_of.call(su["unit"], other["unit"]))
			su["los"] = matrix
	var objectives: Array = []
	if objectives_provider.is_valid():
		var objs: Variant = objectives_provider.call()
		for i in range(objs.size()):
			objectives.append({
				"pos": objs[i],
				"owner": int(objective_owner_of.call(i)) if objective_owner_of.is_valid() else 0,
			})
	var state := {
		"round": round_no,
		"rounds_total": rounds_total,
		"units": units,
		"objectives": objectives,
	}
	if terrain_at.is_valid():   # absent key = pre-T2b snapshot, byte-identical
		state["terrain_at"] = terrain_at
	return state
