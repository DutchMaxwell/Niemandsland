extends SceneTree
## NML-1073 M3-4 — the TERRAIN BANK: N school boards written in exactly the
## act-header terrain shape, so the Rust port can be gated on boards no corpus
## covers. `tools/core_selfplay.gd:182` builds its board as
## `SchoolTerrain.generate(game_seed)` and the recorder writes it out through
## `AiActRecorder._school_terrain_line` (act_recorder.gd:188-197); this tool
## calls BOTH of those, so the bank cannot drift from what a real game records.
##
## Each board also carries the GDScript side's own reading of the board — a 3"
## LATTICE of `SchoolTerrain.type_at` answers, one sample per cell — so the
## Rust reader can be diffed against the generator instead of against itself.
## The lattice is anchored `LATTICE_OFFSET_IN` past each cell's CENTRE, i.e.
## 0.25" short of the cell's far corner: a RED proof that shifts the lattice by
## 0.5" then lands in the NEXT cell. Anchored at the centre, a 0.5" shift could
## never leave a 3" cell and the red proof would be vacuous.
##
## Run: godot --headless -s res://tools/terrain_bank_dump.gd -- \
##        [out=<dir>] [from=1] [to=200]
## Writes one file per seed: <out>/board_<seed>.json
##
## NML-1073 M3-9b: each board ALSO carries `pieces`, `SchoolTerrain.generate`'s
## drawing list — the `terrain` field of a `core_s<seed>.json`. A bank written
## before that key existed is still a valid board bank; a trainer asked to write
## the result field off such a bank raises instead of guessing.
##
## NML-1155 (bank v2): each board ALSO carries the prop layer the twin's
## deployment blocked law reads (core/nml-core/src/deployment.rs
## `wall_blocked`/`spot_blocked`), in the SAME table-centred inch frame as
## `pieces`:
##   * `walls` — TerrainOverlay.get_wall_segments_world()'s exact answer for
##     this layout (terrain_overlay.gd:1682-1709): the container OBB edges
##     (:2834-2843) plus the ruin wall segments (_segment_world_placement,
##     :2361-2415). Exactly the array `Terrain::set_walls_world_m` consumes.
##   * `blockers` — one disc [x, y, r] per SOLID prop the deployment physics
##     probe (ai_deployment.gd:294-308: a 0.02 m sphere at 0.07 m height hits
##     any collider outside group "miniature") would hit: the 6"x2.5"x3"
##     container boxes (BoxShape terrain_overlay.gd:2886-2891; the textured
##     path builds the identical collider, :3153-3158). Radius = the box's XZ
##     INCIRCLE (half the shorter side, 1.5") — the largest disc whose own
##     0.02 m dilation stays inside the box, so disc ⊕ probe ⊆ box ⊕ probe and
##     the twin never out-blocks the table's own 0.02 m band around the box's
##     OBB edges (near_wall, ai_deployment.gd:312-316) — measured on the 100
##     fixture dumps: 0/1042 recorded-clear spots flip; a circumscribed disc
##     (3.354") flips 114. Trees, mines and signs are decorative — NO
##     collision (terrain_overlay.gd:2851-2864, :2896-2897). Ruin wall boxes
##     and corner posts ride `walls`: the probe reaches only 1.81 cm past
##     their surfaces (sphere centre 0.07 m over a 2.5"-high box top) vs the
##     2 cm wall band, so their discs would over-block that 1.4 mm gap.
##   * `blocker_boxes` (NML-1152 step 4d) — per collider the deployment probe
##     can hit, its REAL XZ footprint: `[cx, cy, half_w, half_h, angle, reach]`
##     (centred inches, radians, reach inches) read straight off the body's
##     CollisionShape3D + global transform (containers
##     terrain_overlay.gd:2886-2891 / :3153-3158, shell + procedural walls
##     :1967-1972 / :2062-2067, corner posts :1910-1915). `walls` carries the
##     wall bodies' CENTRELINES, so the twin's 0.02 m band only reaches
##     0.02 − 0.125" past a wall surface — the probe reaches 0.0181 m (the
##     sphere's XZ reach at 0.07 m over a 2.5"-high box, ai_deployment.gd:296,
##     :303): that 1.3 mm ring is step 5's twin-permissive residue. `reach`
##     stores exactly that per-box figure, so the twin's box layer mirrors the
##     probe instead of guessing. A non-box shape is recorded as a convex
##     polygon `[[x, y], ...]` in the same frame (the twin reads boxes only;
##     no such shape exists in the corpus).
## A bank dumped without the prop keys still loads (serde defaults twin-side).

