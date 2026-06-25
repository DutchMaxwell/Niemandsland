extends Node3D
## Terrain Overlay - Displays terrain zones on the 3D table surface
##
## Shows colored, transparent overlays for each terrain type placed on the map layout editor.
## Meshes are positioned slightly above the table surface to prevent z-fighting.
##
## The overlay automatically updates when the map layout changes and applies rotation
## to match the grid orientation.

# ==============================================================================
# CONSTANTS
# ==============================================================================

const INCHES_TO_METERS := 0.0254
const GRID_SIZE_INCHES := 3.0
const FINE_GRID_SIZE_INCHES := 1.0  # 1" grid for custom zone editing

## Height offset above table to prevent z-fighting (2mm)
const Z_FIGHT_OFFSET := 0.002

## Flat-overlay heights above the TABLE SURFACE (world metres). Draw order between these
## near-coplanar TRANSPARENT layers is fixed by the *_RENDER_PRIORITY constants above, NOT by
## these sub-mm Y values, so they never flip with the camera angle. The deployment zone sits
## just above the table — BELOW the unit base bodies (which span 0–3 mm, see opr_army_manager)
## — so it reads as printed on the table UNDER the minis instead of tinting the lower two-thirds
## of every base (issue #71). The overlay node sits at Z_FIGHT_OFFSET, so child positions are
## derived as (WORLD_Y - Z_FIGHT_OFFSET).
const TERRAIN_TILE_WORLD_Y := 0.001
const DEPLOYMENT_ZONE_WORLD_Y := 0.0006  # just above the table, under the base bodies (issue #71)
const OBJECTIVE_WORLD_Y := 0.003
const SEIZE_RING_HEIGHT := 0.002  # the 3" seize ring disc; the token sits on top of it
## The translucent 3" seize-area ring is drawn just above the table, UNDER the unit base bodies
## (which span 0–3 mm), so the opaque bases occlude it where they overlap — it tints the table,
## not the bases / on-model tokens standing on the objective (issue #71). render_priority keeps it
## above the terrain tiles + deployment zone. The objective TOKEN (opaque) stays up at OBJECTIVE_WORLD_Y.
const SEIZE_RING_WORLD_Y := 0.0006

## Render priority deterministically orders the near-coplanar TRANSPARENT overlay layers so
## they never flip draw order as the camera orbits (issue #71). Higher = drawn on top. Opaque
## layers (table, unit bases, objective tokens) sort by depth and need no priority; battlefield
## blood/oil stains sit at priority 1 (see battlefield_stains.gd), between tiles and zones.
const TERRAIN_TILE_RENDER_PRIORITY := 0
const DEPLOYMENT_ZONE_RENDER_PRIORITY := 2
const SEIZE_RING_RENDER_PRIORITY := 3

## Mesh size reduction factor to show grid lines between cells
const CELL_SIZE_REDUCTION := 0.95

## Terrain type enumeration (matches map_layout.gd TerrainType enum)
enum TerrainType {
	NONE = 0,
	RUINS = 1,
	FOREST = 2,
	CONTAINER = 3,
	DANGEROUS = 4
}

## Overlay display mode for terrain visualization
## FLAT: Colored 2D planes only (default, existing behavior)
## MODELS: 3D GLB models only (generated terrain)
## BOTH: 2D planes + 3D models overlaid
enum OverlayMode {
	FLAT = 0,
	MODELS = 1,
	BOTH = 2
}

## Deployment zone types
## NOTE: Only FRONT_LINE is included from OPR free rules.
## Other deployment types (Ground War, Spearhead, etc.) are behind OPR's paywall.
## CUSTOM allows players to draw their own deployment zones using polygon vertices.
enum DeploymentType {
	NONE = 0,
	FRONT_LINE = 1,   # 12" from long edges (OPR free rules)
	CUSTOM = 2        # User-defined polygon zones
}

# Terrain colors (matching map_layout.gd)
const TERRAIN_COLORS := {
	TerrainType.RUINS: Color(0.3, 0.5, 0.8, 0.4),      # Blue
	TerrainType.FOREST: Color(0.2, 0.6, 0.2, 0.4),     # Green
	TerrainType.CONTAINER: Color(0.6, 0.4, 0.2, 0.4),  # Brown
	TerrainType.DANGEROUS: Color(0.8, 0.2, 0.2, 0.4)   # Red
}

# Deployment zone colors
const DEPLOYMENT_COLORS := {
	"player1": Color(0.2, 0.5, 1.0, 0.3),  # Blue for Player 1
	"player2": Color(1.0, 0.3, 0.2, 0.3)   # Red for Player 2
}

# ==============================================================================
# PROCEDURAL TERRAIN PROP DIMENSIONS (inches)
# ==============================================================================
# All terrain props (walls, trees, containers, dangerous hazards) are built from
# primitive meshes with the shared holographic material. The rulebook "Height 5"
# is a line-of-sight category, NOT a physical mesh height.

const WALL_HEIGHT_INCHES := 2.5
const WALL_THICKNESS_INCHES := 0.25
const CORNER_SIZE_INCHES := 0.25

const TREE_TRUNK_HEIGHT_INCHES := 1.2
const TREE_TRUNK_RADIUS_INCHES := 0.25
const TREE_CROWN_HEIGHT_INCHES := 2.2
const TREE_CROWN_RADIUS_INCHES := 1.0

## Textured deciduous trees (R2 panels via TreesLibrary): each tree is two crossed
## alpha-scissor quads showing a keyed tree photo — organic from every angle, with a
## deterministic per-tree variant / size / facing so all clients match. The procedural
## trunk+cone above stays as the offline fallback.
const TREE_HEIGHT_INCHES := 3.4  # billboard height at 100% (trunk+crown of the fallback)
const TREE_SCALE_MIN := 0.75
const TREE_SCALE_MAX := 1.25
const TREE_CROWN_CAP_FRAC := 0.68  # crown-cap quad height (the crown's widest point)
const TREE_MODEL_MIN_DEPTH_RATIO := 0.05  # thinner GLBs are degenerate "relief" slabs -> billboard

const CONTAINER_LENGTH_INCHES := 6.0
const CONTAINER_DEPTH_INCHES := 3.0
const CONTAINER_HEIGHT_INCHES := 2.5

const MINE_BOTTOM_RADIUS_INCHES := 0.7
const MINE_TOP_RADIUS_INCHES := 0.3
const MINE_HEIGHT_INCHES := 0.5

const PUDDLE_RADIUS_INCHES := 1.3
const PUDDLE_HEIGHT_INCHES := 0.08

## Textured minefield props (R2 via HazardsLibrary): flat anti-tank mine discs wearing
## the pressure-plate texture on top, and warning signs on posts at the field corners.
const MINE_DISC_RADIUS_INCHES := 0.3
const MINE_DISC_HEIGHT_INCHES := 0.12
const SIGN_WIDTH_INCHES := 0.9
const SIGN_POST_HEIGHT_INCHES := 1.2
const SIGN_POST_RADIUS_INCHES := 0.04
const MINE_BODY_COLOR := Color(0.25, 0.27, 0.18)  # olive-drab side of the mine disc
const SIGN_POST_COLOR := Color(0.35, 0.33, 0.3)   # weathered steel post
## Z-fight margin for overlays on SMALL props (mine top, sign plates). The global
## Z_FIGHT_OFFSET (2 mm) is sized for walls — on a 3 mm mine disc it visibly floats.
const PROP_SURFACE_LIFT := 0.0003

## Glowing lava pool: the DANGEROUS-terrain prop in the volcanic biome (replaces the mine
## disc; no warning signs there — the lava is self-evident). A shallow molten disc with a
## dark cooled-crust rim, emissive so it glows under the scene's bloom. Decorative:
## dangerous terrain stays passable (OPR: Dangerous, not Impassable). Orientation is
## seeded from the object's identity (deterministic -> MP/save safe; never a global RNG).
const LAVA_POOL_RADIUS_INCHES := 1.0
const LAVA_POOL_HEIGHT_INCHES := 0.05        # very shallow molten pool
const LAVA_POOL_SIDES := 9                     # low-poly disc -> slightly irregular rim
const LAVA_CORE_FRAC := 0.72                   # bright molten core radius vs the crust rim
const LAVA_CRUST_COLOR := Color(0.09, 0.05, 0.04)     # dark cooled basalt crust rim
const LAVA_EMISSION_COLOR := Color(1.0, 0.35, 0.06)    # molten orange-red core
## Emission is kept LOW: the scene runs a strong bloom, so even a low multiplier reads as
## molten glow. Higher values blow the whole pool to flat white and hide the texture.
const LAVA_EMISSION_ENERGY := 0.7              # procedural-fallback core
## R2 hazard panel name for the lava-pool texture (top-down round molten pool, alpha-keyed);
## used as both albedo and emission map. Until cached, the pool uses the procedural fallback.
const LAVA_PANEL := "lava_pool"
const LAVA_TEXTURE_EMISSION_ENERGY := 0.35     # textured pool (the texture is already bright)

## Preferred prop: a TRELLIS 3D lava CRATER GLB (rocky bowl + molten lava, overflowing the
## rim). Scaled to this footprint and given a targeted OmniLight for the emanating glow.
## Falls back to the texture quad, then the procedural pool, until the GLB is cached.
const LAVA_CRATER_MODEL := "lava_crater"
const LAVA_CRATER_DIAMETER_INCHES := 2.4       # footprint the GLB is scaled to fit
## Craters must not overlap: the dense grassland minefield layout (MINES_PER_CELL) is
## thinned at render time for volcanic to non-overlapping craters at least this far apart
## (centre-to-centre, a touch over a crater diameter). This naturally yields ~3-5 craters
## per dangerous field; the rest of the mine slots are skipped.
const CRATER_MIN_SPACING_INCHES := LAVA_CRATER_DIAMETER_INCHES * 1.1
## Targeted glow light for each crater (the molten lava). Every kept crater gets one — they
## are few (non-overlapping) so the scene isn't flooded, and no field is left dark.
const LAVA_LIGHT_COLOR := Color(1.0, 0.45, 0.13)
const LAVA_LIGHT_RANGE_M := 0.17
const LAVA_LIGHT_ENERGY := 0.4   # dialed down — the craters were still radiating too hard
const LAVA_LIGHT_HEIGHT_M := 0.02

## Alien-jungle dangerous terrain: a TRELLIS 3D carnivorous-plant clump GLB. Same
## non-overlapping thinning as the lava craters (CRATER_MIN_SPACING_INCHES, ~3-5 per field).
## No glow light (unlike the lava crater). Per-biome model picked in update_placed_objects.
const BIOME_HAZARD_MODELS := {"volcanic_": LAVA_CRATER_MODEL, "jungle_": "carnivore_plant"}
const CARNIVORE_MODEL := "carnivore_plant"
const CARNIVORE_DIAMETER_INCHES := 1.8

## Textured ruins walls (first pass): the wall + corner-post props use a lit, world-
## triplanar stone material instead of the hologram look (other props stay holographic for
## now). The texture repeats every STONE_TILE_METERS in world space.
const RUINS_WALL_TEX_PATH := "res://assets/terrain/props/ruins_wall.webp"
const STONE_TILE_METERS := 0.085  # ~3.3" per tile -> ~1 cm stone blocks at 28 mm scale

## Shell-wall ruins (second pass): per-role mossy masonry panels delivered on demand from
## R2 (RuinsLibrary). Each wall cell renders as a SHELL — front + back panel quad + a
## plain-stone top cap — so doorway/window/crumble holes are see-through; collision stays
## a full-height Impassable box (OPR: ruin walls are Impassable). Until the panel set is
## cached locally, walls keep the triplanar first-pass material above as the fallback.
## Ported from tools/render_ruin_walls.gd.
const RUIN_SHELL_THICKNESS_INCHES := 0.4  # shell depth; reads better than the 0.25" box
const RUIN_PANEL_ROUGHNESS := 0.93
const RUIN_NORMAL_STRENGTH := 1.4
const RUIN_ALPHA_SCISSOR_THRESHOLD := 0.5
const RUIN_WINDOW_CHANCE := 0.05   # share of "full" panels showing the gothic window
const RUIN_OPENING_CHANCE := 0.25  # cumulative roll: 0.05..0.25 -> see-through doorway
const _RUIN_SOLID_PANELS: Array[String] = ["solid_a", "solid_b", "topdmg_a"]

## Shell closure: the wall's top/side faces follow the panel's alpha profile, so caps sit
## on the real stone silhouette (stepped crumble, knocked-out top courses) instead of
## floating at full height, and free wall ends + interior openings get stone reveals.
const RUIN_POST_SIZE_INCHES := 0.6  # corner posts sit proud of the 0.4" shells (kills coplanar z-fighting)
const RUIN_POST_EXTRA_HEIGHT_INCHES := 0.1  # ...and rise past the wall caps (same reason, on top)
const RUIN_CAP_STRIPS := 96         # alpha-profile resolution: ~16 strips per stone course
const RUIN_CAP_MERGE_FRAC := 0.025  # strips within 2.5% wall height merge into one cap
const RUIN_ALPHA_OPAQUE := 0.5      # alpha >= this counts as stone when profiling panels
const RUIN_PROFILE_SAMPLE_PX := 4   # pixel step when scanning panel alpha
const RUIN_HOLE_GRID := 64          # downsample width for interior-opening detection
const RUIN_HOLE_MIN_CELLS := 4      # ignore alpha specks smaller than this many grid cells
const RUIN_HOLE_REFINE_STEP_PX := 2 # pixel step when snapping a hole onto its alpha edges
const RUIN_MIN_CAP_FRAC := 0.04     # skip caps/end faces below 4% wall height

## Quad +U world direction per edge_side (N=0,E=1,S=2,W=3) under this renderer's
## wall_y_rotation convention (N=0, E=+90°, S=180°, W=-90°). A crumble panel is U-mirrored
## iff its taper_dir (the arm's free-end direction, from TerrainPrefabs) differs from this,
## so the wall steps DOWN toward the open end.
const _RUIN_QUAD_U_DIR: Array[int] = [1, 0, 3, 2]

## Spatial-hash primes seeding the per-segment panel pick. Walls are rebuilt locally on
## every client, so the "full" panel draw must be deterministic from stable segment
## identity — never a global RNG (§6 gotcha #5).
const _RUIN_SEED_PRIME_X := 73856093
const _RUIN_SEED_PRIME_Y := 19349663
const _RUIN_SEED_PRIME_SIDE := 83492791

## Biome-themed prop sets: per-biome name prefix into the ruins/trees manifests
## (grassland = the default unprefixed set; desert = adobe walls + cacti; tundra =
## snowed-in stone + snow-laden conifers). Containers have their own theme map (only
## the tundra snows them in); minefield props are biome-agnostic.
const BIOME_PROP_THEMES := {
	"arid_desert": "desert_", "frozen_tundra": "tundra_",
	"volcanic_ash": "volcanic_", "alien_jungle": "jungle_", "urban_ruins": "urban_",
}
const BIOME_CONTAINER_THEMES := {
	"frozen_tundra": "tundra_",
	"volcanic_ash": "volcanic_", "alien_jungle": "jungle_", "urban_ruins": "urban_",
}

## War-torn ruin fires: a deterministic share of wall cells carries a small FireProp
## (flames + smoke + flickering light). The pick derives ONLY from synced segment data
## via a salted, FRESH RNG — it must never consume draws from the panel RNG, or every
## window/doorway pick on every map would silently change (multiplayer + saves!).
const RUIN_FIRE_CHANCE := 0.22
const _RUIN_SEED_SALT_FIRE := 2654435761
## Max flickering OmniLights per quality tier (PERFORMANCE..ULTRA); beyond the cap,
## fires render without a light. PERFORMANCE spawns no fires at all.
const FIRE_MAX_LIGHTS: Array[int] = [0, 4, 8, 12, 12]
const FIRE_INSET_FROM_WALL_M := 0.012
const FIRE_ALONG_WALL_MAX_FRAC := 0.3  # offset from the wall centre, fraction of length

## Rubble at ruin wall bases: small loose stones scattered along both sides of every
## wall segment, densest directly at the wall and tapering out to 1". One MultiMesh
## for the whole overlay (a single draw call), deterministic per segment (own salt),
## stone counts gated by quality tier (PERFORMANCE..ULTRA; 0 = no rubble).
const _RUIN_SEED_SALT_RUBBLE := 40503
const RUBBLE_STONES_PER_SEGMENT: Array[int] = [0, 40, 80, 130, 180]
const RUBBLE_MAX_DIST_M := 0.0254          # taper ends 1" from the wall face
const RUBBLE_STONE_MIN_M := 0.003
const RUBBLE_STONE_MAX_M := 0.010
const RUBBLE_EMBED_FRAC := 0.35            # stones sink partly into the ground
## Fragments wear the wall's own themed masonry via WORLD triplanar projection, so
## every brick samples a different patch of the texture (same tile scale as the
## first-pass wall material) and the biome theme carries over for free.
const RUBBLE_TEXTURE_TILE_M := 0.085

# ==============================================================================
# STATE
# ==============================================================================

var overlay_meshes: Array[MeshInstance3D] = []
var deployment_zone_meshes: Array[MeshInstance3D] = []
var table_size_feet := Vector2(6, 4)
var current_deployment_type := DeploymentType.NONE
var deployment_zones_visible := false
var grid_cells := {}  # Dictionary[Vector2i, TerrainType] - stores terrain data
var grid_rotation_degrees := 0.0

## Overlay mode: FLAT (2D planes), MODELS (3D GLBs), BOTH
var overlay_mode := OverlayMode.FLAT

## Custom deployment zone polygons (in meters, world coordinates)
## Each zone is an array of Vector3 points defining the polygon vertices
var custom_zone_player1: Array[Vector3] = []
var custom_zone_player2: Array[Vector3] = []

## Custom zone editing mode
enum CustomZoneMode {
	NONE,           # Not editing custom zones
	SYMMETRIC,      # Both zones mirrored (point-symmetric around table center)
	ASYMMETRIC_P1,  # Drawing Player 1 zone
	ASYMMETRIC_P2   # Drawing Player 2 zone
}
var custom_zone_mode := CustomZoneMode.NONE

## Signal emitted when custom zone editing state changes
signal custom_zone_editing_changed(is_editing: bool, mode: CustomZoneMode)
signal custom_zone_vertex_added(player: int, vertex: Vector3)
signal custom_zone_completed(player: int)
## Emitted after the war-torn ruin fires were (re)built (also when cleared), so the
## atmosphere layer can re-park its fire-crackle audio emitters.
signal fires_rebuilt

