extends SceneTree
## Ruin-town M1 capture (plan PLAN_RUINTOWN, M1): the greybox stills of the town, REAL display, 1600 px JPG q90.
##   godot --path . -s <abs>/bg_capture_town.gd -- <out> [seeds=3,7,25] [theme=ruintown] [only=overview,top] [yaw=0] [presets=medium,ultra,low]
## Cameras per seed (Medium): overview45 (28 and 118 deg), top, play (game camera, both armies), street (model eye height, four models
## ahead), fountain / statue / pool / hall (one close-up per landmark kind the seed has, two models beside), tower (a 9 in cell).
## Also writes <out>/s<seed>_plan.txt (the ASCII plan with landmarks) and <out>/manifest.json (written LAST = the result artefact).
## Derived from bg_capture_aaa.gd (same table clearing, armies, street pick). `perf=1`: the perf sweep. `baseline=1` (plan PLAN_RUINTOWN_AAA step R0): Medium + Ultra + Low,
## every camera incl. macro / gate / yard / band, perf + readability gate per seed and preset, a plain dark table under the board and a neutral backdrop.

const IN := 0.0254
const ZOOM := 1.25
const STILL_YAW := 28.0
const PLAY_PITCH := -50.0
const PLAY_ZOOM := 1.1
const WIDTH := 1600
const MEDIUM := 2

var _out := ""
var _main: Node
var _theme := "ruintown"
var _perf_mode := false
var _rounds := 3
var _perf: Array = []
var _baseline := false
var _suffix := ""
var _gate: Array = []
var _cur_layout: Dictionary = {}
var _cur_board: Node3D = null
var _only: Array = []
var _play_yaw := 0.0   # yaw= : the play camera's yaw in degrees (0 = the default player's side, 180 = the opposite player's side)
var _presets: Array = [2, 4, 1]   # presets=medium,ultra,low : the baseline mode's quality presets
var _models: Array[Node3D] = []
var _model_y: Array[float] = []
var _model_z: Array[float] = []
var _north: Array[int] = []
var _south: Array[int] = []
var _manifest := {"stills": [], "plans": [], "godot": "", "gpu": ""}


func _initialize() -> void:
	ProjectSettings.set_setting("niemandsland/harness_mode", true)
	_run.call_deferred()


func _fail(msg: String) -> void:
	printerr("BGCAP_FAIL ", msg)
	quit(1)


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or DisplayServer.get_name() == "headless":
		_fail("needs a real display (no --headless) and an output directory after --")
		return
	_out = args[0]
	var seeds: Array = [3, 7, 25]
	for a in args.slice(1):
		if a.begins_with("seeds="):
			seeds = Array(a.trim_prefix("seeds=").split(",", false)).map(func(s: String) -> int: return int(s))
		elif a.begins_with("only="):
			_only = Array(a.trim_prefix("only=").split(",", false))
		elif a.begins_with("theme="):
			_theme = a.trim_prefix("theme=")
		elif a == "perf=1":
			_perf_mode = true
		elif a == "baseline=1":
			_baseline = true
		elif a.begins_with("yaw="):
			_play_yaw = float(a.trim_prefix("yaw="))
		elif a.begins_with("presets="):
			_presets = Array(a.trim_prefix("presets=").split(",", false)).map(func(n: String) -> int: return {"medium": 2, "ultra": 4, "low": 1}[n])
		elif a.begins_with("rounds="):
			_rounds = int(a.trim_prefix("rounds="))
	DirAccess.make_dir_recursive_absolute(_out)
	change_scene_to_file("res://scenes/main.tscn")
	await process_frame
	await process_frame
	_main = current_scene
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	for _i in 5:
		await process_frame
	_main.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var gs: Node = root.get_node("GraphicsSettings")
	gs.apply_preset(MEDIUM)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_main.atmosphere_controller.set_fires_enabled(false)
	_main.atmosphere_controller.set_war_sounds_enabled(false)
	if await _main.save_manager.load_game("res://assets/tutorial/tutorial_board.nml") != OK:
		_fail("board load failed")
		return
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 9000:
		await process_frame
	_main.table.setup_table(Vector2(4, 4))
	_main.atmosphere_controller.apply_atmosphere("Overcast", true)
	var lc: Node = _main.lighting_controller   # a bright neutral overcast: the Day sun draws fine stripes on the big flat faces
	lc.set_sun_energy(1.1)
	lc.set_ambient_energy(1.1)
	lc.set_exposure(1.0)
	_clear_table()
	_split_armies()
	_manifest["godot"] = Engine.get_version_info()["string"]
	_manifest["gpu"] = RenderingServer.get_video_adapter_name()
	print("VIEWPORT ", root.get_visible_rect().size, " models ", _models.size())
	var pivot: Node = _main.get_node("CameraPivot")
	pivot.process_mode = Node.PROCESS_MODE_DISABLED
	pivot.set_tilt_shift_enabled(false)
	if _perf_mode:
		await _perf_sweep(seeds)
	elif _baseline:
		_manifest["backdrop"] = "neutral colour + 72 in table plane: perf here is NOT comparable to the perf=1 sweep (no star-field sky)"
		_stage_table()
		for preset: int in _presets:
			root.get_node("GraphicsSettings").apply_preset(preset)
			_main.get_node("CameraPivot").set_tilt_shift_enabled(false)
			_suffix = {2: "", 4: "_ultra", 1: "_low"}[preset]
			for _i in 20:
				await process_frame
			_backdrop()
			for board_seed: int in seeds:
				await _one_seed(board_seed, preset)
	else:
		for board_seed: int in seeds:
			await _one_seed(board_seed)
	_manifest["perf"] = _perf
	_manifest["gate"] = _gate
	var f := FileAccess.open(_out.path_join("manifest.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(_manifest, "\t"))
	f.close()
	print("BGCAP_DONE ", _out)
	current_scene.queue_free()
	await process_frame
	quit()


## Perf sweep: `_rounds` rounds over seeds x [ruintown, deepworks] x [Medium, Ultra], the PLAY camera with both armies, 300 frames each: median frame ms, GPU ms,
## draw calls, primitives, texture / video memory; `others` = Godot processes besides this one (> 0 = a shared laptop, the sample is DIRTY).
func _perf_sweep(seeds: Array) -> void:
	for round_no in _rounds:
		for preset: int in [2, 4]:
			_main.get_node("CameraPivot").set_tilt_shift_enabled(false)
			root.get_node("GraphicsSettings").apply_preset(preset)
			for _i in 20:
				await process_frame
			for board_seed: int in seeds:
				for theme: String in ["ruintown", "deepworks", "none"]:   # none = the table and both armies without a board: the cost to subtract
					var layout: Dictionary = ClassDB.instantiate("NmlCore").boardgen_layout_themed(board_seed, "ruintown" if theme == "none" else theme)
					var tex0 := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED)
					var board: Node3D = _main.table if theme == "none" else BoardgenGreybox.attach(_main.table, layout)
					for _i in 90:
						await process_frame
					var armies := _place_armies(board, layout)
					_pose(0.0, PLAY_PITCH, PLAY_ZOOM)
					await _perf_one(round_no, preset, board_seed, theme, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED) - tex0)
					armies.free()
					if theme != "none":
						board.queue_free()
					await process_frame


