class_name BattlefieldStains
extends Node3D
## Persistent battlefield marks left where a model was removed (issue #60): a BLOOD splatter
## for infantry, an OIL slick + 1-3 fires for a destroyed vehicle, each sized to the model's
## base. The stain is a flat textured DECAL (generated splatter texture on a quad), not a 3D
## disc — a plain coloured disc is only the fallback until the R2 texture is cached. Lives
## OUTSIDE ObjectManager so it survives model cleanup, and is not saved. Fed by main.gd on
## removal (local + remote) with the world position, base radius and vehicle flag.

# === Constants ===

const BLOOD_PANEL := "blood_stain"   # R2 hazard decal textures (top-down splatter, alpha)
const OIL_PANEL := "oil_stain"
## The decal quad is a bit larger than the base so the splatter's central pool reads as
## roughly base-sized while its droplets spill just past the footprint.
const STAIN_SIZE_SCALE := 1.7
const STAIN_MIN_RADIUS_M := 0.01
## The terrain overlay renders its tile layer at this absolute world Y (mirror of
## TerrainOverlay.TERRAIN_TILE_WORLD_Y — keep in sync). The stain must clear it so it never
## z-fights / sorts under the terrain tiles depending on camera angle (issue #72).
const TERRAIN_TILE_TOP_Y_M := 0.001
const STAIN_CLEARANCE_M := 0.0005    # clear the terrain tiles; the deployment zone draws on top via render_priority
const Z_LIFT_M := TERRAIN_TILE_TOP_Y_M + STAIN_CLEARANCE_M  # = 0.0015
## Draw the alpha-blended stain after the terrain-tile overlays (render_priority 0) so it
## never sorts under them; deployment zones / seize rings carry higher priorities and stay
## on top (see terrain_overlay.gd). Issue #72.
const STAIN_RENDER_PRIORITY := 1
const DECAL_ROUGHNESS := 0.4
const OIL_METALLIC := 0.35           # oily sheen (blood stays matte)

## Fallback flat disc (until the decal texture is cached): plain coloured cylinder.
const BLOOD_COLOR := Color(0.32, 0.02, 0.02)
const OIL_COLOR := Color(0.05, 0.05, 0.06)
const FALLBACK_HEIGHT_M := 0.0004    # thin transient disc; its top stays below the deployment-zone plane
const FALLBACK_SIDES := 16

## A destroyed vehicle gets this many small fires scattered within the oil slick.
const VEHICLE_FIRE_MIN := 1
const VEHICLE_FIRE_MAX := 3
const FIRE_SPREAD_FRAC := 0.55
## Per-tier cap on LIT oil fires across all stains (PERFORMANCE..ULTRA); beyond it fires
## still burn, just without a dynamic light. PERFORMANCE spawns no fire lights.
const FIRE_MAX_LIGHTS: Array[int] = [0, 4, 8, 12, 12]

# === Private state ===

var _hazards: HazardsLibrary = null
var _materials: Dictionary = {}     # panel name -> cached decal material
var _fire_lights_used := 0

# === Lifecycle ===

func _ready() -> void:
	# Own HazardsLibrary for the decal textures; prefetch so the first kill already has them.
	_hazards = HazardsLibrary.new()
	_hazards.name = "StainsHazardsLibrary"
	add_child(_hazards)
	_prefetch()


func _prefetch() -> void:
	await _hazards.ensure_panel(BLOOD_PANEL)
	await _hazards.ensure_panel(OIL_PANEL)

# === Public ===