## Fine grid (1") for custom zone editing
var fine_grid_meshes: Array[MeshInstance3D] = []
var fine_grid_visible := false

## Vertex markers showing placed polygon points during editing
var vertex_markers: Array[MeshInstance3D] = []
var preview_line_mesh: MeshInstance3D = null

## Mission objectives - displayed as markers with 3" seize radius
var objective_meshes: Array[Node3D] = []  # Can be MeshInstance3D or Node3D containers
var objective_ring_meshes: Array[MeshInstance3D] = []
var mission_objectives: Array[Vector3] = []  # World positions in meters
var objective_owners: Array[int] = []  # Owner per objective (0 = neutral, else player_id)

## Wall instances (procedural walls + corner posts; ruins use a textured stone material)
var _wall_instances: Array[Node3D] = []

## Lit, world-triplanar stone material for the ruins walls + corner posts (built once,
## shared). Null until first built; falls back to the hologram material if the texture is
## missing.
var _ruins_wall_material: Material = null

## On-demand ruin shell-wall panel delivery (R2) + the per-(panel|mirror|slice) material
## cache. The last wall layout is kept so the triplanar fallback can upgrade itself to
## shell walls in place once the panel download finishes.
var _ruins_library: RuinsLibrary = null
var _ruin_panel_materials: Dictionary = {}
var _ruin_panel_profiles: Dictionary = {}    # panel name -> PackedFloat32Array strip heights
var _ruin_panel_hole_rects: Dictionary = {}  # panel name -> Array[Rect2] interior openings

## On-demand tree billboard delivery (R2) + per-panel material cache. The last placed
## objects are kept so fallback trees can upgrade to textured ones once cached.
var _trees_library: TreesLibrary = null
var _tree_panel_materials: Dictionary = {}
var _tree_fetch_started := false
var _last_objects: Array = []
var _last_obj_table_size := Vector2.ZERO
var _last_obj_rotation := 0.0

## On-demand container face delivery (R2) + per-panel material cache.
var _containers_library: ContainersLibrary = null
var _container_panel_materials: Dictionary = {}
var _container_fetch_started := false

## On-demand minefield texture delivery (R2) + material cache.
var _hazards_library: HazardsLibrary = null
var _hazard_materials: Dictionary = {}
var _hazard_fetch_started := false

## One-time async fetches for the volcanic lava texture + the per-biome 3D hazard GLBs
## (lava crater, carnivore plant), keyed by model name.
var _lava_fetch_started := false
var _hazard_model_fetch_started: Dictionary = {}
## XZ centres (metres) of lava craters kept this layout, so further mine slots that would
## overlap are skipped (reset per update_placed_objects). Keeps craters from clumping.
var _crater_positions: Array[Vector2] = []

## Active biome prop themes (name prefixes into the panel sets).
var _prop_theme := ""
var _container_theme := ""

## War-torn ruin fires (FireProp instances + their world positions, capped order).
var _fires_enabled := false
var _fire_instances: Array[Node3D] = []
var _fire_positions: Array[Vector3] = []

## Rubble at the ruin wall bases (one MultiMesh for the whole overlay).
var _rubble_instance: MultiMeshInstance3D = null
var _ruin_fetch_started := false
var _last_wall_segments: Array = []
var _last_wall_table_size := Vector2.ZERO
var _last_wall_rotation := 0.0

## Placed object instances (trees + containers)
var _object_instances: Array[Node3D] = []

## Always-visible Asgard terrain-effect labels (one Label3D per terrain zone).
var _terrain_labels: Array[Node3D] = []

## Cells that carry a wall (from the last wall_segments) so effect labels can avoid
## sitting under a wall. Cached grid geometry lets labels rebuild once walls arrive.
var _wall_cells: Dictionary = {}
var _grid_dims: Vector2i = Vector2i.ZERO
var _cell_size_m: float = 0.0

## Neighbour offset per edge_side (0=N, 1=E, 2=S, 3=W).
const _EDGE_DELTA: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]


func _ready() -> void:
	# Position slightly above table surface to avoid z-fighting
	position.y = Z_FIGHT_OFFSET
	_ruins_library = RuinsLibrary.new()
	_ruins_library.name = "RuinsLibrary"
	add_child(_ruins_library)
	_trees_library = TreesLibrary.new()
	_trees_library.name = "TreesLibrary"
	add_child(_trees_library)
	_containers_library = ContainersLibrary.new()
	_containers_library.name = "ContainersLibrary"
	add_child(_containers_library)
	_hazards_library = HazardsLibrary.new()
	_hazards_library.name = "HazardsLibrary"
	add_child(_hazards_library)
	# Re-gate the war-torn fires (light/smoke caps) when the quality tier changes.
	GraphicsSettings.settings_applied.connect(_on_graphics_settings_applied)


## Clear all terrain overlay meshes from the scene
func clear_overlay() -> void:
	for mesh in overlay_meshes:
		if is_instance_valid(mesh):
			mesh.queue_free()
	overlay_meshes.clear()
	_clear_terrain_labels()


## Update terrain overlay based on map layout
##
## @param cells_data: Dictionary mapping Vector2i cell positions to terrain types
## @param table_size: Table dimensions in feet (Vector2)
## @param grid_rotation: Grid rotation angle in degrees
func update_overlay(cells_data: Dictionary, table_size: Vector2, grid_rotation: float) -> void:
	# Validate inputs
	if not is_instance_valid(self):
		push_error("TerrainOverlay: Invalid instance during update")
		return

	if table_size.x <= 0 or table_size.y <= 0:
		push_error("TerrainOverlay: Invalid table size (%.1f, %.1f)" % [table_size.x, table_size.y])
		return

	clear_overlay()
	table_size_feet = table_size
	grid_rotation_degrees = grid_rotation

	# Store grid_cells for terrain lookup
	self.grid_cells = cells_data

	# Update deployment zones when table size changes
	_update_deployment_zones()

	if cells_data.is_empty():
		return

	var grid_dims := _calculate_grid_dims(table_size)
	var cell_size_meters := GRID_SIZE_INCHES * INCHES_TO_METERS
	var rotation_rad := deg_to_rad(grid_rotation)
	var table_width_m := table_size_feet.x * 12.0 * INCHES_TO_METERS
	var table_depth_m := table_size_feet.y * 12.0 * INCHES_TO_METERS
	_grid_dims = grid_dims
	_cell_size_m = cell_size_meters

	# Per-cell colored planes: one flat, transparent quad per terrain cell.
	# Colors follow the rulebook scheme (ruins blue / forest green / container brown /
	# dangerous red); the standing 3D props on top are holographic (see wall/object code).
	for cell_pos: Vector2i in cells_data:
		var terrain_type: int = cells_data[cell_pos]
		if terrain_type == TerrainType.NONE:
			continue
		if not _is_cell_visible(cell_pos, grid_dims, cell_size_meters, rotation_rad, table_width_m, table_depth_m):
			continue
		var color: Color = TERRAIN_COLORS.get(terrain_type, Color.WHITE)
		var local_x: float = (cell_pos.x - grid_dims.x / 2.0 + 0.5) * cell_size_meters
		var local_z: float = (cell_pos.y - grid_dims.y / 2.0 + 0.5) * cell_size_meters
		var rotated_x: float = local_x * cos(rotation_rad) - local_z * sin(rotation_rad)
		var rotated_z: float = local_x * sin(rotation_rad) + local_z * cos(rotation_rad)
		var mesh_instance := _create_cell_mesh(
				Vector3(rotated_x, TERRAIN_TILE_WORLD_Y - Z_FIGHT_OFFSET, rotated_z),
				cell_size_meters, color, grid_rotation)
		mesh_instance.visible = true
		add_child(mesh_instance)
		overlay_meshes.append(mesh_instance)

	# Always-visible Asgard effect labels per terrain zone (shown in any overlay mode).
	# Wall-aware: rebuilt again from update_wall_models() once wall data is known.
	_rebuild_terrain_labels()


## Calculate grid dimensions from table size
func _calculate_grid_dims(table_size: Vector2) -> Vector2i:
	var width_inches := table_size.x * 12.0
	var height_inches := table_size.y * 12.0
	var diagonal := sqrt(width_inches * width_inches + height_inches * height_inches)
	var grid_size := int(ceil(diagonal / GRID_SIZE_INCHES))
	if grid_size % 2 != 0:
		grid_size += 1
	return Vector2i(grid_size, grid_size)


## Check if a cell has any corner within table bounds (for culling)
func _is_cell_visible(cell_pos: Vector2i, grid_dims: Vector2i, cell_size_meters: float, rotation_rad: float, table_width_m: float, table_depth_m: float) -> bool:
	var local_x := (cell_pos.x - grid_dims.x / 2.0 + 0.5) * cell_size_meters
	var local_z := (cell_pos.y - grid_dims.y / 2.0 + 0.5) * cell_size_meters
	var half_cell := cell_size_meters / 2.0
	var corners: Array[Vector2] = [
		Vector2(local_x - half_cell, local_z - half_cell),
		Vector2(local_x + half_cell, local_z - half_cell),
		Vector2(local_x + half_cell, local_z + half_cell),
		Vector2(local_x - half_cell, local_z + half_cell)
	]
	for corner: Vector2 in corners:
		var rx: float = corner.x * cos(rotation_rad) - corner.y * sin(rotation_rad)
		var rz: float = corner.x * sin(rotation_rad) + corner.y * cos(rotation_rad)
		if abs(rx) <= table_width_m / 2.0 and abs(rz) <= table_depth_m / 2.0:
			return true
	return false


## Create a mesh instance for a single terrain cell
##
## Creates a flat quad mesh with transparent colored material
##
## @param pos: World position for the mesh center (already rotated)
## @param cell_size: Cell size in meters
## @param color: Terrain color with alpha for transparency
## @param grid_rotation: Grid rotation for the mesh itself
## @return: Configured MeshInstance3D ready to be added to scene tree
func _create_cell_mesh(pos: Vector3, cell_size: float, color: Color, grid_rotation: float = 0.0) -> MeshInstance3D:
	var mesh_instance = MeshInstance3D.new()

	# Create a flat quad (slightly smaller to show grid lines between cells)
	var plane_mesh = PlaneMesh.new()
	plane_mesh.size = Vector2(cell_size * CELL_SIZE_REDUCTION, cell_size * CELL_SIZE_REDUCTION)

	mesh_instance.mesh = plane_mesh
	mesh_instance.position = pos
	# Negate rotation because Godot Y-axis rotation is clockwise (viewed from above)
	# while our position rotation is counter-clockwise
	mesh_instance.rotation.y = -deg_to_rad(grid_rotation)

	# Create transparent, unshaded material
	var material = StandardMaterial3D.new()
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED  # Visible from both sides
	material.render_priority = TERRAIN_TILE_RENDER_PRIORITY  # lowest overlay layer (issue #71)

	mesh_instance.material_override = material

	return mesh_instance


## Toggle visibility of all terrain overlay meshes
##
## @param show_overlay: true to show overlays, false to hide them
func set_visible_overlay(show_overlay: bool) -> void:
	for mesh in overlay_meshes:
		if is_instance_valid(mesh):
			mesh.visible = show_overlay


## Set deployment zone type and create visualizations
##
## @param deployment_type: Type of deployment zone to display
func set_deployment_zones(deployment_type: int) -> void:
	current_deployment_type = deployment_type
	_update_deployment_zones()


## Toggle visibility of deployment zones
##
## @param show_zones: true to show deployment zones, false to hide them
func set_deployment_zones_visible(show_zones: bool) -> void:
	deployment_zones_visible = show_zones
	for mesh in deployment_zone_meshes:
		if is_instance_valid(mesh):
			mesh.visible = show_zones


## Clear all deployment zone meshes
func _clear_deployment_zones() -> void:
	for mesh in deployment_zone_meshes:
		if is_instance_valid(mesh):
			mesh.queue_free()
	deployment_zone_meshes.clear()


## Update deployment zone visualization based on current type
func _update_deployment_zones() -> void:
	_clear_deployment_zones()

	if current_deployment_type == DeploymentType.NONE:
		return

	# Convert table size from feet to meters
	var table_width_m = table_size_feet.x * 12.0 * INCHES_TO_METERS  # Long edge (X-axis)
	var table_depth_m = table_size_feet.y * 12.0 * INCHES_TO_METERS  # Short edge (Z-axis)

	match current_deployment_type:
		DeploymentType.FRONT_LINE:
			_create_front_line_zones(table_width_m, table_depth_m)
		DeploymentType.CUSTOM:
			_create_custom_polygon_zones()


## Create Front-line deployment zones (12" from long table edges)
func _create_front_line_zones(table_width: float, table_depth: float) -> void:
	var deployment_depth = 12.0 * INCHES_TO_METERS  # 12" deployment zone

	# Player 1 zone (bottom, facing forward along +Z). Absolute world Y = DEPLOYMENT_ZONE_WORLD_Y
	# (0.0006, just under the 3 mm base bodies); draw order vs bases/tokens is fixed by render_priority (issue #71).
	var p1_position = Vector3(0, DEPLOYMENT_ZONE_WORLD_Y - Z_FIGHT_OFFSET, -table_depth/2 + deployment_depth/2)
	var p1_size = Vector2(table_width, deployment_depth)
	var p1_mesh = _create_deployment_zone_mesh(p1_position, p1_size, DEPLOYMENT_COLORS["player1"])
	add_child(p1_mesh)
	deployment_zone_meshes.append(p1_mesh)

	# Player 2 zone (top, facing backward along -Z)
	var p2_position = Vector3(0, DEPLOYMENT_ZONE_WORLD_Y - Z_FIGHT_OFFSET, table_depth/2 - deployment_depth/2)
	var p2_size = Vector2(table_width, deployment_depth)
	var p2_mesh = _create_deployment_zone_mesh(p2_position, p2_size, DEPLOYMENT_COLORS["player2"])
	add_child(p2_mesh)
	deployment_zone_meshes.append(p2_mesh)

	p1_mesh.visible = deployment_zones_visible
	p2_mesh.visible = deployment_zones_visible


# ==============================================================================
# CUSTOM POLYGON DEPLOYMENT ZONES
# ==============================================================================

## Create custom polygon deployment zones from stored vertices
func _create_custom_polygon_zones() -> void:
	# Create Player 1 zone if vertices exist
	if custom_zone_player1.size() >= 3:
		var p1_mesh = _create_polygon_zone_mesh(custom_zone_player1, DEPLOYMENT_COLORS["player1"])
		add_child(p1_mesh)
		deployment_zone_meshes.append(p1_mesh)
		p1_mesh.visible = deployment_zones_visible

	# Create Player 2 zone if vertices exist
	if custom_zone_player2.size() >= 3:
		var p2_mesh = _create_polygon_zone_mesh(custom_zone_player2, DEPLOYMENT_COLORS["player2"])
		add_child(p2_mesh)
		deployment_zone_meshes.append(p2_mesh)
		p2_mesh.visible = deployment_zones_visible


## Create a mesh from polygon vertices using triangulation
func _create_polygon_zone_mesh(vertices: Array[Vector3], color: Color) -> MeshInstance3D:
	var mesh_instance = MeshInstance3D.new()

	if vertices.size() < 3:
		return mesh_instance

	# Convert 3D vertices to 2D for triangulation (XZ plane)
	var points_2d: PackedVector2Array = PackedVector2Array()
	for v in vertices:
		points_2d.append(Vector2(v.x, v.z))

	# Triangulate the polygon
	var indices = Geometry2D.triangulate_polygon(points_2d)
	if indices.is_empty():
		push_warning("TerrainOverlay: Failed to triangulate custom zone polygon")
		return mesh_instance

	# Create mesh using SurfaceTool
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Add vertices
	for i in range(indices.size()):
		var idx = indices[i]
		var v = vertices[idx]
		st.add_vertex(Vector3(v.x, DEPLOYMENT_ZONE_WORLD_Y - Z_FIGHT_OFFSET, v.z))

	st.generate_normals()
	mesh_instance.mesh = st.commit()

	# Create semi-transparent material
	var material = StandardMaterial3D.new()
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.render_priority = DEPLOYMENT_ZONE_RENDER_PRIORITY  # above terrain tiles + stains (issue #71)

	mesh_instance.material_override = material

	return mesh_instance


# ==============================================================================
# CUSTOM ZONE EDITING API
# ==============================================================================

## Start editing custom deployment zones
## @param symmetric: If true, both zones are drawn simultaneously (point-symmetric)
func start_custom_zone_editing(symmetric: bool) -> void:
	if symmetric:
		custom_zone_mode = CustomZoneMode.SYMMETRIC
	else:
		custom_zone_mode = CustomZoneMode.ASYMMETRIC_P1

	# Clear existing custom zones
	custom_zone_player1.clear()
	custom_zone_player2.clear()

	# Show fine grid for vertex placement
	show_fine_grid()
	_clear_vertex_markers()

	custom_zone_editing_changed.emit(true, custom_zone_mode)


## Add a vertex to the current custom zone being edited
## @param world_pos: Position in world coordinates (meters)
## Note: Position is automatically snapped to 1" grid intersection
func add_custom_zone_vertex(world_pos: Vector3) -> void:
	# Snap to 1" grid intersection
	var snapped_pos = snap_to_fine_grid(world_pos)

	match custom_zone_mode:
		CustomZoneMode.SYMMETRIC:
			# Add vertex to P1 zone
			custom_zone_player1.append(snapped_pos)
			custom_zone_vertex_added.emit(1, snapped_pos)

			# Add point-symmetric vertex to P2 zone (mirrored around center)
			var mirrored_pos = Vector3(-snapped_pos.x, snapped_pos.y, -snapped_pos.z)
			custom_zone_player2.append(mirrored_pos)
			custom_zone_vertex_added.emit(2, mirrored_pos)

		CustomZoneMode.ASYMMETRIC_P1:
			custom_zone_player1.append(snapped_pos)
			custom_zone_vertex_added.emit(1, snapped_pos)

		CustomZoneMode.ASYMMETRIC_P2:
			custom_zone_player2.append(snapped_pos)
			custom_zone_vertex_added.emit(2, snapped_pos)

	# Update visualization
	_update_deployment_zones()
	_update_vertex_markers()


