extends Node
class_name SaveManager
## Manages saving and loading of game state
## Supports both local saves and multiplayer sync

signal save_completed(path: String)
signal load_completed(object_count: int)
signal load_failed(error: String)

const SAVE_VERSION = "1.6"  # Schema checkpoint (goal 002): normalises the post-1.5 no-bump additions.
# RULE: whoever bumps SAVE_VERSION ships the matching SaveMigrations step + fixture test in the SAME
# change — see scripts/save_migrations.gd for the chain and docs/ARCHITECTURE.md.
const SAVE_EXTENSION = "nml"  # Niemandsland Save
## Yield to the main loop every N object spawns during a load/army-receive so heavy GLB
## instantiation never blocks the thread for seconds — a long stall starves the relay
## heartbeat (_poll runs in _process) and the relay drops the client, kicking off a reconnect.
## Yield after EVERY object: a first-time GLB goes through a synchronous GLTFDocument parse
## (~200-800ms each), and yielding every 3 let up to three parses pile into one frame (the
## observed 7.6s freeze on a guest receiving an army). Every-1 caps a frozen frame at a single
## parse so a heartbeat always fires between parses. Tray reveal / hero-attach / regiment-form
## all run AFTER this loop, so finer yielding can't reveal models piecemeal or race attachment.
const DESERIALIZE_YIELD_EVERY := 1

var object_manager: Node3D
var table: Node3D
var army_manager: OPRArmyManager  # Reference for GameUnit data
var map_layout_editor: Control  # Reference to map layout editor (terrain, zones, objectives)
var terrain_overlay: Node3D  # Reference to 3D terrain overlay
var radial_menu_controller: Node  # Reference for token/marker visualization after load


func _ready() -> void:
	# Will be set by main.gd
	pass


## Serialize current game state to dictionary
func serialize_game_state() -> Dictionary:
	var state = {
		"version": SAVE_VERSION,
		"saved_at": Time.get_datetime_string_from_system(),
		"table": _serialize_table(),
		"objects": _serialize_objects(),
		"game_units": _serialize_game_units(),
		"game_state": _serialize_game_state(),
		"object_counter": object_manager._object_counter if object_manager else 0
	}
	# OPR special-rule descriptions so loaded saves + remote peers can show them
	# (they carry no OPRArmy with the descriptions otherwise).
	if army_manager and army_manager.has_method("get_all_rule_descriptions"):
		state["rule_descriptions"] = army_manager.get_all_rule_descriptions()
	# Faction spell lists (per player) so loaded saves + remote casters can show their spells.
	if army_manager and army_manager.has_method("get_all_player_spells"):
		state["player_spells"] = army_manager.get_all_player_spells()
	# player_id -> army name, so a .nml load / late-joiner can rebuild each army's tray.
	state["army_names"] = _army_names_by_player()
	return state


## player_id -> army name for the loaded/synced armies.
func _army_names_by_player() -> Dictionary:
	var names := {}
	if army_manager:
		for pid in army_manager.armies:
			var a = army_manager.armies[pid]
			if a:
				names[pid] = a.name
	return names


## Recreate each army's TRAY (the platform it stands on) from the just-loaded game units.
## .nml load AND the late-joiner state sync rebuild units + models but NOT the tray, so without
## this an army shows as floating models with no tableau. One tray per distinct player_id.
func restore_army_trays_after_load(army_names: Dictionary) -> void:
	if not army_manager:
		return
	var seen := {}
	for unit_id in _loaded_game_units:
		var gu = _loaded_game_units[unit_id].get("game_unit")
		if gu == null:
			continue
		var pid := int(gu.unit_properties.get("player_id", 0))
		if pid > 0 and not seen.has(pid):
			seen[pid] = true
			var aname := str(army_names.get(pid, "Army"))
			var acol = OPRArmyManager.army_color(pid, Color.GRAY)
			army_manager._create_army_tray(pid, aname, acol)