func _perf_one(round_no: int, preset: int, board_seed: int, theme: String, board_tex_bytes: int) -> void:
	var vp := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	for _i in 60:
		await process_frame
	var frame: Array[float] = []
	var gpu: Array[float] = []
	var last := Time.get_ticks_usec()
	for _i in 300:
		await process_frame
		var now := Time.get_ticks_usec()
		frame.append(float(now - last) / 1000.0)
		last = now
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(vp))
	frame.sort()
	gpu.sort()
	var out := []
	OS.execute("pgrep", ["-xc", "godot"], out)
	_perf.append({"round": round_no, "preset": {1: "low", 2: "medium", 4: "ultra"}[preset], "seed": board_seed, "theme": theme,
		"others": maxi(int(str(out[0] if not out.is_empty() else "1").strip_edges()) - 1, 0),
		"draw_calls": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		"frame_ms": snappedf(frame[150], 0.001), "frame_ms_p90": snappedf(frame[270], 0.001), "gpu_ms": snappedf(gpu[150], 0.001), "gpu_ms_p90": snappedf(gpu[270], 0.001),
		"texture_mem_mb_total": snappedf(float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED)) / 1048576.0, 0.01),
		"texture_mem_mb_board": snappedf(float(board_tex_bytes) / 1048576.0, 0.001),
		"video_mem_mb": snappedf(float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED)) / 1048576.0, 0.01)})
	RenderingServer.viewport_set_measure_render_time(vp, false)
	print("PERF ", _perf[-1])


func _want(cam: String) -> bool:
	if _baseline and _suffix == "_ultra" and not ["overview45", "play", "wall", "macro"].has(cam):
		return false
	if _baseline and _suffix == "_low" and not ["overview45", "play"].has(cam):
		return false
	return _only.is_empty() or _only.any(func(o: String) -> bool: return cam.begins_with(o))


