class_name TableBiomePresenter
extends Node3D
## Dresses the GAME table with the accepted reference biome look (scripts/visual/grassland_reference.gd).
##
## DISPLAY ONLY. It adds no collider, changes no rule, LOS volume, footprint or save data, and is never
## saved: the presentation is rebuilt from table.biome whenever the layout is (re)made:
##   - a biome change or a table resize (the table emits both),
##   - a save load,
##   - the start of play (DEPLOYMENT -> PLAYING: the layout is final),
##   - an explicit layout change during setup (map layout editor closed, clear table, sort table).
## During play only a load or a biome change rebuilds (both hitch anyway) — never a mid-game freeze.
##
## The reference writes into nodes it does not own (table plane + material, grass field, base tops, table
## frame, environment, sun). Everything it touches is snapshot before apply() and restored by teardown();
## walls and placed objects are rebuilt by the terrain overlay, which drops their reference dressing.

const ReferenceScript := preload("res://scripts/visual/grassland_reference.gd")
## Table ids (table.gd BIOMES) -> reference profile ids (reference_biomes.gd). Only grassland differs.
const TABLE_TO_REFERENCE := {"temperate_grassland": "grassland"}
const REBUILD_DELAY_S := 0.25
## Scatter density per quality preset (GraphicsSettings.QualityPreset); presets missing here are NOT dressed
## (Performance, Low): they keep today's battlemap table, the escape hatch for weak GPUs.
const PRESET_DENSITY := {2: 1.0, 3: 1.0, 4: 1.0}   # MEDIUM, HIGH, ULTRA
## Maintainer decision D4: the game's ground mist is hidden while a biome is dressed — the accepted
## look had none (the reference scene hides it too). The mist comes back on teardown.
const HIDE_GROUND_MIST := true
## Scatter counts are per m²; above a 6x4 ft table the density falls instead of the frame rate.
const REFERENCE_AREA_M2 := 6.0 * 0.3048 * 4.0 * 0.3048
const ENV_PROPS: Array[String] = ["background_mode", "reflected_light_source", "ambient_light_source",
	"ssao_radius", "ssao_intensity", "ssao_power", "ssil_enabled", "sdfgi_enabled", "tonemap_agx_contrast",
	"ssr_enabled", "ssr_max_steps", "ssr_fade_in", "ssr_fade_out", "ssr_depth_tolerance",
	"volumetric_fog_enabled", "volumetric_fog_density", "volumetric_fog_albedo", "volumetric_fog_emission",
	"volumetric_fog_length", "volumetric_fog_detail_spread", "volumetric_fog_gi_inject",
	"volumetric_fog_ambient_inject", "volumetric_fog_temporal_reprojection_enabled",
	"volumetric_fog_temporal_reprojection_amount", "glow_enabled", "glow_bloom", "glow_intensity", "fog_enabled"]
const SUN_PROPS: Array[String] = ["directional_shadow_max_distance", "directional_shadow_pancake_size",
	"light_volumetric_fog_energy"]

signal presentation_built(reference_biome: String)
signal presentation_removed

## Master switch (the review-page / cut flag). Off = the table as shipped before this work.
var enabled := true
## Headless runs (CI, gdUnit) skip the dressing unless a test opts in.
var allow_headless := false

var _main: Node = null
var _table: Node3D = null
var _presentation: Node3D = null
var _building := false
var _rebuild_again := false
var _rebuild_queued := false
var _saved := {}
var _applied_mesh: Mesh = null
var _applied_material: Material = null
var _applied_density := -1.0


## A table id -> the reference profile id that dresses it.
static func reference_biome(table_biome: String) -> String:
	return TABLE_TO_REFERENCE.get(table_biome, table_biome)


## Wire to the live game. `main` is the Main node (table, terrain overlay, lighting, save manager).
func setup(main: Node) -> void:
	_main = main
	_table = main.get_node("Table")
	_table.biome_changed.connect(func(_b: String) -> void: request_rebuild("biome"))
	_table.table_resized.connect(func(_s: Vector2) -> void: request_rebuild("resize"))
	main.save_manager.load_completed.connect(func(_n: int) -> void: request_rebuild("load"))
	main.opr_army_manager.game_phase_changed.connect(_on_game_phase_changed)
	if main.map_layout_editor != null:
		main.map_layout_editor.layout_closed.connect(func() -> void: request_rebuild("layout"))
	var graphics := get_node_or_null("/root/GraphicsSettings")
	if graphics != null:
		graphics.settings_applied.connect(_on_graphics_settings_applied)
	# D1 order: the atmosphere controller writes the mood's lighting first (restore_saved() after the intro,
	# or a mood change), THEN the biome profile goes on top. atmosphere_changed fires at the end of
	# apply_atmosphere; a blended change is waited out before the profile is applied.
	if main.atmosphere_controller != null:
		main.atmosphere_controller.atmosphere_changed.connect(_on_atmosphere_changed)
	request_rebuild("start")