const IN2M := 0.0254
## The probe sphere's radius and centre height (ai_deployment.gd:296, :303).
const PROBE_RADIUS_M := 0.02
const PROBE_HEIGHT_M := 0.07
## Half a cell minus a quarter inch — see the anchor note above.
const LATTICE_OFFSET_IN := 1.25

var _out := ""
var _from := 1
var _to := 200
var _ovl: Node3D


func _init() -> void:
	_out = OS.get_environment("HOME").path_join("selfplay_out/terrain_bank")
	for a in OS.get_cmdline_user_args():
		var arg := str(a)
		if arg.begins_with("out="):
			_out = arg.substr(4)
		elif arg.begins_with("from="):
			_from = int(arg.substr(5))
		elif arg.begins_with("to="):
			_to = int(arg.substr(3))


## The NML-1155 overlay harvest needs the tree initialized (the overlay builds
## its panel libraries in _ready, terrain_overlay.gd:427-441) — the arena
## harness's own launch pattern (tools/arena_match.gd:114-116).
func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var out := _out
	var from := _from
	var to := _to
	DirAccess.make_dir_recursive_absolute(out)
	_ovl = (load("res://scripts/terrain_overlay.gd") as GDScript).new()
	root.add_child(_ovl)
	var cells_total := 0
	var walls_total := 0
	var blockers_total := 0
	var boxes_total := 0
	for layout_seed in range(from, to + 1):
		var world := SchoolTerrain.generate(layout_seed)
		var n := int(world["n"])
		cells_total += (world["cells"] as Dictionary).size()
		var board := {
			"seed": layout_seed,
			"n": n,
			"cells_set": (world["cells"] as Dictionary).size(),
			# The header line verbatim — the SAME function the act recorder calls.
			"terrain": AiActRecorder._school_terrain_line(world),
			# NML-1073 M3-9b: the DRAWING list `tools/core_selfplay.gd:725` writes
			# out as the result file's `terrain`. It is NOT derivable from the
			# header line above — that one merges every footprint into a cell map
			# and drops each piece's origin, size and rotation — so the bank has to
			# carry it, or the Godot-free trainer cannot write the field at all.
			"pieces": world.get("pieces", []),
			"lattice": _lattice(world, n),
		}
		# --- NML-1155: the prop layer, harvested from the REAL overlay. The
		# arena seeds the same layouter this way (arena_match.gd:278-283 with
		# symmetric=1, which SchoolTerrain.generate pins, school_terrain.gd:21),
		# then reads the overlay the harness drove (main.gd:14992-15010). The
		# grid_cells equality below proves the second run matches the first.
		var ml: Control = (load("res://scripts/map_layout.gd") as GDScript).new()
		ml.table_size_feet = Vector2(6.0, 4.0)
		ml.point_symmetry_enabled = true
		ml.grid_rotation_degrees = 0.0
		seed(layout_seed)
		ml._generate_terrain_layout()
		ml._rebuild_derived()
		if ml._calculate_grid_dimensions().x != n or ml.grid_cells != world["cells"]:
			printerr("[BANK] seed %d: second layout run diverged from SchoolTerrain" % layout_seed)
			quit(1)
			return
		_ovl.update_wall_models(ml.wall_segments, Vector2(6.0, 4.0), 0.0)
		_ovl.update_placed_objects(ml.placed_objects, Vector2(6.0, 4.0), 0.0)
		var walls: Array = []
		for seg in _ovl.get_wall_segments_world():
			walls.append([seg[0].x / IN2M, seg[0].y / IN2M, seg[1].x / IN2M, seg[1].y / IN2M])
		var blockers: Array = []
		for inst in _ovl._object_instances:
			if not (inst is StaticBody3D):
				continue   # trees / mines / signs: decorative, no collision
			for c in inst.get_children():
				if c is CollisionShape3D and (c as CollisionShape3D).shape is BoxShape3D:
					var sz: Vector3 = ((c as CollisionShape3D).shape as BoxShape3D).size
					blockers.append([c.global_position.x / IN2M, c.global_position.z / IN2M,
						minf(sz.x, sz.z) * 0.5 / IN2M])
		# NML-1152 step 4d: the probe's REAL footprints — containers AND wall
		# bodies (walls ride `walls` as centrelines; the 0.25"-thick bodies,
		# terrain_overlay.gd:1967-1972, out-reach that band by the ring above).
		var boxes: Array = []
		for inst in _ovl._object_instances:
			boxes.append_array(_collider_boxes(inst))
		for inst in _ovl._wall_instances:
			boxes.append_array(_collider_boxes(inst))
		board["walls"] = walls
		board["blockers"] = blockers
		board["blocker_boxes"] = boxes
		walls_total += walls.size()
		blockers_total += blockers.size()
		boxes_total += boxes.size()
		print("[BANKV2] seed %d walls %d blockers %d boxes %d"
			% [layout_seed, walls.size(), blockers.size(), boxes.size()])
		ml.free()
		var f := FileAccess.open(out.path_join("board_%d.json" % layout_seed), FileAccess.WRITE)
		if f == null:
			printerr("[BANK] cannot write board_%d.json to %s" % [layout_seed, out])
			quit(1)
			return
		f.store_string(JSON.stringify(board, "", true, true))
		f.close()
	print("[BANK] wrote %d boards (seeds %d..%d) to %s — %d terrain cells, %d wall segments, %d blocker discs, %d blocker boxes"
		% [to - from + 1, from, to, out, cells_total, walls_total, blockers_total, boxes_total])
	quit(0)