func _one_seed(board_seed: int, preset := 2) -> void:
	var core: Object = ClassDB.instantiate("NmlCore")
	var layout: Dictionary = core.boardgen_layout_themed(board_seed, _theme)
	var tag := "s%d" % board_seed
	var plan := _ascii(layout)
	var pf := FileAccess.open(_out.path_join("%s_plan.txt" % tag), FileAccess.WRITE)
	pf.store_string("seed %d  theme %s  problems %s\n%s" % [board_seed, layout.get("theme", "Deepworks"), layout["problems"], plan])
	pf.close()
	_manifest["plans"].append("%s_plan.txt" % tag)
	var board := BoardgenGreybox.attach(_main.table, layout)
	_cur_layout = layout
	_cur_board = board
	for _i in 60:
		await process_frame
	var armies := _place_armies(board, layout)
	if _want("overview"):
		_pose(STILL_YAW, -45.0, ZOOM)
		await _still(tag, "overview45")
		_pose(STILL_YAW + 90.0, -45.0, ZOOM)   # +180 would be the same picture: the board is a half-turn mirror
		await _still(tag, "overview45b")
	if _want("top"):
		_pose(0.0, -89.0, 1.45)
		await _still(tag, "top")
	if _want("play"):
		_pose(_play_yaw, PLAY_PITCH, PLAY_ZOOM)
		await _still(tag, "play")
		if _baseline:
			await _readability(tag, _suffix)
			await _perf_one(1, preset, board_seed, "ruintown", 0)
	if _want("macro"):
		var m := _macro_pick(layout)
		if not m.is_empty():
			var stand_m := _stand_ins(board, [m["model"]])
			_pose(m["yaw"], -22.0, 0.075, m["target"])
			await _still(tag, "macro")
			stand_m.free()
	armies.free()
	if _want("street"):
		var walk := _street(layout)
		var lo: Vector3 = walk["from"]
		var hi: Vector3 = walk["to"]
		var dir := (hi - lo).normalized()
		var side := Vector3(-dir.z, 0.0, dir.x)
		var spots: Array[Vector2] = []
		for k in [[0.46, 0.8], [0.54, -1.0], [0.64, 0.5], [0.76, -0.6]]:
			var at: Vector3 = lo.lerp(hi, float(k[0])) + side * float(k[1]) * IN
			spots.append(Vector2(at.x, at.z) / IN)
		var stand := _stand_ins(board, spots)
		var cam_t := 0.22   # the camera keeps 4 in clear of every lantern post (a lantern at the lens over-warms the still)
		if layout.get("theme", "") == "RuinTown":
			for t: float in [0.22, 0.12, 0.30, 0.06, 0.38]:
				var at3: Vector3 = lo.lerp(hi, t)
				var clear := true
				for l: Dictionary in BoardgenTownDressing.lanterns(layout):
					if (l["at"] as Vector2).distance_to(Vector2(at3.x, at3.z) / IN) < 4.0:
						clear = false
				if clear:
					cam_t = t
					break
		_pose(walk["yaw"], -3.0, 0.16, lo.lerp(hi, cam_t))
		await _still(tag, "street")
		stand.free()
	# one close-up per landmark kind the seed has
	var names := {"TankCluster": "fountain", "Crane": "statue", "Sump": "pool", "PumpHouse": "hall"}
	var zooms := {"TankCluster": 0.32, "Crane": 0.22, "Sump": 0.30, "PumpHouse": 0.34}
	var pitches := {"TankCluster": -34.0, "Crane": -32.0, "Sump": -55.0, "PumpHouse": -34.0}
	var done := {}
	for lm: Dictionary in layout["landmarks"]:
		var kind: String = lm["kind"]
		if done.has(kind) or not _want(names[kind]):
			continue
		done[kind] = true
		var cell := float(layout["cell_in"])
		var half := Vector2(lm["w"], lm["h"]) * cell * 0.5
		var c := (Vector2(lm["x"], lm["z"]) * cell - Vector2(layout["nx"], layout["nz"]) * cell * 0.5) + half
		var top := _cell_top(layout, int(lm["x"]), int(lm["z"]))
		var ty := top + (0.6 if kind == "PumpHouse" else 1.0)
		var yaw := _open_yaw(layout, c, ty, float(pitches[kind]), float(zooms[kind]) / IN, Rect2(c - half, half * 2.0))
		var perp := Vector2(sin(deg_to_rad(yaw + 90.0)), cos(deg_to_rad(yaw + 90.0)))
		var spots: Array = []
		for sgn in [1.0, -1.0]:
			var q: Vector2 = c + perp * sgn * (half.x + half.y * 0.5 + 2.2)
			if _open(layout, q):
				spots.append(q)
		var stand := _stand_ins(board, spots if kind != "PumpHouse" else [])
		_pose(yaw, float(pitches[kind]), float(zooms[kind]), Vector3(c.x * IN, ty * IN, c.y * IN))
		await _still(tag, names[kind])
		stand.free()
	# the city wall: its middle cell, from the side with the best sight line; and the roof mix: the intact house nearest the board centre
	if _want("wall"):
		var wall_cells: Array = layout["cells"].filter(func(cd: Dictionary) -> bool: return cd["lot_kind"] == "Wall" and cd["level"] >= 2 and cd["x"] < 8)
		if not wall_cells.is_empty():
			var wc: Dictionary = wall_cells[wall_cells.size() / 2]
			var c := (Vector2(wc["x"] + 0.5, wc["z"] + 0.5) * float(layout["cell_in"]) - Vector2(layout["nx"], layout["nz"]) * float(layout["cell_in"]) * 0.5)
			var yaw := _open_yaw(layout, c, 4.0, -32.0, 16.0, Rect2(c - Vector2(1.5, 1.5), Vector2(3.0, 3.0)))
			var stand := _stand_ins(board, [c + Vector2(sin(deg_to_rad(yaw + 90.0)), cos(deg_to_rad(yaw + 90.0))) * 4.5])
			_pose(yaw, -32.0, 0.5, Vector3(c.x * IN, 3.0 * IN, c.y * IN))
			await _still(tag, "wall")
			stand.free()
	if _want("roofs"):
		var best := {}
		for lot: Dictionary in layout["lots"]:
			if lot["kind"] == "Roofed":
				var d := Vector2(lot["x"] + lot["w"] * 0.5 - 8.0, lot["z"] + lot["h"] * 0.5 - 8.0).length()
				if best.is_empty() or d < best["d"]:
					best = {"d": d, "lot": lot}
		if not best.is_empty():
			var lot: Dictionary = best["lot"]
			var c := (Vector2(lot["x"] + lot["w"] * 0.5, lot["z"] + lot["h"] * 0.5) * float(layout["cell_in"]) - Vector2(layout["nx"], layout["nz"]) * float(layout["cell_in"]) * 0.5)
			var yaw := _open_yaw(layout, c, 2.0, -40.0, 20.0, Rect2(c - Vector2(3.0, 3.0), Vector2(6.0, 6.0)))
			_pose(yaw, -40.0, 0.6, Vector3(c.x * IN, 1.5 * IN, c.y * IN))
			await _still(tag, "roofs")
	if _want("gate"):
		var g := _gate_pick(layout)
		if not g.is_empty():
			_pose(_open_yaw(layout, g["at"], 3.0, -30.0, 14.0, Rect2(g["at"] - Vector2(1.5, 1.5), Vector2(3.0, 3.0))), -30.0, 0.34, Vector3(g["at"].x * IN, 3.0 * IN, g["at"].y * IN))
			await _still(tag, "gate")
	if _want("yard"):
		var y := _yard_pick(layout)
		if not y.is_empty():
			var ya: Vector2 = y["at"]
			_pose(_open_yaw(layout, ya, 1.5, -30.0, 14.0, Rect2(ya - Vector2(1.5, 1.5), Vector2(3.0, 3.0))), -30.0, 0.34, Vector3(ya.x * IN, 1.0 * IN, ya.y * IN))
			await _still(tag, "yard")
	if _want("band"):
		var band_armies := _place_armies(board, layout)
		_pose(-90.0, -4.0, 0.2, Vector3(-14.0 * IN, 1.0 * IN, 19.5 * IN))   # eye height along the south deployment band
		await _still(tag, "band")
		band_armies.free()
	# a tower: the first level-3 cell
	if _want("tower"):
		for cd: Dictionary in layout["cells"]:
			if cd["level"] == 3:
				var c := (Vector2(cd["x"] + 0.5, cd["z"] + 0.5) * float(layout["cell_in"]) - Vector2(layout["nx"], layout["nz"]) * float(layout["cell_in"]) * 0.5)
				var yaw := _open_yaw(layout, c, 5.0, -25.0, 18.0, Rect2(c - Vector2(1.5, 1.5), Vector2(3.0, 3.0)))
				_pose(yaw, -25.0, 0.5, Vector3(c.x * IN, 5.0 * IN, c.y * IN))
				await _still(tag, "tower")
				break
	board.queue_free()
	await process_frame


