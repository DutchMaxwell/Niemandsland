class_name CoreActivation
extends RefCounted
## One-core P3 step 19: the table's skeleton for core-resolved activations. INERT: nothing calls this until
## NML_ONE_CORE_ACTIVATION=1 (default OFF), and every later door asks one of the three predicates first.

static var _env := -1


## The flag, read once (the BattleSim.core_enabled pattern).
static func enabled() -> bool:
	if _env < 0:
		_env = 1 if OS.get_environment("NML_ONE_CORE_ACTIVATION") == "1" else 0
	return _env == 1


## The engine resolves at this table: an AI seat, or an agreed Automatic online room. Hotseat and Manual rooms: false.
static func applies(main) -> bool:
	return enabled() and ClassDB.class_exists("NmlCore") \
		and (not main.solo_ai_slots.is_empty() or main._online_turn_room())


## No unit rule, no attachment, no weapon rule: the volley the core resolves exactly as the table does.
static func is_plain(gu: GameUnit) -> bool:
	if not (gu.unit_properties.get("special_rules", []) as Array).is_empty() \
			or gu.has_attached_heroes() or gu.is_attached() or not gu.source_data is OPRApiClient.OPRUnit:
		return false
	for w in (gu.source_data as OPRApiClient.OPRUnit).weapons:
		if not w.special_rules.is_empty():
			return false
	return true


## (1) A human unit of this table's player while the game is PLAYING: it gets the explicit activation (O14 (1b)).
static func is_lifecycle_unit(main, gu: GameUnit) -> bool:
	return gu != null and applies(main) and not main._solo_is_ai_unit(gu) and main._solo_i_own_unit(gu) \
		and main.opr_army_manager.game_phase == OPRArmyManager.GamePhase.PLAYING


## (2) A lifecycle unit whose shot, End and digest resolve in the core.
static func is_core_unit(main, gu: GameUnit) -> bool:
	return is_lifecycle_unit(main, gu) and is_plain(gu)


## (3) Equal to (2) for now; step 82 widens it by movement rule.
static func on_move_path(main, gu: GameUnit) -> bool:
	return is_core_unit(main, gu)


## A core handle for the board as it stands (BattleSim.capture, plain form, gate reads); 0 on failure.
static func capture(main) -> int:
	var sc: SoloController = main.solo_controller
	var core: Object = sc._core_node_ready() if sc != null else null
	if core == null:
		return 0
	var round_no: int = main.opr_army_manager.current_round
	var state := BattleSim.capture(main.opr_army_manager, sc.objectives_provider, sc.objective_owner_of, round_no,
		maxi(sc.game_rounds, round_no), sc.majority_in_cover, sc._has_los, sc.terrain_type_at, int(sc.ai_slot))
	var plain := BattleSim.state_to_plain(state)
	AiActRecorder._stamp_gate_reads(state, plain)
	return int(core.capture_plain(plain))


## Calls per activation before the driver gives up (a plain volley asks three to four times).
const MAX_STEPS := 64


## One activation through the core: ask, print the lines not printed yet, land, throw on the owner's tray, ask again.
## `transcript` gains one faces entry per throw; `on_throw(kind, index)` runs before each throw (a test seam).
## Returns the core's last answer plus "steps" (calls), "core_us" (their total time) and "max_us" (the slowest).
static func drive(main, h: int, unit: GameUnit, transcript: Array, ai: bool,
		on_throw: Callable = Callable()) -> Dictionary:
	var core: Object = (main.solo_controller as SoloController)._core_node_ready()
	var enforce: bool = main.object_manager._strict_movement_enforced()
	var printed := 0
	var start_models := _start_models(main)
	var landed := {}
	var core_us := 0
	var max_us := 0
	var r: Dictionary = {}
	for step in MAX_STEPS:
		var t0 := Time.get_ticks_usec()
		r = core.step_activation(h, unit.unit_id, transcript, enforce)
		var us := Time.get_ticks_usec() - t0
		core_us += us
		max_us = maxi(max_us, us)
		var lines: Array = r.get("lines", [])
		for i in range(printed, lines.size()):
			var line: Dictionary = lines[i]
			main._log_rule_event(int(line["category"]), str(line["text"]), ai, str(line["detail"]))
		printed = maxi(printed, lines.size())
		await land_step(main, unit, r.get("landings", []), start_models, landed)
		if str(r["step"]) == "done":
			await land_delta(main, r.get("delta", []), start_models, landed)
		if str(r["step"]) != "need_roll":
			r.merge({"steps": step + 1, "core_us": core_us, "max_us": max_us}, true)
			return r
		var owner := str(r["owner"])
		var roller := _roller_of(main, unit, transcript, owner)
		var label: String = "AI (%s)" % owner if main._solo_is_ai_unit(roller) else main._roller_label(roller)
		if on_throw.is_valid():
			on_throw.call(str(r["kind"]), int(r["index"]))
		var faces: Array = await main._owner_roll(roller, int(r["faces"]), int(r["target"]), str(r["kind"]), "",
			{"label": label, "what": "%s dice" % r["kind"]})
		transcript.append({"t": "faces", "faces": faces})
	push_error("CoreActivation.drive: %s still needs dice after %d steps" % [unit.get_name(), MAX_STEPS])
	r.merge({"steps": MAX_STEPS, "core_us": core_us, "max_us": max_us}, true)
	return r


