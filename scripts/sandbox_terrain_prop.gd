class_name SandboxTerrainProp
extends StaticBody3D
## A freely-placed casual-sandbox ruin that the player picks from the shelf and drags/rotates
## directly on the 3D table — NOT bound to the competitive 3" grid. It is a first-class
## selectable object under ObjectManager, so the existing select/drag/rotate/undo/multiplayer
## machinery moves it with no special code.
##
## SHAPE: an L-shaped corner building — two wings meet at a fixed anchor corner and the storeys
## shrink toward that corner as they rise (base widest, narrowing up). The walls are FAÇADE
## PANEL CELLS — the SAME authored masonry/window/crumble art as the map-layout grid ruins
## (RuinsLibrary WebPs on R2, see terrain_overlay.gd). Because every cell — solid wall, gothic
## window, crumbled top — is from one art set, the stone around a window matches the wall. The
## outer cells crumble (jagged rim); windows sit in the tall intact bays.
##
## Multi-storey ruins are WALKABLE: each floor height becomes thin arm colliders on the ground
## layer, so a mini dropped over the ruin settles on the highest surviving platform beneath it.
## Representation / handling only; no OPR rule is enforced here. No GLB / model-forge assets.

# === Constants ===

const GROUP := "sandbox_terrain"

## Physics layers — kept in sync with object_manager.gd. The prop sits on the GROUND layer
## (minis settle on its platforms) AND a dedicated movable-terrain layer marking it as
## player-movable. Mask 0: it never settles on anything.
const GROUND_COLLISION_LAYER := 1
const MOVABLE_TERRAIN_COLLISION_LAYER := 4

const INCHES_TO_METERS := 0.0254
const FLOOR_THICKNESS_M := 0.01
const WALL_THICKNESS_INCHES := 0.4         # façade shell depth (front + back panel)

## L-shape: arms sized for GAMEPLAY (~2.5" deep ≈ two base widths), capped so tiny ruins don't
## become a solid block; storeys taper toward the corner.
const ARM_WIDTH_INCHES := 2.5
const ARM_MAX_RATIO := 0.85
const MIN_TOP_SCALE := 0.34                 # smallest top-storey arm length (share of base)
const TAPER_POW := 1.0                       # LINEAR → the wall triangle's hypotenuse is a straight slope
## Extra wall height above the top floor.
const CORNER_RISE_INCHES := 0.0
const CELL_HEIGHT_INCHES := 3.0             # storey spacing (platform/collider levels)

## The wall of each arm is a TRIANGLE MESH (full height at the corner, sloping to nothing at the
## free end) textured with object-local TRIPLANAR masonry, so the sloped top edge cuts the stone
## along a clean diagonal — the stones "break off" along the hypotenuse, no 3" stair-steps.
const WALL_STONE_PANEL := "solid_a"
const NORMAL_PANEL := "normal"              # masonry normal map (relief), as the grid ruins use
## One stone-texture tile spans this (triplanar scale). Deliberately COARSE so the masonry panel
## reads as a few large courses across a wall instead of a finely repeating pattern (the earlier
## 2.6″/3.35″ values tiled far too small). A ~9″ arm shows roughly one full panel → minimal repeat.
const MASONRY_TILE_INCHES := 10.0
## Match the map-layout grid ruins' material (terrain_overlay.gd) so the stone looks the same.
const STONE_ROUGHNESS := 0.93
const STONE_NORMAL_STRENGTH := 1.4
## The diagonal break is built from stone-sized vertical columns, each snapped to a whole number
## of stone courses → the broken edge steps along the masonry (whole stones), not a clean cut.
const STONE_INCHES := 0.42
const STONE_RAGGED_MODULO := 4              # ~1 in 4 columns loses a stone (ragged edge)

## Gothic windows are the authored "window" panel, UV-cropped to just the tracery (so the
## surrounding stone is the wall's own masonry), placed as alpha-scissor quads on the triangle.
const WINDOW_PANEL := "window"
const WINDOW_WIDTH_INCHES := 1.3
const WINDOW_HEIGHT_INCHES := 2.15
const WINDOW_SILL_INCHES := 0.5
const WINDOW_SPACING_INCHES := 3.0          # horizontal spacing of window columns
const WINDOW_VSTEP_INCHES := 3.0            # vertical spacing of window rows
const WINDOW_CHANCE := 0.55
const WINDOW_ALPHA_SCISSOR := 0.4
const WINDOW_UV_OFFSET := Vector2(0.31, 0.15)
const WINDOW_UV_SCALE := Vector2(0.38, 0.70)

