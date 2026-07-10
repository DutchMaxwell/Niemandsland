class_name BaseDecor
extends RefCounted
## "Perfectly based" miniature bases. Replaces the legacy solid player-coloured disc with a
## three-part base that reads like a hobbyist's basing job:
##   1. a terrain-projected TOP that samples the battlefield ground under the model (a live
##      window onto the biome texture — see shaders/base_terrain_top.gdshader), plus a subtle
##      AO vignette toward the rim for readability;
##   2. a near-black, slightly beveled RIM (a shallow frustum) like a real tabletop base edge;
##   3. for SOLO models only (units of one / loose single models), a player-coloured affiliation
##      RING on the rim — the one-model equivalent of a multi-model unit's boundary rubberband
##      (multi-model units keep a clean black rim; their affiliation IS the rubberband).
##
## Performance: all materials are SHARED — one black rim material, one ring material per player
## colour (cached), and the terrain-top material is owned+shared by Table (one per biome/table
## state, so a biome switch updates every base). Meshes are cached per (shape, size) so a whole
## squad of identical bases reuses one mesh resource. Nothing here allocates per frame.

# ===== Constants =====

## Base puck thickness (metres) — unchanged from the legacy solid disc so collision/tokens line up.
const BASE_HEIGHT_M: float = 0.003
## Terrain-top radius as a fraction of the base radius. The outer band (TOP..RIM..1.0) is the rim.
const TOP_RADIUS_RATIO: float = 0.86
## Rim frustum top radius / affiliation-ring outer radius (fraction of base radius). The flat black
## rim ring is [TOP_RADIUS_RATIO..RIM_TOP_RATIO]; the beveled wall is [RIM_TOP_RATIO..1.0].
const RIM_TOP_RATIO: float = 0.93
## Vertical stack offsets (metres) so the stacked flat surfaces never z-fight with the rim cap.
const TOP_Y: float = BASE_HEIGHT_M + 0.00020
const RING_Y: float = BASE_HEIGHT_M + 0.00028
## Perimeter tessellation for round/oval tops (matches CylinderMesh smoothness for a clean edge).
const CIRCLE_SEGMENTS: int = 48
## Perimeter points per square edge (a smoother rim vignette than the 4 bare corners).
const SQUARE_EDGE_SEGMENTS: int = 6
## Near-black rim colour (not pure black, so the bevel still catches a highlight).
const RIM_COLOR: Color = Color(0.045, 0.045, 0.05)
const RIM_ROUGHNESS: float = 0.85
## Ring readability: a touch of emission so the affiliation colour reads at a glance like the
## unshaded boundary rubberband, while staying a physically-lit rim accent.
const RING_ROUGHNESS: float = 0.5
const RING_EMISSION_ENERGY: float = 0.4
## Meta flag stamped on every decor MeshInstance3D so shared-material mutators (e.g. the lock
## dimmer in object_manager.gd) skip them and never contaminate a shared material.
const SHARED_MATERIAL_META: String = "shared_base_material"

# ===== Feature toggle =====

## Killswitch / legacy comparator. When true, build_base falls back to the pre-feature solid
## player-coloured disc (the "before" look). Default false = the terrain-projected base is ON.
## Doubles as a safe visual fallback (mirrors the pink-table killswitch precedent) and is the hook
## the QA render tool flips for its before/after shots.
static var legacy_solid_disc: bool = false

# ===== Shared material / mesh caches =====

static var _rim_material: StandardMaterial3D = null
static var _ring_materials: Dictionary = {}   # color html (String) -> StandardMaterial3D
static var _mesh_cache: Dictionary = {}        # geometry key (String) -> Mesh

# ===== Public: ring assignment rule =====

## Solo models (units of one / loose single models) get the affiliation ring; members of a
## multi-model unit do not — their affiliation is the boundary "rubberband" (maintainer design).
static func should_ring(unit_size: int) -> bool:
	return unit_size <= 1

# ===== Public: shared materials =====

## The shared near-black rim material (one instance for the whole session).
static func rim_material() -> StandardMaterial3D:
	if _rim_material == null:
		var m := StandardMaterial3D.new()
		m.albedo_color = RIM_COLOR
		m.roughness = RIM_ROUGHNESS
		m.metallic = 0.0
		_rim_material = m
	return _rim_material

## A player-coloured affiliation-ring material, cached per colour so all solo models of a player
## share one material. Uses the SAME colour source as the boundary rubberband (player palette).
static func ring_material(color: Color) -> StandardMaterial3D:
	var key := color.to_html(false)
	var cached: StandardMaterial3D = _ring_materials.get(key, null)
	if cached != null:
		return cached
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = RING_ROUGHNESS
	m.metallic = 0.0
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = RING_EMISSION_ENERGY
	m.cull_mode = BaseMaterial3D.CULL_DISABLED   # flat annulus — visible from above regardless of winding
	_ring_materials[key] = m
	return m

# ===== Public: base assembly =====