## Serialize table state including map layout (terrain, deployment, objectives)
func _serialize_table() -> Dictionary:
	if not table:
		return {"size_feet": [6, 4]}

	var data = {
		"size_feet": [table.table_size.x, table.table_size.y],
		"biome": table.biome
	}

	# Serialize map layout data from map_layout_editor
	if map_layout_editor:
		data["grid_rotation"] = map_layout_editor.grid_rotation_degrees
		data["deployment_type"] = map_layout_editor.deployment_type

		# Grid cells - convert Vector2i keys to strings for JSON
		var cells = {}
		for cell_pos in map_layout_editor.grid_cells:
			var key = "%d,%d" % [cell_pos.x, cell_pos.y]
			cells[key] = map_layout_editor.grid_cells[cell_pos]
		data["grid_cells"] = cells

		# Custom deployment zones (1" coordinates)
		var custom_zones = {"player1": [], "player2": []}
		for v in map_layout_editor.custom_zone_vertices_p1:
			custom_zones["player1"].append({"x": v.x, "y": v.y})
		for v in map_layout_editor.custom_zone_vertices_p2:
			custom_zones["player2"].append({"x": v.x, "y": v.y})
		data["custom_zones"] = custom_zones

		# Mission objectives (1" coordinates) + per-objective owner (capture state)
		var objectives = []
		var obj_owners: Array = []
		if terrain_overlay and terrain_overlay.has_method("get_objective_owners"):
			obj_owners = terrain_overlay.get_objective_owners()
		for i in range(map_layout_editor.mission_objectives.size()):
			var obj = map_layout_editor.mission_objectives[i]
			var owner_id := int(obj_owners[i]) if i < obj_owners.size() else 0
			objectives.append({"x": obj.x, "y": obj.y, "owner": owner_id})
		data["mission_objectives"] = objectives

		# Wall segments (modular terrain). role/taper_dir drive the ruin shell-wall
		# look (crumble taper + panel pick); old saves without them fall back to "full".
		var walls = []
		for wall in map_layout_editor.wall_segments:
			walls.append({
				"edge_cell_x": wall.get("edge_cell", Vector2i.ZERO).x,
				"edge_cell_y": wall.get("edge_cell", Vector2i.ZERO).y,
				"edge_side": wall.get("edge_side", 0),
				"wall_key": wall.get("wall_key", ""),
				"length_inches": wall.get("length_inches", 3.0),
				"sub_position": wall.get("sub_position", 0),
				"role": wall.get("role", "full"),
				"taper_dir": wall.get("taper_dir", -1),
			})
		data["wall_segments"] = walls

		# Placed objects (trees, containers)
		var objects = []
		for obj in map_layout_editor.placed_objects:
			objects.append({
				"object_key": obj.get("object_key", ""),
				"cell_x": obj.get("cell", Vector2i.ZERO).x,
				"cell_y": obj.get("cell", Vector2i.ZERO).y,
				"offset_x": obj.get("offset", Vector2(0.5, 0.5)).x,
				"offset_y": obj.get("offset", Vector2(0.5, 0.5)).y,
				"object_type": obj.get("object_type", "tree"),
			})
		data["placed_objects"] = objects

	# Terrain overlay display mode
	if terrain_overlay:
		data["overlay_mode"] = terrain_overlay.get_overlay_mode() if terrain_overlay.has_method("get_overlay_mode") else 0

	return data


## Serialize all objects on the table
func _serialize_objects() -> Array:
	var objects: Array = []

	if not object_manager:
		return objects

	for child in object_manager.get_children():
		if not child is Node3D:
			continue
		if not child.is_in_group("selectable"):
			continue

		var obj_data = _serialize_object(child)
		if not obj_data.is_empty():
			objects.append(obj_data)

	return objects


## Serialize a single object
func _serialize_object(obj: Node3D) -> Dictionary:
	var data: Dictionary = {}

	# Determine object type
	if obj.is_in_group("opr_unit"):
		data["type"] = "opr_unit"
		# Store GameUnit reference info
		var game_unit = obj.get_meta("game_unit", null)
		if game_unit:
			data["game_unit_id"] = game_unit.unit_id
			data["model_index"] = obj.get_meta("model_index", 0)
			# The RESOLVED model key (loadout variant / mount) - restore re-resolves the exact model;
			# absent on pre-0.3.8 saves (falls back to the unit name, the old behavior).
			var stamped_glb: String = str(obj.get_meta("glb_name", ""))
			if not stamped_glb.is_empty():
				data["glb_name"] = stamped_glb
	elif obj.is_in_group("tts_import"):
		data["type"] = "tts_import"
		data["tts_mesh_url"] = obj.get_meta("tts_mesh_url", "")
		data["tts_diffuse_url"] = obj.get_meta("tts_diffuse_url", "")
	elif obj.is_in_group("custom_model"):
		data["type"] = "custom_model"
		data["model_path"] = obj.get_meta("model_path", "")
	elif obj.is_in_group("miniature"):
		data["type"] = "miniature"
	elif obj.is_in_group("sandbox_terrain"):
		# Free-placed casual terrain (ruin / forest / hazard cluster). Checked BEFORE the
		# generic "terrain" group, which it also belongs to. Cluster members rebuild
		# deterministically from the (saved) network_id seed, so only the identity is stored.
		data["type"] = "sandbox_terrain"
		data["prop_id"] = obj.get_meta("prop_id", "")
		data["prop_kind"] = obj.get_meta("prop_kind", 0)
	elif obj.is_in_group("terrain"):
		data["type"] = "terrain"
	else:
		# Unknown type, skip
		return {}

	# Common properties
	data["name"] = obj.name
	data["network_id"] = obj.get_meta("network_id", 0)
	data["position"] = [obj.global_position.x, obj.global_position.y, obj.global_position.z]
	data["rotation"] = [obj.rotation_degrees.x, obj.rotation_degrees.y, obj.rotation_degrees.z]
	# Persist a deleted (hidden) generic object so it stays deleted after reload.
	data["visible"] = obj.visible

	return data


