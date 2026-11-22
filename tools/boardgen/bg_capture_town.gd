extends SceneTree
## Ruin-town M1 capture (plan PLAN_RUINTOWN, M1): the greybox stills of the town, REAL display, 1600 px JPG q90.
##   godot --path . -s <abs>/bg_capture_town.gd -- <out> [seeds=3,7,25] [theme=ruintown] [only=overview,top] [yaw=0] [presets=medium,ultra,low]
## Cameras per seed (Medium): overview45 (28 and 118 deg), top, play (game camera, both armies), halfplay (the play camera at half its distance), street (model eye height, four models
## ahead), fountain / statue / pool / hall (one close-up per landmark kind the seed has, two models beside; `fountain` also writes fountain_eye: the fountain at model eye height), tower (a 9 in cell).
## Also writes <out>/s<seed>_plan.txt (the ASCII plan with landmarks) and <out>/manifest.json (written LAST = the result artefact).
## Derived from bg_capture_aaa.gd (same table clearing, armies, street pick). `perf=1`: the perf sweep. `baseline=1` (plan PLAN_RUINTOWN_AAA step R0): Medium + Ultra + Low,
## every camera incl. macro / gate / yard / band, perf + readability gate per seed and preset, a plain dark table under the board and a neutral backdrop.
## `macro_ground` (plan PLAN_RUINTOWN_GRIT G0): 30 deg down, 3 in above a street cell beside an earth border, no pawn - the paving close-up. `grit_debug=1`: beside every still a
## <still>_grit.png (`grit_debug=2`: <still>_gritmap.png, the raw map) with the board shader's `grit_debug` on (the grit classes as flat colours), every light, the ambient, fog and glow off and a linear tonemap, so the class colours
## survive exactly (the instrument tools/boardgen/grit_metrics.py reads them). `manifest.json` gains `still_info`: per still its camera and pixels per inch at the camera's target.

const IN := 0.0254
const ZOOM := 1.25
const STILL_YAW := 28.0
const PLAY_PITCH := -50.0
const PLAY_ZOOM := 1.1
const WIDTH := 1600
const MEDIUM := 2
const VIS_MIN := 0.4   # gate: a model with less than this share of its own silhouette visible (inside its disc) is `occluded`, not scored (gate change 21.11.)

var _out := ""
var _gate_test := false   # gate_test=1: the sampler's own red / green on three test pawns (_gate_self_test)
var _main: Node
var _theme := "ruintown"
var _perf_mode := false
var _rounds := 3
var _perf: Array = []
var _baseline := false
var _town_sky := false   # sky=town: the look stills keep the environment's sky (the town's blue hour) instead of the neutral backdrop; the readability pass keeps the backdrop
var _real_table := false   # table=1: the game's own table (mesh, grass, biome dressing) stays visible under and round the board, as a player sees it
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
var _manifest := {"stills": [], "plans": [], "godot": "", "gpu": "", "still_info": {}}
var _grit_debug := 0   # grit_debug=1 (classes) / 2 (the raw map): a debug still beside every still (plan PLAN_RUINTOWN_GRIT G0)
var _cam_target := Vector3.ZERO


