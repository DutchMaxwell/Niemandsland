class_name BoardgenTownSilhouette
extends RefCounted
## The town's silhouette from the overview and play cameras (maintainer 21.11.: "still too blocky from above"). LOOK ONLY: no piece here is a collider, no cell changes class,
## every walkable top stays flat and exact at its 3 / 6 / 9 in and keeps its middle free. Pure plans (board inches, origin at the board centre) and one builder.
##   - wall_parts: a raised city-wall or tower cell is drawn thinner - a full-width foot, a stepped batter, the face pulled in by at most REACH_IN on every open face, and a full-width
##     corbelled course under the walk (the walk itself is the cell, exact). The cell's own greybox box keeps the collider and draws nothing.

const REACH_IN := 0.2   # the drawn face may sit at most this far inside the collider's face (plan O3: a model touching the collider still touches the wall)
const FOOT_IN := 0.45
const BATTER_IN := 0.9
const CORBEL_IN := 0.5
const DIRS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]   # N, E, S, W


static func _level(layout: Dictionary, x: int, z: int) -> int:
	if x < 0 or z < 0 or x >= int(layout["nx"]) or z >= int(layout["nz"]):
		return -1
	return int(layout["cells"][z * int(layout["nx"]) + x]["level"])


## {cell index: [side, ...]}: the sides (index into DIRS) of every cell where a ladder arrives at its top.
static func _ladder_tops(layout: Dictionary) -> Dictionary:
	var out := {}
	for c: Dictionary in layout["connectors"]:
		var d := Vector2i(c["low_xz"][0], c["low_xz"][1]) - Vector2i(c["high_xz"][0], c["high_xz"][1])
		(out.get_or_add(int(c["high"]), []) as Array).append(DIRS.find(d))
	return out


## The cells wall_parts draws: every raised city-wall cell (the 3 in low wall of the bands and the buttress too) and every 9 in tower cell. The greybox draws none of these itself (it keeps their colliders).
static func drawn_cells(layout: Dictionary) -> Dictionary:
	var out := {}
	for cd: Dictionary in layout["cells"]:
		if int(cd["level"]) >= 3 or (int(cd["level"]) >= 1 and cd["lot_kind"] == "Wall"):
			out[int(cd["z"]) * int(layout["nx"]) + int(cd["x"])] = true
	return out


## The drawn pieces of the wall and tower cells: [{lo, hi (Vector3, inches), kind, cell}]. Foot and corbel course fill the cell; the batter is pulled in by half, the body by REACH_IN, on
## each OPEN face only (a lower neighbour or the board edge), never on a face a ladder leans on.
static func wall_parts(layout: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var nx: int = layout["nx"]
	var cell_in := float(layout["cell_in"])
	var origin := Vector2(nx, int(layout["nz"])) * cell_in * -0.5
	var ladders := _ladder_tops(layout)
	for i: int in drawn_cells(layout):
		var cd: Dictionary = layout["cells"][i]
		var level: int = cd["level"]
		var top: float = layout["level_in"][level]
		var kind := "wall" if cd["lot_kind"] == "Wall" else "tier3"
		var lo := origin + Vector2(cd["x"], cd["z"]) * cell_in
		var inset := [0.0, 0.0, 0.0, 0.0]
		for side in 4:
			var d := DIRS[side]
			if _level(layout, cd["x"] + d.x, cd["z"] + d.y) < level and not (ladders.get(i, []) as Array).has(side):
				inset[side] = REACH_IN
		var cut := func(f: float, y0: float, y1: float) -> Dictionary:
			return {"lo": Vector3(lo.x + inset[3] * f, y0, lo.y + inset[0] * f), "hi": Vector3(lo.x + cell_in - inset[1] * f, y1, lo.y + cell_in - inset[2] * f), "kind": kind, "cell": i}
		out.append_array([cut.call(0.0, 0.0, FOOT_IN), cut.call(0.5, FOOT_IN, BATTER_IN), cut.call(1.0, BATTER_IN, top - CORBEL_IN), cut.call(0.0, top - CORBEL_IN, top)])
	return out


## All of it on the board's material, in one MultiMesh.
static func build(parent: Node3D, layout: Dictionary, material: Material) -> void:
	var m := BoardgenTownDressing.INCHES_TO_METERS
	var kinds: Array = BoardgenTheme.TOWN_KINDS
	var items: Array = []   # [basis, origin, custom]
	for b: Dictionary in wall_parts(layout):
		var size: Vector3 = b["hi"] - b["lo"]
		items.append([Basis.from_scale(size * m), (b["lo"] + b["hi"]) * 0.5 * m, Color(kinds.find(b["kind"]), size.x, size.y, size.z)])
	_multimesh(parent, "Silhouette", BoxMesh.new(), items, material)


static func _multimesh(parent: Node3D, name: String, mesh: Mesh, items: Array, material: Material) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = items.size()
	for i in items.size():
		mm.set_instance_transform(i, Transform3D(items[i][0], items[i][1]))
		mm.set_instance_custom_data(i, items[i][2])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = name
	mmi.multimesh = mm
	mmi.material_override = material
	parent.add_child(mmi)
