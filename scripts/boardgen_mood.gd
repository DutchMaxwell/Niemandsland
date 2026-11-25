class_name BoardgenMood
extends RefCounted
## The product look of a generated Tiefwerk board (AAA step 5b; maintainer decision D-A4): while a board is on the table and the
## finer look is on (Medium up, not the Compatibility renderer) the table gets its dim industrial light, a board-scale SSAO, a
## colour grade and a subtle fill light that only the models receive. Low / Performance / web keep the mood the player chose.
##   - light_look(): the sun / ambient / exposure the LightingController uses instead of the mood's (set_board_look);
##   - environment_values(): the RenderState "board" layer (SSAO radius and strength at the scale of a 1.2 m board instead of the
##     preset's 0.8 m radius, the grade, the glow);
##   - the fill light: a DirectionalLight3D whose cull mask is the MODEL layer. The board and everything it builds sit on the BOARD
##     layer, so the fill lifts the models off the dim board without washing the board itself.

const MODEL_LAYER := 1   # a render layer bit: models and the rest of the table (the default layer)
const BOARD_LAYER := 2   # a render layer bit: every visual the board builds
const LAMP_IRON_LAYER := 1 << 18   # a render layer bit kept beside BOARD_LAYER: the lamp posts' iron, which their own lantern lights skip (lit from 0.1 in inside the cage it read as white bars)

const SUN_ENERGY := 0.8
const SUN_COLOUR := Color(0.88, 0.90, 0.96)
const AMBIENT_ENERGY := 0.65
const AMBIENT_COLOUR := Color(0.62, 0.64, 0.70)
const EXPOSURE := 1.0

## Board-scale SSAO: the preset's radius is 0.8 m on a 1.22 m board (a mush that no wall foot or pipe can show through).
const SSAO_RADIUS_M := 0.05
const SSAO_INTENSITY := 7.0

const FILL_ENERGY := 0.45
const FILL_COLOUR := Color(0.93, 0.94, 1.0)
const FILL_PITCH_DEG := -38.0   # shines from the player's side, a little from above
const FILL_YAW_DEG := 12.0

## The ruin town's grade (look A/B 21.11., the "grade" part of lookab V1): AgX with more contrast, a touch more colour. The only mood knob of the A/B that kept the
## readability gate green at about +0.1 ms; the town's light is BoardgenTownDressing.dusk, so it gets no light look, no SSAO change and no model fill.
const TOWN_AGX_CONTRAST := 1.25
const TOWN_CONTRAST := 1.08
const TOWN_SATURATION := 1.15
## The grade alone darkens the mean luminance of the play and overview stills by about 12 %; the exposure (the dusk's own EXPOSURE times this) brings it back (lead 21.11.: the maintainer said "too dark").
const TOWN_EXPOSURE_GAIN := 1.4

const OWNER_META := "boardgen_mood_owner"
const MOOD_HOOK_META := "boardgen_mood_hook"   # on a town board: its atmosphere_changed hook (the Night floor follows the mood)
## The ruin town's blue-hour sky (reversible): replaces the star field while a town board is on the table. A pure backdrop:
## the scene's ambient light is a colour and its reflections are off, so it lights nothing; the smallest radiance map, since nothing reads it.
const TOWN_SKY_SHADER := preload("res://shaders/ruintown_sky.gdshader")

static var _grade: GradientTexture1D
static var _town_sky: Sky


## The light the LightingController uses while the board look is on.
static func light_look() -> Dictionary:
	return {"sun_energy": SUN_ENERGY, "sun_color": SUN_COLOUR, "ambient_energy": AMBIENT_ENERGY,
		"ambient_color": AMBIENT_COLOUR, "exposure": EXPOSURE}


## The RenderState "board" layer: board-scale SSAO, the grade (cool blacks, warm highlights, a touch less colour), a small glow.
static func environment_values() -> Dictionary:
	return {"ssao_radius": SSAO_RADIUS_M, "ssao_intensity": SSAO_INTENSITY, "ssao_power": 1.8, "ssao_detail": 0.6,
		"glow_intensity": 0.15, "glow_bloom": 0.0, "adjustment_enabled": true,
		"adjustment_color_correction": grade_curve(), "adjustment_contrast": 1.03, "adjustment_saturation": 0.97,
		"tonemap_agx_contrast": 1.1}


## The RenderState "board" layer of the ruin town: the grade and the town sky. The table's reference layer reflects the sky; over a town the reflections are off, so the
## sky stays a backdrop (measured 21.11.: reflected, it cooled the street setts 43.6 -> 36.2 % warm and raised the earth's saturation 0.48 -> 0.52 at seed 41).
static func town_values() -> Dictionary:
	return {"tonemap_agx_contrast": TOWN_AGX_CONTRAST, "adjustment_enabled": true, "adjustment_contrast": TOWN_CONTRAST, "adjustment_saturation": TOWN_SATURATION,
		"sky": town_sky(), "reflected_light_source": Environment.REFLECTION_SOURCE_DISABLED}


## The town's sky (one shared instance): zenith, horizon band and the ground below by the view's elevation (shaders/ruintown_sky.gdshader).
static func town_sky() -> Sky:
	if _town_sky == null:
		var mat := ShaderMaterial.new()
		mat.shader = TOWN_SKY_SHADER
		_town_sky = Sky.new()
		_town_sky.sky_material = mat
		_town_sky.radiance_size = Sky.RADIANCE_SIZE_32
	return _town_sky