## Complete the current custom zone and move to next (for asymmetric mode)
func complete_current_custom_zone() -> void:
	match custom_zone_mode:
		CustomZoneMode.SYMMETRIC:
			# Both zones completed simultaneously
			custom_zone_mode = CustomZoneMode.NONE
			custom_zone_completed.emit(1)
			custom_zone_completed.emit(2)
			custom_zone_editing_changed.emit(false, CustomZoneMode.NONE)
			# Hide editing aids
			hide_fine_grid()
			_clear_vertex_markers()

		CustomZoneMode.ASYMMETRIC_P1:
			# P1 done, start P2
			custom_zone_completed.emit(1)
			custom_zone_mode = CustomZoneMode.ASYMMETRIC_P2
			custom_zone_editing_changed.emit(true, custom_zone_mode)
			# Keep grid, clear markers for new zone
			_clear_vertex_markers()

		CustomZoneMode.ASYMMETRIC_P2:
			# P2 done, editing complete
			custom_zone_completed.emit(2)
			custom_zone_mode = CustomZoneMode.NONE
			custom_zone_editing_changed.emit(false, CustomZoneMode.NONE)
			# Hide editing aids
			hide_fine_grid()
			_clear_vertex_markers()


## Cancel custom zone editing
func cancel_custom_zone_editing() -> void:
	custom_zone_mode = CustomZoneMode.NONE
	custom_zone_player1.clear()
	custom_zone_player2.clear()
	_update_deployment_zones()
	# Hide editing aids
	hide_fine_grid()
	_clear_vertex_markers()
	custom_zone_editing_changed.emit(false, CustomZoneMode.NONE)


## Remove the last vertex from the current zone being edited
func undo_last_custom_zone_vertex() -> void:
	match custom_zone_mode:
		CustomZoneMode.SYMMETRIC:
			if not custom_zone_player1.is_empty():
				custom_zone_player1.pop_back()
			if not custom_zone_player2.is_empty():
				custom_zone_player2.pop_back()

		CustomZoneMode.ASYMMETRIC_P1:
			if not custom_zone_player1.is_empty():
				custom_zone_player1.pop_back()

		CustomZoneMode.ASYMMETRIC_P2:
			if not custom_zone_player2.is_empty():
				custom_zone_player2.pop_back()

	_update_deployment_zones()
	_update_vertex_markers()


## Check if currently editing custom zones
func is_editing_custom_zones() -> bool:
	return custom_zone_mode != CustomZoneMode.NONE


## Get the current editing mode
func get_custom_zone_mode() -> CustomZoneMode:
	return custom_zone_mode


## Set custom zone vertices directly (for loading saved zones)
func set_custom_zones(p1_vertices: Array[Vector3], p2_vertices: Array[Vector3]) -> void:
	custom_zone_player1 = p1_vertices.duplicate()
	custom_zone_player2 = p2_vertices.duplicate()
	if current_deployment_type == DeploymentType.CUSTOM:
		_update_deployment_zones()


## Get custom zone vertices (for saving)
func get_custom_zones() -> Dictionary:
	return {
		"player1": custom_zone_player1.duplicate(),
		"player2": custom_zone_player2.duplicate()
	}


# ==============================================================================
# FINE GRID (1") FOR CUSTOM ZONE EDITING
# ==============================================================================

## Show the 1" fine grid for custom zone editing
func show_fine_grid() -> void:
	if fine_grid_visible:
		return

	_create_fine_grid()
	fine_grid_visible = true


## Hide the 1" fine grid
func hide_fine_grid() -> void:
	_clear_fine_grid()
	fine_grid_visible = false


## Clear all fine grid meshes
func _clear_fine_grid() -> void:
	for mesh in fine_grid_meshes:
		if is_instance_valid(mesh):
			mesh.queue_free()
	fine_grid_meshes.clear()


## Create the 1" fine grid visualization
func _create_fine_grid() -> void:
	_clear_fine_grid()

	var table_width_m = table_size_feet.x * 12.0 * INCHES_TO_METERS
	var table_depth_m = table_size_feet.y * 12.0 * INCHES_TO_METERS
	var cell_size = FINE_GRID_SIZE_INCHES * INCHES_TO_METERS

	# Grid line color (subtle gray)
	var line_color = Color(0.4, 0.4, 0.4, 0.5)

	# Create horizontal lines (along X axis)
	var num_z_lines = int(table_depth_m / cell_size) + 1
	for i in range(num_z_lines + 1):
		var z = -table_depth_m / 2.0 + i * cell_size
		if z > table_depth_m / 2.0 + 0.001:
			continue
		var line = _create_grid_line(
			Vector3(-table_width_m / 2.0, 0.003, z),
			Vector3(table_width_m / 2.0, 0.003, z),
			line_color
		)
		add_child(line)
		fine_grid_meshes.append(line)

	# Create vertical lines (along Z axis)
	var num_x_lines = int(table_width_m / cell_size) + 1
	for i in range(num_x_lines + 1):
		var x = -table_width_m / 2.0 + i * cell_size
		if x > table_width_m / 2.0 + 0.001:
			continue
		var line = _create_grid_line(
			Vector3(x, 0.003, -table_depth_m / 2.0),
			Vector3(x, 0.003, table_depth_m / 2.0),
			line_color
		)
		add_child(line)
		fine_grid_meshes.append(line)


## Create a single grid line mesh
func _create_grid_line(start: Vector3, end: Vector3, color: Color) -> MeshInstance3D:
	var mesh_instance = MeshInstance3D.new()

	var im = ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	im.surface_add_vertex(start)
	im.surface_add_vertex(end)
	im.surface_end()

	mesh_instance.mesh = im

	var material = StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	mesh_instance.material_override = material

	return mesh_instance


## Snap a world position to the nearest 1" grid intersection
## @param world_pos: Position in world coordinates
## @return: Snapped position on the nearest grid intersection
func snap_to_fine_grid(world_pos: Vector3) -> Vector3:
	var cell_size = FINE_GRID_SIZE_INCHES * INCHES_TO_METERS
	var table_width_m = table_size_feet.x * 12.0 * INCHES_TO_METERS
	var table_depth_m = table_size_feet.y * 12.0 * INCHES_TO_METERS

	# Snap to nearest intersection
	var snapped_x = round((world_pos.x + table_width_m / 2.0) / cell_size) * cell_size - table_width_m / 2.0
	var snapped_z = round((world_pos.z + table_depth_m / 2.0) / cell_size) * cell_size - table_depth_m / 2.0

	# Clamp to table bounds
	snapped_x = clamp(snapped_x, -table_width_m / 2.0, table_width_m / 2.0)
	snapped_z = clamp(snapped_z, -table_depth_m / 2.0, table_depth_m / 2.0)

	return Vector3(snapped_x, 0.0, snapped_z)


## Clear vertex markers
func _clear_vertex_markers() -> void:
	for marker in vertex_markers:
		if is_instance_valid(marker):
			marker.queue_free()
	vertex_markers.clear()


## Update vertex markers to show current polygon vertices
func _update_vertex_markers() -> void:
	_clear_vertex_markers()

	# Get current vertices based on mode
	var vertices: Array[Vector3] = []
	match custom_zone_mode:
		CustomZoneMode.SYMMETRIC, CustomZoneMode.ASYMMETRIC_P1:
			vertices = custom_zone_player1
		CustomZoneMode.ASYMMETRIC_P2:
			vertices = custom_zone_player2

	# Create marker for each vertex
	for i in range(vertices.size()):
		var v = vertices[i]
		var marker = _create_vertex_marker(v, i + 1)
		add_child(marker)
		vertex_markers.append(marker)

	# In symmetric mode, also show P2 markers
	if custom_zone_mode == CustomZoneMode.SYMMETRIC:
		for i in range(custom_zone_player2.size()):
			var v = custom_zone_player2[i]
			var marker = _create_vertex_marker(v, i + 1, DEPLOYMENT_COLORS["player2"])
			add_child(marker)
			vertex_markers.append(marker)


## Create a vertex marker (small sphere with number)
func _create_vertex_marker(pos: Vector3, number: int, color: Color = Color(0.2, 0.5, 1.0, 0.8)) -> MeshInstance3D:
	var mesh_instance = MeshInstance3D.new()

	var sphere = SphereMesh.new()
	sphere.radius = 0.01  # 1cm radius
	sphere.height = 0.02
	mesh_instance.mesh = sphere
	mesh_instance.position = Vector3(pos.x, 0.015, pos.z)  # Slightly above table

	var material = StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	mesh_instance.material_override = material

	# Add number label
	var label = Label3D.new()
	label.text = str(number)
	label.position.y = 0.02
	label.pixel_size = 0.001
	label.font_size = 32
	label.modulate = Color.WHITE
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	mesh_instance.add_child(label)

	return mesh_instance


func _create_deployment_zone_mesh(pos: Vector3, size: Vector2, color: Color) -> MeshInstance3D:
	var mesh_instance = MeshInstance3D.new()

	# Create a flat quad for the deployment zone
	var plane_mesh = PlaneMesh.new()
	plane_mesh.size = size

	mesh_instance.mesh = plane_mesh
	mesh_instance.position = pos

	# Create semi-transparent, unshaded material
	var material = StandardMaterial3D.new()
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.render_priority = DEPLOYMENT_ZONE_RENDER_PRIORITY  # above terrain tiles + stains (issue #71)

	mesh_instance.material_override = material

	return mesh_instance


## Get terrain type at a world position
##
## @param world_pos: Position to check (in 3D world coordinates)
## @return: TerrainType enum value at that position
func get_terrain_at_world_position(world_pos: Vector3) -> int:
	if grid_cells.is_empty():
		return TerrainType.NONE
	return grid_cells.get(world_to_cell(world_pos), TerrainType.NONE)


## Convert a world position to its terrain grid cell, matching update_overlay's
## centered + rotated layout (reverse rotation; even grid dims from the diagonal).
func world_to_cell(world_pos: Vector3) -> Vector2i:
	var width_inches := table_size_feet.x * 12.0
	var height_inches := table_size_feet.y * 12.0
	var diagonal := sqrt(width_inches * width_inches + height_inches * height_inches)
	var grid_size := int(ceil(diagonal / GRID_SIZE_INCHES))
	if grid_size % 2 != 0:
		grid_size += 1
	var cell_size_meters := GRID_SIZE_INCHES * INCHES_TO_METERS
	var rotation_rad := deg_to_rad(grid_rotation_degrees)
	var rotated_x := world_pos.x * cos(-rotation_rad) - world_pos.z * sin(-rotation_rad)
	var rotated_z := world_pos.x * sin(-rotation_rad) + world_pos.z * cos(-rotation_rad)
	var grid_x := int(floor(rotated_x / cell_size_meters + grid_size / 2.0))
	var grid_z := int(floor(rotated_z / cell_size_meters + grid_size / 2.0))
	return Vector2i(grid_x, grid_z)


## True if a terrain type blocks line of sight when drawn THROUGH it (ruins,
## forests, houses). Dangerous terrain is Open and never blocks.
func terrain_blocks_los(terrain_type: int) -> bool:
	return terrain_type == TerrainType.RUINS \
		or terrain_type == TerrainType.FOREST \
		or terrain_type == TerrainType.CONTAINER


## Asgard Height category of a terrain type (blockers are Height 5; open = 0).
func terrain_height_category(terrain_type: int) -> int:
	return 5 if terrain_blocks_los(terrain_type) else 0


## All cells of the contiguous same-type terrain zone containing `start_cell`
## (4-connected). Empty set if start_cell holds no terrain.
func _flood_fill_zone(start_cell: Vector2i) -> Dictionary:
	var result := {}
	var ttype: int = grid_cells.get(start_cell, TerrainType.NONE)
	if ttype == TerrainType.NONE:
		return result
	var stack: Array[Vector2i] = [start_cell]
	result[start_cell] = true
	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		for nb in [Vector2i(c.x + 1, c.y), Vector2i(c.x - 1, c.y), Vector2i(c.x, c.y + 1), Vector2i(c.x, c.y - 1)]:
			if not result.has(nb) and grid_cells.get(nb, TerrainType.NONE) == ttype:
				result[nb] = true
				stack.append(nb)
	return result


## Top-down Asgard line-of-sight between two world points. A blocking terrain zone
## the line crosses blocks LOS only when (a) neither endpoint stands inside that same
## zone ("see in/out, not through") AND (b) the zone's Height is >= BOTH endpoints'
## Height categories (otherwise the taller one sees over it). Dangerous terrain never
## blocks. Heights are Asgard categories 1-6 (see LosRules).
func has_line_of_sight(from_pos: Vector3, to_pos: Vector3, from_height: int, to_height: int) -> bool:
	if grid_cells.is_empty():
		return true
	var from_zone := _flood_fill_zone(world_to_cell(from_pos))
	var to_zone := _flood_fill_zone(world_to_cell(to_pos))
	var span := Vector2(to_pos.x - from_pos.x, to_pos.z - from_pos.z).length()
	var cell_size := GRID_SIZE_INCHES * INCHES_TO_METERS
	var steps := int(ceil(span / (cell_size * 0.5)))
	if steps < 2:
		return true
	for i in range(1, steps):  # skip the exact endpoints
		var cell := world_to_cell(from_pos.lerp(to_pos, float(i) / float(steps)))
		var ttype: int = grid_cells.get(cell, TerrainType.NONE)
		if not terrain_blocks_los(ttype):
			continue
		if from_zone.has(cell) or to_zone.has(cell):
			continue  # own zone: you see in/out of it
		var th := terrain_height_category(ttype)
		if th >= from_height and th >= to_height:
			return false
	return true


## Compact, always-visible Asgard effect label for a terrain type (empty for NONE).
## Players read it to apply Cover/Difficult/Dangerous etc. themselves.
## Three stacked lines for a terrain zone: Type / Height / Special Rules (English).
func _terrain_effect_label(terrain_type: int) -> String:
	match terrain_type:
		TerrainType.RUINS:
			return "Ruins\nHeight 5\nCover, Blocks LoS"
		TerrainType.FOREST:
			return "Forest\nHeight 5\nDifficult, Cover, Blocks LoS"
		TerrainType.CONTAINER:
			return "Container\nHeight 5\nImpassable, Blocks LoS"
		TerrainType.DANGEROUS:
			return "Dangerous\nGround\nDangerous Terrain"
	return ""


## Group terrain cells into contiguous same-type zones (4-connected components).
## Each entry: {"type": int, "cells": Array[Vector2i]}.
func _terrain_zones(cells_data: Dictionary) -> Array:
	var zones: Array = []
	var visited := {}
	for cell in cells_data:
		var ttype: int = cells_data[cell]
		if ttype == TerrainType.NONE or visited.has(cell):
			continue
		var stack: Array[Vector2i] = [cell]
		visited[cell] = true
		var comp: Array = []
		while not stack.is_empty():
			var c: Vector2i = stack.pop_back()
			comp.append(c)
			for nb in [Vector2i(c.x + 1, c.y), Vector2i(c.x - 1, c.y), Vector2i(c.x, c.y + 1), Vector2i(c.x, c.y - 1)]:
				if not visited.has(nb) and cells_data.get(nb, TerrainType.NONE) == ttype:
					visited[nb] = true
					stack.append(nb)
		zones.append({"type": ttype, "cells": comp})
	return zones


## World position of a (possibly fractional) grid cell, matching update_overlay's
## centered + rotated layout. y is 0 (caller lifts the label above the table).
func _cell_to_world(cell_x: float, cell_y: float, grid_dims: Vector2i, cell_size: float, rotation_rad: float) -> Vector3:
	var local_x := (cell_x - grid_dims.x / 2.0 + 0.5) * cell_size
	var local_z := (cell_y - grid_dims.y / 2.0 + 0.5) * cell_size
	var rx := local_x * cos(rotation_rad) - local_z * sin(rotation_rad)
	var rz := local_x * sin(rotation_rad) + local_z * cos(rotation_rad)
	return Vector3(rx, 0.0, rz)


## (Re)build one always-visible effect label per terrain zone — small, lying FLAT on the
## terrain, in a wall-free edge cell of the zone so it stays readable. Uses cached grid
## geometry + _wall_cells, so it can run from update_overlay() and again from
## update_wall_models() once walls are known. Pure-derived; no save/network sync needed.
func _rebuild_terrain_labels() -> void:
	const LABEL_Y := 0.006  # metres above the terrain plane — lies flat, clear of z-fighting
	_clear_terrain_labels()
	if grid_cells.is_empty() or _cell_size_m <= 0.0:
		return
	var rotation_rad := deg_to_rad(grid_rotation_degrees)
	for zone in _terrain_zones(grid_cells):
		var ttype: int = zone["type"]
		var text := _terrain_effect_label(ttype)
		if text.is_empty():
			continue
		var cells: Array = zone["cells"]
		var zone_set := {}
		for c in cells:
			zone_set[c] = true
		var cell := _pick_label_cell(cells, zone_set)
		var pos := _cell_to_world(float(cell.x), float(cell.y), _grid_dims, _cell_size_m, rotation_rad)
		var lbl := Label3D.new()
		lbl.name = "TerrainLabel"
		lbl.text = text
		lbl.billboard = BaseMaterial3D.BILLBOARD_DISABLED  # lie flat on the terrain
		lbl.font_size = 16
		lbl.outline_size = 5
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.modulate = Color.WHITE
		lbl.outline_modulate = Color(0.03, 0.03, 0.03, 0.95)
		lbl.pixel_size = 0.0003  # small (~5 mm per line)
		lbl.rotation_degrees = Vector3(-90.0, rad_to_deg(rotation_rad), 0.0)  # flat, grid-aligned
		lbl.position = Vector3(pos.x, LABEL_Y, pos.z)
		add_child(lbl)
		_terrain_labels.append(lbl)


## Keep the flat terrain labels yawed toward the viewer so they read from any camera angle
## (playtest feedback: the plaques stay flat on the table but follow the viewing direction instead
## of staying grid-aligned). Cheap — only a handful of labels, no per-frame allocations.
func _process(_delta: float) -> void:
	if _terrain_labels.is_empty():
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var cam_pos := cam.global_position
	for lbl in _terrain_labels:
		if not is_instance_valid(lbl):
			continue
		var to_cam := cam_pos - lbl.global_position
		# Stay flat (-90° about X) and yaw around the table normal to face the camera horizontally.
		lbl.rotation = Vector3(-PI / 2.0, atan2(to_cam.x, to_cam.z), 0.0)