## A plain dark table 72 x 72 in under the board and a neutral backdrop instead of the star field (capture only).
func _stage_table() -> void:
	var plane := MeshInstance3D.new()
	plane.name = "CaptureTable"
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(72.0, 72.0) * IN
	plane.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.36, 0.28, 0.21)
	mat.roughness = 0.9
	plane.material_override = mat
	plane.position = Vector3(0.0, -0.003, 0.0)
	_main.table.add_child(plane)


## A neutral backdrop instead of the star field, set AFTER a preset is applied (the render state rewrites the environment whenever a preset lands). Capture only.
func _backdrop() -> void:
	var env: Environment = _main.world_environment.environment
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.13, 0.13, 0.14)


## The ground cell next to a taller wall (or an intact house) nearest the board centre with open floor 3 in out: {model (board inches), yaw, target (m)}.
func _macro_pick(layout: Dictionary) -> Dictionary:
	var nx: int = layout["nx"]
	var nz: int = layout["nz"]
	var cell := float(layout["cell_in"])
	var cands: Array[Dictionary] = []
	for cz in nz:
		for cx in nx:
			var cd: Dictionary = layout["cells"][cz * nx + cx]
			if cd["level"] != 0 or not cd["street"]:
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var ox: int = cx + d.x
				var oz: int = cz + d.y
				if ox < 0 or oz < 0 or ox >= nx or oz >= nz:
					continue
				var nd: Dictionary = layout["cells"][oz * nx + ox]
				if nd["level"] < 1:
					continue
				var centre := Vector2(cx + 0.5 - nx * 0.5, cz + 0.5 - nz * 0.5) * cell
				cands.append({"wall": centre + Vector2(d) * cell * 0.5, "out": Vector2(-d.x, -d.y), "dist": centre.length()})
	cands.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["dist"] < b["dist"])
	for c: Dictionary in cands:
		var w: Vector2 = c["wall"]
		var o: Vector2 = c["out"]
		if _open(layout, w + o * 1.3) and _open(layout, w + o * 2.9):
			return {"model": w + o * 1.3, "yaw": rad_to_deg(atan2(o.x, o.y)), "target": Vector3((w + o * 0.25).x * IN, 0.9 * IN, (w + o * 0.25).y * IN)}
	return {}