## Walkable platforms are one clean slab per arm, top-textured with bespoke floor textures
## (generated to match the masonry): cobbled courtyard for the ground base, cut flagstones for
## the upper platforms. Triplanar so the floor tiles at a fixed real scale.
## All floor slabs share one thickness. The base is built UP from the table (a plinth, so its
## surface clears the table → no z-fighting); upper platforms hang their slab DOWN from the
## storey surface.
const FLOOR_PLATE_THICKNESS_INCHES := 0.16
const FLOOR_BASE_TEX := "res://assets/sandbox_floor_base.webp"
const FLOOR_PLATFORM_TEX := "res://assets/sandbox_floor_platform.webp"
## How many inches one texture tile spans. The platform texture is a ~5×5 grid of small square
## stone tiles → a 3" span gives small ~0.6" tiles; the base cobble reads well a bit larger.
const FLOOR_TILE_BASE_INCHES := 6.0
const FLOOR_TILE_PLATFORM_INCHES := 3.0

## Brick rubble scattered at the foot of each outer wall (mirrors the auto-generated map-layout
## ruins, terrain_overlay.gd). One MultiMesh per ruin; box fragments wear the wall masonry via
## OBJECT-local triplanar (so the rubble rides with the movable prop, unlike the map-layout's
## world triplanar). Sizes/embed match terrain_overlay's RUBBLE_* constants.
const RUBBLE_COUNT_PER_ARM := 20
const RUBBLE_STONE_MIN_M := 0.003
const RUBBLE_STONE_MAX_M := 0.010
const RUBBLE_MAX_DIST_M := 0.0254          # taper ends 1" out from the wall face
const RUBBLE_EMBED_FRAC := 0.35            # fragments sink partly into the ground

## Procedural placeholder (until the panels are cached).
const PLACEHOLDER_COLOR := Color(0.52, 0.50, 0.46)

# === Public state ===

var prop_id: String = ""
var prop_kind: int = 0
var footprint_inches: Vector2 = Vector2.ZERO
var floor_heights_inches: Array = [0.0]

# === Private state ===

var _visual_root: Node3D = null
var _materials: Dictionary = {}  # cache key -> Material (per prop)
## Biome theme prefix for the wall/window/normal panels (e.g. "desert_"); "" = grassland. Set in
## configure() from the prop's biome; selects which themed RuinsLibrary panel set is downloaded + used.
var _theme_prefix: String = ""

# === Public ===

## Set the prop's identity + dimensions and build its floor colliders. Call once right
## after `new()`, before adding to the tree / positioning.
func configure(p_prop_id: String, p_kind: int, p_footprint_inches: Vector2, p_floors: Array, p_theme_prefix: String = "") -> void:
	prop_id = p_prop_id
	prop_kind = p_kind
	footprint_inches = p_footprint_inches
	_theme_prefix = p_theme_prefix
	floor_heights_inches = p_floors.duplicate() if not p_floors.is_empty() else [0.0]

	add_to_group("selectable")
	add_to_group("terrain")
	add_to_group(GROUP)
	collision_layer = GROUND_COLLISION_LAYER | MOVABLE_TERRAIN_COLLISION_LAYER
	collision_mask = 0
	set_meta("prop_id", prop_id)
	set_meta("prop_kind", prop_kind)
	set_meta("sandbox_level_count", floor_heights_inches.size())

	_build_floor_colliders()


## Build the visual (façade panel cells, else procedural placeholder) and, if the panel set
## isn't cached yet, fetch it and rebuild when it arrives.
func build_visual(lib: RuinsLibrary) -> void:
	_apply_visual(lib)
	# Fetch the wall panels if missing, and/or the themed floor panels (optional — bundled fallback)
	# if a biome has them but they're not cached yet, then rebuild so the floors re-theme.
	if lib != null and (not lib.all_panels_cached(_theme_prefix) or not lib.floor_panels_cached(_theme_prefix)):
		_ensure_panels_async(lib)


## Number of walkable storeys (>= 1).
func level_count() -> int:
	return floor_heights_inches.size()

# === Private: L-shape layout ===

func _max_floor_inches() -> float:
	var m := 0.0
	for h in floor_heights_inches:
		m = maxf(m, float(h))
	return m


## Total corner height (metres) used by the taper.
func _total_height_m() -> float:
	return (_max_floor_inches() + CELL_HEIGHT_INCHES + CORNER_RISE_INCHES) * INCHES_TO_METERS