## Pick a zone cell for the effect label: prefer a wall-free EDGE cell (a Randfeld), then
## any wall-free cell, then the first cell. Returns the candidate nearest the candidates'
## centroid for a stable, central placement.
func _pick_label_cell(cells: Array, zone_set: Dictionary) -> Vector2i:
	var edge_clear: Array = []
	var any_clear: Array = []
	for c: Vector2i in cells:
		if _wall_cells.has(c):
			continue
		any_clear.append(c)
		for d: Vector2i in _EDGE_DELTA:
			if not zone_set.has(c + d):
				edge_clear.append(c)
				break
	if not edge_clear.is_empty():
		return _central_cell(edge_clear)
	if not any_clear.is_empty():
		return _central_cell(any_clear)
	return cells[0]


## The cell nearest the centroid of the candidates (deterministic, central).
func _central_cell(cands: Array) -> Vector2i:
	var sx := 0.0
	var sy := 0.0
	for c: Vector2i in cands:
		sx += c.x
		sy += c.y
	var cx := sx / cands.size()
	var cy := sy / cands.size()
	var best: Vector2i = cands[0]
	var best_d := INF
	for c: Vector2i in cands:
		var d: float = (c.x - cx) * (c.x - cx) + (c.y - cy) * (c.y - cy)
		if d < best_d:
			best_d = d
			best = c
	return best


## Remove all terrain effect labels.
func _clear_terrain_labels() -> void:
	for lbl in _terrain_labels:
		if is_instance_valid(lbl):
			lbl.queue_free()
	_terrain_labels.clear()


# ==============================================================================
# MISSION OBJECTIVES
# ==============================================================================

## Update mission objectives display
##
## @param objectives: Array of Vector3 world positions (in meters)
## @param owners: Optional per-objective owner (0 = neutral, else player_id),
##                index-aligned to `objectives`. Missing entries default to 0.
func update_objectives(objectives: Array, owners: Array = []) -> void:
	_clear_objectives()
	mission_objectives.clear()
	objective_owners.clear()

	for i in range(objectives.size()):
		var obj = objectives[i]
		if obj is Vector3:
			mission_objectives.append(obj)
			objective_owners.append(int(owners[i]) if i < owners.size() else 0)

	if mission_objectives.is_empty():
		return

	# Create meshes for each objective
	for i in range(mission_objectives.size()):
		_create_objective_marker(mission_objectives[i], i + 1, objective_owners[i])


## Color for an objective owner: neutral gold for 0, else the army's player color
## (shared with unit boundaries/bases via OPRArmyManager.PLAYER_COLORS).
func _objective_owner_color(owner_id: int) -> Color:
	if owner_id <= 0:
		return Color(1.0, 0.85, 0.2, 1.0)  # Neutral gold/yellow
	var c: Color = OPRArmyManager.PLAYER_COLORS.get(owner_id, Color(1.0, 0.85, 0.2, 1.0))
	return Color(c.r, c.g, c.b, 1.0)


## Sets the owner of an objective and recolors its token + seize ring in place.
func set_objective_owner(index: int, owner_id: int) -> void:
	if index < 0 or index >= objective_meshes.size():
		return
	while objective_owners.size() <= index:
		objective_owners.append(0)
	objective_owners[index] = owner_id

	var color := _objective_owner_color(owner_id)
	var token := objective_meshes[index]
	if is_instance_valid(token):
		var fill := token.get_node_or_null("Fill") as MeshInstance3D
		if fill and fill.material_override is StandardMaterial3D:
			(fill.material_override as StandardMaterial3D).albedo_color = color
		var label := token.get_node_or_null("Number") as Label3D
		if label:
			label.outline_modulate = color
	if index < objective_ring_meshes.size():
		var ring := objective_ring_meshes[index]
		if is_instance_valid(ring) and ring.material_override is StandardMaterial3D:
			(ring.material_override as StandardMaterial3D).albedo_color = Color(color.r, color.g, color.b, 0.25)


## Returns the owner of an objective (0 = neutral) or 0 if out of range.
func get_objective_owner(index: int) -> int:
	if index < 0 or index >= objective_owners.size():
		return 0
	return objective_owners[index]


## Returns a copy of the per-objective owner list (for saving).
func get_objective_owners() -> Array[int]:
	return objective_owners.duplicate()


## Clear all objective meshes
func _clear_objectives() -> void:
	for mesh in objective_meshes:
		if is_instance_valid(mesh):
			mesh.queue_free()
	objective_meshes.clear()

	for mesh in objective_ring_meshes:
		if is_instance_valid(mesh):
			mesh.queue_free()
	objective_ring_meshes.clear()


## Create a single objective marker with 3" seize radius ring
##
## @param pos: World position in meters
## @param number: Objective number for label
## @param owner_id: Owner (0 = neutral gold, else player_id -> army color)
func _create_objective_marker(pos: Vector3, number: int, owner_id: int = 0) -> void:
	var objective_color = _objective_owner_color(owner_id)
	var border_color = Color(0.1, 0.1, 0.1, 1.0)  # Black border
	var ring_color = Color(objective_color.r, objective_color.g, objective_color.b, 0.25)

	# Create 3" seize radius ring (flat disc)
	var seize_radius_m = 3.0 * INCHES_TO_METERS
	var ring_mesh = _create_seize_radius_ring(pos, seize_radius_m, ring_color)
	add_child(ring_mesh)
	objective_ring_meshes.append(ring_mesh)

	# Create objective token marker (1" diameter flat disc with black border)
	var token_container = _create_objective_token(pos, number, objective_color, border_color)
	add_child(token_container)
	objective_meshes.append(token_container)


## Create a ring mesh for the 3" seize radius
func _create_seize_radius_ring(pos: Vector3, radius: float, color: Color) -> MeshInstance3D:
	var mesh_instance = MeshInstance3D.new()

	# Create a flat disc mesh using CylinderMesh with very small height
	var cylinder = CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = SEIZE_RING_HEIGHT
	cylinder.radial_segments = 64

	mesh_instance.mesh = cylinder
	# Sit just above the table, under the base bodies (cylinder is centre-anchored). render_priority
	# keeps it above the other flat overlays; the opaque bases occlude it where they overlap (#71).
	mesh_instance.position = Vector3(pos.x,
			SEIZE_RING_WORLD_Y - Z_FIGHT_OFFSET + cylinder.height / 2.0, pos.z)

	# Create transparent material
	var material = StandardMaterial3D.new()
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.render_priority = SEIZE_RING_RENDER_PRIORITY  # topmost overlay layer, above zones (issue #71)

	mesh_instance.material_override = material

	return mesh_instance


## Create an objective token marker (like unit tokens: 1" diameter, black border,
## numbered). Returns a StaticBody3D so it can be right-clicked for the radial
## capture menu: it joins the "selectable" + "objective" groups and carries an
## "objective_index" meta (see ObjectManager / RadialMenuController).
func _create_objective_token(pos: Vector3, number: int, fill_color: Color, border_color: Color) -> StaticBody3D:
	# Token dimensions: 1" diameter = 0.0254m, but we use half for radius
	var token_radius = 0.5 * INCHES_TO_METERS  # 0.5" radius = 1" diameter
	var border_width = 0.08 * INCHES_TO_METERS  # Border thickness
	var token_height = 0.003  # 3mm thick

	var container = StaticBody3D.new()
	# The token disc rests ON TOP of its seize ring (which sits on the objective
	# layer); the border cylinder is centre-anchored on the container.
	container.position = Vector3(pos.x,
			OBJECTIVE_WORLD_Y - Z_FIGHT_OFFSET + SEIZE_RING_HEIGHT + token_height / 2.0, pos.z)
	container.add_to_group("selectable")
	container.add_to_group("objective")
	container.set_meta("objective_index", number - 1)
	container.collision_layer = 1
	container.collision_mask = 1

	# Collision shape so the raycast picker can hit the token (a bit taller than
	# the disc for an easy click target).
	var collision = CollisionShape3D.new()
	var collision_cyl = CylinderShape3D.new()
	collision_cyl.radius = token_radius + border_width
	collision_cyl.height = token_height + 0.02
	collision.shape = collision_cyl
	collision.position = Vector3(0, token_height / 2.0, 0)
	container.add_child(collision)

	# Create black border disc (slightly larger)
	var border_mesh = MeshInstance3D.new()
	border_mesh.name = "Border"
	var border_cylinder = CylinderMesh.new()
	border_cylinder.top_radius = token_radius + border_width
	border_cylinder.bottom_radius = token_radius + border_width
	border_cylinder.height = token_height
	border_cylinder.radial_segments = 32
	border_mesh.mesh = border_cylinder
	border_mesh.position = Vector3(0, 0, 0)

	var border_material = StandardMaterial3D.new()
	border_material.albedo_color = border_color
	border_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	border_mesh.material_override = border_material
	container.add_child(border_mesh)

	# Create fill disc (on top of border) - colored by owner
	var fill_mesh = MeshInstance3D.new()
	fill_mesh.name = "Fill"
	var fill_cylinder = CylinderMesh.new()
	fill_cylinder.top_radius = token_radius
	fill_cylinder.bottom_radius = token_radius
	fill_cylinder.height = token_height + 0.001  # Slightly higher to prevent z-fighting
	fill_cylinder.radial_segments = 32
	fill_mesh.mesh = fill_cylinder
	fill_mesh.position = Vector3(0, 0.001, 0)

	var fill_material = StandardMaterial3D.new()
	fill_material.albedo_color = fill_color
	fill_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fill_mesh.material_override = fill_material
	container.add_child(fill_mesh)

	# Create 3D text label for the objective number
	var label_3d = Label3D.new()
	label_3d.name = "Number"
	label_3d.text = str(number)
	label_3d.font_size = 72
	label_3d.pixel_size = 0.0003  # Scale to fit on token
	label_3d.position = Vector3(0, token_height + 0.002, 0)
	label_3d.rotation_degrees = Vector3(-90, 0, 0)  # Face upward
	label_3d.modulate = border_color  # Black text
	label_3d.outline_modulate = fill_color
	label_3d.outline_size = 8
	label_3d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_3d.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label_3d.no_depth_test = true  # Always visible
	label_3d.shaded = false
	container.add_child(label_3d)

	return container


func get_objectives() -> Array[Vector3]:
	return mission_objectives.duplicate()


# ==============================================================================
# OVERLAY MODE
# ==============================================================================

## Set the overlay display mode
## FLAT: Shows colored 2D planes (default behavior)
## MODELS: Hides the flat colored planes (only the standing 3D props remain)
## BOTH: Shows flat overlays AND 3D models
func set_overlay_mode(mode: OverlayMode) -> void:
	overlay_mode = mode

	# Update flat overlay visibility based on mode
	var show_flat := mode != OverlayMode.MODELS
	for mesh in overlay_meshes:
		if is_instance_valid(mesh):
			mesh.visible = show_flat


## Get the current overlay mode
func get_overlay_mode() -> OverlayMode:
	return overlay_mode


# ==============================================================================
# WALL 3D PLACEMENT (S8)
# ==============================================================================

## Update wall model instances based on wall segments from map layout
## @param wall_segments: Array of Dictionaries with {edge_cell, edge_side, wall_key,
##                       length_inches, sub_position, role, taper_dir}
## @param t_size: Table size in feet
## @param rotation: Grid rotation in degrees
func update_wall_models(wall_segments: Array, t_size: Vector2, rot_deg: float) -> void:
	_clear_wall_instances()

	# Remember the layout so a finishing panel download can upgrade fallback walls in
	# place; start the one-time fetch as soon as a map actually shows ruin walls.
	_last_wall_segments = wall_segments
	_last_wall_table_size = t_size
	_last_wall_rotation = rot_deg
	var use_shell := _ruin_panels_ready()
	if not use_shell and not wall_segments.is_empty():
		_request_ruin_panels()

	# Record which cells carry a wall (the edge cell + its neighbour across that edge), so
	# terrain effect labels can pick a wall-free field; then rebuild them wall-aware.
	_wall_cells.clear()
	for segment in wall_segments:
		var ec: Vector2i = segment.get("edge_cell", Vector2i.ZERO)
		var es: int = segment.get("edge_side", 0)
		_wall_cells[ec] = true
		if es >= 0 and es < _EDGE_DELTA.size():
			_wall_cells[ec + _EDGE_DELTA[es]] = true
	_rebuild_terrain_labels()

	if wall_segments.is_empty():
		_rebuild_fires()  # clears stale fires (and notifies the atmosphere layer)
		_rebuild_rubble()
		return

	var cell_size_meters := GRID_SIZE_INCHES * INCHES_TO_METERS

	# Compute grid dimensions (same as update_overlay)
	var width_inches := t_size.x * 12.0
	var height_inches := t_size.y * 12.0
	var diagonal := sqrt(width_inches * width_inches + height_inches * height_inches)
	var grid_size := int(ceil(diagonal / GRID_SIZE_INCHES))
	if grid_size % 2 != 0:
		grid_size += 1
	var grid_dims := Vector2i(grid_size, grid_size)

	var rotation_rad := deg_to_rad(rot_deg)

	# Endpoint usage per grid corner point: an endpoint touched by exactly one wall is a
	# FREE end and gets a stone end face; shared endpoints are covered by the collinear
	# neighbour or a corner post (capping those too would z-fight on coplanar quads).
	var corner_counts := {}
	for segment in wall_segments:
		for point in _wall_corner_points(segment):
			corner_counts[point] = int(corner_counts.get(point, 0)) + 1

	for segment in wall_segments:
		var edge_cell: Vector2i = segment.get("edge_cell", Vector2i.ZERO)
		var edge_side: int = segment.get("edge_side", 0)
		var length_inches: float = segment.get("length_inches", GRID_SIZE_INCHES)
		var sub_position: int = segment.get("sub_position", 0)

		# Build the wall for this segment: a textured shell once the panel set is
		# cached, else the triplanar box fallback (upgraded after the download).
		var model: StaticBody3D
		if use_shell:
			# Quad-local +X endpoint per edge_side under the wall_y_rotation set below:
			# N/W walls run +X toward corner_b, E/S walls toward corner_a.
			var points := _wall_corner_points(segment)
			var pos_x_point: Vector2i = points[1] if (edge_side == 0 or edge_side == 3) else points[0]
			var neg_x_point: Vector2i = points[0] if (edge_side == 0 or edge_side == 3) else points[1]
			var cap_neg_x := int(corner_counts.get(neg_x_point, 0)) == 1
			var cap_pos_x := int(corner_counts.get(pos_x_point, 0)) == 1
			model = _create_shell_wall(segment, length_inches, cap_neg_x, cap_pos_x)
		else:
			model = _create_procedural_wall(length_inches, WALL_HEIGHT_INCHES)

		# Place the wall — its mesh is already lifted so the base sits on the table.
		# Placement math is shared with the war-torn fires (_segment_world_placement).
		var placement := _segment_world_placement(segment, grid_dims, cell_size_meters, rotation_rad, rot_deg, t_size)
		if placement.is_empty():
			model.free()  # outside table boundaries
			continue
		var wall_position: Vector3 = placement["position"]
		model.position.x = wall_position.x
		model.position.z = wall_position.z
		model.rotation.y = placement["y_rotation"]
		add_child(model)
		_wall_instances.append(model)

	# Add corner pieces where perpendicular walls meet
	_add_wall_corner_pieces(wall_segments, grid_dims, cell_size_meters, rotation_rad, rot_deg, t_size)

	# (Re)place the war-torn fires + the wall-base rubble for the new layout.
	_rebuild_fires()
	_rebuild_rubble()


## Add corner pieces at intersections where two perpendicular walls meet
func _add_wall_corner_pieces(wall_segments: Array, grid_dims: Vector2i, cell_size_meters: float, rotation_rad: float, rot_deg: float, t_size: Vector2) -> void:
	# In shell mode the post is a masonry prism slightly PROUD of the 0.4" wall shells —
	# matching their depth exactly put its faces coplanar with the wall quads (z-fighting
	# right at the post). Fallback keeps the slim triplanar box post.
	var use_shell := _ruin_panels_ready()
	var corner_inches := RUIN_POST_SIZE_INCHES if use_shell else CORNER_SIZE_INCHES
	var corner_size := corner_inches * INCHES_TO_METERS

	# Build a dictionary of wall endpoints: corner_pos -> Array of wall_keys
	# Each wall segment touches two corners of its edge
	var corner_walls := {}  # Vector2i corner point -> Array[String] of adjacent wall keys

	for segment in wall_segments:
		var wall_key: String = segment.get("wall_key", "")
		for point in _wall_corner_points(segment):
			if not corner_walls.has(point):
				corner_walls[point] = []
			corner_walls[point].append(wall_key)

	# Place corner pieces where 2+ walls share a corner point
	for corner_point: Vector2i in corner_walls:
		var keys: Array = corner_walls[corner_point]
		if keys.size() < 2:
			continue

		# Corner position in local grid coordinates (grid points are at cell boundaries)
		var local_x := (corner_point.x - grid_dims.x / 2.0) * cell_size_meters
		var local_z := (corner_point.y - grid_dims.y / 2.0) * cell_size_meters

		var rotated_x := local_x * cos(rotation_rad) - local_z * sin(rotation_rad)
		var rotated_z := local_x * sin(rotation_rad) + local_z * cos(rotation_rad)

		if not _is_position_within_table(rotated_x, rotated_z, t_size):
			continue

		var target_height := WALL_HEIGHT_INCHES * INCHES_TO_METERS

		# Procedural holographic corner post (StaticBody so it blocks like a wall)
		var body := StaticBody3D.new()
		body.add_to_group("terrain")
		body.add_to_group("terrain_piece")

		if use_shell:
			# Masonry prism from quads: a BoxMesh would smear the 0..1-UV panel through
			# its per-face UV atlas. Sides wear a post-width slice of the wall masonry.
			# The post rises slightly past the wall caps — flush tops were coplanar with
			# the neighbouring caps and z-fought right above the post.
			var post_height := target_height + RUIN_POST_EXTRA_HEIGHT_INCHES * INCHES_TO_METERS
			var y_mid := post_height / 2.0 - Z_FIGHT_OFFSET
			var half := corner_size / 2.0
			var post_mat := _ruin_panel_material("solid_a", false, corner_inches / GRID_SIZE_INCHES, 0.0)
			var side := Vector2(corner_size, post_height)
			_add_shell_quad(body, side, Vector3(0, y_mid, half), Vector3.ZERO, post_mat)
			_add_shell_quad(body, side, Vector3(0, y_mid, -half), Vector3.ZERO, post_mat)
			_add_shell_quad(body, side, Vector3(half, y_mid, 0), Vector3(0, PI / 2.0, 0), post_mat)
			_add_shell_quad(body, side, Vector3(-half, y_mid, 0), Vector3(0, PI / 2.0, 0), post_mat)
			_add_shell_quad(body, Vector2(corner_size, corner_size),
					Vector3(0, post_height - Z_FIGHT_OFFSET, 0), Vector3(-PI / 2.0, 0, 0), post_mat)
		else:
			var mesh_instance := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(corner_size, target_height, corner_size)
			mesh_instance.mesh = box
			mesh_instance.material_override = _get_ruins_wall_material()
			mesh_instance.position.y = target_height / 2.0 - Z_FIGHT_OFFSET
			mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			body.add_child(mesh_instance)

		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(corner_size, target_height, corner_size)
		collision.shape = shape
		collision.position.y = target_height / 2.0 - Z_FIGHT_OFFSET
		body.add_child(collision)

		body.position.x = rotated_x
		body.position.z = rotated_z
		add_child(body)
		_wall_instances.append(body)