## Scatter density for this table and preset (0 = do not dress).
static func density_for(preset: int, table_size_feet: Vector2) -> float:
	if not PRESET_DENSITY.has(preset):
		return 0.0
	var area := table_size_feet.x * 0.3048 * table_size_feet.y * 0.3048
	return float(PRESET_DENSITY[preset]) * minf(1.0, REFERENCE_AREA_M2 / maxf(area, 0.0001))


func _current_density() -> float:
	var graphics := get_node_or_null("/root/GraphicsSettings")
	var preset: int = int(graphics.current_preset) if graphics != null else 2
	return density_for(preset, _table.table_size)


## Is the table dressed right now?
func is_dressed() -> bool:
	return is_instance_valid(_presentation)


func current_presentation() -> Node3D:
	return _presentation if is_instance_valid(_presentation) else null


## Should the table be dressed at all in this run?
func should_dress() -> bool:
	if not enabled or _table == null:
		return false
	if DisplayServer.get_name() == "headless" and not allow_headless:
		return false
	# The reference shaders are Forward+ only (the web export runs gl_compatibility).
	if DisplayServer.get_name() != "headless" and RenderingServer.get_current_rendering_method() != "forward_plus":
		return false
	return _current_density() > 0.0


## Ask for a rebuild. Layout reasons count only during setup (DEPLOYMENT); everything else always.
## Debounced: a burst of events (biome + resize + load) builds once.
func request_rebuild(reason: String = "") -> void:
	if reason == "layout" and _in_play():
		return
	if _rebuild_queued:
		return
	_rebuild_queued = true
	await get_tree().create_timer(REBUILD_DELAY_S).timeout
	_rebuild_queued = false
	if not is_inside_tree():
		return
	await rebuild()


## Tear the current dressing down and build it again from table.biome.
func rebuild() -> void:
	if _building:
		_rebuild_again = true
		return
	_building = true
	teardown()
	if should_dress():
		var presentation: Node3D = ReferenceScript.new()
		presentation.name = "TableBiomeReference"
		presentation.biome = reference_biome(str(_table.biome))
		presentation.table_tier = true
		presentation.density_scale = _current_density()
		_applied_density = presentation.density_scale
		add_child(presentation)
		await presentation.prepare()
		if is_instance_valid(presentation) and is_instance_valid(_table) and is_inside_tree():
			_snapshot()
			presentation.apply(_main)
			_presentation = presentation
			var surface := _surface()
			_applied_mesh = surface.mesh
			_applied_material = surface.material_override
			# The floor needs no shadow of its own; with relief its vertex shader (wall loop included) ran
			# again in every shadow cascade.
			surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var mist = _main.get("atmospheric_clouds")
			if HIDE_GROUND_MIST and mist != null:
				mist.visible = false
			print("TABLE_BIOME built %s (table %s, %s ft)" % [presentation.biome, _table.biome, str(_table.table_size)])
			presentation_built.emit(str(presentation.biome))
	_building = false
	if _rebuild_again:
		_rebuild_again = false
		await rebuild()


## Remove the dressing and put back everything the reference wrote into nodes it does not own.
func teardown() -> void:
	if not is_instance_valid(_presentation):
		_presentation = null
		return
	var presentation := _presentation
	_presentation = null
	# Nodes the reference parented outside itself.
	var fog = presentation.get("_fog")
	if is_instance_valid(fog):
		fog.queue_free()
	for stream in presentation.get("_dust"):
		if is_instance_valid(stream):
			stream.queue_free()
	# Remove synchronously so its _exit_tree restores TAA / render scale / shadow atlas NOW, before a
	# follow-up apply() snapshots the viewport.
	remove_child(presentation)
	presentation.queue_free()
	_restore()
	presentation_removed.emit()