## Leave a stain where a model was removed. `world_pos` is the table position, `base_radius_m`
## its base radius (the pool matches the base), `is_vehicle` picks oil+fire vs blood, and
## `seed_val` makes the orientation + fire scatter deterministic (multiplayer/replay safe).
## `owner` (the removed model's node) records the created stain nodes in its `stain_nodes` meta so
## an undo of the deletion can hide the residue together with the restored model (see undo_manager).
func add_stain(world_pos: Vector3, base_radius_m: float, is_vehicle: bool, seed_val: int,
		owner: Node3D = null) -> void:
	var radius := maxf(base_radius_m, STAIN_MIN_RADIUS_M)
	var panel := OIL_PANEL if is_vehicle else BLOOD_PANEL
	var tex: Texture2D = _hazards.get_texture(panel) if _hazards != null else null
	var created: Array[Node3D] = []
	if tex != null:
		var decal := _make_decal(world_pos, radius, panel, tex, seed_val)
		add_child(decal)
		created.append(decal)
	else:
		var disc := _make_disc_fallback(world_pos, radius, is_vehicle)
		add_child(disc)
		created.append(disc)
	if is_vehicle:
		created.append_array(_add_fires(world_pos, radius, seed_val))
	if owner != null and is_instance_valid(owner):
		owner.set_meta("stain_nodes", created)

# === Private ===

## Flat textured splatter decal: a quad lying on the table wearing the blood/oil texture,
## randomly spun so repeated stains don't look identical.
func _make_decal(world_pos: Vector3, radius: float, panel: String, tex: Texture2D,
		seed_val: int) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var root := Node3D.new()
	root.position = Vector3(world_pos.x, Z_LIFT_M, world_pos.z)
	root.rotation.y = rng.randf() * TAU
	var quad := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	var side := radius * 2.0 * STAIN_SIZE_SCALE
	mesh.size = Vector2(side, side)
	quad.mesh = mesh
	quad.material_override = _decal_material(panel, tex)
	quad.rotation.x = -PI / 2.0  # lay the +Z-facing quad flat, facing up
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(quad)
	return root


func _decal_material(panel: String, tex: Texture2D) -> StandardMaterial3D:
	if _materials.has(panel):
		return _materials[panel]
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = DECAL_ROUGHNESS
	mat.metallic = OIL_METALLIC if panel == OIL_PANEL else 0.0
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mat.texture_repeat = false
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Deterministic draw order for a flat alpha decal: draw after the terrain tiles and don't
	# write depth (standard for a ground decal). Avoid no_depth_test so real 3D props/minis
	# still occlude it correctly. Issue #72.
	mat.render_priority = STAIN_RENDER_PRIORITY
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_materials[panel] = mat
	return mat


## Plain coloured disc, used only until the decal texture is cached (transient).
func _make_disc_fallback(world_pos: Vector3, radius: float, is_vehicle: bool) -> MeshInstance3D:
	var disc := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = FALLBACK_HEIGHT_M
	mesh.radial_segments = FALLBACK_SIDES
	disc.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = OIL_COLOR if is_vehicle else BLOOD_COLOR
	mat.roughness = DECAL_ROUGHNESS
	mat.metallic = OIL_METALLIC if is_vehicle else 0.0
	disc.material_override = mat
	disc.position = Vector3(world_pos.x, FALLBACK_HEIGHT_M / 2.0 + Z_LIFT_M, world_pos.z)
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return disc


func _add_fires(world_pos: Vector3, radius: float, seed_val: int) -> Array[Node3D]:
	var fires: Array[Node3D] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var tier: int = clampi(GraphicsSettings.current_preset, 0, FIRE_MAX_LIGHTS.size() - 1)
	var with_smoke: bool = tier >= GraphicsSettings.QualityPreset.MEDIUM
	var count := rng.randi_range(VEHICLE_FIRE_MIN, VEHICLE_FIRE_MAX)
	for i in range(count):
		var fire := FireProp.new()
		var with_light: bool = _fire_lights_used < FIRE_MAX_LIGHTS[tier]
		if with_light:
			_fire_lights_used += 1
		fire.setup(seed_val + i, with_light, with_smoke)
		var ang := rng.randf() * TAU
		var dist := rng.randf() * radius * FIRE_SPREAD_FRAC
		fire.position = Vector3(world_pos.x + cos(ang) * dist, 0.0, world_pos.z + sin(ang) * dist)
		add_child(fire)
		fires.append(fire)
	return fires