## The unit a roll's `owner` names: the actor or the target of its shot (by name), else the actor.
static func _roller_of(main, unit: GameUnit, transcript: Array, owner: String) -> GameUnit:
	if unit.get_name() == owner:
		return unit
	for e in transcript:
		if str((e as Dictionary).get("t", "")) == "intent":
			var foe = main.opr_army_manager.game_units.get(str((e as Dictionary).get("shoot", "")))
			if foe is GameUnit and (foe as GameUnit).get_name() == owner:
				return foe
	return unit


## Every living model on the table and its position at the activation start, in get_alive_models() order.
static func _start_models(main) -> Array:
	var out: Array = []
	for gu in main.opr_army_manager.game_units.values():
		for m in (gu as GameUnit).get_alive_models():
			if m.node != null and is_instance_valid(m.node):
				out.append({"model": m, "at": m.node.global_position})
	return out


## The start model of `gu` whose captured position equals `at` exactly; null when none does.
static func _model_at(start_models: Array, gu: GameUnit, at: Vector3) -> ModelInstance:
	for e in start_models:
		var m: ModelInstance = e["model"]
		if m.unit == gu and e["at"] == at:
			return m
	return null


## Lands one step's landings on the table (O4 b): a wound shows at once on the wound marker, the dead leave right
## after the saves. Every need_roll repeats the earlier landings; `done` skips what this activation already landed.
static func land_step(main, _gu: GameUnit, landings: Array, start_models: Array, done: Dictionary) -> void:
	for entry in landings:
		var lgu: GameUnit = main.opr_army_manager.game_units.get(str(entry["unit"]))
		var died: Array[ModelInstance] = []
		for lm in entry["models"]:
			var m: ModelInstance = _model_at(start_models, lgu, lm["at"]) if lgu != null else null
			if m == null:
				push_error("CoreActivation.land_step: no model of %s at %s" % [entry["unit"], lm["at"]])
				continue
			if done.has(m):
				continue
			done[m] = true
			var before := m.wounds_current
			if bool(lm["dead"]):
				m.apply_damage(before)
				main._vfx_pip(ResultPips.Kind.KILL, m, 1)
				died.append(m)
			elif int(lm["wounds_left"]) < before:
				m.wounds_current = int(lm["wounds_left"])
				main._vfx_pip(ResultPips.Kind.WOUND, m, before - m.wounds_current)
				main.radial_menu_controller._update_wound_marker(m)
				if main.network_manager != null and main.network_manager.has_method("broadcast_model_wounds"):
					main.network_manager.broadcast_model_wounds(m)
		if not died.is_empty():
			await main._solo_remove_dead_models(lgu, died, int(lgu.unit_properties.get("player_id", 1)))


## The activation's final delta (binding step 17): Shaken onto the table; a unit that moved AND lost models is
## accepted only when its losses already landed per step, else nothing lands and done["unknown"] is set.
static func land_delta(main, delta: Array, start_models: Array, done: Dictionary) -> void:
	for d in delta:
		var gu: GameUnit = main.opr_army_manager.game_units.get(str(d["unit"]))
		if gu == null:
			continue
		if bool(d["unknown"]):
			var start_alive := start_models.filter(func(e) -> bool: return (e["model"] as ModelInstance).unit == gu)
			var landed_dead := start_alive.filter(func(e) -> bool: return done.has(e["model"]) \
				and not (e["model"] as ModelInstance).is_alive)
			if landed_dead.size() != start_alive.size() - int(d["alive"]):
				push_error("CoreActivation.land_delta: %s moved and lost models the steps did not land" % gu.get_name())
				done["unknown"] = true
				return
		if bool(d["shaken"]) != gu.is_shaken:
			main.radial_menu_controller.card_toggle_shaken(gu)
			main._solo_mirror_shaken(gu)