func _snapshot() -> void:
	_saved.clear()
	var surface := _surface()
	_saved["mesh"] = surface.mesh
	_saved["cast_shadow"] = surface.cast_shadow
	var mist = _main.get("atmospheric_clouds")
	if mist != null:
		_saved["mist_visible"] = mist.visible
	_saved["grass_visible"] = _table.get_node("GrassField").visible
	_saved["base_shader"] = _table.get_base_top_material().shader
	var frames := {}
	for child in _table.get_children():
		if child is MeshInstance3D and child != surface:
			frames[child] = child.material_override
	_saved["frames"] = frames
	var floors := {}
	for group in get_tree().get_nodes_in_group("terrain_group_base"):
		var floor_mesh = group.get("_floor_mesh")
		if is_instance_valid(floor_mesh):
			floors[floor_mesh] = floor_mesh.material_override
	_saved["floors"] = floors
	var env: Environment = _main.get_node("WorldEnvironment").environment
	var env_values := {}
	for prop in ENV_PROPS:
		env_values[prop] = env.get(prop)
	_saved["env"] = env_values
	var sun: DirectionalLight3D = _main.get_node("DirectionalLight3D")
	var sun_values := {}
	for prop in SUN_PROPS:
		sun_values[prop] = sun.get(prop)
	_saved["sun"] = sun_values


func _restore() -> void:
	if _saved.is_empty() or not is_instance_valid(_table):
		return
	var surface := _surface()
	if surface.mesh == _applied_mesh and _saved.get("mesh") != null:
		surface.mesh = _saved["mesh"]
	if surface.material_override == _applied_material:
		surface.material_override = _table._build_ground_material()
	surface.cast_shadow = _saved.get("cast_shadow", GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
	var mist = _main.get("atmospheric_clouds")
	if mist != null and _saved.has("mist_visible"):
		mist.visible = bool(_saved["mist_visible"])
	_table.get_node("GrassField").visible = bool(_saved.get("grass_visible", true))
	var base: ShaderMaterial = _table.get_base_top_material()
	base.shader = _saved["base_shader"]
	_table._update_base_top_material()
	for frame in _saved["frames"]:
		if is_instance_valid(frame):
			frame.material_override = _saved["frames"][frame]
	for floor_mesh in _saved["floors"]:
		if is_instance_valid(floor_mesh):
			floor_mesh.material_override = _saved["floors"][floor_mesh]
	var env: Environment = _main.get_node("WorldEnvironment").environment
	for prop in _saved["env"]:
		env.set(prop, _saved["env"][prop])
	var sun: DirectionalLight3D = _main.get_node("DirectionalLight3D")
	for prop in _saved["sun"]:
		sun.set(prop, _saved["sun"][prop])
	# Walls and placed objects: the overlay rebuild drops weathering, hidden trees and attached dressing.
	if _main.terrain_overlay != null and _main.terrain_overlay.has_method("set_biome"):
		_main.terrain_overlay.set_biome(str(_table.biome))
	# Lighting and the camera's own tilt-shift attributes come back through their usual owners.
	if _main.atmosphere_controller != null:
		_main.atmosphere_controller.apply_atmosphere(_main.atmosphere_controller.get_current_atmosphere(), true)
	var pivot = _main.get("camera_pivot")
	var graphics := get_node_or_null("/root/GraphicsSettings")
	if pivot != null and pivot.has_method("set_tilt_shift_enabled") and graphics != null:
		pivot.set_tilt_shift_enabled(graphics.tilt_shift)
	_saved.clear()
	_applied_mesh = null
	_applied_material = null


## The table rebuilds its ground material when a battlemap download finishes (table.gd _apply_biome),
## which would silently put the old battlemap back under the dressing. Re-assert ours (two compares).
func _process(_delta: float) -> void:
	if _building or not is_instance_valid(_presentation) or not is_instance_valid(_table):
		return
	var surface := _surface()
	if surface.material_override != _applied_material:
		surface.material_override = _applied_material
	var grass: Node3D = _table.get_node("GrassField")
	if grass.visible:
		grass.visible = false


func _on_atmosphere_changed(mood: String) -> void:
	var tween = _main.atmosphere_controller.get("_transition_tween")
	if tween is Tween and tween.is_valid() and tween.is_running():
		await tween.finished
	if _building or not is_instance_valid(_presentation):
		return
	# The mood may have changed again while the blend ran: apply the current one.
	_presentation.apply_table_mood(_main.atmosphere_controller.get_current_atmosphere())


## A quality-preset change: rebuild only when the dressing state or the density actually changes.
func _on_graphics_settings_applied(_preset_name: String) -> void:
	if _building or _table == null:
		return
	var want := should_dress()
	if want != is_dressed() or (want and not is_equal_approx(_current_density(), _applied_density)):
		request_rebuild("preset")


func _on_game_phase_changed(phase: int) -> void:
	if phase == OPRArmyManager.GamePhase.PLAYING:
		request_rebuild("start_play")


func _in_play() -> bool:
	var manager = _main.get("opr_army_manager") if _main != null else null
	return manager != null and int(manager.game_phase) == OPRArmyManager.GamePhase.PLAYING


func _surface() -> MeshInstance3D:
	return _table.get_node("TableMesh") as MeshInstance3D