## The centre (board inches) of the street cell of a wall gate nearest the board centre; {} when the board has no wall.
func _gate_pick(layout: Dictionary) -> Dictionary:
	var per_col := {}
	for cd: Dictionary in layout["cells"]:
		if cd["lot_kind"] == "Wall" and cd["level"] >= 1:
			per_col[cd["x"]] = int(per_col.get(cd["x"], 0)) + 1
	var best := {}
	for cd: Dictionary in layout["cells"]:
		if cd["street"] and cd["level"] == 0 and int(per_col.get(cd["x"], 0)) >= 5:
			var at := (Vector2(cd["x"] + 0.5, cd["z"] + 0.5) - Vector2(layout["nx"], layout["nz"]) * 0.5) * float(layout["cell_in"])
			if best.is_empty() or at.length() < (best["at"] as Vector2).length():
				best = {"at": at}
	return best


## The centre (board inches) of a yard nearest the board centre: a RUINS yard (level-0 rest of a Terrace lot), else a garden plot, else open ground beside a raised cell: {at} or {}.
func _yard_pick(layout: Dictionary) -> Dictionary:
	var nx: int = layout["nx"]
	var nz: int = layout["nz"]
	var best := {}
	for cd: Dictionary in layout["cells"]:
		if cd["level"] != 0 or cd["street"] or cd["lot_kind"] == "Hazard":
			continue
		var prio := 0 if cd["lot_kind"] == "Terrace" else (1 if cd["lot_kind"] == "Rough" else 9)
		if prio == 9 and cd["lot_kind"] == "Street":
			var raised := false
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var ox: int = cd["x"] + d.x
				var oz: int = cd["z"] + d.y
				if ox >= 0 and oz >= 0 and ox < nx and oz < nz and layout["cells"][oz * nx + ox]["level"] > 0 and layout["cells"][oz * nx + ox]["lot_kind"] != "Wall":
					raised = true
			if not raised:
				continue
			prio = 2
		elif prio == 9:
			continue
		var at := (Vector2(cd["x"] + 0.5, cd["z"] + 0.5) - Vector2(nx, nz) * 0.5) * float(layout["cell_in"])
		if best.is_empty() or prio < best["prio"] or (prio == best["prio"] and at.length() < (best["at"] as Vector2).length()):
			best = {"at": at, "prio": prio}
	return best