## Serialize all GameUnits with model-level data
func _serialize_game_units() -> Array:
	var units: Array = []

	if not army_manager:
		return units

	for game_unit in army_manager.get_all_game_units():
		var unit_data = game_unit.to_dict()

		# Add node positions for each model
		var model_positions: Array = []
		for model in game_unit.models:
			if model.node and is_instance_valid(model.node):
				# A parked dead loose model is saved at its REVIVE spot (its original table position),
				# not the tray slot — restore places it there and the post-load hook re-parks it (G4).
				var is_dead: bool = bool(model.node.get_meta("deleted", false))
				var pos: Vector3 = model.node.global_position
				if is_dead and model.node.has_meta("revive_transform"):
					pos = (model.node.get_meta("revive_transform") as Transform3D).origin
				var entry: Dictionary = {
					"position": [pos.x, pos.y, pos.z],
					"rotation": [model.node.rotation_degrees.x, model.node.rotation_degrees.y, model.node.rotation_degrees.z],
					"visible": model.node.visible
				}
				if is_dead:
					entry["deleted"] = true
					entry["dead_slot"] = int(model.node.get_meta("dead_slot", -1))
				model_positions.append(entry)
			else:
				model_positions.append(null)

		unit_data["model_positions"] = model_positions

		# Age of Fantasy: Regiments — persist the movement-tray block (frontage +
		# tray transform). Member models are the unit's own models.
		if army_manager.regiments.has(game_unit.unit_id):
			var reg = army_manager.regiments[game_unit.unit_id]
			if reg and is_instance_valid(reg.tray):
				unit_data["regiment"] = reg.to_dict()

		units.append(unit_data)

	return units


## Serialize global game state (round, turn, etc.)
func _serialize_game_state() -> Dictionary:
	var lib: Dictionary = {}
	if radial_menu_controller and radial_menu_controller.token_library:
		lib = radial_menu_controller.token_library.to_dict()
	return {
		"current_round": army_manager.current_round if army_manager else 1,
		# Formal game phase (0 = deployment, 1 = playing). A game saved mid-play reloads in PLAYING;
		# a fresh table saved during setup reloads in DEPLOYMENT. Also carried on the MP full-state
		# push (host -> joining/reconnecting guest) since that path reuses this serializer.
		"game_phase": army_manager.game_phase if army_manager else OPRArmyManager.GamePhase.DEPLOYMENT,
		"current_player": 1,  # No turn-order system yet; players track this themselves
		"token_library": lib
	}


## Save game state to file
func save_game(path: String) -> Error:
	var state = serialize_game_state()

	var json_string = JSON.stringify(state, "\t")  # Pretty print with tabs

	var file = FileAccess.open(path, FileAccess.WRITE)
	if not file:
		var error = FileAccess.get_open_error()
		push_error("Failed to open save file: %s (error %d)" % [path, error])
		return error

	file.store_string(json_string)
	file.close()

	print("Game saved to: %s (%d objects)" % [path, state.objects.size()])
	save_completed.emit(path)
	return OK


## Load game state from file
func load_game(path: String) -> Error:
	if not FileAccess.file_exists(path):
		load_failed.emit("File not found: %s" % path)
		return ERR_FILE_NOT_FOUND

	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		var error = FileAccess.get_open_error()
		load_failed.emit("Failed to open file: %s" % path)
		return error

	var json_string = file.get_as_text()
	file.close()

	var json = JSON.new()
	var parse_error = json.parse(json_string)
	if parse_error != OK:
		load_failed.emit("JSON parse error at line %d" % json.get_error_line())
		return parse_error

	var state = json.data
	if not state is Dictionary:
		load_failed.emit("Invalid save file format")
		return ERR_INVALID_DATA

	# Versioned migration (goal 002): the current format passes through, supported older formats are
	# lifted step by step, pre-alpha or newer-build saves fail with a CLEAR message instead of loading
	# into silent data damage (the old code only push_warning'ed and loaded anyway).
	var migration := SaveMigrations.migrate(state)
	if not bool(migration["ok"]):
		load_failed.emit(str(migration["error"]))
		return ERR_INVALID_DATA
	state = migration["state"]
	if not str(migration["migrated_from"]).is_empty():
		print("[SaveManager] migrated save from version %s to %s" % [migration["migrated_from"], SAVE_VERSION])

	# Clear current state
	if object_manager:
		object_manager.clear_all_objects()

	# Load table
	_deserialize_table(state.get("table", {}))

	# Restore OPR special-rule descriptions so the loaded army shows them.
	if army_manager and army_manager.has_method("merge_rule_descriptions"):
		army_manager.merge_rule_descriptions(state.get("rule_descriptions", {}))

	# Load GameUnits first (they contain model-level state)
	var game_units_loaded = _deserialize_game_units(state.get("game_units", []))

	# Load objects (async for TTS downloads)
	var loaded_count = await _deserialize_objects(state.get("objects", []))

	# Rebuild Age of Fantasy: Regiments movement-tray blocks now that the model
	# nodes exist and are wired to their loaded GameUnits.
	_restore_regiments_after_load()

	# Recreate each army's tray (the platform it stands on) — same gap as the late-joiner sync.
	restore_army_trays_after_load(state.get("army_names", {}))

	# Re-park loose models saved dead (needs the trays above to exist so slots can be claimed).
	_restore_dead_parking_after_load()

	# Restore game state
	_deserialize_game_state(state.get("game_state", {}))

	# Rebuild hero attachment (stored as unit_ids) into live GameUnit refs.
	_restore_hero_attachments_after_load()

	# Restore token/marker visualizations for all loaded game units
	_restore_markers_after_load()

	print("Game loaded from: %s (%d objects, %d game units)" % [path, loaded_count, game_units_loaded])
	load_completed.emit(loaded_count)
	return OK