func _initialize() -> void:
	ProjectSettings.set_setting("niemandsland/harness_mode", true)
	BoardgenTownLife.pinned = true   # the life clock stands at t = 0: a still (and the readability gate) is reproducible
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
		elif a == "gate_test=1":
			_gate_test = true
		elif a == "baseline=1":
			_baseline = true
		elif a == "sky=town":
			_town_sky = true
		elif a == "table=1":
			_real_table = true
		elif a.begins_with("yaw="):
			_play_yaw = float(a.trim_prefix("yaw="))
		elif a.begins_with("presets="):
			_presets = Array(a.trim_prefix("presets=").split(",", false)).map(func(n: String) -> int: return {"medium": 2, "ultra": 4, "low": 1}[n])
		elif a.begins_with("rounds="):
			_rounds = int(a.trim_prefix("rounds="))
		elif a.begins_with("grit_debug="):
			_grit_debug = int(a.trim_prefix("grit_debug="))
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
	print("BOARD %s decals %d life %d" % [tag, board.find_children("*", "Decal", true, false).size(), board.find_children("*", "GPUParticles3D", true, false).size()])
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
			if _gate_test:
				await _gate_self_test()
			await _perf_one(1, preset, board_seed, "ruintown", 0)
	if _want("halfplay"):   # the play camera at half the distance on the board's middle (40 px per inch: a story piece reads by kind here, not at the full-board zoom)
		_pose(_play_yaw, PLAY_PITCH, PLAY_ZOOM * 0.5)
		await _still(tag, "halfplay")
	if _want("macro"):
		var m := _macro_pick(layout)
		if not m.is_empty():
			var stand_m := _stand_ins(board, [m["model"]])
			_pose(m["yaw"], -22.0, 0.075, m["target"])
			await _still(tag, "macro")
			stand_m.free()
	if _want("macro_ground"):
		var mg := _macro_ground_pick(layout)
		if not mg.is_empty():
			var shown: Array = _models.filter(func(m: Node3D) -> bool: return m.visible)
			for m: Node3D in shown:
				m.visible = false   # no pawn on the paving close-up
			_pose(mg["yaw"], -30.0, 6.0 * IN, mg["target"])   # 6 in from the target at 30 deg down: the lens 3 in above the street
			await _still(tag, "macro_ground")
			for m: Node3D in shown:
				m.visible = true
	if _want("scene") and layout.get("theme", "") == "RuinTown":   # one close-up per story-scene kind (plan PLAN_RUINTOWN_GRIT S1-S3)
		var seen := {}
		for sc: Dictionary in BoardgenTownScenes.plan(layout)["scenes"]:
			if seen.has(sc["kind"]):
				continue
			seen[sc["kind"]] = true
			var at: Vector2 = sc["at"]
			var into: Vector2 = sc["into"]
			var shown_s: Array = _models.filter(func(m: Node3D) -> bool: return m.visible)
			for m: Node3D in shown_s:
				m.visible = false
			var look := at + into * 0.9   # the cluster's middle, a little out from the wall
			var yaw := _open_yaw(layout, look, 0.6, -35.0, 12.0, Rect2(look - Vector2(1.5, 1.5), Vector2(3.0, 3.0)))
			if into != Vector2.ZERO:   # square onto the wall from the open side, turned 30 deg off the wall line; the lens 9 in out must be open ground
				for turn: float in [30.0, -30.0, 0.0, 55.0, -55.0]:
					var y := rad_to_deg(atan2(into.x, into.y)) + turn
					var lens := look + Vector2(sin(deg_to_rad(y)), cos(deg_to_rad(y))) * 9.0 * cos(deg_to_rad(35.0))
					if _open(layout, lens):
						yaw = y
						break
			_pose(yaw, -35.0, 9.0 * IN, Vector3(look.x * IN, 0.4 * IN, look.y * IN))
			await _still(tag, "scene_" + String(sc["kind"]))
			for m: Node3D in shown_s:
				m.visible = true
	if _want("macro_wall"):
		var mw := _macro_wall_pick(layout)
		if not mw.is_empty():
			var shown_w: Array = _models.filter(func(m: Node3D) -> bool: return m.visible)
			for m: Node3D in shown_w:
				m.visible = false
			_pose(mw["yaw"], -5.0, 6.0 * IN, mw["target"])   # 6 in in front of the city wall, square on: the repeat of its stone (plan W0)
			await _still(tag, "macro_wall")
			for m: Node3D in shown_w:
				m.visible = true
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
				var lens := Vector2(at3.x, at3.z) / IN + Vector2(sin(deg_to_rad(walk["yaw"])), cos(deg_to_rad(walk["yaw"]))) * 0.16 / IN
				if not _open(layout, lens):
					clear = false   # the lens itself must stand on open ground (seed 25: it stood inside a house, the still was 3 / 4 black)
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
		if kind == "TankCluster" and _want("fountain_eye"):   # the fountain at model eye height (4 deg down, 12 in out) from the clearest sight line whose lens stands on open ground
			var base := _open_yaw(layout, c, top + 1.2, -4.0, 12.0, Rect2(c - half, half * 2.0))
			for turn: float in [0.0, 45.0, -45.0, 90.0, -90.0, 135.0, -135.0, 180.0]:
				var eye := base + turn
				if _open(layout, c + Vector2(sin(deg_to_rad(eye)), cos(deg_to_rad(eye))) * 12.0):
					_pose(eye, -4.0, 12.0 * IN, Vector3(c.x * IN, (top + 1.2) * IN, c.y * IN))
					await _still(tag, "fountain_eye")
					break
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
func _backdrop(for_gate := false) -> void:
	var env: Environment = _main.world_environment.environment
	if _town_sky and not for_gate:
		env.background_mode = Environment.BG_SKY
		return
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
func _mean_ring(img: Image, c: Vector2, r0: float, r1: float, skip: Array, mask: Image = null, want := false) -> Color:
	var sum := Color(0, 0, 0, 0)
	var n := 0
	for y in range(maxi(int(c.y - r1), 0), mini(int(c.y + r1) + 1, img.get_height())):
		for x in range(maxi(int(c.x - r1), 0), mini(int(c.x + r1) + 1, img.get_width())):
			var d := Vector2(x, y).distance_to(c)
			if d < r0 or d > r1 or (mask != null and _is_mark(mask.get_pixel(x, y)) != want):   # mask: only model pixels (want) or only non-model pixels
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
		_backdrop(true)
		await process_frame
		_hide_scatter()
	var env: Environment = _main.world_environment.environment   # what the gate frames are graded with (the board's mood layer must show up here)
	_manifest["grade"] = {"tonemap_mode": env.tonemap_mode, "agx_contrast": env.tonemap_agx_contrast, "adjustment": env.adjustment_enabled,
		"contrast": env.adjustment_contrast, "saturation": env.adjustment_saturation, "curve": env.adjustment_color_correction != null}
	var cam := root.get_viewport().get_camera_3d()
	var img := root.get_texture().get_image()
	var masks := await _model_masks(_models)
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
	var hidden_px := 0
	for d: Dictionary in discs:
		var others := discs.filter(func(o: Dictionary) -> bool: return o["i"] != d["i"])
		var score := _score(img, masks, d["c"], d["r"], others)
		if score < 0.0:
			hidden_px += 1   # something of the board stands in front of the model: its disc would read that, not the model
			continue
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
	_gate.append({"seed": tag, "yaw": _play_yaw, "preset": "medium" if pname == "" else pname.trim_prefix("_"), "models": scores.size(), "occluded": occluded + hidden_px, "occluded_mask": hidden_px, "offframe": offframe, "below_1": low,
		"min": snappedf(sorted[0] if not sorted.is_empty() else 0.0, 0.01), "median": snappedf(sorted[sorted.size() / 2] if not sorted.is_empty() else 0.0, 0.01), "scores": rows})
	print("GATE ", tag, pname, " models ", scores.size(), " below1 ", low, " occluded ", occluded + hidden_px)


