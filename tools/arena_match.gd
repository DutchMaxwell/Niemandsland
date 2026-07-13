extends SceneTree
## AI ARENA — run ONE native both-AI match to the scoring end, with a DIFFICULTY GRADE per side. The
## foundation launcher the rating-ladder tooling drives: it boots the real game, imports two armies, autogens
## a symmetric board, deploys both sides with the production AI deployment, arms native both-AI mode with the
## graded sides, and runs main._solo_run_both_ai_game() unattended (no dialogs — the AI defender auto-rolls on
## the real dice tray). Same seed + same grades ⇒ identical decisions (the difficulty knobs are seeded).
##
## Run (grades: rekrut | veteran | kriegsherr | albtraum):
##   NML_AI_P1=rekrut NML_AI_P2=kriegsherr NML_AI_SEED=7 \
##     flatpak run --filesystem=home org.godotengine.Godot --path <worktree> \
##       -s res://tools/arena_match.gd
## Headless works for the decision/rules layer; a Vulkan display (or gamescope --backend headless) is needed
## for the physics-probe deployment. Grades/seed may also be passed as -- p1=rekrut p2=kriegsherr seed=7.

const P1_FIXTURE := "res://assets/tutorial/tutorial_army_p1.json"
const P2_FIXTURE := "res://assets/tutorial/tutorial_army_p2.json"
const IN2M := 0.0254
const FRONT_LINE := 1            # MapLayout.DeploymentType.FRONT_LINE
const LAYOUT_SEED := 20260710
const MAX_BOOT_FRAMES := 1200
const SPAWN_SETTLE_FRAMES := 90

var _p1_grade := "kriegsherr"
var _p2_grade := "kriegsherr"
var _seed := 0


func _initialize() -> void:
	ProjectSettings.set_setting("niemandsland/harness_mode", true)
	_run.call_deferred()


func _run() -> void:
	_parse_config()
	printerr("[ARENA] both-AI match — P1=%s vs P2=%s (seed %d)" % [_p1_grade, _p2_grade, _seed])
	change_scene_to_file("res://scenes/main.tscn")
	var main: Node = await _await_main()
	if main == null:
		printerr("[ARENA] FATAL: main.tscn never became ready — see main.gd parse errors above")
		quit(1)
		return
	printerr("[ARENA] main.tscn ready")   # main.gd parsed + _ready ran — the launch gate

	var army_manager: Node = main.get("opr_army_manager")
	var layout_editor: Control = main.get("map_layout_editor")
	var terrain_overlay: Node = main.get("terrain_overlay")
	var table: Node = main.get("table")
	var battle_log: Node = main.get("battle_log")
	if army_manager == null or layout_editor == null or terrain_overlay == null or table == null or battle_log == null:
		printerr("[ARENA] FATAL: a manager is missing")
		quit(1)
		return

	main.set("_solo_fast", true)
	main.set("_solo_dev", OS.get_environment("NML_AI_DEV") == "1")

	if not await _import_and_spawn(army_manager, P1_FIXTURE, 1):
		return
	if not await _import_and_spawn(army_manager, P2_FIXTURE, 2):
		return
	for _i in range(SPAWN_SETTLE_FRAMES):
		await process_frame

	# Symmetric board: the game's own OPR terrain autogen + FRONT_LINE zones + three centre objectives.
	seed(LAYOUT_SEED)
	layout_editor._generate_terrain_layout()
	layout_editor.deployment_type = FRONT_LINE
	layout_editor._rebuild_derived()
	layout_editor._emit_layout_update()
	layout_editor.deployment_type_changed.emit(FRONT_LINE)
	await process_frame
	var objectives_in: Array[Vector2] = [Vector2(-24.0, 0.0), Vector2(0.0, 0.0), Vector2(24.0, 0.0)]
	layout_editor.mission_objectives = objectives_in
	layout_editor.objectives_changed.emit(objectives_in)
	await process_frame

	# Arm native both-AI with the graded sides, then wire the controller for the whole board.
	main.set_both_ai(true, _p1_grade, _p2_grade, _seed)
	main._ensure_solo_controller()
	var solo: Node = main.get("solo_controller")
	if solo == null:
		printerr("[ARENA] FATAL: SoloController not created")
		quit(1)
		return
	solo._rng.seed = _seed

	# Production AI deployment for BOTH sides into their 12" front-line zones.
	var objectives: Array = terrain_overlay.get_objectives()
	var objectives_v2: Array = []
	for o in objectives:
		objectives_v2.append(Vector2((o as Vector3).x, (o as Vector3).z))
	_deploy_side(main, solo, table, terrain_overlay, 1, objectives_v2, _seed + 1)
	_deploy_side(main, solo, table, terrain_overlay, 2, objectives_v2, _seed + 2)
	await process_frame

	# Run the whole match unattended to the SOLO_GAME_ROUNDS scoring end.
	army_manager.current_round = 1
	battle_log.log_event(0, "=== AI ARENA: %s (P1) vs %s (P2) — seed %d ===" % [_p1_grade, _p2_grade, _seed], true)
	await main._solo_run_both_ai_game()

	# Report the objective outcome (the rating signal).
	var owners: Array = terrain_overlay.get_objective_owners() if terrain_overlay.has_method("get_objective_owners") else []
	var p1 := 0
	var p2 := 0
	for o in owners:
		if int(o) == 1:
			p1 += 1
		elif int(o) == 2:
			p2 += 1
	printerr("[ARENA] RESULT seed=%d P1(%s) objectives=%d P2(%s) objectives=%d" % [_seed, _p1_grade, p1, _p2_grade, p2])
	quit(0)


