extends SceneTree
## Stage A: fixed action -> final table model positions vs the Rust executor.
## No target selection, combat, dice, or changes to the production controller.
const Replay := preload("res://tools/node_recheck.gd")
const IN2M := 0.0254

class FixtureArmy extends OPRArmyManager:
	func _ready() -> void:
		# Units are reconstructed below; no model manifest or army API is needed.
		pass


class TableProbe extends SoloController:
	var board_in := Vector2(72, 48)
	var stages: Dictionary = {}
	var gate_calls := 0
	var shorten_calls := 0

	func _table_half_extents() -> Vector2:
		return board_in * IN2M * 0.5

	func _finalize_placement(unit: GameUnit, models: Array, start_world: Array,
			planned_world: Array, allow_contact: bool, target: GameUnit, caps: Array = []) -> Array:
		gate_calls += 1
		stages["final_placement"] = true
		if allow_contact:
			stages["charge_final_placement"] = true
		if CoherencyChecker.is_skirmish_system(unit) and models.size() > 1:
			stages["skirmish_chain"] = true
		for other in army_manager.get_all_game_units():
			if other.is_destroyed() or unit_in_reserve(other):
				continue
			for model in other.get_alive_models():
				var shape := SeparationChecker.shape_for_model(model)
				if shape != null and shape.kind != SeparationChecker.BaseShape.Kind.ROUND:
					stages["base_shapes"] = true
		return super._finalize_placement(unit, models, start_world, planned_world, allow_contact, target, caps)

	func _shorten_world_to_legal(start_world: Array, cfg: Array, models: Array,
			obstacles: Array, max_chain: float) -> Array:
		shorten_calls += 1
		stages["whole_unit_shorten"] = true
		return super._shorten_world_to_legal(start_world, cfg, models, obstacles, max_chain)

	func _has_lateral_room(unit: GameUnit, models: Array, positions: Array, reach_in: float) -> bool:
		var room := super._has_lateral_room(unit, models, positions, reach_in)
		if room:
			stages["boxed_escape"] = true
		return room

	func record_decision(rec: Dictionary) -> void:
		if str(rec.get("rule", "")).begins_with("Coherency invariant: every reach retry ended torn"):
			stages["coherency_hold"] = true
		super.record_decision(rec)


func _initialize() -> void:
	ProjectSettings.set_setting("niemandsland/harness_mode", true)
	_run.call_deferred()


func _run() -> void:
	var fixture_path := "res://test/fixtures/position_parity/cases.json"
	var out_path := ""
	var limit := 0
	for arg in OS.get_cmdline_user_args():
		var kv := arg.split("=", true, 1)
		if kv.size() != 2:
			continue
		match kv[0]:
			"fixtures": fixture_path = kv[1]
			"out": out_path = kv[1]
			"limit": limit = int(kv[1])
	if not ClassDB.class_exists("NmlCore") or OS.get_environment("NML_CORE") != "1" \
			or OS.get_environment("NML_CORE_MOVE") != "1" or out_path.is_empty():
		printerr("POSITION_PARITY_ERROR: extension, both MOVE flags, and out= are required")
		quit(2)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(fixture_path))
	if not parsed is Dictionary or int(parsed.get("schema", 0)) != 1:
		printerr("POSITION_PARITY_ERROR: invalid fixture schema")
		quit(2)
		return
	var core: Object = ClassDB.instantiate("NmlCore")
	var rows: Array = []
	for fixture in parsed["cases"]:
		if limit > 0 and rows.size() >= limit:
			break
		var row := _one(fixture, core)
		if row.is_empty():
			quit(2)
			return
		rows.append(row)
		print("position: id=%s models=%d stages=%s" % [fixture["id"], row["table_end"].size(), row["table_stages"]])
		# Free each board before constructing the next one.
		await process_frame
	var stream := FileAccess.open(out_path, FileAccess.WRITE)
	if stream == null:
		printerr("POSITION_PARITY_ERROR: cannot write report")
		quit(2)
		return
	stream.store_string(JSON.stringify({"schema": 1, "rows": rows}, "", true, true) + "\n")
	stream.close()
	quit(0)


