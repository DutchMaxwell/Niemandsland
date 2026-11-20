class_name BoardgenRails
extends Node3D
## Safety railings for the look pass of a seeded boardgen board: a thin rail (posts, top and mid rail, a kick plate) along every tier
## edge that drops to a lower cell inside the board, a taller post at every convex corner, and a clear gap around the top of each
## ladder. Everything stands within REACH_IN of the edge, so the tier top stays standing room for bases. VISUAL ONLY (no collider).
## parts() is a pure function of the layout (its seed feeds one RandomNumberGenerator); plan() turns it into boxes (ONE MultiMesh: the
## procedural look), kit_plan() into instances of the authored K1 modules (BoardgenKit: tube rails with mesh infill, round posts).

const INCHES_TO_METERS := 0.0254
const INSET_IN := 0.07   # the rail line stands this far in off the tier edge
const REACH_IN := 0.2   # nothing of a railing goes further in than this
const GAP_IN := 0.9   # a ladder top leaves this much clear on each side of its edge point
const STEEL := Color(0.30, 0.31, 0.33)
const RUST := Color(0.36, 0.19, 0.10)
const KIT_MODULES: Array[String] = ["rail_span", "rail_post", "rail_post_corner"]
const SPAN_MODULE_IN := 3.0   # the length of the rail_span module; an instance stretches along the run to its span


