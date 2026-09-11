class_name GameRecordCollector
extends Node
## In-memory record of one game (solo/multiplayer, human/AI seats), fed only by the central seams
## BattleLog uses: move (per-model from->to), activation, dice faces, round advance, final VP.
## No disk, no network; SharedRecordBuilder still filters the payload (assets/privacy/example_record.json).
const NOT_RECORDED := ["charge declarations", "shooting shooter and weapon", "which models fire", "wound-allocation choice", "modal decisions (saves, strike-back, interference, casts)", "human spell casts", "morale choices", "objective seizes in plain multiplayer", "turn structure in human-vs-human games"]
var _main = null
var _actions: Array = []
var _rounds: int = 1
var _current_round: int = 1


func bind(main) -> void:
	_main = main
	if main.opr_army_manager != null:
		_rounds = maxi(1, main.opr_army_manager.current_round)
		_current_round = _rounds


func action_count() -> int:
	return _actions.size()


func on_unit_activated(gu) -> void:
	if gu != null:
		_append("activate", _unit_id(gu), _side(gu), _unit_pos(gu), [], "", [])


func on_selection_dropped(moves: Array) -> void:
	for mv in moves:
		var gu: GameUnit = _main._trail_unit_of(mv.get("node")) if _main != null else null
		if gu == null:
			continue
		var a: Vector3 = mv.get("from", Vector3.ZERO)
		var b: Vector3 = mv.get("to", Vector3.ZERO)
		_append("move", _unit_id(gu), _side(gu), [a.x, a.z], [b.x, b.z], "", [])


func on_dice_rolled(faces: Array, _context: Dictionary) -> void:
	var ints: Array = []
	for f in faces:
		ints.append(int(f))
	_append("roll", "", 0, [], [], "", ints)


func on_round_advanced(round_number: int) -> void:
	_current_round = round_number
	_rounds = maxi(_rounds, round_number)


## The in-memory record (not the payload); `not_recorded` survives here, the allowlist decides what may leave.
func build_record() -> Dictionary:
	var mission := str(_main._solo_mission_id) if _main != null else ""
	var table := {}
	if _main != null and _main.table != null:
		table = {"width_inches": _main.table.table_size.x * 12.0, "height_inches": _main.table.table_size.y * 12.0}
	return {
		"payload_schema_version": 1, "consent_schema_version": 1, "record_id": "local-game",
		"game_version": str(ProjectSettings.get_setting("application/config/version", "")),
		"build_hash": "", "core_abi": 1, "rules_epoch": AiActRecorder.rules_epoch, "training_use": false,
		"brain": {"engine": "classic", "id": "classic", "hash": ""},
		"game": {"system_id": "opr", "mission_id": mission if not mission.is_empty() else "duel", "scoring_id": SoloController.mission_scoring},
		"table": table, "armies": _armies(), "actions": _actions, "rounds": _rounds,
		"final": _final(), "not_recorded": NOT_RECORDED.duplicate(),
	}


func _append(kind: String, unit_id: String, side: int, from: Array, to: Array, target_id: String, faces: Array) -> void:
	var entry := {"index": _actions.size(), "round": _current_round, "side": side, "kind": kind, "from": from, "to": to, "target_id": target_id, "dice_faces": faces}
	if not unit_id.is_empty():
		entry["unit_id"] = unit_id
	_actions.append(entry)


func _armies() -> Array:
	var sides := {}
	if _main != null and _main.opr_army_manager != null:
		for gu in _main.opr_army_manager.game_units.values():
			var side := _side(gu)
			if not sides.has(side):
				sides[side] = {"side": side, "units": []}
			(sides[side]["units"] as Array).append({"unit_id": _unit_id(gu), "profile_id": _unit_id(gu), "quality": int(gu.get_quality()), "defense": int(gu.get_defense()), "model_count": gu.models.size()})
	return sides.values()


func _final() -> Dictionary:
	var vp: Array = []
	if SoloController.mission_vp.size() >= 2:
		vp = [int(SoloController.mission_vp[0]), int(SoloController.mission_vp[1])]
	var outcome := "draw"
	if vp.size() >= 2 and vp[0] != vp[1]:
		outcome = "side-1" if vp[0] > vp[1] else "side-2"
	var owners: Array = []
	if _main != null and _main.terrain_overlay != null:
		owners = _main.terrain_overlay.get_objective_owners()
	return {"vp": vp, "objective_owners": owners, "outcome": outcome}


func _unit_id(gu) -> String:
	return str(gu.unit_id) if gu != null else ""


func _side(gu) -> int:
	return int(gu.unit_properties.get("player_id", 0)) if gu != null else 0


func _unit_pos(gu) -> Array:
	if gu == null:
		return []
	for model in gu.models:
		var mi := model as ModelInstance
		if mi != null and mi.is_alive and mi.node != null and is_instance_valid(mi.node):
			return [mi.node.global_position.x, mi.node.global_position.z]
	return []