## Build the full base (rim + terrain top + optional affiliation ring) as one container Node3D,
## ready to add to a model's wrapper. `top_material` is Table's shared terrain-top material (may be
## null in headless contexts — the top then falls back to a plain neutral disc so tests still run).
static func build_base(
		base_is_oval: bool, base_is_square: bool,
		base_width: float, base_depth: float, base_radius: float,
		player_color: Color, is_solo: bool, top_material: Material) -> Node3D:
	var root := Node3D.new()
	root.name = "Base"

	if legacy_solid_disc:
		root.add_child(_legacy_disc(base_is_oval, base_is_square, base_width, base_depth, base_radius, player_color))
		return root

	# 1) Rim body: near-black beveled frustum (round/oval) or flat box (square).
	var rim := MeshInstance3D.new()
	rim.name = "BaseRim"
	if base_is_square:
		rim.mesh = _box_rim_mesh(base_width, base_depth)
		rim.position.y = BASE_HEIGHT_M * 0.5
	elif base_is_oval:
		rim.mesh = _round_rim_mesh(0.5)   # unit frustum, scaled to the oval below
		rim.scale = Vector3(base_width, 1.0, base_depth)
		rim.position.y = BASE_HEIGHT_M * 0.5
	else:
		rim.mesh = _round_rim_mesh(base_radius)
		rim.position.y = BASE_HEIGHT_M * 0.5
	rim.material_override = rim_material()
	rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	rim.set_meta(SHARED_MATERIAL_META, true)
	root.add_child(rim)

	# 2) Terrain-projected top (with the rim vignette baked into UV.x).
	var top := MeshInstance3D.new()
	top.name = "BaseTop"
	top.mesh = _top_mesh(base_is_square, base_is_oval, base_width, base_depth, base_radius, TOP_RADIUS_RATIO)
	top.position.y = TOP_Y
	top.material_override = top_material if top_material != null else _fallback_top_material()
	top.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	top.set_meta(SHARED_MATERIAL_META, true)
	root.add_child(top)

	# 3) Affiliation ring (solo models only).
	if is_solo:
		var ring := MeshInstance3D.new()
		ring.name = "AffiliationRing"
		ring.mesh = _ring_mesh(base_is_square, base_is_oval, base_width, base_depth, base_radius)
		ring.position.y = RING_Y
		ring.material_override = ring_material(player_color)
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.set_meta(SHARED_MATERIAL_META, true)
		root.add_child(ring)

	return root

# ===== Private: perimeter generators =====