## Every box of the railings, in metres off the board centre: {shape: "box", xf: Transform3D, colour: Color}.
static func plan(layout: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p in parts(layout):
		var yaw: Basis = p["yaw"]
		var d: Vector2i = p["d"]
		var top: float = p["top"]
		var tint: Color = p["tint"]
		if p["part"] == "span":
			var len: float = p["len"]
			out.append(_box(p["at"], top + 0.8, yaw, Vector3(len, 0.05, 0.05), tint))
			out.append(_box(p["at"], top + 0.45, yaw, Vector3(len, 0.04, 0.04), tint))
			out.append(_box(p["at"] + Vector2(d) * 0.03, top + 0.075, yaw, Vector3(len, 0.15, 0.03), tint))
		else:
			var corner: bool = p["part"] == "corner"
			out.append(_box(p["at"], top + (0.55 if corner else 0.42), yaw, Vector3(0.1, 1.1, 0.1) if corner else Vector3(0.07, 0.84, 0.07), tint))
			if corner:
				out.append(_box(p["at"], top + 1.12, yaw, Vector3(0.13, 0.04, 0.13), tint))
	return out


## The railings as instances of the K1 kit modules: {rail_span | rail_post | rail_post_corner: [{xf, colour}]}, metres off the board centre.
static func kit_plan(layout: Dictionary) -> Dictionary:
	var out := {"rail_span": [], "rail_post": [], "rail_post_corner": []}
	for p in parts(layout):
		var span: bool = p["part"] == "span"
		var scale := Vector3(float(p["len"]) / SPAN_MODULE_IN, 1.0, 1.0) if span else Vector3.ONE
		var at: Vector2 = p["at"]
		out["rail_span" if span else "rail_post_corner" if p["part"] == "corner" else "rail_post"].append(
			{"xf": Transform3D((p["yaw"] as Basis) * Basis.from_scale(scale), Vector3(at.x, p["top"], at.y) * INCHES_TO_METERS), "colour": p["tint"]})
	return out


## The railings as abstract parts (board inches): {part: span | post | corner, at: the rail line point (a span: its middle), yaw: Basis with
## local +z off the edge, d: the drop direction, top: the tier top, tint, len (spans)}.
static func parts(layout: Dictionary) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(layout["seed"]) * 69069 + 5
	var nx: int = layout["nx"]
	var cell := float(layout["cell_in"])
	var origin := Vector2(nx, layout["nz"]) * cell * -0.5
	var ladders := {}   # (high cell, drop direction) -> the ladder's edge point, board inches
	for c: Dictionary in layout["connectors"]:
		var high := Vector2i(c["high_xz"][0], c["high_xz"][1])
		var dir := Vector2i(c["low_xz"][0], c["low_xz"][1]) - high
		ladders[Vector4i(high.x, high.y, dir.x, dir.y)] = Vector2(c["edge_in"][0], c["edge_in"][1]) + origin
	var posts := {}   # one post per spot, shared by the cells that meet there
	var out: Array[Dictionary] = []
	for z in layout["nz"]:
		for x in nx:
			var top := float(layout["level_in"][layout["cells"][z * nx + x]["level"]])
			var centre := origin + (Vector2(x, z) + Vector2(0.5, 0.5)) * cell
			for d in BoardgenProps.DIRS:
				if not _drops(layout, Vector2i(x, z), d):
					continue
				var along := Vector2(-d.y, d.x)
				var yaw := Basis(Vector3.UP, atan2(float(d.x), float(d.y)))   # local +z points off the edge
				var line := centre + Vector2(d) * (cell * 0.5 - INSET_IN)
				var spans: Array[Vector2] = [Vector2(-cell * 0.5, cell * 0.5)]
				var key := Vector4i(x, z, d.x, d.y)
				if ladders.has(key):
					var t0: float = (ladders[key] - centre).dot(along)
					spans = [Vector2(-cell * 0.5, t0 - GAP_IN), Vector2(t0 + GAP_IN, cell * 0.5)]
				for span in spans:
					if span.y - span.x < 0.2:
						continue
					var len := span.y - span.x
					var mid := line + along * (span.x + span.y) * 0.5
					var tint := STEEL.lerp(RUST, rng.randf() * 0.35)
					out.append({"part": "span", "at": mid, "yaw": yaw, "d": d, "top": top, "len": len, "tint": tint})
					for end: float in [span.x, span.y]:
						var e := Vector2i((along * signf(end)).round())   # the way along the edge past this end
						var corner: bool = absf(end) >= cell * 0.5 - 0.001 and _drops(layout, Vector2i(x, z), e)
						var at := line + along * end - (Vector2(e) * INSET_IN if corner else Vector2.ZERO)
						if posts.has(Vector2i((at * 100.0).round())):
							continue
						posts[Vector2i((at * 100.0).round())] = true
						out.append({"part": "corner" if corner else "post", "at": at, "yaw": yaw, "d": d, "top": top, "tint": tint})
	return out


## Does the tier cell `c` drop to its neighbour in direction `d` (a cell inside the board with a lower level)?
static func _drops(layout: Dictionary, c: Vector2i, d: Vector2i) -> bool:
	var o := c + d
	if o.x < 0 or o.y < 0 or o.x >= layout["nx"] or o.y >= layout["nz"]:
		return false
	return layout["cells"][c.y * layout["nx"] + c.x]["level"] > layout["cells"][o.y * layout["nx"] + o.x]["level"]


static func _box(pos: Vector2, y: float, rot: Basis, size: Vector3, colour: Color) -> Dictionary:
	return {"shape": "box", "xf": Transform3D(rot * Basis.from_scale(size * INCHES_TO_METERS), Vector3(pos.x, y, pos.y) * INCHES_TO_METERS), "colour": colour}


## The kit modules when `kit` has them all cached (one MultiMesh each), else every box in ONE MultiMesh: one draw call.
func build(layout: Dictionary, kit: BoardgenKit = null) -> void:
	if kit != null and kit.usable(KIT_MODULES):
		var groups := kit_plan(layout)
		for module in KIT_MODULES:
			BoardgenKit.add_multimesh(self, module, kit.mesh_or(module), groups[module], module == "rail_span")   # only the span throws a shadow
		return
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 0.6
	mat.metallic = 0.4
	var mesh := BoxMesh.new()
	mesh.material = mat
	BoardgenKit.add_multimesh(self, "Rails", mesh, plan(layout))