## The score of one model (gate change 21.11.): its VISIBLE body pixels against the ring of board round its base without any model pixel, score = max(dY / 0.10, dC / 0.10);
## -1 (occluded) when less than VIS_MIN of its whole silhouette inside the disc is visible.
func _score(img: Image, masks: Array[Image], c: Vector2, r: float, others: Array) -> float:
	var whole := _mean_ring(masks[1], c, 0.0, r * 0.9, [], masks[1], true).a
	var body := _mean_ring(img, c, 0.0, r * 0.9, [], masks[0], true)
	if whole < 1.0 or body.a / whole < VIS_MIN:
		return -1.0
	var ring := _mean_ring(img, c, r * 1.3, r * 1.9, others, masks[0], false)
	var cb := Vector2(body.r - body.g, body.b - (body.r + body.g) * 0.5)
	var cr := Vector2(ring.r - ring.g, ring.b - (ring.r + ring.g) * 0.5)
	return maxf(absf(_luma(body) - _luma(ring)) / 0.10, cb.distance_to(cr) / 0.10)


## The gate's model masks: every model drawn flat magenta (unshaded), once with the board as it stands (what is in front of a model hides it) and once with every other
## piece of the board hidden (the model's whole silhouette). Returns [visible, whole]; everything is put back.
func _model_masks(models: Array) -> Array[Image]:
	var mark := StandardMaterial3D.new()
	mark.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mark.albedo_color = Color(0.6, 0.0, 0.6)
	var saved := {}
	for m: Node3D in models:
		for g: GeometryInstance3D in m.find_children("*", "GeometryInstance3D", true, false):
			saved[g] = g.material_override
			g.material_override = mark
	var out: Array[Image] = [await _gate_frame()]
	var hidden: Array[Node3D] = []
	for ch: Node in _cur_board.get_children():
		if ch is Node3D and (ch as Node3D).visible and not models.any(func(m: Node3D) -> bool: return ch == m or ch.is_ancestor_of(m)):
			(ch as Node3D).visible = false
			hidden.append(ch)
	out.append(await _gate_frame())
	for ch: Node3D in hidden:
		ch.visible = true
	for g: GeometryInstance3D in saved:
		g.material_override = saved[g]
	return out