## Lit, world-triplanar stone material for the ruins walls + corner posts. Built once and
## shared; falls back to the holographic material if the bundled texture is unavailable.
func _get_ruins_wall_material() -> Material:
	if _ruins_wall_material != null:
		return _ruins_wall_material
	var tex: Texture2D = load(RUINS_WALL_TEX_PATH) if ResourceLoader.exists(RUINS_WALL_TEX_PATH) else null
	if tex == null:
		_ruins_wall_material = TerrainHologram.make_material()
		return _ruins_wall_material
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	var tile_scale := 1.0 / STONE_TILE_METERS
	mat.uv1_scale = Vector3(tile_scale, tile_scale, tile_scale)
	mat.roughness = 0.95
	mat.metallic = 0.0
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_ruins_wall_material = mat
	return _ruins_wall_material


## Build a procedural wall sized to a segment, with a matching collision body so it
## physically blocks movement (ruin walls are Impassable per the rulebook). The ruins use
## a textured stone material (see _get_ruins_wall_material).
func _create_procedural_wall(length_inches: float, height_inches: float) -> StaticBody3D:
	var target_length := length_inches * INCHES_TO_METERS
	var target_height := height_inches * INCHES_TO_METERS
	var thickness := WALL_THICKNESS_INCHES * INCHES_TO_METERS

	var body := StaticBody3D.new()
	body.add_to_group("terrain")
	body.add_to_group("terrain_piece")

	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(target_length, target_height, thickness)
	mesh_instance.mesh = box
	mesh_instance.material_override = _get_ruins_wall_material()
	# Box centered at half height so the bottom sits on the table surface.
	mesh_instance.position.y = target_height / 2.0 - Z_FIGHT_OFFSET
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	body.add_child(mesh_instance)

	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box.size
	collision.shape = shape
	collision.position.y = target_height / 2.0 - Z_FIGHT_OFFSET
	body.add_child(collision)

	return body


# ==============================================================================
# RUIN SHELL WALLS (per-role masonry panels, delivered from R2)
# ==============================================================================

## Switch the prop texture theme to the biome's set and rebuild walls + props in place.
## Called by table.set_biome; unknown biomes use the default (grassland) set.
func set_biome(biome_name: String) -> void:
	var theme: String = BIOME_PROP_THEMES.get(biome_name, "")
	var container_theme: String = BIOME_CONTAINER_THEMES.get(biome_name, "")
	if theme == _prop_theme and container_theme == _container_theme:
		return
	_prop_theme = theme
	_container_theme = container_theme
	# Allow fresh fetches for the new theme's panel sets, then re-render in place.
	_ruin_fetch_started = false
	_tree_fetch_started = false
	_container_fetch_started = false
	_hazard_fetch_started = false
	_lava_fetch_started = false
	_hazard_model_fetch_started.clear()
	if not _last_wall_segments.is_empty():
		update_wall_models(_last_wall_segments, _last_wall_table_size, _last_wall_rotation)
	if not _last_objects.is_empty():
		update_placed_objects(_last_objects, _last_obj_table_size, _last_obj_rotation)


## True once the full ruin panel set is cached locally (sync; no network access).
func _ruin_panels_ready() -> bool:
	return _ruins_library != null and _ruins_library.all_panels_cached(_prop_theme)


## Start the one-time async panel download. On success the last wall layout is rebuilt,
## upgrading the triplanar fallback walls to shells in place; on failure the flag resets
## so the next layout update retries (e.g. after the player comes back online).
func _request_ruin_panels() -> void:
	if _ruin_fetch_started or _ruins_library == null:
		return
	_ruin_fetch_started = true
	_fetch_ruin_panels()


func _fetch_ruin_panels() -> void:
	var ok: bool = await _ruins_library.ensure_all_panels(_prop_theme)
	if not ok:
		_ruin_fetch_started = false
		return
	if not _last_wall_segments.is_empty():
		update_wall_models(_last_wall_segments, _last_wall_table_size, _last_wall_rotation)


## Build one wall cell as a textured SHELL — front + back masonry quad, closed along the
## panel's real stone silhouette: stepped top caps + risers from the alpha profile, stone
## end faces at free wall ends, and reveal faces lining interior openings (gothic window
## lights, doorways). Collision stays a full-height Impassable box: the holes are visual
## only (OPR: ruin walls are Impassable). Look based on tools/render_ruin_walls.gd::_wall.
func _create_shell_wall(segment: Dictionary, length_inches: float, cap_neg_x: bool, cap_pos_x: bool) -> StaticBody3D:
	var width := length_inches * INCHES_TO_METERS
	var height := WALL_HEIGHT_INCHES * INCHES_TO_METERS
	var thickness := RUIN_SHELL_THICKNESS_INCHES * INCHES_TO_METERS

	var body := StaticBody3D.new()
	body.add_to_group("terrain")
	body.add_to_group("terrain_piece")

	var panel := _panel_for_segment(segment)
	var mirrored := panel.begins_with("crumble") and _crumble_needs_flip(segment)
	# Sub-3" free-wall segments show their matching horizontal slice of the panel so the
	# stone course scale + alignment stay identical to full segments (§6 gotcha #3).
	var u_width := length_inches / GRID_SIZE_INCHES
	var u_offset := 0.0
	if length_inches < GRID_SIZE_INCHES:
		u_offset = float(segment.get("sub_position", 0)) * u_width
	var face := _ruin_panel_material(panel, mirrored, u_width, u_offset)

	var y_mid := height / 2.0 - Z_FIGHT_OFFSET
	_add_shell_quad(body, Vector2(width, height), Vector3(0, y_mid, thickness / 2.0), Vector3.ZERO, face)
	_add_shell_quad(body, Vector2(width, height), Vector3(0, y_mid, -thickness / 2.0), Vector3.ZERO, face)
	_add_shell_caps(body, panel, mirrored, u_width, u_offset, width, height, thickness, cap_neg_x, cap_pos_x)
	_add_shell_reveals(body, panel, mirrored, u_width, u_offset, width, height, thickness)

	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(width, height, thickness)
	collision.shape = shape
	collision.position.y = y_mid
	body.add_child(collision)

	return body


## Close the shell from above along the panel's stone silhouette: per-strip top caps at
## the alpha-profile height (so crumble steps and knocked-out top courses are capped on
## the stones themselves — never a lid floating at full height), vertical risers closing
## every step, and a stone end face where a wall end is FREE (not continued by a
## neighbour or covered by a corner post).
func _add_shell_caps(body: Node3D, panel: String, mirrored: bool, u_width: float, u_offset: float, width: float, height: float, thickness: float, cap_neg_x: bool, cap_pos_x: bool) -> void:
	var profile := _ruin_panel_profile(panel)
	# Profile strips covering this wall's texture slice, mapped into local-x order.
	var strips: Array[Dictionary] = []
	for j in RUIN_CAP_STRIPS:
		var strip_u0 := float(j) / float(RUIN_CAP_STRIPS)
		var strip_u1 := float(j + 1) / float(RUIN_CAP_STRIPS)
		var lo := maxf(strip_u0, u_offset)
		var hi := minf(strip_u1, u_offset + u_width)
		if hi <= lo:
			continue
		var x0 := ((lo - u_offset) / u_width - 0.5) * width
		var x1 := ((hi - u_offset) / u_width - 0.5) * width
		if mirrored:
			var mirrored_x0 := -x1
			x1 = -x0
			x0 = mirrored_x0
		strips.append({"x0": x0, "x1": x1, "h": profile[j]})
	if strips.is_empty():
		return
	strips.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.x0 < b.x0)

	# Merge near-equal neighbours (stone-surface noise) so each painted step stays one
	# cap quad; the cap height hugs the LOWEST merged strip so it never floats.
	var runs: Array[Dictionary] = []
	for strip in strips:
		if not runs.is_empty() and absf(runs[-1].h - strip.h) < RUIN_CAP_MERGE_FRAC:
			runs[-1].x1 = strip.x1
			runs[-1].h = minf(runs[-1].h, strip.h)
			continue
		runs.append(strip.duplicate())

	var previous_h := 0.0  # ground level at the wall's -X start
	for i in runs.size():
		var run: Dictionary = runs[i]
		var run_w: float = run.x1 - run.x0
		if run.h > RUIN_MIN_CAP_FRAC and run_w > 0.001:
			var cap_mat := _ruin_panel_material("solid_a", false, u_width * run_w / width,
					u_offset + (run.x0 + width / 2.0) / width * u_width)
			_add_shell_quad(body, Vector2(run_w, thickness),
					Vector3((run.x0 + run.x1) / 2.0, run.h * height - Z_FIGHT_OFFSET, 0),
					Vector3(-PI / 2.0, 0, 0), cap_mat)
		# Riser at this run's leading edge; at the very start only when the end is free.
		if (i > 0 or cap_neg_x) and absf(run.h - previous_h) > RUIN_CAP_MERGE_FRAC:
			_add_shell_end_face(body, run.x0, minf(previous_h, run.h), maxf(previous_h, run.h),
					height, thickness, u_width, u_offset, width)
		previous_h = run.h
	if cap_pos_x and previous_h > RUIN_MIN_CAP_FRAC:
		_add_shell_end_face(body, runs[-1].x1, 0.0, previous_h, height, thickness, u_width, u_offset, width)


## One vertical stone face across the wall thickness (step riser, free end, window jamb).
func _add_shell_end_face(body: Node3D, x: float, lo_frac: float, hi_frac: float, height: float, thickness: float, u_width: float, u_offset: float, width: float) -> void:
	var face_h := (hi_frac - lo_frac) * height
	var face_u_width := u_width * thickness / width
	var face_u_offset := clampf(u_offset + (x + width / 2.0) / width * u_width - face_u_width / 2.0,
			0.0, 1.0 - face_u_width)
	var mat := _ruin_panel_material("solid_a", false, face_u_width, face_u_offset)
	_add_shell_quad(body, Vector2(thickness, face_h),
			Vector3(x, (lo_frac + hi_frac) / 2.0 * height - Z_FIGHT_OFFSET, 0),
			Vector3(0, PI / 2.0, 0), mat)


## Line interior see-through openings (gothic window lights, doorway slots) with stone
## reveal faces — jambs, head and sill — so the opening reads as a thick wall, not as a
## hollow two-plane shell.
func _add_shell_reveals(body: Node3D, panel: String, mirrored: bool, u_width: float, u_offset: float, width: float, height: float, thickness: float) -> void:
	for rect: Rect2 in _ruin_panel_hole_list(panel):
		var lo := maxf(rect.position.x, u_offset)
		var hi := minf(rect.end.x, u_offset + u_width)
		if hi <= lo:
			continue
		var x0 := ((lo - u_offset) / u_width - 0.5) * width
		var x1 := ((hi - u_offset) / u_width - 0.5) * width
		if mirrored:
			var mirrored_x0 := -x1
			x1 = -x0
			x0 = mirrored_x0
		var top_frac := 1.0 - rect.position.y
		var bottom_frac := 1.0 - rect.end.y
		# Jambs left/right.
		_add_shell_end_face(body, x0, bottom_frac, top_frac, height, thickness, u_width, u_offset, width)
		_add_shell_end_face(body, x1, bottom_frac, top_frac, height, thickness, u_width, u_offset, width)
		# Head + sill.
		var span := x1 - x0
		var cap_mat := _ruin_panel_material("solid_a", false, u_width * span / width,
				u_offset + (x0 + width / 2.0) / width * u_width)
		_add_shell_quad(body, Vector2(span, thickness),
				Vector3((x0 + x1) / 2.0, top_frac * height - Z_FIGHT_OFFSET, 0),
				Vector3(-PI / 2.0, 0, 0), cap_mat)
		_add_shell_quad(body, Vector2(span, thickness),
				Vector3((x0 + x1) / 2.0, bottom_frac * height + Z_FIGHT_OFFSET, 0),
				Vector3(-PI / 2.0, 0, 0), cap_mat)


## One face of a wall shell.
func _add_shell_quad(parent: Node3D, size: Vector2, pos: Vector3, rot: Vector3, mat: Material) -> void:
	var mesh_instance := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = size
	mesh_instance.mesh = quad
	mesh_instance.material_override = mat
	mesh_instance.position = pos
	mesh_instance.rotation = rot
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mesh_instance)


## Texture panel for a wall segment: crumble roles map 1:1 onto their texture; "full"
## cells (and role-less free walls / legacy saves) draw a deterministic random pick —
## seeded from the segment's stable cell identity so every client and every rebuild
## shows the same window/doorway (§6 gotcha #5; never a global RNG).
func _panel_for_segment(segment: Dictionary) -> String:
	var role: String = segment.get("role", "full")
	if role.begins_with("crumble"):
		return role
	var edge_cell: Vector2i = segment.get("edge_cell", Vector2i.ZERO)
	var edge_side: int = segment.get("edge_side", 0)
	var rng := RandomNumberGenerator.new()
	rng.seed = edge_cell.x * _RUIN_SEED_PRIME_X ^ edge_cell.y * _RUIN_SEED_PRIME_Y ^ edge_side * _RUIN_SEED_PRIME_SIDE
	var roll := rng.randf()
	if roll < RUIN_WINDOW_CHANCE:
		return "window"
	if roll < RUIN_OPENING_CHANCE:
		return "opening_a"
	return _RUIN_SOLID_PANELS[rng.randi() % _RUIN_SOLID_PANELS.size()]


## Cached alpha-top profile of a panel: RUIN_CAP_STRIPS height fractions (1.0 = full).
func _ruin_panel_profile(panel: String) -> PackedFloat32Array:
	var themed := _prop_theme + panel
	if _ruin_panel_profiles.has(themed):
		return _ruin_panel_profiles[themed]
	var tex: Texture2D = _ruins_library.get_texture(themed) if _ruins_library != null else null
	var profile := _alpha_top_profile(tex.get_image() if tex != null else null, RUIN_CAP_STRIPS)
	_ruin_panel_profiles[themed] = profile
	return profile


## Cached interior see-through openings of a panel (normalized texture-UV rects).
func _ruin_panel_hole_list(panel: String) -> Array[Rect2]:
	var themed := _prop_theme + panel
	if _ruin_panel_hole_rects.has(themed):
		return _ruin_panel_hole_rects[themed]
	var tex: Texture2D = _ruins_library.get_texture(themed) if _ruins_library != null else null
	var holes := _alpha_interior_holes(tex.get_image() if tex != null else null)
	_ruin_panel_hole_rects[themed] = holes
	return holes


## Top stone silhouette of a panel: for each of `strips` vertical strips, the fraction of
## the panel height (from the bottom) that is opaque, scanning columns from the top. The
## lowest column in a strip wins, so caps never float above missing stones. Panels
## without alpha yield 1.0 everywhere. Static so tests can feed synthetic images.
static func _alpha_top_profile(img: Image, strips: int) -> PackedFloat32Array:
	var profile := PackedFloat32Array()
	profile.resize(maxi(strips, 0))
	profile.fill(1.0)
	if img == null or strips <= 0:
		return profile
	var w := img.get_width()
	var h := img.get_height()
	if w <= 0 or h <= 0 or img.detect_alpha() == Image.ALPHA_NONE:
		return profile
	for j in strips:
		var x0 := int(j * w / float(strips))
		var x1 := maxi(x0 + 1, int((j + 1) * w / float(strips)))
		var deepest_top := 0
		var x := x0
		while x < x1:
			var first_opaque := h
			var y := 0
			while y < h:
				if img.get_pixel(x, y).a >= RUIN_ALPHA_OPAQUE:
					first_opaque = y
					break
				y += RUIN_PROFILE_SAMPLE_PX
			deepest_top = maxi(deepest_top, first_opaque)
			x += RUIN_PROFILE_SAMPLE_PX
		profile[j] = 1.0 - float(deepest_top) / float(h)
	return profile