func _one(f: Dictionary, core: Object) -> Dictionary:
	var board := Node3D.new()
	root.add_child(board)
	var army := FixtureArmy.new()
	board.add_child(army)
	var solo := TableProbe.new()
	board.add_child(solo)
	solo.setup(army, null, null)
	solo.board_in = Vector2(f["board_in"][0], f["board_in"][1])
	army.current_round = int(f["round"])
	solo.prewarm_enabled = false
	MovementPlanner.fast_planner = bool(f["fast_planner"])
	MovementPlanner.fast_planner_guard = int(f["fast_planner_guard"])
	# This instance is the reference oracle. The Rust path is called explicitly
	# below, so fallback cannot secretly provide either side of the comparison.
	SoloController._move_seam_env = 0
	SoloController._move_check_env = 0
	var units: Dictionary = {}
	var plain_units: Dictionary = {}
	for spec in f["units"]:
		var u := GameUnit.new()
		u.unit_id = str(spec["id"])
		u.unit_properties = {
			"name": u.unit_id, "player_id": int(spec["player"]), "special_rules": spec["rules"],
			"game_system": str(spec["game_system"]), "quality": 4, "defense": 4,
			"base_is_oval": spec["base_shape"] == "oval", "base_width_mm": int(spec["base_w_mm"]),
			"base_depth_mm": int(spec["base_d_mm"]), "base_size_round": int(spec["base_w_mm"]),
			"ambush_reserve": bool(spec["dormant"]),
		}
		for i in spec["positions"].size():
			var m := ModelInstance.new()
			m.unit = u
			m.is_alive = true
			m.wounds_current = maxi(1, int(spec["wounds"][i]))
			m.wounds_max = maxi(m.wounds_current, int(spec["tough"]))
			m.properties = {"tough": int(spec["tough"])}
			var node := Node3D.new()
			board.add_child(node)
			node.global_position = Replay._vec3(spec["positions"][i])
			m.node = node
			u.models.append(m)
			if absf(SoloController.model_base_radius_m(m) - float(spec["radii"][i])) > 0.00001:
				printerr("POSITION_PARITY_ERROR: base reconstruction %s/%s:%d table=%s fixture=%s" % [
					f["id"],u.unit_id,i,SoloController.model_base_radius_m(m),spec["radii"][i]])
				board.queue_free()
				return {}
		units[u.unit_id] = u
		army.game_units[u.unit_id] = u
		plain_units[u.unit_id] = {
			"player":spec["player"], "positions":spec["positions"], "radii":spec["radii"],
			"alive":spec["positions"].size(), "wounds":spec["wounds"], "activated":false,
			"attached":spec["attached"], "attached_to":spec["attached_to"], "dormant":spec["dormant"],
			"aircraft":spec["aircraft"], "charge_no_difficult":spec["charge_no_difficult"],
			"charge_probe_r":spec["charge_probe_r"],
			"profile":{"unit_id":u.unit_id, "name":u.unit_id,"quality":4,"defense":4,
				"model_count":spec["positions"].size(),"wounds_max":spec["wounds"],
				"base_shape":spec["base_shape"],"base_w_mm":spec["base_w_mm"],"base_d_mm":spec["base_d_mm"],
				"game_system":spec["game_system"],"special_rules":spec["rules"],"weapons":[]},
		}
	for spec in f["units"]:
		var u: GameUnit = units[spec["id"]]
		var heroes: Array = []
		for key in spec["attached"]:
			heroes.append(units[key])
		u.unit_properties["attached_heroes"] = heroes
		if not str(spec["attached_to"]).is_empty():
			u.unit_properties["attached_to"] = units[spec["attached_to"]]
	solo.terrain_type_at = Replay.terrain_at_from_plain(f["terrain"])
	var walls: Array = []
	for wall in f["terrain"]["walls"]:
		walls.append([Vector2(wall[0][0],wall[0][1]),Vector2(wall[1][0],wall[1][1])])
	solo.walls_provider = func() -> Array: return walls
	var action: Dictionary = f["action"]
	var actor: GameUnit = units[action["unit"]]
	var target: GameUnit = units.get(action["target"])
	var models := solo._moving_models(actor)
	var ids: Array = []
	for model in models:
		ids.append("%s:%d" % [model.unit.unit_id,model.unit.models.find(model)])
	var charge_gap: Variant = null
	var snap_in: Variant = null
	var started := Time.get_ticks_usec()
	if int(action["kind"]) == 3:
		solo._charge_move(actor, target, float(action["band_in"]))
		charge_gap = solo.nearest_melee_gap_in(actor,target)
		if float(charge_gap) <= SoloController.MELEE_ENGAGE_IN:
			solo.stages["charge_snap"] = true
			snap_in = solo.snap_charge(actor,target,solo.last_move_remaining_in())
	elif int(action["kind"]) in [1,2]:
		solo._move_toward(actor,Replay._vec3(action["dest"]),float(action["band_in"]),false)
	var table_us := Time.get_ticks_usec()-started
	var table_end := _points(solo._positions_of(models))
	var envelope := {"state":{"units":plain_units,"round":int(f["round"]),"rounds_total":4,
		"scoring":"end_of_round","objectives":[]},"terrain":f["terrain"],"band_in":action["band_in"],
		"action":{"unit":action["unit"],"kind":action["kind"],"dest":action["dest"],"charge":action["target"]}}
	started = Time.get_ticks_usec()
	var rust: Dictionary = core.plan_unit_step({"position_action":envelope},
		MovementPlanner.fast_planner,MovementPlanner.fast_planner_guard)
	var rust_us := Time.get_ticks_usec()-started
	var row := {"id":f["id"],"model_ids":ids,"table_end":table_end,
		"rust_end":_points(rust.get("position_end",[])),"rust_model_ids":rust.get("model_ids",[]),
		"rust_ok":bool(rust.get("ok",false)),"boundary_reason":str(rust.get("decline_reason","")),
		"boundary_error":str(rust.get("error","")),"table_stages":solo.stages.keys(),
		"rust_capabilities":rust.get("stage_a_capabilities",[]),"gate_calls":solo.gate_calls,
		"shorten_calls":solo.shorten_calls,"timing_us":{"table":table_us,"rust":rust_us},
		"table_budget_in":solo.last_move_budget_in,"rust_budget_in":rust.get("budget_in",0.0),
		"table_charge_gap_in":charge_gap,"table_snap_in":snap_in,
		"rust_arc_in":rust.get("arc_in",0.0),"rust_snap_in":rust.get("snap_in",null)}
	if f.has("formation_call"):
		# The ordinary seam marshals JSON-widened cells back to integers before
		# its corpus reader runs. Reuse that normalization, then obtain live vectors.
		var normalized: String = core.move_call_roundtrip(f["formation_call"])
		var call: Dictionary = core.move_line_to_dict(normalized)
		if call.is_empty():
			printerr("POSITION_PARITY_ERROR: formation input %s: %s" % [f["id"],core.last_error()])
			board.queue_free()
			return {}
		var result: Dictionary = core.plan_unit_step(call,MovementPlanner.fast_planner,MovementPlanner.fast_planner_guard)
		var trails: Array = []
		var opts: Dictionary = call["opts"].duplicate(true)
		var reference := MovementPlanner.plan_unit_step(call["model_pos"],call["delta"],call["walls"],
			call["grid"],call["allow_contact"],call["board_in"],trails,opts)
		row["formation"] = {"table":_points2(reference),"rust":_points2(result.get("planned",[])),
			"recorded":f["formation_call"]["planned"],"ok":bool(result.get("ok",false)),
			"reason":str(result.get("decline_reason",""))}
	# Break RefCounted model/unit and attached-hero cycles before freeing nodes.
	for u in units.values():
		u.unit_properties["attached_heroes"] = []
		u.unit_properties["attached_to"] = null
		for model in u.models:
			model.unit = null
			model.node = null
		u.models.clear()
	army.game_units.clear()
	board.queue_free()
	return row


func _points(points: Array) -> Array:
	var out: Array = []
	for p in points:
		out.append([p.x,p.y,p.z])
	return out


func _points2(points: Array) -> Array:
	var out: Array = []
	for p in points:
		out.append([p.x,p.y])
	return out