## Per-storey L params (metres): anchor corner (ax, az), X/Z arm lengths (shrinking toward the
## corner via the taper), arm width, storey top Y.
func _l_params(i: int) -> Dictionary:
	var fw0 := footprint_inches.x * INCHES_TO_METERS
	var fd0 := footprint_inches.y * INCHES_TO_METERS
	var h := float(floor_heights_inches[i]) * INCHES_TO_METERS
	var total := _total_height_m()
	var shrink := maxf(pow(clampf(1.0 - h / total, 0.0, 1.0), 1.0 / TAPER_POW), MIN_TOP_SCALE)
	return {
		"ax": -fw0 * 0.5,
		"az": -fd0 * 0.5,
		"lx": fw0 * shrink,
		"lz": fd0 * shrink,
		"arm": minf(ARM_WIDTH_INCHES * INCHES_TO_METERS, minf(fw0, fd0) * ARM_MAX_RATIO),
		"top": h,
	}

## NML-005 step 5: the prop's two L outer walls as world XZ segments (metres) — the AI's
## MOVEMENT wall channel (planner swept checks, rest clamps). Sight stays area-semantics
## (ruins: see in/out, not through), so these segments are NOT fed to the LOS/fan side.
func wall_segments_world() -> Array:
	var l := _l_params(0)
	var ax := float(l["ax"])
	var az := float(l["az"])
	var lx := float(l["lx"])
	var lz := float(l["lz"])
	var xf := global_transform
	var out: Array = []
	for seg in [[Vector3(ax, 0, az), Vector3(ax + lx, 0, az)],
			[Vector3(ax, 0, az), Vector3(ax, 0, az + lz)]]:
		var a := xf * (seg[0] as Vector3)
		var b := xf * (seg[1] as Vector3)
		out.append([Vector2(a.x, a.z), Vector2(b.x, b.z)])
	return out


# === Private: colliders ===

## Two walkable arm slabs per storey (an L), each top at the walkable surface, shrinking toward
## the corner. The ground surface is raised onto the base plinth so minis stand on it (matching
## the visual). They overlap at the corner — harmless.
func _build_floor_colliders() -> void:
	for i in range(floor_heights_inches.size()):
		var l := _l_params(i)
		var surface := float(l["top"])
		if i == 0:
			surface += FLOOR_PLATE_THICKNESS_INCHES * INCHES_TO_METERS
		var y := surface - FLOOR_THICKNESS_M * 0.5
		_add_arm_collider(Vector3(l["lx"], FLOOR_THICKNESS_M, l["arm"]),
			Vector3(l["ax"] + float(l["lx"]) * 0.5, y, l["az"] + float(l["arm"]) * 0.5))
		_add_arm_collider(Vector3(l["arm"], FLOOR_THICKNESS_M, l["lz"]),
			Vector3(l["ax"] + float(l["arm"]) * 0.5, y, l["az"] + float(l["lz"]) * 0.5))