func _gate_frame() -> Image:
	for _i in 8:
		_backdrop(true)
		await process_frame
		_hide_scatter()
	return root.get_texture().get_image()


func _is_mark(c: Color) -> bool:
	return c.r - c.g > 0.2 and c.b - c.g > 0.2 and absf(c.r - c.b) < 0.25


## gate_test=1 (red / green of the sampler): three copies of the first model float 12 in above the board's middle, where nothing of the board can stand in front of them.
## One behind a 2 in box must read `occluded`; one painted flat pale on a plate of the same flat pale must read below 1 (visible, but no contrast); the same pale pawn on a
## black plate must read 1 or more.
func _gate_self_test() -> void:
	var cam := root.get_viewport().get_camera_3d()
	var tests: Array = []
	var props: Array[Node3D] = []
	var pale := StandardMaterial3D.new()
	pale.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pale.albedo_color = Color(0.8, 0.8, 0.78)
	var dark := pale.duplicate() as StandardMaterial3D
	dark.albedo_color = Color.BLACK
	for t in 3:
		var pawn := _models[0].duplicate() as Node3D
		_cur_board.add_child(pawn)
		pawn.global_position = _cur_board.global_position + Vector3((t - 1) * 6.0, 12.0, 0.0) * IN
		tests.append(pawn)
		if t > 0:
			for g: GeometryInstance3D in pawn.find_children("*", "GeometryInstance3D", true, false):
				g.material_override = pale
		var prop := MeshInstance3D.new()
		if t == 0:
			prop.mesh = BoxMesh.new()
			(prop.mesh as BoxMesh).size = Vector3.ONE * 2.0 * IN
			_cur_board.add_child(prop)
			prop.global_position = pawn.global_position + (cam.global_position - pawn.global_position).normalized() * 2.0 * IN
		else:
			prop.mesh = PlaneMesh.new()
			(prop.mesh as PlaneMesh).size = Vector2.ONE * 3.0 * IN
			prop.material_override = pale if t == 1 else dark
			_cur_board.add_child(prop)
			prop.global_position = pawn.global_position - Vector3.UP * 0.0005
		props.append(prop)
	var img := await _gate_frame()
	var masks := await _model_masks(tests)
	var k := float(img.get_width()) / root.get_visible_rect().size.x
	var got: Array[float] = []
	for pawn: Node3D in tests:
		var p := pawn.global_position + Vector3.UP * 0.004
		var c := cam.unproject_position(p) * k
		got.append(_score(img, masks, c, maxf((cam.unproject_position(p + cam.global_transform.basis.x * 0.016) * k - c).length(), 2.5), []))
	var ok := got[0] < 0.0 and got[1] >= 0.0 and got[1] < 1.0 and got[2] >= 1.0
	_manifest["gate_test"] = {"behind_box": got[0], "pale_on_pale": got[1], "on_black": got[2], "pass": ok}
	print("GATE_TEST behind_box %.2f (occluded = -1) pale_on_pale %.2f (< 1) on_black %.2f (>= 1) -> %s" % [got[0], got[1], got[2], "PASS" if ok else "FAIL"])
	for n: Node3D in tests + props:
		n.free()


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
	return cd["level"] == 0 and not ["Hazard", "Roofed", "Tower"].has(cd["lot_kind"])   # (roofs lane 22.11.: a house or a tall tower is level 0 but solid - no lens, no model there)


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
	var cam3 := root.get_viewport().get_camera_3d()
	var k := float(WIDTH) / root.get_visible_rect().size.x
	_manifest["still_info"][file] = {"cam": cam, "px_per_in": snappedf((cam3.unproject_position(_cam_target + cam3.global_transform.basis.x * IN) - cam3.unproject_position(_cam_target)).length() * k, 0.01)}
	if _grit_debug > 0:
		await _grit_still(file.get_basename() + ("_grit.png" if _grit_debug == 1 else "_gritmap.png"))