## Deserialize table state including map layout (terrain, deployment, objectives)
func _deserialize_table(table_data: Dictionary) -> void:
	if not table:
		return

	var size = table_data.get("size_feet", [6, 4])
	var table_size = Vector2(6, 4)
	if size is Array and size.size() >= 2:
		table_size = Vector2(size[0], size[1])
		table.setup_table(table_size)

	if table_data.has("biome") and table.has_method("set_biome"):
		table.set_biome(table_data["biome"])

	# Restore map layout data
	_deserialize_map_layout(table_data, table_size)


## Deserialize map layout data (terrain grid, deployment zones, objectives)
func _deserialize_map_layout(table_data: Dictionary, table_size: Vector2) -> void:
	var grid_rotation = float(table_data.get("grid_rotation", 0.0))
	var deployment_type = int(table_data.get("deployment_type", 0))

	# Parse grid cells (string keys -> Vector2i)
	var grid_cells = {}
	var cells_data = table_data.get("grid_cells", {})
	if cells_data is Dictionary:
		for key in cells_data:
			var coords = str(key).split(",")
			if coords.size() == 2:
				var cell_pos = Vector2i(int(coords[0]), int(coords[1]))
				grid_cells[cell_pos] = int(cells_data[key])

	# Parse custom deployment zones (1" coordinates)
	var custom_p1: Array[Vector2] = []
	var custom_p2: Array[Vector2] = []
	var custom_zones = table_data.get("custom_zones", {})
	if custom_zones is Dictionary:
		for v in custom_zones.get("player1", []):
			if v is Dictionary:
				custom_p1.append(Vector2(float(v.get("x", 0)), float(v.get("y", 0))))
		for v in custom_zones.get("player2", []):
			if v is Dictionary:
				custom_p2.append(Vector2(float(v.get("x", 0)), float(v.get("y", 0))))

	# Parse mission objectives (1" coordinates) + owners (default neutral)
	var objectives: Array[Vector2] = []
	var objective_owners: Array[int] = []
	for obj in table_data.get("mission_objectives", []):
		if obj is Dictionary:
			objectives.append(Vector2(float(obj.get("x", 0)), float(obj.get("y", 0))))
			objective_owners.append(int(obj.get("owner", 0)))

	# Parse wall segments (role/taper_dir default for saves from before the shell walls)
	var wall_segments: Array[Dictionary] = []
	for w in table_data.get("wall_segments", []):
		if w is Dictionary:
			wall_segments.append({
				"edge_cell": Vector2i(int(w.get("edge_cell_x", 0)), int(w.get("edge_cell_y", 0))),
				"edge_side": int(w.get("edge_side", 0)),
				"wall_key": str(w.get("wall_key", "")),
				"length_inches": float(w.get("length_inches", 3.0)),
				"sub_position": int(w.get("sub_position", 0)),
				"role": str(w.get("role", "full")),
				"taper_dir": int(w.get("taper_dir", -1)),
			})

	# Parse placed objects
	var placed_objects: Array[Dictionary] = []
	for o in table_data.get("placed_objects", []):
		if o is Dictionary:
			placed_objects.append({
				"object_key": str(o.get("object_key", "")),
				"cell": Vector2i(int(o.get("cell_x", 0)), int(o.get("cell_y", 0))),
				"offset": Vector2(float(o.get("offset_x", 0.5)), float(o.get("offset_y", 0.5))),
				"object_type": str(o.get("object_type", "tree")),
			})

	# Apply to map_layout_editor (stores raw data in 1" / cell coordinates)
	if map_layout_editor:
		map_layout_editor.table_size_feet = table_size
		map_layout_editor.grid_cells = grid_cells
		map_layout_editor.grid_rotation_degrees = grid_rotation
		map_layout_editor.deployment_type = deployment_type
		map_layout_editor.custom_zone_vertices_p1 = custom_p1
		map_layout_editor.custom_zone_vertices_p2 = custom_p2
		map_layout_editor.mission_objectives = objectives
		map_layout_editor.wall_segments = wall_segments
		map_layout_editor.placed_objects = placed_objects

	# Apply to 3D terrain overlay
	if terrain_overlay:
		# Update terrain cells
		if terrain_overlay.has_method("update_overlay"):
			terrain_overlay.update_overlay(grid_cells, table_size, grid_rotation)

		# Set deployment zones
		if terrain_overlay.has_method("set_deployment_zones"):
			# For custom zones, set zone vertices first
			if deployment_type == 2 and map_layout_editor:
				var zone_data = map_layout_editor.get_custom_zone_data()
				if terrain_overlay.has_method("set_custom_zones"):
					terrain_overlay.set_custom_zones(zone_data.player1_world, zone_data.player2_world)
			terrain_overlay.set_deployment_zones(deployment_type)

		# Show deployment zones if a type is set
		if deployment_type > 0 and terrain_overlay.has_method("set_deployment_zones_visible"):
			terrain_overlay.set_deployment_zones_visible(true)

		# Update mission objectives (convert 1" to world coords), restoring owners
		if not objectives.is_empty() and map_layout_editor:
			if map_layout_editor.has_method("get_objectives_for_overlay"):
				var world_objectives = map_layout_editor.get_objectives_for_overlay()
				if terrain_overlay.has_method("update_objectives"):
					terrain_overlay.update_objectives(world_objectives, objective_owners)

		# Restore wall models in 3D
		if not wall_segments.is_empty():
			if terrain_overlay.has_method("update_wall_models"):
				terrain_overlay.update_wall_models(wall_segments, table_size, grid_rotation)

		# Restore placed objects (trees, containers) in 3D
		if not placed_objects.is_empty():
			if terrain_overlay.has_method("update_placed_objects"):
				terrain_overlay.update_placed_objects(placed_objects, table_size, grid_rotation)

	# Restore terrain overlay display mode
	if terrain_overlay:
		var overlay_mode_val: int = int(table_data.get("overlay_mode", 0))
		if terrain_overlay.has_method("set_overlay_mode"):
			terrain_overlay.set_overlay_mode(overlay_mode_val)

	print("Map layout restored: %d cells, rotation=%.1f, deployment=%d, walls=%d, objects=%d" % [
		grid_cells.size(), grid_rotation, deployment_type,
		wall_segments.size(), placed_objects.size()
	])