func _import_and_spawn(army_manager: Node, fixture: String, player_id: int) -> bool:
	var text := FileAccess.get_file_as_string(fixture)
	if text.is_empty():
		printerr("[ARENA] FATAL: fixture missing/empty: %s" % fixture)
		quit(1)
		return false
	var army = await army_manager.api_client._parse_tts_api_response(text)
	if army == null or army.units.is_empty():
		printerr("[ARENA] FATAL: player %d import produced no units (network needed for the army-book fetch?)" % player_id)
		quit(1)
		return false
	army.player_id = player_id
	army_manager.get("armies")[player_id] = army
	await army_manager.spawn_army(army)
	printerr("[ARENA] player %d = '%s' — %d units spawned" % [player_id, army.name,
		army_manager.get_game_units_for_player(player_id).size()])
	return true


func _deploy_side(main: Node, solo: Node, table: Node, terrain_overlay: Node, slot: int, objectives_v2: Array, seed_value: int) -> void:
	solo.ai_slot = slot
	solo.human_slot = 2 if slot == 1 else 1
	var w: float = table.table_size.x * 0.3048
	var d: float = table.table_size.y * 0.3048
	var depth: float = 12.0 * IN2M
	var zmin: float = (-d / 2.0) if slot == 1 else (d / 2.0 - depth)
	var zone := Rect2(Vector2(-w / 2.0, zmin), Vector2(w, depth))
	var space = terrain_overlay.get_world_3d().direct_space_state if terrain_overlay != null else null
	var probe := PhysicsShapeQueryParameters3D.new()
	var probe_shape := SphereShape3D.new()
	probe_shape.radius = 0.02
	probe.shape = probe_shape
	probe.collide_with_areas = false
	var hits_prop := func(p: Vector2) -> bool:
		if space == null:
			return false
		probe.transform = Transform3D(Basis.IDENTITY, Vector3(p.x, 0.07, p.y))
		for hit in space.intersect_shape(probe, 6):
			var col: Object = hit.get("collider")
			if col is Node3D and not (col as Node3D).is_in_group("miniature"):
				return true
		return false
	var blocked_normal := func(p: Vector2) -> bool:
		if hits_prop.call(p):
			return true
		var t: int = terrain_overlay.get_terrain_at_world_position(Vector3(p.x, 0.0, p.y))
		return t == terrain_overlay.TerrainType.FOREST or t == terrain_overlay.TerrainType.DANGEROUS \
			or t == terrain_overlay.TerrainType.CONTAINER or t == terrain_overlay.TerrainType.RUINS
	var blocked_flying := func(p: Vector2) -> bool:
		if hits_prop.call(p):
			return true
		var t: int = terrain_overlay.get_terrain_at_world_position(Vector3(p.x, 0.0, p.y))
		return t == terrain_overlay.TerrainType.CONTAINER or t == terrain_overlay.TerrainType.RUINS
	var res: Dictionary = solo.deploy_army(zone, objectives_v2, blocked_normal, blocked_flying, seed_value)
	for u in solo.ambush_reserve:
		main._solo_set_unit_visible(u, false)
	printerr("[ARENA] P%d deployed %d units (%d reserve)" % [slot, int(res.get("deployed", 0)), int(res.get("reserved", 0))])


func _await_main() -> Node:
	for _i in range(MAX_BOOT_FRAMES):
		await process_frame
		var scene := current_scene
		if scene != null and scene.get("opr_army_manager") != null and scene.get("map_layout_editor") != null \
				and scene.get("terrain_overlay") != null and scene.get("battle_log") != null:
			return scene
	return null


## Grades/seed from env (NML_AI_P1/P2/SEED) or `-- p1=… p2=… seed=…` cmdline args.
func _parse_config() -> void:
	_p1_grade = _env_or("NML_AI_P1", _p1_grade)
	_p2_grade = _env_or("NML_AI_P2", _p2_grade)
	var s := OS.get_environment("NML_AI_SEED").strip_edges()
	if s.is_valid_int():
		_seed = int(s)
	for arg in OS.get_cmdline_user_args():
		var a := str(arg)
		if a.begins_with("p1="):
			_p1_grade = a.substr(3)
		elif a.begins_with("p2="):
			_p2_grade = a.substr(3)
		elif a.begins_with("seed=") and a.substr(5).is_valid_int():
			_seed = int(a.substr(5))


func _env_or(key: String, fallback: String) -> String:
	var v := OS.get_environment(key).strip_edges()
	return v if v != "" else fallback
