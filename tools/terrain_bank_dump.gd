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

const IN2M := 0.0254
## Half a cell minus a quarter inch — see the anchor note above.
const LATTICE_OFFSET_IN := 1.25


func _init() -> void:
	var out := OS.get_environment("HOME").path_join("selfplay_out/terrain_bank")
	var from := 1
	var to := 200
	for a in OS.get_cmdline_user_args():
		var arg := str(a)
		if arg.begins_with("out="):
			out = arg.substr(4)
		elif arg.begins_with("from="):
			from = int(arg.substr(5))
		elif arg.begins_with("to="):
			to = int(arg.substr(3))
	DirAccess.make_dir_recursive_absolute(out)
	var cells_total := 0
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
		var f := FileAccess.open(out.path_join("board_%d.json" % layout_seed), FileAccess.WRITE)
		if f == null:
			printerr("[BANK] cannot write board_%d.json to %s" % [layout_seed, out])
			quit(1)
			return
		f.store_string(JSON.stringify(board, "", true, true))
		f.close()
	print("[BANK] wrote %d boards (seeds %d..%d) to %s — %d terrain cells in total"
		% [to - from + 1, from, to, out, cells_total])
	quit(0)


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