## Deserialize all objects (async for TTS downloads)
func _deserialize_objects(objects_data: Array) -> int:
	if not object_manager:
		return 0

	var loaded_count = 0
	var since_yield := 0

	for obj_data in objects_data:
		if not obj_data is Dictionary:
			continue

		var success = await _deserialize_object(obj_data)
		if success:
			loaded_count += 1

		# Keep the main loop (and the relay heartbeat) alive during a big synchronous spawn.
		since_yield += 1
		if since_yield >= DESERIALIZE_YIELD_EVERY:
			since_yield = 0
			if is_inside_tree():
				await get_tree().process_frame

	return loaded_count


## Deserialize and spawn a single object (async for TTS downloads)
func _deserialize_object(data: Dictionary) -> bool:
	var obj_type = data.get("type", "")
	var position = _array_to_vector3(data.get("position", [0, 0, 0]))
	var rotation = _array_to_vector3(data.get("rotation", [0, 0, 0]))

	var spawned_obj: Node3D = null

	# Preserve network_id from serialized data (broadcast=false to avoid re-broadcasting)
	var net_id = int(data.get("network_id", -1))

	match obj_type:
		"opr_unit":
			var game_unit_id = data.get("game_unit_id", "")
			var model_idx = data.get("model_index", 0)
			if army_manager and _loaded_game_units.has(game_unit_id):
				# Idempotency: the host army is delivered via BOTH state-sync and broadcast, so a
				# model can arrive twice. If one with this network_id already exists, rebind it
				# instead of spawning a duplicate (restore_game_unit_state only sets metas/pos).
				if net_id >= 0 and object_manager.has_method("find_by_network_id"):
					var existing: Node3D = object_manager.find_by_network_id(net_id)
					if is_instance_valid(existing):
						restore_game_unit_state(existing, game_unit_id, model_idx)
						return true
				var loaded = _loaded_game_units[game_unit_id]
				var game_unit = loaded.game_unit as GameUnit
				var props = game_unit.unit_properties
				# Per-model base: pass this model's Tough so an upgraded model (weapon team) re-derives
				# its bigger base on the remote/save side (no schema change — tough is already synced).
				var model_tough := 0
				if model_idx < game_unit.models.size():
					model_tough = int(game_unit.models[model_idx].properties.get("tough", 0))
				# Heartbeat tick right before a possibly first-time synchronous GLTF parse.
				if is_inside_tree():
					await get_tree().process_frame
				spawned_obj = army_manager.create_model_from_properties(props, model_tough, str(data.get("glb_name", "")))
				if spawned_obj:
					object_manager.add_child(spawned_obj)
					spawned_obj.global_position = position
					spawned_obj.rotation_degrees = rotation
					if net_id >= 0:
						spawned_obj.set_meta("network_id", net_id)
					restore_game_unit_state(spawned_obj, game_unit_id, model_idx)
					return true
			else:
				push_warning("Could not restore OPR unit: game_unit_id=%s" % game_unit_id)
			return false
		"tts_import":
			spawned_obj = await _spawn_tts_object(data, position)
		"custom_model":
			var model_path = data.get("model_path", "")
			if not model_path.is_empty():
				spawned_obj = object_manager.spawn_custom_model(model_path, position)
		"miniature":
			spawned_obj = object_manager.spawn_miniature(position, false, net_id)
		"terrain":
			spawned_obj = object_manager.spawn_terrain(position, false, net_id)
		"sandbox_terrain":
			var prop_id = data.get("prop_id", "")
			var prop_kind = int(data.get("prop_kind", 0))
			spawned_obj = object_manager.spawn_sandbox_terrain(prop_id, prop_kind, position, false, net_id)
		_:
			push_warning("Unknown object type: %s" % obj_type)
			return false

	if spawned_obj:
		spawned_obj.rotation_degrees = rotation
		# Preserve serialized network_id for all object types (TTS, custom models, etc.)
		if net_id >= 0:
			spawned_obj.set_meta("network_id", net_id)
		# Restore a persisted delete (hidden) state for generic objects. A hidden/deleted object
		# also drops its collision so it isn't measured/selected at its old spot (dead-base bug).
		var was_visible := bool(data.get("visible", true))
		spawned_obj.visible = was_visible
		spawned_obj.set_meta("deleted", not was_visible)
		if not was_visible and spawned_obj is CollisionObject3D:
			spawned_obj.collision_layer = 0
		return true

	return false