## Interior see-through openings of a panel: connected transparent regions NOT touching
## the image border (border-connected damage is silhouette, handled by the caps), as
## normalized UV rects. Flood-filled on a RUIN_HOLE_GRID-wide downsample. Static for tests.
static func _alpha_interior_holes(img: Image) -> Array[Rect2]:
	var holes: Array[Rect2] = []
	if img == null:
		return holes
	var w := img.get_width()
	var h := img.get_height()
	if w <= 0 or h <= 0 or img.detect_alpha() == Image.ALPHA_NONE:
		return holes
	var gw := mini(RUIN_HOLE_GRID, w)
	var gh := maxi(1, int(gw * h / float(w)))
	var open := PackedByteArray()
	open.resize(gw * gh)
	for gy in gh:
		for gx in gw:
			var px := int((gx + 0.5) * w / float(gw))
			var py := int((gy + 0.5) * h / float(gh))
			open[gy * gw + gx] = 1 if img.get_pixel(px, py).a < RUIN_ALPHA_OPAQUE else 0
	var visited := PackedByteArray()
	visited.resize(gw * gh)
	for start in gw * gh:
		if open[start] == 0 or visited[start] == 1:
			continue
		# Flood fill one transparent component, tracking its bounds.
		var queue: Array[int] = [start]
		visited[start] = 1
		var min_x := gw
		var max_x := -1
		var min_y := gh
		var max_y := -1
		var cells := 0
		var touches_border := false
		while not queue.is_empty():
			var idx: int = queue.pop_back()
			var cx := idx % gw
			var cy := int(idx / float(gw))
			cells += 1
			min_x = mini(min_x, cx)
			max_x = maxi(max_x, cx)
			min_y = mini(min_y, cy)
			max_y = maxi(max_y, cy)
			if cx == 0 or cy == 0 or cx == gw - 1 or cy == gh - 1:
				touches_border = true
			for delta: Vector2i in _EDGE_DELTA:
				var nx := cx + delta.x
				var ny := cy + delta.y
				if nx < 0 or ny < 0 or nx >= gw or ny >= gh:
					continue
				var neighbour := ny * gw + nx
				if open[neighbour] == 1 and visited[neighbour] == 0:
					visited[neighbour] = 1
					queue.append(neighbour)
		if touches_border or cells < RUIN_HOLE_MIN_CELLS:
			continue
		# Pixel-precise refinement: the coarse grid is off by up to one cell (~1.5%), so
		# snap the bounds onto the actual alpha edges — reveals must sit flush with the
		# opening. Scans the coarse bbox expanded by one cell on each side.
		var cell_w := w / float(gw)
		var cell_h := h / float(gh)
		var px0 := maxi(0, int((min_x - 1) * cell_w))
		var px1 := mini(w - 1, int((max_x + 2) * cell_w))
		var py0 := maxi(0, int((min_y - 1) * cell_h))
		var py1 := mini(h - 1, int((max_y + 2) * cell_h))
		var fine_min_x := w
		var fine_max_x := -1
		var fine_min_y := h
		var fine_max_y := -1
		for py in range(py0, py1 + 1, RUIN_HOLE_REFINE_STEP_PX):
			for px in range(px0, px1 + 1, RUIN_HOLE_REFINE_STEP_PX):
				if img.get_pixel(px, py).a < RUIN_ALPHA_OPAQUE:
					fine_min_x = mini(fine_min_x, px)
					fine_max_x = maxi(fine_max_x, px)
					fine_min_y = mini(fine_min_y, py)
					fine_max_y = maxi(fine_max_y, py)
		if fine_max_x < fine_min_x:
			continue
		holes.append(Rect2(float(fine_min_x) / w, float(fine_min_y) / h,
				float(fine_max_x - fine_min_x + 1) / w, float(fine_max_y - fine_min_y + 1) / h))
	return holes


## The two grid corner points (grid-point space) bounding a wall segment's edge.
static func _wall_corner_points(segment: Dictionary) -> Array[Vector2i]:
	var edge_cell: Vector2i = segment.get("edge_cell", Vector2i.ZERO)
	match int(segment.get("edge_side", 0)):
		1:  # East edge
			return [Vector2i(edge_cell.x + 1, edge_cell.y), Vector2i(edge_cell.x + 1, edge_cell.y + 1)]
		2:  # South edge
			return [Vector2i(edge_cell.x, edge_cell.y + 1), Vector2i(edge_cell.x + 1, edge_cell.y + 1)]
		3:  # West edge
			return [edge_cell, Vector2i(edge_cell.x, edge_cell.y + 1)]
		_:  # North edge
			return [edge_cell, Vector2i(edge_cell.x + 1, edge_cell.y)]


## World placement of a wall segment: edge-centre position (y = 0), the wall's Y
## rotation, the unit direction from the wall toward its cell's interior and the unit
## direction along the wall (all grid-rotation aware). Empty if the segment lies
## outside the table. Shared by the walls and the war-torn fires so the two can never
## drift apart.
func _segment_world_placement(segment: Dictionary, grid_dims: Vector2i, cell_size_meters: float, rotation_rad: float, rot_deg: float, t_size: Vector2) -> Dictionary:
	var edge_cell: Vector2i = segment.get("edge_cell", Vector2i.ZERO)
	var edge_side: int = segment.get("edge_side", 0)
	var length_inches: float = segment.get("length_inches", GRID_SIZE_INCHES)
	var sub_position: int = segment.get("sub_position", 0)

	# Edge centre position
	var local_x := (edge_cell.x - grid_dims.x / 2.0 + 0.5) * cell_size_meters
	var local_z := (edge_cell.y - grid_dims.y / 2.0 + 0.5) * cell_size_meters
	var half_cell := cell_size_meters / 2.0
	var edge_offset := Vector2.ZERO
	var wall_y_rotation := 0.0
	match edge_side:
		0:  # Nord (top edge, -Z)
			edge_offset = Vector2(0, -half_cell)
			wall_y_rotation = 0.0
		1:  # Ost (right edge, +X)
			edge_offset = Vector2(half_cell, 0)
			wall_y_rotation = PI / 2.0
		2:  # Sued (bottom edge, +Z)
			edge_offset = Vector2(0, half_cell)
			wall_y_rotation = PI
		3:  # West (left edge, -X)
			edge_offset = Vector2(-half_cell, 0)
			wall_y_rotation = -PI / 2.0
	local_x += edge_offset.x
	local_z += edge_offset.y

	# Offset for 1"-segments within the 3"-edge (sub_position: 0=left, 1=center, 2=right)
	if length_inches < GRID_SIZE_INCHES:
		var sub_offset := (float(sub_position) - 1.0) * INCHES_TO_METERS
		match edge_side:
			0, 2:  # Horizontal edges
				local_x += sub_offset
			1, 3:  # Vertical edges
				local_z += sub_offset

	# Apply grid rotation; skip segments outside the table boundaries.
	var rotated_x := local_x * cos(rotation_rad) - local_z * sin(rotation_rad)
	var rotated_z := local_x * sin(rotation_rad) + local_z * cos(rotation_rad)
	if not _is_position_within_table(rotated_x, rotated_z, t_size):
		return {}

	var interior := -edge_offset.normalized()
	var along := Vector2(interior.y, -interior.x)
	return {
		"position": Vector3(rotated_x, 0.0, rotated_z),
		"y_rotation": wall_y_rotation - deg_to_rad(rot_deg),
		"interior_dir": Vector3(
				interior.x * cos(rotation_rad) - interior.y * sin(rotation_rad), 0.0,
				interior.x * sin(rotation_rad) + interior.y * cos(rotation_rad)),
		"along_dir": Vector3(
				along.x * cos(rotation_rad) - along.y * sin(rotation_rad), 0.0,
				along.x * sin(rotation_rad) + along.y * cos(rotation_rad)),
	}


# ==============================================================================
# WAR-TORN RUIN FIRES
# ==============================================================================

## Toggle the war-torn fires; rebuilds immediately for the current layout.
func set_fires_enabled(enabled: bool) -> void:
	if enabled == _fires_enabled:
		return
	_fires_enabled = enabled
	_rebuild_fires()


func get_fires_enabled() -> bool:
	return _fires_enabled


## World positions of the active fires, in the deterministic capped order (for the
## atmosphere layer's fire-crackle audio emitters).
func get_fire_positions() -> Array[Vector3]:
	return _fire_positions


## Deterministic per-segment fire pick from synced wall data — a FRESH salted RNG, so
## the panel RNG's draw sequence (windows/doorways) stays byte-identical (§6 gotcha #5).
static func segment_has_fire(segment: Dictionary) -> bool:
	return _fire_rng_for(segment).randf() < RUIN_FIRE_CHANCE


## The fire RNG for a segment: draw #1 decides has-fire, draws #2/#3 are the along-wall
## offset and the FireProp seed (consumed in _rebuild_fires).
static func _fire_rng_for(segment: Dictionary) -> RandomNumberGenerator:
	var edge_cell: Vector2i = segment.get("edge_cell", Vector2i.ZERO)
	var edge_side: int = segment.get("edge_side", 0)
	var rng := RandomNumberGenerator.new()
	rng.seed = edge_cell.x * _RUIN_SEED_PRIME_X ^ edge_cell.y * _RUIN_SEED_PRIME_Y \
			^ edge_side * _RUIN_SEED_PRIME_SIDE ^ _RUIN_SEED_SALT_FIRE
	return rng


## Rebuild the FireProp instances for the last wall layout. Sorted by segment identity
## so the light/crackle caps land on the same fires on every client; light and smoke
## are gated by the graphics quality tier (PERFORMANCE spawns nothing).
func _rebuild_fires() -> void:
	_clear_fire_instances()
	var tier: int = clampi(GraphicsSettings.current_preset, 0, FIRE_MAX_LIGHTS.size() - 1)
	if not _fires_enabled or _last_wall_segments.is_empty() \
			or tier == GraphicsSettings.QualityPreset.PERFORMANCE:
		fires_rebuilt.emit()
		return

	# Same grid math as update_wall_models (kept in lockstep via the shared placement).
	var cell_size_meters := GRID_SIZE_INCHES * INCHES_TO_METERS
	var width_inches := _last_wall_table_size.x * 12.0
	var height_inches := _last_wall_table_size.y * 12.0
	var diagonal := sqrt(width_inches * width_inches + height_inches * height_inches)
	var grid_size := int(ceil(diagonal / GRID_SIZE_INCHES))
	if grid_size % 2 != 0:
		grid_size += 1
	var grid_dims := Vector2i(grid_size, grid_size)
	var rotation_rad := deg_to_rad(_last_wall_rotation)

	var fire_segments: Array[Dictionary] = []
	for segment in _last_wall_segments:
		if segment_has_fire(segment):
			fire_segments.append(segment)
	fire_segments.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var cell_a: Vector2i = a.get("edge_cell", Vector2i.ZERO)
		var cell_b: Vector2i = b.get("edge_cell", Vector2i.ZERO)
		if cell_a.x != cell_b.x:
			return cell_a.x < cell_b.x
		if cell_a.y != cell_b.y:
			return cell_a.y < cell_b.y
		return int(a.get("edge_side", 0)) < int(b.get("edge_side", 0)))

	var with_smoke: bool = tier >= GraphicsSettings.QualityPreset.MEDIUM
	var max_lights: int = FIRE_MAX_LIGHTS[tier]
	for segment in fire_segments:
		var placement := _segment_world_placement(segment, grid_dims, cell_size_meters,
				rotation_rad, _last_wall_rotation, _last_wall_table_size)
		if placement.is_empty():
			continue
		var rng := _fire_rng_for(segment)
		rng.randf()  # draw #1: the has-fire decision (already consumed semantically)
		var length_m: float = segment.get("length_inches", GRID_SIZE_INCHES) * INCHES_TO_METERS
		var along: float = rng.randf_range(-FIRE_ALONG_WALL_MAX_FRAC, FIRE_ALONG_WALL_MAX_FRAC) * length_m
		var fire_seed := rng.randi()

		var fire := FireProp.new()
		fire.setup(fire_seed, _fire_instances.size() < max_lights, with_smoke)
		var base: Vector3 = placement["position"]
		fire.position = base + placement["interior_dir"] * FIRE_INSET_FROM_WALL_M \
				+ placement["along_dir"] * along
		add_child(fire)
		_fire_instances.append(fire)
		_fire_positions.append(fire.position)
	fires_rebuilt.emit()


# ==============================================================================
# RUBBLE AT RUIN WALL BASES
# ==============================================================================

## Deterministic local rubble placements for one wall segment: positions in the
## WALL's local frame (x along the wall, z across it, y = embed height), scale and
## rotation per stone. Density is highest at the wall face and tapers quadratically
## to RUBBLE_MAX_DIST_M. Static + pure for tests.
static func rubble_placements_for(segment: Dictionary, count: int) -> Array[Transform3D]:
	var placements: Array[Transform3D] = []
	if count <= 0:
		return placements
	var edge_cell: Vector2i = segment.get("edge_cell", Vector2i.ZERO)
	var edge_side: int = segment.get("edge_side", 0)
	var rng := RandomNumberGenerator.new()
	rng.seed = edge_cell.x * _RUIN_SEED_PRIME_X ^ edge_cell.y * _RUIN_SEED_PRIME_Y \
			^ edge_side * _RUIN_SEED_PRIME_SIDE ^ _RUIN_SEED_SALT_RUBBLE
	var length_m: float = segment.get("length_inches", GRID_SIZE_INCHES) * INCHES_TO_METERS
	var half_wall := RUIN_SHELL_THICKNESS_INCHES * INCHES_TO_METERS / 2.0
	for _i in count:
		var along := rng.randf_range(-0.5, 0.5) * length_m
		# Quadratic falloff: squaring a uniform draw clusters distances at the wall.
		var dist := rng.randf() * rng.randf() * RUBBLE_MAX_DIST_M
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var stone := rng.randf_range(RUBBLE_STONE_MIN_M, RUBBLE_STONE_MAX_M)
		var basis := Basis.from_euler(Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU))
		# Brick-format fragments (the rubble's source IS the wall): elongated boxes
		# with flat-ish height, randomly tumbled.
		basis = basis.scaled(Vector3(stone * rng.randf_range(1.0, 2.0),
				stone * rng.randf_range(0.45, 0.75), stone * rng.randf_range(0.6, 1.1)))
		var origin := Vector3(along, stone * RUBBLE_EMBED_FRAC, side * (half_wall + dist))
		placements.append(Transform3D(basis, origin))
	return placements


## Rebuild the rubble MultiMesh for the last wall layout (one draw call total).
func _rebuild_rubble() -> void:
	if _rubble_instance != null:
		_rubble_instance.queue_free()
		_rubble_instance = null
	var tier: int = clampi(GraphicsSettings.current_preset, 0, RUBBLE_STONES_PER_SEGMENT.size() - 1)
	var per_segment: int = RUBBLE_STONES_PER_SEGMENT[tier]
	if per_segment <= 0 or _last_wall_segments.is_empty():
		return

	# Same grid math as update_wall_models (shared placement helper).
	var cell_size_meters := GRID_SIZE_INCHES * INCHES_TO_METERS
	var width_inches := _last_wall_table_size.x * 12.0
	var height_inches := _last_wall_table_size.y * 12.0
	var diagonal := sqrt(width_inches * width_inches + height_inches * height_inches)
	var grid_size := int(ceil(diagonal / GRID_SIZE_INCHES))
	if grid_size % 2 != 0:
		grid_size += 1
	var grid_dims := Vector2i(grid_size, grid_size)
	var rotation_rad := deg_to_rad(_last_wall_rotation)

	var transforms: Array[Transform3D] = []
	for segment in _last_wall_segments:
		var placement := _segment_world_placement(segment, grid_dims, cell_size_meters,
				rotation_rad, _last_wall_rotation, _last_wall_table_size)
		if placement.is_empty():
			continue
		var wall_xform := Transform3D(Basis.from_euler(Vector3(0.0, placement["y_rotation"], 0.0)),
				placement["position"])
		for local in rubble_placements_for(segment, per_segment):
			transforms.append(wall_xform * local)
	if transforms.is_empty():
		return

	var color_rng := RandomNumberGenerator.new()
	color_rng.seed = _RUIN_SEED_SALT_RUBBLE

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = _rubble_stone_mesh()
	multimesh.instance_count = transforms.size()
	for i in transforms.size():
		multimesh.set_instance_transform(i, transforms[i])
		# Brightness jitter over the masonry texture (alpha untouched).
		var jitter := color_rng.randf_range(0.65, 1.0)
		multimesh.set_instance_color(i, Color(jitter, jitter, jitter, 1.0))

	_rubble_instance = MultiMeshInstance3D.new()
	_rubble_instance.multimesh = multimesh
	_rubble_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_rubble_instance)


## Shared brick fragment: an angular box wearing the theme's masonry panel in WORLD
## triplanar projection — each fragment samples a different patch automatically.
## Falls back to the bundled triplanar wall texture (or flat grey) while the themed
## panel is not cached yet.
func _rubble_stone_mesh() -> Mesh:
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	mat.metallic = 0.0
	var tex: Texture2D = null
	if _ruins_library != null:
		tex = _ruins_library.get_texture(_prop_theme + "solid_a")
	if tex == null and ResourceLoader.exists(RUINS_WALL_TEX_PATH):
		tex = load(RUINS_WALL_TEX_PATH) as Texture2D
	if tex != null:
		mat.albedo_texture = tex
		mat.uv1_triplanar = true
		mat.uv1_world_triplanar = true
		var tile := 1.0 / RUBBLE_TEXTURE_TILE_M
		mat.uv1_scale = Vector3(tile, tile, tile)
	else:
		mat.albedo_color = Color(0.45, 0.43, 0.4)
	box.material = mat
	return box


func _clear_fire_instances() -> void:
	for fire in _fire_instances:
		if is_instance_valid(fire):
			fire.queue_free()
	_fire_instances.clear()
	_fire_positions.clear()


func _on_graphics_settings_applied(_preset_name: String) -> void:
	if _fires_enabled:
		_rebuild_fires()
	_rebuild_rubble()


## A crumble panel descends toward its +U (right) edge. Mirror U iff the quad's local +U
## (per _RUIN_QUAD_U_DIR) does not already point at the arm's free end (taper_dir, emitted
## by TerrainPrefabs and transformed with the piece). Unknown taper — legacy saves or
## hand-drawn walls — keeps the unmirrored panel (§6 gotcha #1).
func _crumble_needs_flip(segment: Dictionary) -> bool:
	var taper_dir: int = segment.get("taper_dir", -1)
	if taper_dir < 0 or taper_dir >= _RUIN_QUAD_U_DIR.size():
		return false
	var edge_side: int = segment.get("edge_side", 0)
	if edge_side < 0 or edge_side >= _RUIN_QUAD_U_DIR.size():
		return false
	return _RUIN_QUAD_U_DIR[edge_side] != taper_dir