## The same frame with the board shader's `grit_debug` on: every light, the ambient, sky reflections, fog and glow off, a linear tonemap at exposure 1, the models hidden, so only the
## shader's flat class colours (emission) reach the image, unchanged. Everything is put back afterwards. Saved as PNG (no JPEG ringing on the class edges).
func _grit_still(file: String) -> void:
	var env: Environment = _main.world_environment.environment
	var keys := ["background_mode", "background_color", "ambient_light_energy", "reflected_light_source", "tonemap_mode", "tonemap_exposure", "glow_enabled", "fog_enabled",
		"volumetric_fog_enabled", "adjustment_enabled", "ssao_enabled", "ssil_enabled", "sdfgi_enabled", "ssr_enabled"]
	var saved := {}
	for key: String in keys:
		saved[key] = env.get(key)
	var lights: Array = []
	for l in _main.get_tree().root.find_children("*", "Light3D", true, false):
		if (l as Light3D).visible:
			lights.append(l)
			(l as Light3D).visible = false
	var shown: Array = _models.filter(func(m: Node3D) -> bool: return m.visible)
	for m: Node3D in shown:
		m.visible = false
	_cur_board.get("_material").set_shader_parameter("grit_debug", _grit_debug)
	for _i in 6:
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color.BLACK
		env.ambient_light_energy = 0.0
		env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
		env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
		env.tonemap_exposure = 1.0
		for key: String in ["glow_enabled", "fog_enabled", "volumetric_fog_enabled", "adjustment_enabled", "ssao_enabled", "ssil_enabled", "sdfgi_enabled", "ssr_enabled"]:
			env.set(key, false)
		await process_frame
		_hide_scatter()
	var img := root.get_texture().get_image()
	img.resize(WIDTH, int(float(WIDTH) * img.get_height() / img.get_width()), Image.INTERPOLATE_NEAREST)
	img.save_png(_out.path_join(file))
	_cur_board.get("_material").set_shader_parameter("grit_debug", 0)
	for key: String in keys:
		env.set(key, saved[key])
	for l in lights:
		(l as Light3D).visible = true
	for m: Node3D in shown:
		m.visible = true
	for _i in 4:
		await process_frame