## The lighting controller's board look of the ruin town: the exposure (the dusk's, raised by the gain that cancels the grade's darkening) and, under
## Night without bounce light (Medium: High / Ultra have SDFGI and SSIL), the dusk's sky fill as a floor (decision D-N1: half the board was below luma 8).
static func town_look(bounce := false, night := false) -> Dictionary:
	var look := {"exposure": BoardgenTownDressing.EXPOSURE * TOWN_EXPOSURE_GAIN}
	if night:   # the fill stays the dusk's, across the axis between the deployment zones (D-G5): the table rig turns it to one player's side after a blended pick
		look["fill_rotation"] = Vector3(-BoardgenTownDressing.MOON_ELEVATION, BoardgenTownDressing.MOON_AZIMUTH - 180.0, 0.0)
	if night and not bounce:
		look["ambient_energy_min"] = BoardgenTownDressing.AMBIENT_ENERGY
		look["fill_light_energy_min"] = BoardgenTownDressing.MOON2_ENERGY
	return look


## The town look for the mood and preset in force now.
static func _town_look_now(main: Node) -> Dictionary:
	var graphics: Node = main.get_node_or_null("/root/GraphicsSettings")
	var bounce: bool = graphics != null and int(graphics.current_preset) >= GraphicsSettings.QualityPreset.HIGH
	var atmosphere: Variant = main.get("atmosphere_controller")
	return town_look(bounce, is_instance_valid(atmosphere) and atmosphere.get_current_atmosphere() == "Night")


## One atmosphere_changed hook per town board (kept in its meta): a new mood sets the town look again; off or leaving, the hook goes.
static func _hook_mood(board: Node, main: Node, lighting: Variant, on: bool) -> void:
	var atmosphere: Variant = main.get("atmosphere_controller")
	if not is_instance_valid(atmosphere) or not atmosphere.has_signal("atmosphere_changed"):
		return
	if board.has_meta(MOOD_HOOK_META):
		var old: Callable = board.get_meta(MOOD_HOOK_META)
		if atmosphere.atmosphere_changed.is_connected(old):
			atmosphere.atmosphere_changed.disconnect(old)
		board.remove_meta(MOOD_HOOK_META)
	if on and lighting != null:
		var hook := func(_name: String) -> void:
			if is_instance_valid(board) and is_instance_valid(lighting) and main.get_meta(OWNER_META, 0) == board.get_instance_id():
				lighting.set_board_look(_town_look_now(main))
		atmosphere.atmosphere_changed.connect(hook)
		board.set_meta(MOOD_HOOK_META, hook)


## A per-channel curve: the blacks lean cool and are lifted a hair, the highlights lean warm (the lamps), the middle stays.
static func grade_curve() -> GradientTexture1D:
	if _grade == null:
		var curve := GradientTexture1D.new()
		curve.width = 256
		curve.gradient = Gradient.new()
		curve.gradient.offsets = PackedFloat32Array([0.0, 0.25, 0.5, 0.75, 1.0])
		curve.gradient.colors = PackedColorArray([Color(0.012, 0.015, 0.019), Color(0.244, 0.25, 0.257), Color(0.498, 0.5, 0.502),
			Color(0.768, 0.75, 0.735), Color.WHITE])
		_grade = curve
	return _grade


## The fill light of the models: cool, subtle, no shadow, seen by the MODEL layer only.
static func make_fill_light() -> DirectionalLight3D:
	var light := DirectionalLight3D.new()
	light.name = "ModelFill"
	light.light_energy = FILL_ENERGY
	light.light_color = FILL_COLOUR
	light.light_specular = 0.2
	light.light_cull_mask = MODEL_LAYER
	light.shadow_enabled = false
	light.rotation_degrees = Vector3(FILL_PITCH_DEG, FILL_YAW_DEG, 0.0)
	return light


## Everything the board draws goes on the BOARD layer (and off the MODEL layer), so the fill light never reaches it.
static func assign_layers(root: Node) -> void:
	if root is GeometryInstance3D:   # (a light's reach is its cull mask, not its layer)
		(root as GeometryInstance3D).layers = BOARD_LAYER | ((root as GeometryInstance3D).layers & LAMP_IRON_LAYER)
	for child in root.get_children():
		assign_layers(child)


## Turn the look on or off for `board` (a BoardgenGreybox in a table). The game's Main owns the RenderState and the LightingController
## (the parent of the table); outside the game (a unit test, the menu) there is none and only the fill light exists. `town`: the ruin town's grade instead of the Tiefwerk look.
static func apply(board: Node, on: bool, town := false) -> void:
	var fill := board.get_node_or_null("ModelFill") as DirectionalLight3D
	if fill != null:
		fill.visible = on
	var main := board.get_parent().get_parent() if board.get_parent() != null else null
	if main == null:
		return
	var lighting: Variant = main.get("lighting_controller")   # (untyped: at teardown the controller can already be freed)
	if not is_instance_valid(lighting):
		lighting = null
	_hook_mood(board, main, lighting, on and town)
	if not on and main.get_meta(OWNER_META, 0) != board.get_instance_id():
		return   # another board took the look over (a re-attach frees the old board after the new one is ready)
	var render_state: RenderState = main.get("render_state")
	if render_state != null:
		render_state.set_layer("board", (town_values() if town else environment_values()) if on else {})
	if lighting != null and lighting.has_method("set_board_look"):
		lighting.set_board_look((_town_look_now(main) if town else light_look()) if on else {})
	if on:
		main.set_meta(OWNER_META, board.get_instance_id())
	else:
		main.remove_meta(OWNER_META)
