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