## NML-1152 step 4d: the probe-visible collision footprints of one overlay
## body — per CollisionShape3D child, the XZ oriented box the deployment probe
## actually tests (ai_deployment.gd:300-309), from the shape + its GLOBAL
## transform (the same transform `update_placed_objects` / `update_wall_models`
## spawned it with). `reach` = the probe sphere's XZ reach past THIS box:
## sqrt(r² − dy²) with dy the sphere centre's y-gap to the nearest box face —
## 0 when the box top sits below the sphere's bottom (the probe can never hit
## it, so no box is recorded). A non-box shape is recorded as a convex polygon.
func _collider_boxes(inst: Node) -> Array:
	var out: Array = []
	for c in inst.get_children():
		var cs := c as CollisionShape3D
		if cs == null or cs.shape == null:
			continue
		var xf := cs.global_transform
		if cs.shape is BoxShape3D:
			var sz: Vector3 = (cs.shape as BoxShape3D).size
			var top: float = xf.origin.y + sz.y * 0.5
			var bot: float = xf.origin.y - sz.y * 0.5
			var dy: float = maxf(maxf(0.0, PROBE_HEIGHT_M - top), bot - PROBE_HEIGHT_M)
			var reach: float = sqrt(maxf(0.0, PROBE_RADIUS_M * PROBE_RADIUS_M - dy * dy))
			if reach <= 0.0:
				continue
			var b := xf.basis
			# Godot yaw θ: basis.x = (cos θ, 0, −sin θ) — the twin rotates sample
			# points into the box frame with exactly this angle.
			out.append([xf.origin.x / IN2M, xf.origin.z / IN2M,
				sz.x * 0.5 / IN2M, sz.z * 0.5 / IN2M,
				atan2(-b.x.z, b.x.x), reach / IN2M])
		elif cs.shape is ConvexPolygonShape3D:
			var poly: Array = []
			for p in (cs.shape as ConvexPolygonShape3D).points:
				var w := xf * p
				poly.append([w.x / IN2M, w.z / IN2M])
			out.append(poly)
		else:
			printerr("[BANKV2] unsupported collider shape %s skipped" % cs.shape.get_class())
	return out


## One `SchoolTerrain.type_at` answer per cell, at the cell centre plus
## `LATTICE_OFFSET_IN` in both axes. `pts` are WORLD METRES (the shape
## `type_at` takes, y always 0); `types` is one digit per point, in the same
## order — `TerrainRules.TerrainType` is 0..4, so a digit is enough and the
## file stays a tenth of the size an array of ints would be.
func _lattice(world: Dictionary, n: int) -> Dictionary:
	var pts: Array = []
	var types := ""
	for cx in range(n):
		for cz in range(n):
			var c := SchoolTerrain.cell_centre_in(Vector2i(cx, cz), n)
			var p := Vector3((c.x + LATTICE_OFFSET_IN) * IN2M, 0.0,
				(c.y + LATTICE_OFFSET_IN) * IN2M)
			pts.append([p.x, p.z])
			types += str(SchoolTerrain.type_at(world, p))
	return {"step_in": SchoolTerrain.CELL_IN, "offset_in": LATTICE_OFFSET_IN,
		"order": "cell x outer, cell z inner", "pts": pts, "types": types}