func _luma(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


## Mean colour of the pixels within the annulus r0..r1 (px) round `c`, skipping pixels inside any of the `skip` discs (port of bg_capture_aaa2.gd).
func _mean_ring(img: Image, c: Vector2, r0: float, r1: float, skip: Array) -> Color:
	var sum := Color(0, 0, 0, 0)
	var n := 0
	for y in range(maxi(int(c.y - r1), 0), mini(int(c.y + r1) + 1, img.get_height())):
		for x in range(maxi(int(c.x - r1), 0), mini(int(c.x + r1) + 1, img.get_width())):
			var d := Vector2(x, y).distance_to(c)
			if d < r0 or d > r1:
				continue
			var hidden := false
			for sk: Dictionary in skip:
				if Vector2(x, y).distance_to(sk["c"]) < float(sk["r"]) * 1.15:
					hidden = true
					break
			if not hidden:
				sum += img.get_pixel(x, y)
				n += 1
	return Color(sum.r / maxf(n, 1.0), sum.g / maxf(n, 1.0), sum.b / maxf(n, 1.0), float(n))


## READABILITY GATE (port of bg_capture_aaa2.gd): at the PLAY camera with both armies, the contrast of every model's body disc against the ring of board
## round its base: score = max(dY / 0.10, dC / 0.10); a model reads at >= 1. Per-model scores go to manifest.gate in model order (paired before / after).
func _readability(tag: String, pname: String) -> void:
	for _i in 40:   # (was 6) the GI of the Ultra preset (SDFGI, SSIL) settles over frames: a short wait made its rows bimodal between repeats
		_backdrop()
		await process_frame
		_hide_scatter()
	var cam := root.get_viewport().get_camera_3d()
	var img := root.get_texture().get_image()
	var k := float(img.get_width()) / root.get_visible_rect().size.x
	var discs: Array[Dictionary] = []
	var occluded := 0
	var offframe := 0
	for i in _models.size():
		var m := _models[i]
		if not m.visible:
			continue
		var p := m.global_position + Vector3.UP * 0.004
		var c := cam.unproject_position(p) * k
		var r := (cam.unproject_position(p + cam.global_transform.basis.x * 0.016) * k - c).length()
		var from := cam.global_position
		var query := PhysicsRayQueryParameters3D.create(from, p + Vector3.UP * 0.008)
		query.collision_mask = 0xFFFFFFFF
		var hit := root.world_3d.direct_space_state.intersect_ray(query)
		var hidden: bool = not hit.is_empty() and (hit["collider"] as Node).name == "Colliders" and from.distance_to(hit["position"]) < from.distance_to(p + Vector3.UP * 0.008) - 0.02
		if hidden:
			occluded += 1
			continue
		if c.x < 1.9 * maxf(r, 2.5) or c.y < 1.9 * maxf(r, 2.5) or c.x > img.get_width() - 1.9 * maxf(r, 2.5) or c.y > img.get_height() - 1.9 * maxf(r, 2.5):
			offframe += 1   # the disc and its ring are not wholly in the frame: the ring would read clamped border pixels (lead 21.11.: an instrument fault found in the 4 bottom models of seed 3)
			continue
		discs.append({"i": i, "c": c, "r": maxf(r, 2.5)})
	var scores: Array[float] = []
	var rows: Array = []
	for d: Dictionary in discs:
		var others := discs.filter(func(o: Dictionary) -> bool: return o["i"] != d["i"])
		var body := _mean_ring(img, d["c"], 0.0, float(d["r"]) * 0.9, [])
		var ring := _mean_ring(img, d["c"], float(d["r"]) * 1.3, float(d["r"]) * 1.9, others)
		var dy := absf(_luma(body) - _luma(ring))
		var cb := Vector2(body.r - body.g, body.b - (body.r + body.g) * 0.5)
		var cr := Vector2(ring.r - ring.g, ring.b - (ring.r + ring.g) * 0.5)
		var score := maxf(dy / 0.10, cb.distance_to(cr) / 0.10)
		scores.append(score)
		var at := ((_models[int(d["i"])].global_position - _cur_board.global_position) / IN) if _cur_board != null else Vector3.ZERO
		var cx := clampi(int(floorf(at.x / 3.0 + 8.0)), 0, 15)
		var cz := clampi(int(floorf(at.z / 3.0 + 8.0)), 0, 15)
		var cell: Dictionary = _cur_layout["cells"][cz * 16 + cx] if not _cur_layout.is_empty() else {}
		rows.append([d["i"], snappedf(score, 0.01), int((d["c"] as Vector2).x * float(WIDTH) / float(img.get_width())), int((d["c"] as Vector2).y * float(WIDTH) / float(img.get_width())), cell.get("lot_kind", "?"), cell.get("level", -1), snappedf(at.y, 0.1)])
	var sorted := scores.duplicate()
	sorted.sort()
	var low := 0
	for sc: float in scores:
		low += 1 if sc < 1.0 else 0
	_gate.append({"seed": tag, "yaw": _play_yaw, "preset": "medium" if pname == "" else pname.trim_prefix("_"), "models": scores.size(), "occluded": occluded, "offframe": offframe, "below_1": low,
		"min": snappedf(sorted[0] if not sorted.is_empty() else 0.0, 0.01), "median": snappedf(sorted[sorted.size() / 2] if not sorted.is_empty() else 0.0, 0.01), "scores": rows})
	print("GATE ", tag, pname, " models ", scores.size(), " below1 ", low)


## The ASCII plan: 3 / 2 / 1 raised, ~ hazard lot, y yard (level-0 rest of a Terrace), " garden plot, R intact house, w breach / b buttress / W wall ridge / T wall tower, . street, , ground; landmarks overlaid: F fountain,
## S statue, P pool, H hall mark.
func _ascii(layout: Dictionary) -> String:
	var nx: int = layout["nx"]
	var rows: Array = []
	for z in layout["nz"]:
		var row := ""
		for x in nx:
			var c: Dictionary = layout["cells"][z * nx + x]
			var ch := ","
			if c["lot_kind"] == "Wall":
				ch = ["w", "b", "W", "T"][c["level"]]   # breach / buttress / wall ridge / wall tower
			elif c["level"] > 0:
				ch = str(c["level"])
			elif c["lot_kind"] == "Hazard":
				ch = "~"
			elif c["street"]:
				ch = "."
			elif c["lot_kind"] == "Terrace":
				ch = "y"
			elif c["lot_kind"] == "Rough":
				ch = "\""
			elif c["lot_kind"] == "Roofed":
				ch = "R"
			row += ch
		rows.append(row)
	var marks := {"TankCluster": "F", "Crane": "S", "Sump": "P", "PumpHouse": "H"}
	for lm: Dictionary in layout["landmarks"]:
		for dz in int(lm["h"]):
			for dx in int(lm["w"]):
				var r: String = rows[int(lm["z"]) + dz]
				var xx := int(lm["x"]) + dx
				rows[int(lm["z"]) + dz] = r.substr(0, xx) + marks[lm["kind"]] + r.substr(xx + 1)
	return "\n".join(rows) + "\n"


func _cell_top(layout: Dictionary, x: int, z: int) -> float:
	return float(layout["level_in"][layout["cells"][z * int(layout["nx"]) + x]["level"]])


## The yaw (camera on the side `(sin yaw, cos yaw)` of the target) whose sight line from the camera to the target at height `ty` clears the
## most cells: the line rises `tan(pitch)` per inch away from the target, a cell taller than the line counts its excess.
func _open_yaw(layout: Dictionary, at: Vector2, ty: float, pitch_deg: float, reach_in: float, skip: Rect2) -> float:
	var best := STILL_YAW
	var best_cost := 1e9
	for k in 8:
		var yaw := STILL_YAW + 45.0 * k
		var cost := 0.0
		var d := 1.5
		while d <= reach_in:
			var p: Vector2 = at + Vector2(sin(deg_to_rad(yaw)), cos(deg_to_rad(yaw))) * d
			var cx: int = floori(p.x / float(layout["cell_in"]) + float(layout["nx"]) * 0.5)
			var cz: int = floori(p.y / float(layout["cell_in"]) + float(layout["nz"]) * 0.5)
			if cx >= 0 and cz >= 0 and cx < int(layout["nx"]) and cz < int(layout["nz"]) and not skip.has_point(p):
				cost += maxf(0.0, _cell_top(layout, cx, cz) - (ty + d * tan(deg_to_rad(-pitch_deg))))
			d += 1.5
		if cost < best_cost - 0.001:
			best_cost = cost
			best = yaw
	return best


## A stand-in spot is open when its cell is level-0 ground that is not dangerous.
func _open(layout: Dictionary, p: Vector2) -> bool:
	var cx: int = floori(p.x / float(layout["cell_in"]) + float(layout["nx"]) * 0.5)
	var cz: int = floori(p.y / float(layout["cell_in"]) + float(layout["nz"]) * 0.5)
	if cx < 0 or cz < 0 or cx >= int(layout["nx"]) or cz >= int(layout["nz"]):
		return false
	var cd: Dictionary = layout["cells"][cz * int(layout["nx"]) + cx]
	return cd["level"] == 0 and cd["lot_kind"] != "Hazard"


func _split_armies() -> void:
	var order: Array[int] = []
	for i in _models.size():
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool: return _model_z[a] < _model_z[b])
	var half := order.size() / 2
	for k in order.size():
		(_north if k < half else _south).append(order[k])