## Spawn a TTS object from saved data
func _spawn_tts_object(data: Dictionary, position: Vector3) -> Node3D:
	var mesh_url = data.get("tts_mesh_url", "")
	var diffuse_url = data.get("tts_diffuse_url", "")

	if mesh_url.is_empty():
		return null

	# Check if we have this in cache already
	var dm = TTSDownloadManager.new()
	add_child(dm)

	var mesh_path = dm.find_cached_file(mesh_url, true)
	var texture_path = ""
	if not diffuse_url.is_empty():
		texture_path = dm.find_cached_file(diffuse_url, false)

	if mesh_path.is_empty():
		# Need to download - queue it
		dm.queue_download(mesh_url, true)
		if not diffuse_url.is_empty():
			dm.queue_download(diffuse_url, false)

		# Wait for downloads
		await dm.all_downloads_completed

		mesh_path = dm.find_cached_file(mesh_url, true)
		if not diffuse_url.is_empty():
			texture_path = dm.find_cached_file(diffuse_url, false)

	dm.queue_free()

	if mesh_path.is_empty():
		push_warning("Failed to get mesh for TTS object")
		return null

	# Load the model
	var model = object_manager._load_obj_model(mesh_path, texture_path, true)
	if not model:
		return null

	# Scale it (TTS units to meters)
	var tts_scale = 0.0254
	model.scale = Vector3(tts_scale, tts_scale, tts_scale)

	# Create wrapper
	object_manager._object_counter += 1
	var wrapper = StaticBody3D.new()
	wrapper.name = "TTS_Loaded_%d" % object_manager._object_counter
	wrapper.set_meta("network_id", object_manager._object_counter + 30000)
	wrapper.set_meta("tts_mesh_url", mesh_url)
	wrapper.set_meta("tts_diffuse_url", diffuse_url)
	wrapper.add_to_group("selectable")
	wrapper.add_to_group("tts_import")

	# Position model on base
	model.position.y = 0.003
	wrapper.add_child(model)

	# Add base
	var base = object_manager._create_miniature_base()
	wrapper.add_child(base)

	# Add collision
	var collision = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(0.032, 0.05, 0.032)
	collision.shape = shape
	collision.position = Vector3(0, 0.025, 0)
	wrapper.add_child(collision)

	# Add selection script
	wrapper.set_script(preload("res://scripts/selectable_object.gd"))

	object_manager.add_child(wrapper)
	wrapper.global_position = position

	return wrapper


## Helper: Convert array to Vector3
func _array_to_vector3(arr: Array) -> Vector3:
	if arr.size() >= 3:
		return Vector3(arr[0], arr[1], arr[2])
	return Vector3.ZERO