## The city wall close-up (plan PLAN_RUINTOWN_GRIT W0): the longest run of standing wall cells (level 1+) in one column whose face has open level-0 ground in front of at least half of it
## and whose lens spot 6 in out is open ground or off the board; square on, the target half way up the run's lowest cell on the cell edge at the run's middle: {yaw, target (m)}.
func _macro_wall_pick(layout: Dictionary) -> Dictionary:
	var nx: int = layout["nx"]
	var nz: int = layout["nz"]
	var cell := float(layout["cell_in"])
	var best := {}
	for x in nx:
		var run := 0
		var low := 99
		for z in nz + 1:
			var cd: Dictionary = layout["cells"][z * nx + x] if z < nz else {}
			if z < nz and cd["lot_kind"] == "Wall" and int(cd["level"]) >= 1:
				run += 1
				low = mini(low, int(cd["level"]))
				continue
			if run >= 3 and (best.is_empty() or run > int(best["len"])):
				for side in [-1, 1]:
					var open := 0
					for zz in range(z - run, z):
						if x + side >= 0 and x + side < nx and _open(layout, (Vector2(x + side, zz) + Vector2(0.5, 0.5) - Vector2(nx, nz) * 0.5) * cell):
							open += 1
					var ex: float = (float(x) + (1.0 if side > 0 else 0.0) - nx * 0.5) * cell
					var ez: float = (float(z) - run * 0.5 - nz * 0.5) * cell
					var lens := Vector2(ex + side * 6.0, ez)
					var off_board := absf(lens.x) > nx * cell * 0.5
					if open * 2 >= run and (off_board or _open(layout, lens)) and (best.is_empty() or run > int(best["len"])):
						best = {"len": run, "yaw": 90.0 if side > 0 else -90.0, "target": Vector3(ex * IN, float(layout["level_in"][low]) * 0.5 * IN, ez * IN)}
			run = 0
			low = 99
	if best.is_empty():
		return {}
	return {"yaw": best["yaw"], "target": best["target"]}


## The paving close-up (plan PLAN_RUINTOWN_GRIT G0): a level-0 street cell beside a level-0 earth cell, nearest the board centre, whose camera spot 5 in out over the street is open
## ground and has no lantern post within 2.5 in of the target or the lens. The target is 1 in onto the street from the cell border: {yaw, target (m)}.
func _macro_ground_pick(layout: Dictionary) -> Dictionary:
	var nx: int = layout["nx"]
	var nz: int = layout["nz"]
	var cell := float(layout["cell_in"])
	var cands: Array[Dictionary] = []
	for cz in nz:
		for cx in nx:
			var cd: Dictionary = layout["cells"][cz * nx + cx]
			if cd["level"] != 0 or not cd["street"] or cd["lot_kind"] == "Hazard":
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var ox: int = cx + d.x
				var oz: int = cz + d.y
				if ox < 0 or oz < 0 or ox >= nx or oz >= nz:
					continue
				var nd: Dictionary = layout["cells"][oz * nx + ox]
				if BoardgenGreybox._cell_kind(nd, true) != "ground":
					continue
				var centre := Vector2(cx + 0.5 - nx * 0.5, cz + 0.5 - nz * 0.5) * cell
				var border := centre + Vector2(d) * cell * 0.5
				cands.append({"at": border - Vector2(d) * 1.0, "out": -Vector2(d), "dist": centre.length()})
	cands.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["dist"] < b["dist"])
	var posts: Array = BoardgenTownDressing.lanterns(layout) if layout.get("theme", "") == "RuinTown" else []
	for c: Dictionary in cands:
		var at: Vector2 = c["at"]
		var lens: Vector2 = at + (c["out"] as Vector2) * 5.2
		if not _open(layout, lens):
			continue
		if posts.any(func(l: Dictionary) -> bool: return (l["at"] as Vector2).distance_to(at) < 2.5 or (l["at"] as Vector2).distance_to(lens) < 2.5):
			continue
		var o: Vector2 = c["out"]
		return {"yaw": rad_to_deg(atan2(o.x, o.y)), "target": Vector3(at.x * IN, 0.0, at.y * IN)}
	return {}


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
	_main.table.get_node("TableMesh").visible = _real_table
	for d in _main.find_children("*", "Decal", true, false):
		(d as Decal).visible = false
	_main.get_node("TableBiomePresenter/TableBiomeReference").visible = _real_table
	_main.table.get_node("GrassField").visible = _real_table
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
	if _real_table:
		return
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
	_cam_target = target