func _place_armies(board: Node3D, layout: Dictionary) -> Node3D:
	var handle := Node3D.new()
	handle.name = "Armies"
	board.add_child(handle)
	var nx: int = layout["nx"]
	var nz: int = layout["nz"]
	var cell := float(layout["cell_in"])
	var rng := RandomNumberGenerator.new()
	rng.seed = int(layout["seed"]) + 77
	var used: Array[Vector2] = []
	for side in 2:
		var group: Array[int] = _north if side == 0 else _south
		for idx: int in group:
			for _try in 400:
				var z_in := rng.randf_range(-0.5, -0.26) if side == 0 else rng.randf_range(0.26, 0.5)
				var p := Vector2(rng.randf_range(-0.46, 0.46) * nx * cell, z_in * nz * cell)
				var cx := clampi(floori(p.x / cell + nx * 0.5), 0, nx - 1)
				var cz := clampi(floori(p.y / cell + nz * 0.5), 0, nz - 1)
				var cd: Dictionary = layout["cells"][cz * nx + cx]
				if cd["level"] > 0 or cd["lot_kind"] == "Hazard" or used.any(func(o: Vector2) -> bool: return o.distance_to(p) < 2.4):
					continue
				used.append(p)
				_models[idx].global_position = Vector3(p.x * IN, _model_y[idx], p.y * IN)
				_models[idx].visible = true
				break
	handle.tree_exiting.connect(func() -> void:
		for m in _models:
			m.visible = false)
	return handle


func _stand_ins(board: Node3D, spots: Array) -> Node3D:
	var handle := Node3D.new()
	handle.name = "StandIns"
	board.add_child(handle)
	for i in mini(spots.size(), _models.size()):
		var p: Vector2 = spots[i]
		_models[i].global_position = Vector3(p.x * IN, _model_y[i], p.y * IN)
		_models[i].visible = true
	handle.tree_exiting.connect(func() -> void:
		for m in _models:
			m.visible = false)
	return handle


func _still(tag: String, cam: String) -> void:
	var file := "%s_%s%s.jpg" % [tag, cam, _suffix]
	for _i in 6:
		if _baseline:
			_backdrop()   # the render state rewrites the environment whenever a layer changes (dusk, a preset): set it again right before every frame we keep
		await process_frame
		_hide_scatter()
	var img := root.get_texture().get_image()
	img.resize(WIDTH, int(float(WIDTH) * img.get_height() / img.get_width()), Image.INTERPOLATE_LANCZOS)
	img.save_jpg(_out.path_join(file), 0.9)
	_manifest["stills"].append(file)