## Get save file path with dialog (called from main.gd)
static func get_default_save_dir() -> String:
	var dir = OS.get_user_data_dir().path_join("saves")
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	return dir


## Newest .nml save in a directory (default: the standard save dir), for the menu's
## CONTINUE entry. Returns {} when none exist, else { "path", "name", "modified_unix" }.
static func latest_save_info(dir_path: String = "") -> Dictionary:
	var dir := dir_path if not dir_path.is_empty() else get_default_save_dir()
	var best_path := ""
	var best_time := 0
	for file in DirAccess.get_files_at(dir):
		if not file.to_lower().ends_with(".nml"):
			continue
		var path := dir.path_join(file)
		var modified := FileAccess.get_modified_time(path)
		if modified > best_time:
			best_time = modified
			best_path = path
	if best_path.is_empty():
		return {}
	return {
		"path": best_path,
		"name": best_path.get_file().get_basename(),
		"modified_unix": best_time,
	}


# ===== GameUnit Deserialization =====

## Temporary storage for loaded game units (used during load)
var _loaded_game_units: Dictionary = {}  # unit_id -> GameUnit

# === Restore lock (serializes concurrent network restores) ===
## Two receive paths deserialize armies — the full state-sync on join AND the per-army broadcast
## — and both call _deserialize_game_units() which clears _loaded_game_units. If they interleave
## (host imports an army while a guest is joining), one path's clear() wipes the dict mid-restore
## of the other → "Could not restore OPR unit" + missing/duplicate models. This async mutex
## serializes them. GDScript coroutines are cooperative on the main thread, so the while/await is
## a correct lock; each waiter re-checks the flag after the unlock signal fires.
signal _restore_unlocked
var _restore_in_flight: bool = false

## Acquire the restore lock — await until any in-flight restore finishes, then claim it.
func begin_restore() -> void:
	while _restore_in_flight:
		await _restore_unlocked
	_restore_in_flight = true

## Release the restore lock. Idempotent: safe to call on any exit path / more than once.
func end_restore() -> void:
	_restore_in_flight = false
	_restore_unlocked.emit()

## Force-release on a connection drop, so a restore stranded on a dead await (its coroutine
## abandoned by the disconnect) can't block the post-reconnect re-sync forever.
func reset_restore_lock() -> void:
	_restore_in_flight = false
	_restore_unlocked.emit()


## Whether a save/load restore is currently running — the autosave gate reads this so a periodic
## snapshot never fires mid-restore (it would serialize a half-rebuilt table).
func is_restore_in_flight() -> bool:
	return _restore_in_flight


## Deserialize GameUnits from saved data
func _deserialize_game_units(units_data: Array) -> int:
	_loaded_game_units.clear()

	if units_data.is_empty():
		return 0

	var count = 0
	for unit_data in units_data:
		if not unit_data is Dictionary:
			continue

		var game_unit = GameUnit.from_dict(unit_data)
		if game_unit:
			_loaded_game_units[game_unit.unit_id] = {
				"game_unit": game_unit,
				"model_positions": unit_data.get("model_positions", []),
				"regiment": unit_data.get("regiment", null)
			}
			count += 1

	return count


## Rebuild Age of Fantasy: Regiments movement-tray blocks for loaded units that had
## one. Runs after the model nodes exist and are wired to their loaded GameUnits.
func _restore_regiments_after_load() -> void:
	if not army_manager:
		return
	for unit_id in _loaded_game_units:
		var entry = _loaded_game_units[unit_id]
		var reg_data = entry.get("regiment", null)
		if reg_data == null:
			continue
		var game_unit = entry.game_unit as GameUnit
		if game_unit == null:
			continue
		var frontage = int(reg_data.get("frontage", 5))
		var pos = _array_to_vector3(reg_data.get("tray_pos", [0, 0, 0]))
		var rot_y = float(reg_data.get("tray_rot_y", 0.0))
		var wounds_taken = int(reg_data.get("wounds_taken", 0))
		var saved_net_id = int(reg_data.get("network_id", -1))   # keep tray MP identity (bus 036)
		army_manager.restore_regiment(game_unit, frontage, pos, rot_y, wounds_taken, saved_net_id)