func _add_arm_collider(size: Vector3, pos: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position = pos
	add_child(collider)

# === Private: visuals ===

func _apply_visual(lib: RuinsLibrary) -> void:
	if _visual_root != null and is_instance_valid(_visual_root):
		_visual_root.queue_free()
	_materials.clear()
	_visual_root = Node3D.new()
	_visual_root.name = "Visual"
	add_child(_visual_root)
	if lib != null and lib.all_panels_cached(_theme_prefix):
		_build_ruin(lib)
	else:
		_build_placeholder()


## Download the wall panel set (and, best-effort, the themed floor panels) off the main thread,
## then rebuild once if still alive. Fire-and-forget. The floor panels are optional — a biome
## without them keeps the bundled fallback — so they never gate the wall build.
func _ensure_panels_async(lib: RuinsLibrary) -> void:
	var ok: bool = await lib.ensure_all_panels(_theme_prefix)
	if not is_instance_valid(self):
		return
	await lib.ensure_floor_panels(_theme_prefix)
	if ok and is_instance_valid(self):
		_apply_visual(lib)


## Build the L: each arm wall is a TRIANGLE mesh (clean diagonal hypotenuse) of triplanar
## masonry, with gothic window quads set into it. Each arm is a gallery (outer + inner wall) so
## the walkable floor is framed on both sides. Plus a floor platform per storey.
func _build_ruin(lib: RuinsLibrary) -> void:
	var total := _total_height_m()
	var l0 := _l_params(0)
	var ax: float = l0["ax"]
	var az: float = l0["az"]
	var fw0: float = l0["lx"]
	var fd0: float = l0["lz"]
	# One thin wall per arm (a front+back shell), forming the L's two outer walls.
	_build_arm_facade(true, ax, az, fw0, az, -1.0, total, lib)              # X-arm (faces -Z)
	_build_arm_facade(false, ax, az, fd0, ax, -1.0, total, lib)             # Z-arm (faces -X)
	for i in range(floor_heights_inches.size()):
		var l := _l_params(i)
		_build_platform(i, ax, az, float(l["lx"]), float(l["lz"]), float(l["arm"]), float(l["top"]), lib)
	# Brick rubble at the foot of the two outer walls (like the auto-generated map-layout ruins).
	_build_rubble(ax, az, fw0, fd0, lib)


## Linear hypotenuse height at along-corner distance `u`: full at the corner, 0 at the free end.
func _hyp(u: float, arm_len: float, total: float) -> float:
	return total * clampf(1.0 - u / maxf(arm_len, 0.0001), 0.0, 1.0)


## One arm wall: a thin front+back shell built from stone-sized vertical columns, each snapped
## to a whole number of stone courses along the hypotenuse — so the sloped top is a ragged break
## along the masonry (whole stones remain), not a clean cut. Gothic windows are HOLES cut in the
## stone (the columns skip the window band) with the tracery panel set into the opening.
func _build_arm_facade(is_x: bool, ax: float, az: float, arm_len: float, p: float, outward: float, total: float, lib: RuinsLibrary) -> void:
	var arm_id := 0 if is_x else 1
	var stone := STONE_INCHES * INCHES_TO_METERS
	var depth := WALL_THICKNESS_INCHES * INCHES_TO_METERS
	var mat := _wall_material(lib)
	var windows := _window_list(arm_len, total, arm_id)
	var n := maxi(1, int(round(arm_len / stone)))
	var cw := arm_len / n
	var heights: Array[float] = []  # per-column top (0 = skipped/too-short), for the side-edge caps
	for k in range(n):
		var uc := (k + 0.5) * cw
		var rows := int(round(_hyp(uc, arm_len, total) / stone))
		if _hash3(arm_id, k, 7) % STONE_RAGGED_MODULO == 0:
			rows -= 1
		var h := rows * stone
		if h < stone * 0.5:
			heights.append(0.0)
			continue
		heights.append(h)
		var bands: Array = []
		for w in windows:
			if absf(uc - float(w["uc"])) <= float(w["half"]):
				bands.append([float(w["vb"]), float(w["vt"])])
		for seg in _subtract_bands(0.0, h, bands):
			_add_wall_segment(is_x, ax, az, uc, p, outward, seg[0], seg[1], cw, depth, mat)
		# Close the open TOP of this column so the ragged rim reads solid, not see-through (a
		# column is otherwise only its front + back faces — issue: open wall edges).
		_add_cap_top(is_x, ax, az, uc, p, outward, h, cw, depth, mat)
	# Close the open SIDE reveals at the diagonal stair-steps between neighbouring columns.
	for k in range(n - 1):
		var lo := minf(heights[k], heights[k + 1])
		var hi := maxf(heights[k], heights[k + 1])
		if hi - lo >= 0.003:
			_add_cap_side(is_x, ax, az, (k + 1) * cw, p, outward, lo, hi, depth, mat)
	for w in windows:
		var wuc := float(w["uc"])
		var whw := float(w["half"])  # half window width
		var wvb := float(w["vb"])
		var wvt := float(w["vt"])
		# Close the window REVEAL (jamb) so the opening reads as a real recessed window through the
		# wall thickness, not an open hole: a lintel + sill (horizontal caps) and the two side jambs
		# (vertical caps), reusing the column-cap helpers. Stone-lined (the wall masonry material).
		_add_cap_top(is_x, ax, az, wuc, p, outward, wvt, whw * 2.0, depth, mat)   # lintel (top)
		_add_cap_top(is_x, ax, az, wuc, p, outward, wvb, whw * 2.0, depth, mat)   # sill (bottom)
		_add_cap_side(is_x, ax, az, wuc - whw, p, outward, wvb, wvt, depth, mat)  # left jamb
		_add_cap_side(is_x, ax, az, wuc + whw, p, outward, wvb, wvt, depth, mat)  # right jamb
		_add_window_quad(is_x, ax, az, wuc, p, outward, (wvb + wvt) * 0.5, depth, lib)


## A stone wall segment [y0, y1] of a column: a thin front+back shell (each face lit on its side).
func _add_wall_segment(is_x: bool, ax: float, az: float, uc: float, p: float, outward: float, y0: float, y1: float, cw: float, depth: float, mat: Material) -> void:
	var hh := y1 - y0
	if hh < 0.003:
		return
	var cy := (y0 + y1) * 0.5
	if is_x:
		var rf := PI if outward < 0.0 else 0.0
		_add_quad(mat, Vector3(ax + uc, cy, p), cw, hh, rf)
		_add_quad(mat, Vector3(ax + uc, cy, p - outward * depth), cw, hh, PI - rf)
	else:
		var rf := -PI * 0.5 if outward < 0.0 else PI * 0.5
		_add_quad(mat, Vector3(p, cy, az + uc), cw, hh, rf)
		_add_quad(mat, Vector3(p - outward * depth, cy, az + uc), cw, hh, -rf)


## Deterministic window openings on an arm: a column/row grid, kept only where the window fits
## fully under the sloped top. Each entry = {uc, half, vb, vt} (centre, half-width, bottom, top).
func _window_list(arm_len: float, total: float, arm_id: int) -> Array:
	var spacing := WINDOW_SPACING_INCHES * INCHES_TO_METERS
	var vstep := WINDOW_VSTEP_INCHES * INCHES_TO_METERS
	var ww := WINDOW_WIDTH_INCHES * INCHES_TO_METERS
	var wh := WINDOW_HEIGHT_INCHES * INCHES_TO_METERS
	var sill := WINDOW_SILL_INCHES * INCHES_TO_METERS
	var half := ww * 0.5
	var out: Array = []
	var j := 0
	while true:
		var uc := (j + 0.5) * spacing
		if uc > arm_len - half:
			break
		var col_h := _hyp(uc + half, arm_len, total)
		var row := 0
		while true:
			var vc := sill + row * vstep + wh * 0.5
			row += 1
			if vc + wh * 0.5 > col_h - 0.01:
				break
			if float(_hash3(arm_id, j, row) % 1000) / 1000.0 < WINDOW_CHANCE:
				out.append({"uc": uc, "half": half, "vb": vc - wh * 0.5, "vt": vc + wh * 0.5})
		j += 1
	return out


## Subtract `bands` ([lo,hi] pairs) from [lo, hi] → the remaining solid intervals.
func _subtract_bands(lo: float, hi: float, bands: Array) -> Array:
	bands.sort_custom(func(a, b): return a[0] < b[0])
	var out: Array = []
	var cur := lo
	for b in bands:
		var bs := clampf(b[0], lo, hi)
		var be := clampf(b[1], lo, hi)
		if bs > cur:
			out.append([cur, bs])
		cur = maxf(cur, be)
	if cur < hi:
		out.append([cur, hi])
	return out


## Add a flat quad to the visual, BAKING its position + Y-rotation into the mesh vertices (instead
## of transforming the MeshInstance). This is what lets the wall's object-local triplanar masonry
## project CONTINUOUSLY across all the separate column quads: if each quad sat at the MeshInstance
## origin, triplanar would sample the identical texture slice on every column and read as vertical
## stripes. Baked into the prop-local space, the projection still rides + rotates with the movable
## prop (unlike world triplanar, which would swim on drag and skew when the ruin is rotated).
func _add_quad(mat: Material, pos: Vector3, w: float, h: float, rot_y: float) -> void:
	var basis := Basis(Vector3.UP, rot_y)
	var nrm := basis * Vector3(0.0, 0.0, 1.0)
	var hw := w * 0.5
	var hh := h * 0.5
	var bl := pos + basis * Vector3(-hw, -hh, 0.0)
	var br := pos + basis * Vector3(hw, -hh, 0.0)
	var tr := pos + basis * Vector3(hw, hh, 0.0)
	var tl := pos + basis * Vector3(-hw, hh, 0.0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(nrm)
	st.add_vertex(bl); st.add_vertex(br); st.add_vertex(tr)
	st.add_vertex(bl); st.add_vertex(tr); st.add_vertex(tl)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	_visual_root.add_child(mi)


## Close the open TOP of a wall column: a horizontal cap quad spanning the wall thickness (front
## to back) at the column's top, so the ragged rim reads solid instead of see-through. The
## material is CULL_DISABLED, so the up/down facing is moot.
func _add_cap_top(is_x: bool, ax: float, az: float, uc: float, p: float, outward: float, top: float, cw: float, depth: float, mat: Material) -> void:
	var mid := p - outward * depth * 0.5  # centre of the wall thickness
	if is_x:
		_add_flat_quad(mat, Vector3(ax + uc, top, mid), cw, depth)
	else:
		_add_flat_quad(mat, Vector3(mid, top, az + uc), depth, cw)


## A horizontal (XZ-plane) quad facing up, with its position baked into the vertices — same
## continuous-triplanar reason as _add_quad (no per-cap stripe).
func _add_flat_quad(mat: Material, center: Vector3, size_x: float, size_z: float) -> void:
	var hx := size_x * 0.5
	var hz := size_z * 0.5
	var a := center + Vector3(-hx, 0.0, -hz)
	var b := center + Vector3(hx, 0.0, -hz)
	var c := center + Vector3(hx, 0.0, hz)
	var d := center + Vector3(-hx, 0.0, hz)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	st.add_vertex(a); st.add_vertex(b); st.add_vertex(c)
	st.add_vertex(a); st.add_vertex(c); st.add_vertex(d)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	_visual_root.add_child(mi)


## Close an open SIDE reveal between two neighbouring columns of differing height: a vertical cap
## spanning the wall thickness at their shared boundary, so the diagonal stair-step rim is solid.
func _add_cap_side(is_x: bool, ax: float, az: float, bu: float, p: float, outward: float, lo: float, hi: float, depth: float, mat: Material) -> void:
	var mid := p - outward * depth * 0.5
	var cy := (lo + hi) * 0.5
	var hh := hi - lo
	if is_x:
		_add_quad(mat, Vector3(ax + bu, cy, mid), depth, hh, PI * 0.5)
	else:
		_add_quad(mat, Vector3(mid, cy, az + bu), depth, hh, 0.0)


## The cropped-"window" alpha-scissor tracery quad set into the cut opening, at the MID-plane of
## the wall thickness so it reads (and shows through) from both sides.
func _add_window_quad(is_x: bool, ax: float, az: float, uc: float, p: float, outward: float, vc: float, depth: float, lib: RuinsLibrary) -> void:
	var ww := WINDOW_WIDTH_INCHES * INCHES_TO_METERS
	var wh := WINDOW_HEIGHT_INCHES * INCHES_TO_METERS
	var pm := p - outward * depth * 0.5
	var rot: float
	var pos: Vector3
	if is_x:
		rot = PI if outward < 0.0 else 0.0
		pos = Vector3(ax + uc, vc, pm)
	else:
		rot = -PI * 0.5 if outward < 0.0 else PI * 0.5
		pos = Vector3(pm, vc, az + uc)
	var mesh := QuadMesh.new()
	mesh.size = Vector2(ww, wh)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _window_material(lib)
	mi.position = pos
	mi.rotation.y = rot
	_visual_root.add_child(mi)


## Object-local triplanar masonry — one continuous stone at a fixed scale (so the broken edge
## reads at stone scale), with the SAME albedo + normal map + roughness as the map-layout grid
## ruins, so it looks identical. Local (not world) triplanar so it rides with the prop.
func _wall_material(lib: RuinsLibrary) -> Material:
	var key := "wall_" + WALL_STONE_PANEL
	if _materials.has(key):
		return _materials[key]
	var tiles := 1.0 / (MASONRY_TILE_INCHES * INCHES_TO_METERS)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = lib.get_texture(_theme_prefix + WALL_STONE_PANEL)
	mat.albedo_color = PLACEHOLDER_COLOR if mat.albedo_texture == null else Color.WHITE
	mat.roughness = STONE_ROUGHNESS
	mat.metallic = 0.0
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mat.texture_repeat = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = false
	mat.uv1_scale = Vector3(tiles, tiles, tiles)
	var ntex: Texture2D = lib.get_texture(_theme_prefix + NORMAL_PANEL)
	if ntex != null:
		mat.normal_enabled = true
		mat.normal_texture = ntex
		mat.normal_scale = STONE_NORMAL_STRENGTH
	_materials[key] = mat
	return mat


## Alpha-scissor material for the "window" panel, UV-cropped to just the tracery so the
## surrounding stone is the wall's own masonry. Cached.
func _window_material(lib: RuinsLibrary) -> Material:
	if _materials.has("window"):
		return _materials["window"]
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = lib.get_texture(_theme_prefix + WINDOW_PANEL)
	mat.roughness = STONE_ROUGHNESS
	mat.metallic = 0.0
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mat.texture_repeat = false
	mat.uv1_offset = Vector3(WINDOW_UV_OFFSET.x, WINDOW_UV_OFFSET.y, 0.0)
	mat.uv1_scale = Vector3(WINDOW_UV_SCALE.x, WINDOW_UV_SCALE.y, 1.0)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = WINDOW_ALPHA_SCISSOR
	var ntex: Texture2D = lib.get_texture(_theme_prefix + NORMAL_PANEL)
	if ntex != null:
		mat.normal_enabled = true
		mat.normal_texture = ntex
		mat.normal_scale = STONE_NORMAL_STRENGTH
	_materials["window"] = mat
	return mat


## A walkable platform at storey `i`: one clean slab per L arm, top-textured with the cobbled
## base floor (ground, i == 0) or the cut-flagstone platform floor (upper storeys). The base is
## a thick plinth; upper platforms stay thin. Top edge sits at the storey height.
func _build_platform(i: int, ax: float, az: float, lx: float, lz: float, arm: float, top: float, lib: RuinsLibrary) -> void:
	var is_base := i == 0
	var plate_t := FLOOR_PLATE_THICKNESS_INCHES * INCHES_TO_METERS
	var mat := _floor_material(is_base, lib)
	# Base = a plinth sitting ON the table (thickness UP from `top`, so its surface clears the
	# table → no z-fighting); upper platforms hang their thin slab DOWN from the storey surface.
	var y := (top + plate_t * 0.5) if is_base else (top - plate_t * 0.5)
	# Two slabs form the L. The X-arm spans the full corner; the Z-arm is CLIPPED to start past the
	# corner square so the two never overlap — coplanar slabs at the same Y z-fight (the texture
	# overlap flickers on camera movement). A tiny ruin whose Z-arm is no longer than the corner is
	# fully covered by the X-arm, so the Z-arm is dropped.
	#
	# Also INSET the slab edges that meet the two OUTER arm walls (X-arm wall at z=az, Z-arm wall at
	# x=ax) by the wall thickness + a hair, so no slab face sits coplanar with a wall face — that
	# coplanarity z-fights (flickers) when looking at the corner from outside. The free arm ends and
	# the interior edge between the two slabs keep their extent. Colliders (built separately) still
	# reach the walls, so the walkable area is unchanged.
	var wi := WALL_THICKNESS_INCHES * INCHES_TO_METERS + 0.0005
	var xsize := lx - wi
	var zsize := arm - wi
	if xsize > 0.0 and zsize > 0.0:
		_add_slab(Vector3(xsize, plate_t, zsize), Vector3(ax + (lx + wi) * 0.5, y, az + (arm + wi) * 0.5), mat)
	var lz_clip := lz - arm
	if lz_clip > 0.0 and (arm - wi) > 0.0:
		_add_slab(Vector3(arm - wi, plate_t, lz_clip), Vector3(ax + (arm + wi) * 0.5, y, az + arm + lz_clip * 0.5), mat)


func _add_slab(size: Vector3, pos: Vector3, mat: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	_visual_root.add_child(mi)


## Brick rubble at the foot of the two outer arm walls: one MultiMesh of small box fragments wearing
## the wall masonry (object-local triplanar so it rides with the movable prop), scattered along each
## wall base and tapering out to 1". Mirrors the auto-generated map-layout ruins' rubble; per-instance
## brightness jitter gives variation without the map-layout's world-triplanar swim.
func _build_rubble(ax: float, az: float, fw0: float, fd0: float, lib: RuinsLibrary) -> void:
	var transforms: Array[Transform3D] = []
	var colors := PackedColorArray()
	_rubble_along(transforms, colors, true, ax, az, fw0, 0)   # X-arm wall (faces -Z)
	_rubble_along(transforms, colors, false, ax, az, fd0, 1)  # Z-arm wall (faces -X)
	if transforms.is_empty():
		return
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	box.material = _rubble_material(lib)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = box
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
		mm.set_instance_color(i, colors[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_visual_root.add_child(mmi)


## Scatter RUBBLE_COUNT_PER_ARM tumbled, brick-shaped box fragments along one wall's base on its
## outward side, appending to `transforms` + `colors`. Deterministic (hashed seed) so every client
## builds the identical rubble.
func _rubble_along(transforms: Array, colors: PackedColorArray, is_x: bool, ax: float, az: float, arm_len: float, arm_id: int) -> void:
	var rng := RandomNumberGenerator.new()
	# Vary the scatter per ruin size (footprint is identical on every client, so this stays
	# MP-deterministic) and per arm, so neighbouring ruins don't share the exact same rubble.
	rng.seed = _hash3(arm_id, int(footprint_inches.x * 100.0), int(footprint_inches.y * 100.0))
	for _k in range(RUBBLE_COUNT_PER_ARM):
		var along := rng.randf() * arm_len
		var dist := rng.randf() * rng.randf() * RUBBLE_MAX_DIST_M  # quadratic taper outward
		var stone := rng.randf_range(RUBBLE_STONE_MIN_M, RUBBLE_STONE_MAX_M)
		var pos := Vector3(ax + along, stone * RUBBLE_EMBED_FRAC, az - dist) if is_x \
			else Vector3(ax - dist, stone * RUBBLE_EMBED_FRAC, az + along)
		var b := Basis.from_euler(Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU))
		b = b.scaled(Vector3(stone * rng.randf_range(1.6, 2.4), stone, stone * rng.randf_range(1.0, 1.5)))
		transforms.append(Transform3D(b, pos))
		var j := rng.randf_range(0.65, 1.0)  # brightness jitter over the masonry
		colors.append(Color(j, j, j, 1.0))


## Masonry material for the rubble fragments: the wall stone via object-local triplanar, with
## per-instance vertex colour enabled for the brightness jitter (the wall material has no vertex
## colour, so the rubble needs its own).
func _rubble_material(lib: RuinsLibrary) -> Material:
	if _materials.has("rubble"):
		return _materials["rubble"]
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = lib.get_texture(_theme_prefix + WALL_STONE_PANEL)
	mat.albedo_color = PLACEHOLDER_COLOR if mat.albedo_texture == null else Color.WHITE
	mat.vertex_color_use_as_albedo = true
	mat.roughness = STONE_ROUGHNESS
	mat.metallic = 0.0
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mat.texture_repeat = true
	if mat.albedo_texture != null:
		var tiles := 1.0 / (MASONRY_TILE_INCHES * INCHES_TO_METERS)
		mat.uv1_triplanar = true
		mat.uv1_world_triplanar = false
		mat.uv1_scale = Vector3(tiles, tiles, tiles)
	_materials["rubble"] = mat
	return mat


## Floor material (object-local triplanar) for storey `i`. Prefers the BIOME-THEMED floor panel
## (the same R2-delivered theming as the walls — `<prefix>floor_base` / `<prefix>floor_platform` in
## RuinsLibrary), and falls back to the bundled grassland-tuned cobble/flagstone texture until the
## themed asset is cached (or for grassland, which has no themed entry). On the async panel-arrival
## rebuild the cache is cleared, so a ruin re-themes its floor once the asset downloads.
func _floor_material(is_base: bool, lib: RuinsLibrary) -> Material:
	var key := "floor_base" if is_base else "floor_platform"
	if _materials.has(key):
		return _materials[key]
	var tex: Texture2D = lib.get_texture(_theme_prefix + key) if lib != null else null
	if tex == null:
		tex = _load_floor_texture(FLOOR_BASE_TEX if is_base else FLOOR_PLATFORM_TEX)
	var span := FLOOR_TILE_BASE_INCHES if is_base else FLOOR_TILE_PLATFORM_INCHES
	var tiles := 1.0 / (span * INCHES_TO_METERS)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.albedo_color = PLACEHOLDER_COLOR if tex == null else Color.WHITE
	mat.roughness = STONE_ROUGHNESS
	mat.metallic = 0.0
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mat.texture_repeat = true
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = false
	mat.uv1_scale = Vector3(tiles, tiles, tiles)
	_materials[key] = mat
	return mat


static var _floor_tex_cache: Dictionary = {}

static func _load_floor_texture(path: String) -> Texture2D:
	if _floor_tex_cache.has(path):
		return _floor_tex_cache[path]
	var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_floor_tex_cache[path] = tex
	return tex


# === Private: shared helpers ===

## Stable non-negative hash of a triple → identical layout on every client without an RNG.
static func _hash3(a: int, b: int, c: int) -> int:
	return absi((a * 73856093) ^ (b * 19349663) ^ (c * 83492791))


## Grey stone fallback shown until the masonry panels finish downloading: the same L layout
## (arm plates + outer walls) per storey, anchored at the shared corner.
func _build_placeholder() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = PLACEHOLDER_COLOR
	mat.roughness = 0.95
	mat.metallic = 0.0
	var wall_h := CELL_HEIGHT_INCHES * INCHES_TO_METERS
	var t := WALL_THICKNESS_INCHES * INCHES_TO_METERS
	for i in range(floor_heights_inches.size()):
		var l := _l_params(i)
		var ax: float = l["ax"]
		var az: float = l["az"]
		var lx: float = l["lx"]
		var lz: float = l["lz"]
		var arm: float = l["arm"]
		var ht: float = l["top"]
		var wy := ht + wall_h * 0.5
		_add_box(Vector3(lx, FLOOR_THICKNESS_M, arm), Vector3(ax + lx * 0.5, ht - FLOOR_THICKNESS_M * 0.5, az + arm * 0.5), mat)
		_add_box(Vector3(arm, FLOOR_THICKNESS_M, lz), Vector3(ax + arm * 0.5, ht - FLOOR_THICKNESS_M * 0.5, az + lz * 0.5), mat)
		_add_box(Vector3(lx, wall_h, t), Vector3(ax + lx * 0.5, wy, az + t * 0.5), mat)
		_add_box(Vector3(t, wall_h, lz), Vector3(ax + t * 0.5, wy, az + lz * 0.5), mat)


func _add_box(size: Vector3, pos: Vector3, mat: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	_visual_root.add_child(mi)