## Lit material for a ruin panel, cached by (panel | mirror | U-slice). Panels keep their
## authored 0..1 UVs (bottom-anchored, shared masonry scale — §6 gotcha #3); holed panels
## use alpha scissor whose hard edges survive the runtime WebP decode (§6 gotcha #4). All
## panels render double-sided: the shell's back quad shares the front's orientation, so
## its back face IS the wall's correct world-space appearance from behind — and the orbit
## camera can look at every wall from both sides.
func _ruin_panel_material(panel: String, mirrored: bool, u_width: float, u_offset: float) -> Material:
	var themed := _prop_theme + panel
	var key := "%s|%s|%.3f|%.3f" % [themed, mirrored, u_width, u_offset]
	if _ruin_panel_materials.has(key):
		return _ruin_panel_materials[key]
	var tex: Texture2D = _ruins_library.get_texture(themed)
	if tex == null:
		# Mid-download / decode-failure safety net; intentionally not cached so a later
		# rebuild can pick up the real panel.
		return _get_ruins_wall_material()
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.roughness = RUIN_PANEL_ROUGHNESS
	mat.metallic = 0.0
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	# Panels are 0..1-UV one-shot images, never tiled. Repeat would wrap-bleed the
	# opposite texture edge at u=1.0 under anisotropic filtering — full-height stone
	# slivers at the free end of (mirrored) crumble walls.
	mat.texture_repeat = false
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var normal_tex: Texture2D = _ruins_library.get_texture(_prop_theme + "normal")
	if normal_tex != null:
		mat.normal_enabled = true
		mat.normal_texture = normal_tex
		mat.normal_scale = RUIN_NORMAL_STRENGTH
	if panel != "solid_a" and panel != "solid_b":
		# Everything else has knocked-out stones (RGBA): top damage, doorway, crumble,
		# window — exactly the reference renderer's use_alpha rule.
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		mat.alpha_scissor_threshold = RUIN_ALPHA_SCISSOR_THRESHOLD
	# Map the quad's 0..1 U onto [u_offset, u_offset + u_width], mirrored when the
	# crumble must step the other way (u' = (u_offset + u_width) - u * u_width).
	var u_scale := (-u_width) if mirrored else u_width
	var u_off := (u_offset + u_width) if mirrored else u_offset
	mat.uv1_scale = Vector3(u_scale, 1.0, 1.0)
	mat.uv1_offset = Vector3(u_off, 0.0, 0.0)
	_ruin_panel_materials[key] = mat
	return mat


## Clear all wall instances
func _clear_wall_instances() -> void:
	for instance in _wall_instances:
		if is_instance_valid(instance):
			instance.queue_free()
	_wall_instances.clear()


# ==============================================================================
# PLACED OBJECTS: TREES + CONTAINERS (S9)
# ==============================================================================

## Update placed object instances (trees and containers)
## @param objects: Array of Dictionaries {object_key, cell, offset, object_type}
## @param t_size: Table size in feet
## @param rotation: Grid rotation in degrees
func update_placed_objects(objects: Array, t_size: Vector2, rot_deg: float) -> void:
	_clear_placed_objects()

	# Remember the layout so a finishing panel download can upgrade fallback trees in
	# place; start the one-time fetch as soon as a map actually shows trees.
	_last_objects = objects
	_last_obj_table_size = t_size
	_last_obj_rotation = rot_deg
	var use_tree_panels := _tree_panels_ready() or _tree_models_ready()
	var use_container_panels := _container_panels_ready()
	var use_hazard_panels := _hazard_panels_ready()
	# Biomes with a 3D dangerous-terrain prop (volcanic lava crater / alien-jungle carnivore
	# plant) render their own GLB instead of mines and show NO warning signs, so they fetch
	# the model GLB (+ the lava texture for volcanic) rather than the mine/sign panel set.
	var hazard_model: String = BIOME_HAZARD_MODELS.get(_prop_theme, "")
	_crater_positions.clear()
	for obj in objects:
		var obj_type: String = obj.get("object_type", "tree")
		if obj_type == "tree" and not (_tree_panels_ready() and _tree_models_ready()):
			_request_tree_panels()
		elif obj_type == "container" and not use_container_panels:
			_request_container_panels()
		elif obj_type == "mine" and hazard_model != "":
			if not _hazard_model_ready(hazard_model):
				_request_hazard_model(hazard_model)
			# Volcanic also fetches the flat lava texture as a fallback while the GLB loads.
			if _prop_theme == "volcanic_" and not _lava_panel_ready():
				_request_lava_panel()
		elif (obj_type == "mine" or obj_type == "warning_sign") and not use_hazard_panels \
				and hazard_model == "":
			_request_hazard_panels()

	if objects.is_empty():
		return

	var cell_size_meters := GRID_SIZE_INCHES * INCHES_TO_METERS

	# Compute grid dimensions
	var width_inches := t_size.x * 12.0
	var height_inches := t_size.y * 12.0
	var diagonal := sqrt(width_inches * width_inches + height_inches * height_inches)
	var grid_size := int(ceil(diagonal / GRID_SIZE_INCHES))
	if grid_size % 2 != 0:
		grid_size += 1
	var grid_dims := Vector2i(grid_size, grid_size)

	var rotation_rad := deg_to_rad(rot_deg)

	for obj in objects:
		var cell: Vector2i = obj.get("cell", Vector2i.ZERO)
		var offset: Vector2 = obj.get("offset", Vector2(0.5, 0.5))
		var object_type: String = obj.get("object_type", "tree")

		# Calculate world position
		var local_x := (cell.x - grid_dims.x / 2.0 + offset.x) * cell_size_meters
		var local_z := (cell.y - grid_dims.y / 2.0 + offset.y) * cell_size_meters

		# Apply grid rotation
		var rotated_x := local_x * cos(rotation_rad) - local_z * sin(rotation_rad)
		var rotated_z := local_x * sin(rotation_rad) + local_z * cos(rotation_rad)

		# Skip objects outside table boundaries
		if not _is_position_within_table(rotated_x, rotated_z, t_size):
			continue

		# Build the prop for this object type (trees, containers and minefield props
		# upgrade to their textured versions once cached; the rest stays procedural).
		# Textured props set their own deterministic facing.
		var model: Node3D
		var handles_own_facing := false
		if object_type == "tree" and use_tree_panels:
			model = _create_textured_tree(obj)
			handles_own_facing = true
		elif object_type == "container" and use_container_panels:
			model = _create_textured_container(obj)
		elif object_type == "mine" and hazard_model != "":
			# Biomes with a 3D hazard prop (volcanic lava crater / jungle carnivore plant):
			# thin the dense mine layout to a non-overlapping few (~3-5 per field); skip
			# slots that would overlap an already-placed one.
			if _crater_spot_free(rotated_x, rotated_z):
				_crater_positions.append(Vector2(rotated_x, rotated_z))
				model = _create_lava_pool(obj) if _prop_theme == "volcanic_" else _create_carnivore_plant(obj)
				handles_own_facing = true
			# else: model stays null -> this overlapping mine slot is skipped
		elif object_type == "warning_sign" and hazard_model != "":
			# No warning signs in biomes with a self-evident 3D hazard prop.
			model = null
		elif object_type == "mine" and use_hazard_panels:
			model = _create_textured_mine(obj)
			handles_own_facing = true
		elif object_type == "warning_sign" and use_hazard_panels:
			model = _create_textured_warning_sign(obj)
			handles_own_facing = true
		else:
			model = _get_object_model(object_type)
		if not model:
			continue

		model.position.x = rotated_x
		model.position.z = rotated_z
		if object_type == "container":
			# Blockers align to the grid + the piece's own rotation so the 6x3 box
			# fits its (possibly rotated) footprint.
			var angle_deg: float = obj.get("angle_deg", 0.0)
			model.rotation.y = -rotation_rad + deg_to_rad(angle_deg)
		elif not handles_own_facing:
			model.rotation.y = randf() * TAU
		add_child(model)
		_object_instances.append(model)


## Build a procedural holographic prop for a placed object type.
## "tree"/"mine"/"puddle" are decorative (no collision); "container" blocks like a wall.
func _get_object_model(object_type: String) -> Node3D:
	match object_type:
		"container":
			return _create_procedural_container()
		"tree":
			return _create_procedural_tree()
		"mine":
			return _create_procedural_mine()
		"warning_sign":
			return _create_procedural_sign()
		"puddle":
			return _create_procedural_puddle()
	return null


## Blocker / container: a solid 6x3 box that blocks movement (Impassable + Blocking).
func _create_procedural_container() -> StaticBody3D:
	var length := CONTAINER_LENGTH_INCHES * INCHES_TO_METERS
	var depth := CONTAINER_DEPTH_INCHES * INCHES_TO_METERS
	var height := CONTAINER_HEIGHT_INCHES * INCHES_TO_METERS

	var body := StaticBody3D.new()
	body.add_to_group("terrain")
	body.add_to_group("terrain_piece")

	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(length, height, depth)
	mesh_instance.mesh = box
	mesh_instance.material_override = TerrainHologram.make_material()
	mesh_instance.position.y = height / 2.0 - Z_FIGHT_OFFSET
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(mesh_instance)

	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box.size
	collision.shape = shape
	collision.position.y = height / 2.0 - Z_FIGHT_OFFSET
	body.add_child(collision)

	return body


## Forest tree: trunk + conical crown. Decorative only — forests stay passable.
func _create_procedural_tree() -> Node3D:
	var root := Node3D.new()
	var trunk_height := TREE_TRUNK_HEIGHT_INCHES * INCHES_TO_METERS
	var crown_height := TREE_CROWN_HEIGHT_INCHES * INCHES_TO_METERS

	var trunk := MeshInstance3D.new()
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = TREE_TRUNK_RADIUS_INCHES * INCHES_TO_METERS
	trunk_mesh.bottom_radius = TREE_TRUNK_RADIUS_INCHES * INCHES_TO_METERS
	trunk_mesh.height = trunk_height
	trunk.mesh = trunk_mesh
	trunk.material_override = TerrainHologram.make_material()
	trunk.position.y = trunk_height / 2.0 - Z_FIGHT_OFFSET
	trunk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(trunk)

	var crown := MeshInstance3D.new()
	var crown_mesh := CylinderMesh.new()
	crown_mesh.top_radius = 0.0
	crown_mesh.bottom_radius = TREE_CROWN_RADIUS_INCHES * INCHES_TO_METERS
	crown_mesh.height = crown_height
	crown.mesh = crown_mesh
	crown.material_override = TerrainHologram.make_material()
	crown.position.y = trunk_height + crown_height / 2.0 - Z_FIGHT_OFFSET
	crown.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(crown)

	return root


# ==============================================================================
# TEXTURED TREES (deciduous billboard panels, delivered from R2)
# ==============================================================================

## True once the full tree panel set is cached locally (sync; no network access).
func _tree_panels_ready() -> bool:
	return _trees_library != null and _trees_library.all_panels_cached(_prop_theme)


## True once the textured tree GLBs are cached locally (sync; no network access).
func _tree_models_ready() -> bool:
	return _trees_library != null and _trees_library.all_models_cached(_prop_theme)


## Start the one-time async panel download. On success the last object layout is
## rebuilt, upgrading the procedural fallback trees in place; on failure the flag
## resets so the next layout update retries.
func _request_tree_panels() -> void:
	if _tree_fetch_started or _trees_library == null:
		return
	_tree_fetch_started = true
	_fetch_tree_panels()


## Progressive enhancement: the small billboard panels land first (trees pop in as
## cutouts), then the textured GLBs upgrade them to volumetric models in place.
func _fetch_tree_panels() -> void:
	var panels_ok: bool = await _trees_library.ensure_all_panels(_prop_theme)
	if panels_ok and not _last_objects.is_empty():
		update_placed_objects(_last_objects, _last_obj_table_size, _last_obj_rotation)
	var models_ok: bool = await _trees_library.ensure_all_models(_prop_theme)
	if models_ok and not _last_objects.is_empty():
		update_placed_objects(_last_objects, _last_obj_table_size, _last_obj_rotation)
	if not panels_ok and not models_ok:
		_tree_fetch_started = false  # offline — retry on the next layout update


## A deciduous tree, volumetric when available: the textured TRELLIS GLB of the variant
## (a real 3D model, like a model-railroad tree), else two crossed alpha-scissor quads
## plus a bird's-eye crown cap, else the procedural fallback. Variant, size (75-125%)
## and facing are seeded from the object's stable cell+offset identity so every client
## and rebuild shows the same tree. Decorative only — forests stay passable.
func _create_textured_tree(obj: Dictionary) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = _placed_object_seed(obj)
	var variants: Array[String] = TreesLibrary.TREE_VARIANTS
	var panel: String = _prop_theme + variants[rng.randi() % variants.size()]
	var tree_scale := rng.randf_range(TREE_SCALE_MIN, TREE_SCALE_MAX)
	var height := TREE_HEIGHT_INCHES * INCHES_TO_METERS * tree_scale
	var facing := rng.randf() * TAU

	# Volumetric tree: instance the variant's GLB, scaled so the model stands on the
	# table at the same height the billboard would have.
	var scene: PackedScene = _trees_library.get_model_scene(panel)
	if scene != null:
		var model := scene.instantiate() as Node3D
		if model != null:
			var aabb := _model_space_aabb(model)
			# Reject degenerate flat "relief" reconstructions (TRELLIS occasionally
			# fails to infer depth) — the billboard tier looks far better than a slab.
			var depth_ok := aabb.size.y > 0.001 \
					and minf(aabb.size.x, aabb.size.z) / aabb.size.y >= TREE_MODEL_MIN_DEPTH_RATIO
			if depth_ok:
				var fit := height / aabb.size.y
				model.scale = Vector3(fit, fit, fit)
				model.position.y = -aabb.position.y * fit
				var model_root := Node3D.new()
				model_root.add_child(model)
				model_root.rotation.y = facing
				return model_root
			model.free()

	var tex: Texture2D = _trees_library.get_texture(panel)
	if tex == null:
		return _create_procedural_tree()  # mid-download / decode-failure safety net

	var width := height * float(tex.get_width()) / float(tex.get_height())

	var root := Node3D.new()
	var side_mat := _tree_panel_material(panel)
	for i in 2:
		var quad_instance := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(width, height)
		quad_instance.mesh = quad
		quad_instance.material_override = side_mat
		quad_instance.position.y = height / 2.0
		quad_instance.rotation.y = i * PI / 2.0
		quad_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		root.add_child(quad_instance)

	var top_tex: Texture2D = _trees_library.get_texture(panel + "_top")
	if top_tex != null:
		var cap_instance := MeshInstance3D.new()
		var cap := QuadMesh.new()
		cap.size = Vector2(width, width * float(top_tex.get_height()) / float(top_tex.get_width()))
		cap_instance.mesh = cap
		cap_instance.material_override = _tree_panel_material(panel + "_top")
		cap_instance.position.y = height * TREE_CROWN_CAP_FRAC
		cap_instance.rotation.x = -PI / 2.0
		cap_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		root.add_child(cap_instance)

	root.rotation.y = facing
	return root


## Combined local-space AABB of all meshes under `node` (transforms accumulated), used
## to scale a runtime GLB tree to its target height and stand it on the table.
static func _model_space_aabb(node: Node3D) -> AABB:
	return _merge_mesh_aabbs(node, Transform3D.IDENTITY, AABB(), true)[1]


## Uniformly scale a runtime GLB so its widest horizontal extent fits `target_diameter_m`,
## and drop it so its base sits on the table (y = 0). For wide-and-flat props like the
## lava crater (scaled by footprint, not height, unlike the trees).
func _fit_to_footprint(node: Node3D, target_diameter_m: float) -> void:
	var aabb := _model_space_aabb(node)
	var widest := maxf(aabb.size.x, aabb.size.z)
	if widest < 0.0001:
		return
	var fit := target_diameter_m / widest
	node.scale = Vector3(fit, fit, fit)
	node.position.y = -aabb.position.y * fit


static func _merge_mesh_aabbs(node: Node, xform: Transform3D, acc: AABB, first: bool) -> Array:
	var node_xform := xform
	if node is Node3D:
		node_xform = xform * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mesh_aabb: AABB = node_xform * (node as MeshInstance3D).mesh.get_aabb()
		acc = mesh_aabb if first else acc.merge(mesh_aabb)
		first = false
	for child: Node in node.get_children():
		var result := _merge_mesh_aabbs(child, node_xform, acc, first)
		first = result[0]
		acc = result[1]
	return [first, acc]


## Lit cutout material for a tree panel, cached per panel (0..1 UVs, never tiled).
func _tree_panel_material(panel: String) -> Material:
	if _tree_panel_materials.has(panel):
		return _tree_panel_materials[panel]
	var tex: Texture2D = _trees_library.get_texture(panel)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.roughness = 0.95
	mat.metallic = 0.0
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mat.texture_repeat = false
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = RUIN_ALPHA_SCISSOR_THRESHOLD
	_tree_panel_materials[panel] = mat
	return mat


## Stable per-object seed from the synced placed-object data (cell + sub-cell offset),
## so visual draws (tree variant/size, container colourway) are identical on every
## client (never a global RNG).
func _placed_object_seed(obj: Dictionary) -> int:
	var cell: Vector2i = obj.get("cell", Vector2i.ZERO)
	var offset: Vector2 = obj.get("offset", Vector2(0.5, 0.5))
	return cell.x * _RUIN_SEED_PRIME_X ^ cell.y * _RUIN_SEED_PRIME_Y \
			^ int(offset.x * 4096.0) * _RUIN_SEED_PRIME_SIDE ^ int(offset.y * 4096.0)


# ==============================================================================
# TEXTURED CONTAINERS (shipping-container faces, delivered from R2)
# ==============================================================================

## True once the container face set is cached locally (sync; no network access).
func _container_panels_ready() -> bool:
	return _containers_library != null and _containers_library.all_panels_cached(_container_theme)


## Start the one-time async panel download; the last object layout rebuilds on success.
func _request_container_panels() -> void:
	if _container_fetch_started or _containers_library == null:
		return
	_container_fetch_started = true
	_fetch_container_panels()


func _fetch_container_panels() -> void:
	var ok: bool = await _containers_library.ensure_all_panels(_container_theme)
	if not ok:
		_container_fetch_started = false
		return
	if not _last_objects.is_empty():
		update_placed_objects(_last_objects, _last_obj_table_size, _last_obj_rotation)


