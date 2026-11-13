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
		land_step(main, unit, r.get("landings", []), [], landed)
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


## Lands one step's landings on the table (O4 b). Empty until step 21.
static func land_step(_main, _gu: GameUnit, _landings: Array, _start_models: Array, _done: Dictionary) -> void:
	pass
