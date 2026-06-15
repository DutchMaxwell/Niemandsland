class_name BattlefieldStains
extends Node3D
## Persistent battlefield marks left where a model was removed (issue #60): a BLOOD pool for
## infantry, an OIL pool + 1-3 fires for a destroyed vehicle, each sized to the model's base.
## Decorative; lives OUTSIDE ObjectManager so it survives model cleanup, and is not saved.
## The caller (main.gd) feeds it the world position, base radius and vehicle flag on removal.

# === Constants ===

const BLOOD_COLOR := Color(0.32, 0.02, 0.02)   # dark arterial red
const OIL_COLOR := Color(0.05, 0.05, 0.06)     # near-black oil
const STAIN_HEIGHT_M := 0.002                  # flat disc, just proud of the table
const STAIN_SIDES := 16
const STAIN_ROUGHNESS := 0.35                  # wet sheen
const OIL_METALLIC := 0.35                     # oily iridescent sheen (blood stays matte)
const STAIN_MIN_RADIUS_M := 0.01
const Z_LIFT_M := 0.0009                       # sit above terrain overlays + the table

## A destroyed vehicle gets this many small fires scattered within the oil pool.
const VEHICLE_FIRE_MIN := 1
const VEHICLE_FIRE_MAX := 3
const FIRE_SPREAD_FRAC := 0.55                 # fires scatter within this fraction of the radius
## Per-tier cap on LIT oil fires across all stains (PERFORMANCE..ULTRA); beyond it fires
## still burn, just without a dynamic light. PERFORMANCE spawns no fire lights.
const FIRE_MAX_LIGHTS: Array[int] = [0, 4, 8, 12, 12]

# === Private state ===

var _fire_lights_used := 0  # running count this session, capped by FIRE_MAX_LIGHTS[tier]

# === Public ===

## Leave a stain where a model was removed. `world_pos` is the model's table position,
## `base_radius_m` its base radius (the pool matches the base), `is_vehicle` picks oil+fire
## vs blood, and `seed_val` makes the fire scatter deterministic (multiplayer/replay safe).
func add_stain(world_pos: Vector3, base_radius_m: float, is_vehicle: bool, seed_val: int) -> void:
	var radius := maxf(base_radius_m, STAIN_MIN_RADIUS_M)
	add_child(_make_pool(world_pos, radius, is_vehicle))
	if is_vehicle:
		_add_fires(world_pos, radius, seed_val)

# === Private ===

func _make_pool(world_pos: Vector3, radius: float, is_vehicle: bool) -> MeshInstance3D:
	var disc := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = STAIN_HEIGHT_M
	mesh.radial_segments = STAIN_SIDES
	disc.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = OIL_COLOR if is_vehicle else BLOOD_COLOR
	mat.roughness = STAIN_ROUGHNESS
	mat.metallic = OIL_METALLIC if is_vehicle else 0.0
	disc.material_override = mat
	disc.position = Vector3(world_pos.x, STAIN_HEIGHT_M / 2.0 + Z_LIFT_M, world_pos.z)
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return disc


func _add_fires(world_pos: Vector3, radius: float, seed_val: int) -> void:
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