func _street(layout: Dictionary) -> Dictionary:
	var nx: int = layout["nx"]
	var nz: int = layout["nz"]
	var cells: Array = layout["cells"]
	var cell := float(layout["cell_in"])
	var best := {"len": 0}
	for along_x in [true, false]:
		for line in (nz if along_x else nx):
			var run := 0
			for k in (nx if along_x else nz):
				var c: Dictionary = cells[(line * nx + k) if along_x else (k * nx + line)]
				run = run + 1 if (c["level"] == 0 and c["street"]) else 0
				if run > best["len"]:
					best = {"len": run, "line": line, "end": k, "x": along_x}
	if best["len"] < 3:
		best = {"len": nx, "line": nz / 2, "end": nx - 1, "x": true}
	var span: float = (nx if best["x"] else nz) * cell * 0.5
	var lo: float = (best["end"] - best["len"] + 1.0) * cell - span
	var hi: float = (best["end"] + 1.0) * cell - span
	var fix: float = (best["line"] + 0.5) * cell - (nz if best["x"] else nx) * cell * 0.5
	var open_hi := _line_open(layout, best, int(best["line"]) + 1)
	var open_lo := _line_open(layout, best, int(best["line"]) - 1)
	fix += (0.5 if open_hi and not open_lo else -0.5 if open_lo and not open_hi else 0.0) * cell
	if best["x"]:
		return {"from": Vector3(lo * IN, 0.03, fix * IN), "to": Vector3(hi * IN, 0.03, fix * IN), "yaw": -90.0}
	return {"from": Vector3(fix * IN, 0.03, lo * IN), "to": Vector3(fix * IN, 0.03, hi * IN), "yaw": 180.0}


func _line_open(layout: Dictionary, run: Dictionary, line: int) -> bool:
	var nx: int = layout["nx"]
	var nz: int = layout["nz"]
	if line < 0 or line >= (nz if run["x"] else nx):
		return false
	for k in range(int(run["end"]) - int(run["len"]) + 1, int(run["end"]) + 1):
		var c: Dictionary = layout["cells"][(line * nx + k) if run["x"] else (k * nx + line)]
		if c["level"] != 0 or c["lot_kind"] == "Hazard":
			return false
	return true


func _clear_table() -> void:
	_main.get_node("UI").visible = false
	_main.atmospheric_clouds.visible = false
	_main.terrain_overlay.visible = false
	_main.table.get_node("TableMesh").visible = false
	for d in _main.find_children("*", "Decal", true, false):
		(d as Decal).visible = false
	_main.get_node("TableBiomePresenter/TableBiomeReference").visible = false
	_main.table.get_node("GrassField").visible = false
	for pt in _main.find_children("*", "GPUParticles3D", true, false):
		(pt as GPUParticles3D).visible = false
	_hide_by_name(_main)
	for pattern in ["*Trail*", "*Chalk*", "*Coherency*", "*Boundary*", "*RangeRing*", "*SightFan*", "*MovementRange*", "*Rulers*", "ModelAuras", "BattlefieldStains"]:
		for overlay in _main.find_children(pattern, "Node3D", true, false):
			(overlay as Node3D).visible = false
	for tray in _main.find_children("ArmyTray_Player*", "Node3D", true, false):
		(tray as Node3D).visible = false
	for id in _main.opr_army_manager.game_units:
		for mi in _main.opr_army_manager.game_units[id].models:
			if mi.node != null:
				mi.node.visible = false
				_models.append(mi.node)
				_model_z.append(mi.node.global_position.z)
				_model_y.append(mi.node.global_position.y)
	for group in ["sandbox_terrain", "terrain_group_base"]:
		for n in get_nodes_in_group(group):
			(n as Node3D).visible = false


func _hide_scatter() -> void:
	_main.atmospheric_clouds.visible = false
	var presenter := _main.get_node_or_null("TableBiomePresenter")
	if presenter != null:
		for mm in presenter.find_children("*", "Node3D", true, false):
			(mm as Node3D).visible = false
	_main.table.get_node("GrassField").visible = false
	_hide_by_name(_main)


func _hide_by_name(node: Node) -> void:
	for c in node.get_children():
		if str(c.name).begins_with("ReferenceCanopy") or str(c.name).begins_with("TableTreeForest"):
			(c as Node3D).visible = false
		else:
			_hide_by_name(c)


func _pose(yaw: float, pitch := -38.0, zoom := ZOOM, target := Vector3(0, 0.02, 0)) -> void:
	var pivot: Node = _main.get_node("CameraPivot")
	pivot._target_position = target
	pivot._yaw = yaw
	pivot._pitch = pitch
	pivot._current_zoom = zoom
	pivot._apply_camera_transform()