## An ellipse outline (CCW). Round bases pass rx == rz.
static func ellipse_perimeter(rx: float, rz: float, segments: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(segments):
		var a := (float(i) / float(segments)) * TAU
		pts.append(Vector2(cos(a) * rx, sin(a) * rz))
	return pts

## A square/rectangle outline (CCW), `per_edge` points per side.
static func square_perimeter(half_x: float, half_z: float, per_edge: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var corners := [
		Vector2(-half_x, -half_z), Vector2(half_x, -half_z),
		Vector2(half_x, half_z), Vector2(-half_x, half_z),
	]
	for c in range(4):
		var a: Vector2 = corners[c]
		var b: Vector2 = corners[(c + 1) % 4]
		for s in range(per_edge):
			pts.append(a.lerp(b, float(s) / float(per_edge)))
	return pts

# ===== Private: mesh builders =====

## Rim/top/ring perimeter for the base shape at a radius fraction: square rectangle, oval ellipse,
## or round circle (rx == rz == base_radius). Built at REAL dimensions (no instance scale) so the
## vignette and the world-XZ projection stay correct.
static func _perimeter_for(is_square: bool, is_oval: bool, base_width: float, base_depth: float, base_radius: float, ratio: float) -> PackedVector2Array:
	if is_square:
		return square_perimeter(base_width * 0.5 * ratio, base_depth * 0.5 * ratio, SQUARE_EDGE_SEGMENTS)
	if is_oval:
		return ellipse_perimeter(base_width * 0.5 * ratio, base_depth * 0.5 * ratio, CIRCLE_SEGMENTS)
	return ellipse_perimeter(base_radius * ratio, base_radius * ratio, CIRCLE_SEGMENTS)

## Filled top fan: centre vertex (UV.x=0) + perimeter (UV.x=1), flat at y=0, normal +Y. UV.x is
## the rim vignette coordinate (0 centre → 1 rim). cull_disabled on the material makes winding moot.
## Every vertex also carries a world-aligned +X TANGENT so the terrain-top shader's detail NORMAL_MAP
## uses the same tangent frame the table's PlaneMesh does (identical sun response — see base_terrain_top.gdshader).
static func _top_mesh(is_square: bool, is_oval: bool, base_width: float, base_depth: float, base_radius: float, ratio: float) -> Mesh:
	var key := "top:%s:%s:%d:%d:%d" % [str(is_square), str(is_oval), int(round(base_width * 10000)), int(round(base_depth * 10000)), int(round(base_radius * 10000))]
	var cached: Mesh = _mesh_cache.get(key, null)
	if cached != null:
		return cached
	var perimeter := _perimeter_for(is_square, is_oval, base_width, base_depth, base_radius, ratio)
	# Tangent along +X with binormal sign +1 — matches PlaneMesh's tangent frame for a +Y face.
	var tangent := Plane(1.0, 0.0, 0.0, 1.0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	st.set_tangent(tangent)
	st.set_uv(Vector2(0.0, 0.0))
	st.add_vertex(Vector3.ZERO)   # index 0 = centre
	var n := perimeter.size()
	for i in range(n):
		var p := perimeter[i]
		st.set_normal(Vector3.UP)
		st.set_tangent(tangent)
		st.set_uv(Vector2(1.0, 0.0))
		st.add_vertex(Vector3(p.x, 0.0, p.y))
	for i in range(n):
		st.add_index(0)
		st.add_index(1 + ((i + 1) % n))
		st.add_index(1 + i)
	var mesh := st.commit()
	_mesh_cache[key] = mesh
	return mesh

## Flat affiliation-ring annulus between the terrain-top edge (inner) and the rim-cap edge (outer).
static func _ring_mesh(is_square: bool, is_oval: bool, base_width: float, base_depth: float, base_radius: float) -> Mesh:
	var key := "ring:%s:%s:%d:%d:%d" % [str(is_square), str(is_oval), int(round(base_width * 10000)), int(round(base_depth * 10000)), int(round(base_radius * 10000))]
	var cached: Mesh = _mesh_cache.get(key, null)
	if cached != null:
		return cached
	var inner := _perimeter_for(is_square, is_oval, base_width, base_depth, base_radius, TOP_RADIUS_RATIO)
	var outer := _perimeter_for(is_square, is_oval, base_width, base_depth, base_radius, RIM_TOP_RATIO)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n: int = mini(inner.size(), outer.size())
	for i in range(n):
		var i0 := inner[i]
		var i1 := inner[(i + 1) % n]
		var o0 := outer[i]
		var o1 := outer[(i + 1) % n]
		_add_quad(st, Vector3(i0.x, 0.0, i0.y), Vector3(o0.x, 0.0, o0.y), Vector3(o1.x, 0.0, o1.y), Vector3(i1.x, 0.0, i1.y))
	var mesh := st.commit()
	_mesh_cache[key] = mesh
	return mesh

## Round/oval rim body: a shallow black frustum (bottom = full radius, top = RIM_TOP_RATIO) giving
## a subtle chamfered edge plus a flat top cap the terrain top + ring sit on.
static func _round_rim_mesh(radius: float) -> Mesh:
	var key := "rim_round:%d" % int(round(radius * 100000))
	var cached: Mesh = _mesh_cache.get(key, null)
	if cached != null:
		return cached
	var m := CylinderMesh.new()
	m.bottom_radius = radius
	m.top_radius = radius * RIM_TOP_RATIO
	m.height = BASE_HEIGHT_M
	m.radial_segments = CIRCLE_SEGMENTS
	m.rings = 1
	_mesh_cache[key] = m
	return m

## Square rim body: a flat black box (regiment bases). The inset terrain top leaves the black border.
static func _box_rim_mesh(base_width: float, base_depth: float) -> Mesh:
	var key := "rim_box:%d:%d" % [int(round(base_width * 100000)), int(round(base_depth * 100000))]
	var cached: Mesh = _mesh_cache.get(key, null)
	if cached != null:
		return cached
	var m := BoxMesh.new()
	m.size = Vector3(base_width, BASE_HEIGHT_M, base_depth)
	_mesh_cache[key] = m
	return m

static func _add_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	# Two triangles; the ring material is cull_disabled so winding is irrelevant.
	st.set_normal(Vector3.UP)
	st.add_vertex(a)
	st.set_normal(Vector3.UP)
	st.add_vertex(b)
	st.set_normal(Vector3.UP)
	st.add_vertex(c)
	st.set_normal(Vector3.UP)
	st.add_vertex(a)
	st.set_normal(Vector3.UP)
	st.add_vertex(c)
	st.set_normal(Vector3.UP)
	st.add_vertex(d)

## The pre-feature solid player-coloured disc (legacy_solid_disc killswitch / QA "before" look).
static func _legacy_disc(base_is_oval: bool, base_is_square: bool, base_width: float, base_depth: float, base_radius: float, player_color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "BaseLegacy"
	if base_is_square:
		var box := BoxMesh.new()
		box.size = Vector3(base_width, BASE_HEIGHT_M, base_depth)
		mi.mesh = box
	elif base_is_oval:
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.5
		cyl.bottom_radius = 0.5
		cyl.height = BASE_HEIGHT_M
		mi.mesh = cyl
		mi.scale = Vector3(base_width, 1.0, base_depth)
	else:
		var cyl := CylinderMesh.new()
		cyl.top_radius = base_radius
		cyl.bottom_radius = base_radius
		cyl.height = BASE_HEIGHT_M
		mi.mesh = cyl
	mi.position.y = BASE_HEIGHT_M * 0.5
	var mat := StandardMaterial3D.new()
	mat.albedo_color = player_color
	mat.roughness = 0.7
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	mi.set_meta(SHARED_MATERIAL_META, false)
	return mi


## Neutral fallback top used only when no Table terrain-top material is available (headless tests).
static func _fallback_top_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.2, 0.35, 0.2)
	m.roughness = 0.9
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m