## A blocker as a textured shipping container: a 6x3x2.5" box built from quads wearing
## the corrugated side / cargo-door end / roof faces, in a colourway seeded from the
## object's stable identity. Collision stays the full Impassable box.
func _create_textured_container(obj: Dictionary) -> StaticBody3D:
	var length := CONTAINER_LENGTH_INCHES * INCHES_TO_METERS
	var depth := CONTAINER_DEPTH_INCHES * INCHES_TO_METERS
	var height := CONTAINER_HEIGHT_INCHES * INCHES_TO_METERS

	var rng := RandomNumberGenerator.new()
	rng.seed = _placed_object_seed(obj)
	var colourways: Array[String] = ContainersLibrary.COLOURWAYS
	var colourway: String = _container_theme + colourways[rng.randi() % colourways.size()]
	var side_mat := _container_panel_material(colourway + "_side")
	var end_mat := _container_panel_material(colourway + "_end")
	var top_mat := _container_panel_material(colourway + "_top")
	if side_mat == null or end_mat == null or top_mat == null:
		return _create_procedural_container()  # mid-download safety net

	var body := StaticBody3D.new()
	body.add_to_group("terrain")
	body.add_to_group("terrain_piece")

	# Each face is rotated so its normal points OUTWARD: container materials keep
	# backface culling (correct sun shading), unlike the cull-disabled wall shells.
	var y_mid := height / 2.0 - Z_FIGHT_OFFSET
	_add_shell_quad(body, Vector2(length, height), Vector3(0, y_mid, depth / 2.0), Vector3.ZERO, side_mat)
	_add_shell_quad(body, Vector2(length, height), Vector3(0, y_mid, -depth / 2.0), Vector3(0, PI, 0), side_mat)
	_add_shell_quad(body, Vector2(depth, height), Vector3(length / 2.0, y_mid, 0), Vector3(0, PI / 2.0, 0), end_mat)
	_add_shell_quad(body, Vector2(depth, height), Vector3(-length / 2.0, y_mid, 0), Vector3(0, -PI / 2.0, 0), end_mat)
	_add_shell_quad(body, Vector2(length, depth), Vector3(0, height - Z_FIGHT_OFFSET, 0), Vector3(-PI / 2.0, 0, 0), top_mat)

	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(length, height, depth)
	collision.shape = shape
	collision.position.y = y_mid
	body.add_child(collision)

	return body


## Lit material for a container face, cached per panel (full-bleed RGB, never tiled).
## Returns null while the panel is not cached/decodable so the caller keeps a fallback.
func _container_panel_material(panel: String) -> Material:
	if _container_panel_materials.has(panel):
		return _container_panel_materials[panel]
	var tex: Texture2D = _containers_library.get_texture(panel)
	if tex == null:
		return null
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.roughness = 0.85
	mat.metallic = 0.0
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mat.texture_repeat = false
	_container_panel_materials[panel] = mat
	return mat


# ==============================================================================
# TEXTURED MINEFIELD (anti-tank mines + warning signs, delivered from R2)
# ==============================================================================

## True once the minefield texture set is cached locally (sync; no network access).
func _hazard_panels_ready() -> bool:
	return _hazards_library != null and _hazards_library.all_panels_cached()


## Start the one-time async panel download; the last object layout rebuilds on success.
func _request_hazard_panels() -> void:
	if _hazard_fetch_started or _hazards_library == null:
		return
	_hazard_fetch_started = true
	_fetch_hazard_panels()


func _fetch_hazard_panels() -> void:
	var ok: bool = await _hazards_library.ensure_all_panels()
	if not ok:
		_hazard_fetch_started = false
		return
	if not _last_objects.is_empty():
		update_placed_objects(_last_objects, _last_obj_table_size, _last_obj_rotation)


## True once the volcanic lava-pool texture is cached (sync; no network access). Kept off
## RUNTIME_PANELS so it never gates the grassland mine/sign set.
func _lava_panel_ready() -> bool:
	return _hazards_library != null \
			and not _hazards_library.get_cached_path(LAVA_PANEL).is_empty()


## Start the one-time async lava-texture download; the layout rebuilds (textured) on success.
func _request_lava_panel() -> void:
	if _lava_fetch_started or _hazards_library == null:
		return
	_lava_fetch_started = true
	_fetch_lava_panel()


func _fetch_lava_panel() -> void:
	var ok: bool = await _hazards_library.ensure_panel(LAVA_PANEL)
	if not ok:
		_lava_fetch_started = false
		return
	if not _last_objects.is_empty():
		update_placed_objects(_last_objects, _last_obj_table_size, _last_obj_rotation)


## True once the 3D lava-crater GLB is cached (sync; no network access).
func _hazard_model_ready(model_name: String) -> bool:
	return _hazards_library != null \
			and not _hazards_library.get_cached_model_path(model_name).is_empty()


## Start the one-time async hazard-GLB download (per model name); rebuilds the layout on
## success so the prop upgrades to 3D in place.
func _request_hazard_model(model_name: String) -> void:
	if _hazard_model_fetch_started.get(model_name, false) or _hazards_library == null:
		return
	_hazard_model_fetch_started[model_name] = true
	_fetch_hazard_model(model_name)


func _fetch_hazard_model(model_name: String) -> void:
	var ok: bool = await _hazards_library.ensure_model(model_name)
	if not ok:
		_hazard_model_fetch_started[model_name] = false
		return
	if not _last_objects.is_empty():
		update_placed_objects(_last_objects, _last_obj_table_size, _last_obj_rotation)


## An anti-tank mine: a flat olive-drab disc with the pressure-plate texture laid on
## top (keyed alpha), facing seeded from the object's identity. Decorative only —
## dangerous terrain stays passable (OPR: Dangerous, not Impassable).
func _create_textured_mine(obj: Dictionary) -> Node3D:
	var top_tex: Texture2D = _hazards_library.get_texture("mine_top")
	if top_tex == null:
		return _create_procedural_mine()  # mid-download safety net
	var radius := MINE_DISC_RADIUS_INCHES * INCHES_TO_METERS
	var height := MINE_DISC_HEIGHT_INCHES * INCHES_TO_METERS

	var rng := RandomNumberGenerator.new()
	rng.seed = _placed_object_seed(obj)

	var root := Node3D.new()
	var disc := MeshInstance3D.new()
	var disc_mesh := CylinderMesh.new()
	disc_mesh.top_radius = radius
	disc_mesh.bottom_radius = radius
	disc_mesh.height = height
	disc.mesh = disc_mesh
	disc.material_override = _hazard_flat_material("mine_body", MINE_BODY_COLOR)
	disc.position.y = height / 2.0
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(disc)

	var top := MeshInstance3D.new()
	var top_quad := QuadMesh.new()
	top_quad.size = Vector2(radius * 2.0, radius * 2.0)
	top.mesh = top_quad
	top.material_override = _hazard_texture_material("mine_top", true)
	top.position.y = height + PROP_SURFACE_LIFT
	top.rotation.x = -PI / 2.0
	root.add_child(top)

	root.rotation.y = rng.randf() * TAU
	return root


## A minefield warning sign: weathered plate on a steel post, readable from both sides
## (two back-to-back quads), facing seeded from the object's identity. Decorative.
func _create_textured_warning_sign(obj: Dictionary) -> Node3D:
	var sign_tex: Texture2D = _hazards_library.get_texture("warning_sign")
	if sign_tex == null:
		return _create_procedural_sign()  # mid-download safety net
	var post_height := SIGN_POST_HEIGHT_INCHES * INCHES_TO_METERS
	var post_radius := SIGN_POST_RADIUS_INCHES * INCHES_TO_METERS
	var sign_w := SIGN_WIDTH_INCHES * INCHES_TO_METERS
	var sign_h := sign_w * float(sign_tex.get_height()) / float(sign_tex.get_width())

	var rng := RandomNumberGenerator.new()
	rng.seed = _placed_object_seed(obj)

	var root := Node3D.new()
	var post := MeshInstance3D.new()
	var post_mesh := CylinderMesh.new()
	post_mesh.top_radius = post_radius
	post_mesh.bottom_radius = post_radius
	post_mesh.height = post_height
	post.mesh = post_mesh
	post.material_override = _hazard_flat_material("sign_post", SIGN_POST_COLOR)
	post.position.y = post_height / 2.0
	post.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(post)

	var plate_y := post_height - sign_h / 2.0
	var plate_mat := _hazard_texture_material("warning_sign", false)
	for i in 2:
		var plate := MeshInstance3D.new()
		var plate_quad := QuadMesh.new()
		plate_quad.size = Vector2(sign_w, sign_h)
		plate.mesh = plate_quad
		plate.material_override = plate_mat
		plate.position = Vector3(0, plate_y, (post_radius + PROP_SURFACE_LIFT) * (1 if i == 0 else -1))
		plate.rotation.y = i * PI
		plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		root.add_child(plate)

	root.rotation.y = rng.randf() * TAU
	return root


## Lit cutout/full-bleed material for a hazard texture, cached per panel.
func _hazard_texture_material(panel: String, alpha_cutout: bool) -> Material:
	if _hazard_materials.has(panel):
		return _hazard_materials[panel]
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _hazards_library.get_texture(panel)
	mat.roughness = 0.8
	mat.metallic = 0.0
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mat.texture_repeat = false
	if alpha_cutout:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		mat.alpha_scissor_threshold = RUIN_ALPHA_SCISSOR_THRESHOLD
	_hazard_materials[panel] = mat
	return mat


## Plain coloured material for hazard prop bodies (mine side, sign post), cached.
func _hazard_flat_material(key: String, color: Color) -> Material:
	if _hazard_materials.has(key):
		return _hazard_materials[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.85
	mat.metallic = 0.0
	_hazard_materials[key] = mat
	return mat


## Lava-pool surface material (cached): the round lava texture as albedo + emission map,
## alpha-scissored to the round shape, so the molten cracks glow. Two-sided so the flat
## quad reads from any camera angle.
func _lava_texture_material() -> Material:
	if _hazard_materials.has(LAVA_PANEL):
		return _hazard_materials[LAVA_PANEL]
	var tex := _hazards_library.get_texture(LAVA_PANEL)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = RUIN_ALPHA_SCISSOR_THRESHOLD
	mat.emission_enabled = true
	mat.emission_texture = tex
	mat.emission = Color.WHITE
	mat.emission_energy_multiplier = LAVA_TEXTURE_EMISSION_ENERGY
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mat.texture_repeat = false
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_hazard_materials[LAVA_PANEL] = mat
	return mat


## Dangerous mine: a small tapered dome. Decorative — dangerous terrain is passable.
func _create_procedural_mine() -> Node3D:
	var root := Node3D.new()
	var dome_height := MINE_HEIGHT_INCHES * INCHES_TO_METERS

	var dome := MeshInstance3D.new()
	var dome_mesh := CylinderMesh.new()
	dome_mesh.top_radius = MINE_TOP_RADIUS_INCHES * INCHES_TO_METERS
	dome_mesh.bottom_radius = MINE_BOTTOM_RADIUS_INCHES * INCHES_TO_METERS
	dome_mesh.height = dome_height
	dome.mesh = dome_mesh
	dome.material_override = TerrainHologram.make_material()
	dome.position.y = dome_height / 2.0 - Z_FIGHT_OFFSET
	dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(dome)

	return root


## True if a crater centred at (x, z) world metres is at least CRATER_MIN_SPACING from
## every crater already kept this layout — thins the dense mine layout to non-overlapping
## lava craters (≈3-5 per dangerous field) in the volcanic biome.
func _crater_spot_free(x: float, z: float) -> bool:
	var min_d := CRATER_MIN_SPACING_INCHES * INCHES_TO_METERS
	var p := Vector2(x, z)
	for c in _crater_positions:
		if p.distance_to(c) < min_d:
			return false
	return true


## Glowing lava prop: the DANGEROUS-terrain prop in the volcanic biome (replaces the mine
## disc). Best: a TRELLIS 3D crater GLB + a targeted OmniLight for the molten glow. Until
## that GLB is cached it falls back to a flat alpha-keyed lava-texture quad, then to a
## procedural dark-crust + molten-core disc. Orientation seeded from the object's identity so
## every client + reload matches. Decorative: dangerous terrain stays passable.
func _create_lava_pool(obj: Dictionary) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = _placed_object_seed(obj)

	var radius := LAVA_POOL_RADIUS_INCHES * INCHES_TO_METERS
	var height := LAVA_POOL_HEIGHT_INCHES * INCHES_TO_METERS

	var root := Node3D.new()

	if _hazard_model_ready(LAVA_CRATER_MODEL):
		# Best: the volumetric 3D crater GLB, scaled to its footprint and sitting on the
		# table, with a targeted molten glow light. Kept craters are few (non-overlapping),
		# so lighting every one keeps each dangerous field lit without flooding the scene.
		var scene: PackedScene = _hazards_library.get_model_scene(LAVA_CRATER_MODEL)
		if scene != null:
			var crater := scene.instantiate() as Node3D
			_fit_to_footprint(crater, LAVA_CRATER_DIAMETER_INCHES * INCHES_TO_METERS)
			root.add_child(crater)
			var light := OmniLight3D.new()
			light.light_color = LAVA_LIGHT_COLOR
			light.light_energy = LAVA_LIGHT_ENERGY
			light.omni_range = LAVA_LIGHT_RANGE_M
			light.shadow_enabled = false
			light.position.y = LAVA_LIGHT_HEIGHT_M
			root.add_child(light)
			root.rotation.y = rng.randf() * TAU
			return root

	if _lava_panel_ready():
		# Textured pool: a flat quad wearing the lava texture as albedo + emission map
		# (alpha-keyed to the round shape), so the molten cracks glow.
		var quad := MeshInstance3D.new()
		var quad_mesh := QuadMesh.new()
		quad_mesh.size = Vector2(radius * 2.0, radius * 2.0)
		quad.mesh = quad_mesh
		quad.material_override = _lava_texture_material()
		quad.rotation.x = -PI / 2.0  # lay the +Z-facing quad flat, facing up
		quad.position.y = height + PROP_SURFACE_LIFT
		quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(quad)
	else:
		# Procedural fallback (until the texture is cached): dark cooled-crust rim disc...
		var crust := MeshInstance3D.new()
		var crust_mesh := CylinderMesh.new()
		crust_mesh.top_radius = radius
		crust_mesh.bottom_radius = radius
		crust_mesh.height = height
		crust_mesh.radial_segments = LAVA_POOL_SIDES
		crust.mesh = crust_mesh
		var crust_mat := StandardMaterial3D.new()
		crust_mat.albedo_color = LAVA_CRUST_COLOR
		crust_mat.roughness = 0.95
		crust.material_override = crust_mat
		crust.position.y = height / 2.0 - Z_FIGHT_OFFSET
		crust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(crust)

		# ...and a brighter emissive molten core sitting just proud of the crust.
		var core := MeshInstance3D.new()
		var core_mesh := CylinderMesh.new()
		core_mesh.top_radius = radius * LAVA_CORE_FRAC
		core_mesh.bottom_radius = radius * LAVA_CORE_FRAC
		core_mesh.height = height
		core_mesh.radial_segments = LAVA_POOL_SIDES
		core.mesh = core_mesh
		var core_mat := StandardMaterial3D.new()
		core_mat.albedo_color = LAVA_EMISSION_COLOR
		core_mat.emission_enabled = true
		core_mat.emission = LAVA_EMISSION_COLOR
		core_mat.emission_energy_multiplier = LAVA_EMISSION_ENERGY
		core.material_override = core_mat
		core.position.y = height + PROP_SURFACE_LIFT
		core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(core)

	root.rotation.y = rng.randf() * TAU  # vary the irregular rim per pool
	return root


## Carnivorous-plant clump: the DANGEROUS-terrain prop in the alien_jungle biome (replaces
## the mine disc). Just the TRELLIS 3D GLB scaled to its footprint — NO glow light (the
## bioluminescence is baked into the model's texture). Returns null until the GLB is cached
## (the field fills in once it downloads). Orientation seeded from the object's identity.
func _create_carnivore_plant(obj: Dictionary) -> Node3D:
	if not _hazard_model_ready(CARNIVORE_MODEL):
		return null
	var scene: PackedScene = _hazards_library.get_model_scene(CARNIVORE_MODEL)
	if scene == null:
		return null
	var rng := RandomNumberGenerator.new()
	rng.seed = _placed_object_seed(obj)
	var root := Node3D.new()
	var plant := scene.instantiate() as Node3D
	_fit_to_footprint(plant, CARNIVORE_DIAMETER_INCHES * INCHES_TO_METERS)
	root.add_child(plant)
	root.rotation.y = rng.randf() * TAU
	return root


## Warning sign fallback: holographic post + plate. Decorative.
func _create_procedural_sign() -> Node3D:
	var root := Node3D.new()
	var post_height := SIGN_POST_HEIGHT_INCHES * INCHES_TO_METERS
	var sign_w := SIGN_WIDTH_INCHES * INCHES_TO_METERS

	var post := MeshInstance3D.new()
	var post_mesh := BoxMesh.new()
	post_mesh.size = Vector3(SIGN_POST_RADIUS_INCHES * 2.0 * INCHES_TO_METERS, post_height,
			SIGN_POST_RADIUS_INCHES * 2.0 * INCHES_TO_METERS)
	post.mesh = post_mesh
	post.material_override = TerrainHologram.make_material()
	post.position.y = post_height / 2.0 - Z_FIGHT_OFFSET
	post.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(post)

	var plate := MeshInstance3D.new()
	var plate_mesh := BoxMesh.new()
	plate_mesh.size = Vector3(sign_w, sign_w * 0.75, 0.002)
	plate.mesh = plate_mesh
	plate.material_override = TerrainHologram.make_material()
	plate.position.y = post_height - sign_w * 0.375
	plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(plate)

	return root


## Toxic puddle: a flat disc lying on the table. Decorative.
func _create_procedural_puddle() -> Node3D:
	var root := Node3D.new()
	var height := PUDDLE_HEIGHT_INCHES * INCHES_TO_METERS

	var disc := MeshInstance3D.new()
	var disc_mesh := CylinderMesh.new()
	disc_mesh.top_radius = PUDDLE_RADIUS_INCHES * INCHES_TO_METERS
	disc_mesh.bottom_radius = PUDDLE_RADIUS_INCHES * INCHES_TO_METERS
	disc_mesh.height = height
	disc.mesh = disc_mesh
	disc.material_override = TerrainHologram.make_material()
	disc.position.y = height / 2.0 - Z_FIGHT_OFFSET
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(disc)

	return root


## Clear all placed object instances
func _clear_placed_objects() -> void:
	for instance in _object_instances:
		if is_instance_valid(instance):
			instance.queue_free()
	_object_instances.clear()


## Check if a world-space position is within the table boundaries
func _is_position_within_table(world_x: float, world_z: float, t_size: Vector2) -> bool:
	var table_width_m := t_size.x * 12.0 * INCHES_TO_METERS
	var table_depth_m := t_size.y * 12.0 * INCHES_TO_METERS
	return abs(world_x) <= table_width_m / 2.0 and abs(world_z) <= table_depth_m / 2.0