## Re-park loose models that were saved dead (G4). Their nodes were restored at their revive spot
## (see _serialize_game_units), so routing through set_loose_model_dead rebuilds the greyscale look,
## the "deleted" interaction gate, and the exact tray slot (forced from the save). Runs after
## regiments so regiment casualties (handled by the regiment restore) are skipped here. Older saves
## without the "deleted" field leave the model alive — backwards-compatible.
func _restore_dead_parking_after_load() -> void:
	if not army_manager:
		return
	for unit_id in _loaded_game_units:
		var entry = _loaded_game_units[unit_id]
		var game_unit = entry.game_unit as GameUnit
		if game_unit == null:
			continue
		var model_positions: Array = entry.get("model_positions", [])
		var pid: int = int(game_unit.unit_properties.get("player_id", 1))
		for i in range(game_unit.models.size()):
			if i >= model_positions.size() or model_positions[i] == null:
				continue
			if not bool((model_positions[i] as Dictionary).get("deleted", false)):
				continue
			var model = game_unit.models[i]
			if model.node == null or not is_instance_valid(model.node):
				continue
			if model.node.has_meta("regiment_tray"):
				continue   # regiment casualties are restored by the regiment path, not parked loose
			model.is_alive = false
			var forced_slot: int = int((model_positions[i] as Dictionary).get("dead_slot", -1))
			army_manager.set_loose_model_dead(model.node, pid, true, game_unit.unit_id, forced_slot)


## Deserialize game state (round, turn, etc.)
func _deserialize_game_state(state_data: Dictionary) -> void:
	if army_manager:
		army_manager.set_current_round(int(state_data.get("current_round", 1)))
		# Restore the game phase. Older saves without the key predate the phase gate; a loaded battle
		# with units on the table is a game in progress, so default those to PLAYING (not DEPLOYMENT,
		# which would wrongly suppress the move-trail chalk on a resumed game).
		army_manager.set_game_phase(int(state_data.get("game_phase", OPRArmyManager.GamePhase.PLAYING)))
	# current_player is not restored: there is no turn-order system yet.
	# Restore the custom-token library before markers re-render so colors/effects resolve.
	if radial_menu_controller and radial_menu_controller.token_library:
		radial_menu_controller.token_library.from_dict(state_data.get("token_library", {}))


## Restore GameUnit data to a spawned model node
## Called after OPR units are re-spawned
func restore_game_unit_state(node: Node3D, unit_id: String, model_index: int) -> bool:
	if not _loaded_game_units.has(unit_id):
		return false

	var loaded_data = _loaded_game_units[unit_id]
	var game_unit = loaded_data.game_unit as GameUnit
	var model_positions = loaded_data.model_positions as Array

	if model_index >= game_unit.models.size():
		return false

	# Restore model instance reference
	var model = game_unit.models[model_index]
	model.node = node

	# Set metadata on node
	node.set_meta("game_unit", game_unit)
	node.set_meta("model_instance", model)
	node.set_meta("model_index", model_index)

	# Restore position if available
	if model_index < model_positions.size() and model_positions[model_index] != null:
		var pos_data = model_positions[model_index]
		node.global_position = _array_to_vector3(pos_data.get("position", [0, 0, 0]))
		node.rotation_degrees = _array_to_vector3(pos_data.get("rotation", [0, 0, 0]))
		node.visible = pos_data.get("visible", true)

	# Register with army manager if available. Always map the unit_id to the
	# freshly loaded GameUnit (within one load every model of a unit resolves to
	# the same object, so this is a no-op for them); this also defends against a
	# stale entry from a prior session lingering in game_units.
	if army_manager:
		army_manager.game_units[game_unit.unit_id] = game_unit

	return true


## Rebuilds hero attachment after load: to_dict() stored attached_to /
## attached_heroes as unit_ids (GameUnit refs are not serializable); resolve
## them back to live GameUnit refs now that every unit is registered.
func _restore_hero_attachments_after_load() -> void:
	if not army_manager:
		return

	for game_unit in army_manager.get_all_game_units():
		var props: Dictionary = game_unit.unit_properties

		var attached_to_id = props.get("attached_to", "")
		if attached_to_id is String:
			props["attached_to"] = army_manager.get_game_unit_by_id(attached_to_id) if not attached_to_id.is_empty() else null

		var resolved_heroes: Array = []
		for hero_ref in props.get("attached_heroes", []):
			if hero_ref is String:
				var hero = army_manager.get_game_unit_by_id(hero_ref)
				if hero:
					resolved_heroes.append(hero)
			elif hero_ref is GameUnit:
				resolved_heroes.append(hero_ref)
		props["attached_heroes"] = resolved_heroes


## Restore token/marker visualizations after loading game units
func _restore_markers_after_load() -> void:
	if not radial_menu_controller or not army_manager:
		return

	for game_unit in army_manager.get_all_game_units():
		# Status markers (fatigued, shaken, activated)
		radial_menu_controller.initialize_status_markers_for_unit(game_unit)
		# Caster markers
		radial_menu_controller.initialize_caster_marker_for_unit(game_unit)
		# Wound markers for models with damage
		radial_menu_controller.initialize_wound_markers_for_unit(game_unit)
		# Dialog markers (Pinned, Stunned, custom, ...) re-created as orbit tokens
		radial_menu_controller.initialize_marker_tokens_for_unit(game_unit)
		# Special-weapon rings (derived from loadout)
		radial_menu_controller.initialize_special_weapon_rings_for_unit(game_unit)
