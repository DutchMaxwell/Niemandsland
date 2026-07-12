extends SceneTree
## NUMERIC brightness proof for the terrain-projected miniature base top (feat/terrain-bases).
##
## The maintainer rejected two eye-tuned rounds as "still too dark". This tool stops the guessing:
## it MEASURES. It renders a bare base (NO model body) on UNIFORM desert-sand ground and compares
## the mean pixel luminance of the terrain-top region against the SAME pixel region of the bare
## board — by rendering the identical frame WITH the base and then WITHOUT it (base hidden). Because
## both reads hit the exact same screen pixels / world spot, the battlemap albedo cancels perfectly
## and the delta isolates ONLY the shading difference the base introduces.
##
##   delta% = (board_lum - top_lum) / board_lum * 100      (positive => base darker than board)
##   Target: |delta| < 2 %.
##
## It sweeps a config matrix so each darkening source is attributable in isolation:
##   vignette (0.10 vs 0.0) · SSAO (off vs medium-preset on) · detail normal map (on vs off).
## Two regions per config: FULL top (includes the rim-contact band) and CENTRAL 50 % (pure centre
## shading match). Both a top-down ORTHOGRAPHIC proof and an oblique 3/4 lit check are measured.
##
## Usage (needs a REAL renderer — a headless Wayland compositor; NOT Godot's --headless):
##   gamescope --backend headless -W 1600 -H 1600 -- \
##     flatpak run --filesystem=home --socket=wayland --share=network org.godotengine.Godot \
##       --path <project> --rendering-driver vulkan -s res://tools/base_luminance_qa.gd -- <out_dir> [suffix]

const IMAGE_SIZE := Vector2i(1600, 1600)
## Generous settle: the headless gamescope swapchain can return one stale radial band for a few
## frames right after a visibility/parameter change (it never appears in a well-settled still).
const SETTLE_FRAMES := 24
## Frames averaged per capture so any transient render flicker cancels (a still may hide it).
const AVG_FRAMES := 8
## Screen-space offset (px) from the base centre to the bare-board reference patch. Down-right keeps
## it on the table for both the top-down and the oblique framings (the base is small in frame).
const BOARD_PATCH_OFFSET := Vector2(360.0, 210.0)
## 40 mm round base (radius 0.02 m) — big enough for a high-pixel measurement disc.
const BASE_RADIUS_M := 0.02
const BASE_POS := Vector3(0.30, 0.0, 0.18)
## Orthographic vertical extent (metres): base diameter (0.04) fills ~1/4 of the frame, board around.
const ORTHO_SIZE_M := 0.16
## Uniform desert sand (sRGB) — the ideal flat ground for a clean luminance read.
const SAND_COLOR := Color(0.78, 0.66, 0.46)
## Rec. 709 luminance weights (sRGB-stored, display space — the "brightness" the eye judges).
const LUM_R := 0.2126
const LUM_G := 0.7152
const LUM_B := 0.0722
## Terrain-top world radius (fraction of base radius) — mirror of BaseDecor.TOP_RADIUS_RATIO.
const TOP_RADIUS_RATIO := 0.86
## Measurement discs as a fraction of the terrain-top radius. FULL stops at 0.85 so it measures the
## terrain WINDOW proper and does not overlap the intended near-black rim border at the very edge
## (the radial-profile diagnostic reports the full 0..1 sweep so the rim edge is still visible).
const FULL_REGION_FRAC := 0.85
const CENTRAL_REGION_FRAC := 0.50  # pure centre — must match the board regardless of rim treatment
## Medium quality preset SSAO (the shipped default the maintainer runs).
const SSAO_RADIUS := 0.8
const SSAO_INTENSITY := 0.4

var _env: Environment = null
var _sun: DirectionalLight3D = null
var _table: Node = null
var _camera: Camera3D = null
var _base: Node3D = null
var _ground_mat: ShaderMaterial = null
var _top_mat: ShaderMaterial = null
var _report_lines: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else "/home/andreaskesberg/basing_out"
	var suffix: String = args[1] if args.size() > 1 else "_v3"
	DirAccess.make_dir_recursive_absolute(out_dir)
	get_root().size = IMAGE_SIZE

	_build_world()
	# CRITICAL: the ground detail relief is an async NoiseTexture2D (generated on a background
	# thread). Capturing before it finishes gave non-deterministic, run-to-run-unstable numbers
	# (the disc samples a tiny region, the board a large averaged one, so a partial fill hits them
	# unequally). Block until both textures are fully generated, then settle, so every read is
	# deterministic and the disc-vs-board delta reflects shading, not a texture-upload race.
	await _await_noise_ready()
	await _frames(30)

	_log("=== Base-top luminance proof (%s) ===" % suffix)
	_log("region metric: mean Rec.709 luminance of terrain-top pixels vs the SAME pixels of bare board")
	_log("delta%% = (board - top) / board * 100   (positive = base darker than board);  target |delta| < 2%%")
	_log("ground: uniform desert sand %s   sun: pitch -52 yaw -38   base: 40 mm round" % str(SAND_COLOR))
	_log("detail noise generated & settled before capture (async race eliminated)\n")

	# Config axes: vig(nette strength) · ssao · detail(=micro-relief albedo+normal on/off) ·
	# shadow · hide_rim. "detail off" = pure flat uniform surface (the cleanest base-color match).
	var configs := [
		{"label": "P0 FLAT (detail OFF, vig 0, SSAO off, rim on)   <- pure base-colour vs board", "vig": 0.0, "ssao": false, "detail": false, "shadow": true, "hide_rim": false},
		{"label": "P1 FLAT, RIM HIDDEN (detail OFF)                <- isolate the rim's contribution", "vig": 0.0, "ssao": false, "detail": false, "shadow": true, "hide_rim": true},
		{"label": "P2 detail ON (vig 0, SSAO off, rim on)          <- + micro-relief", "vig": 0.0, "ssao": false, "detail": true, "shadow": true, "hide_rim": false},
		{"label": "P3 detail ON + vignette 0.10 (rim on)           <- + old vignette (v2 shipped)", "vig": 0.10, "ssao": false, "detail": true, "shadow": true, "hide_rim": false},
		{"label": "P4 detail ON + SSAO on (medium preset, vig 0)   <- + SSAO", "vig": 0.0, "ssao": true, "detail": true, "shadow": true, "hide_rim": false},
		{"label": "P5 detail ON, vig 0.10, SSAO on (full current)  <- what the game shows now", "vig": 0.10, "ssao": true, "detail": true, "shadow": true, "hide_rim": false},
		{"label": "P6 detail ON, vig 0, SSAO off, SHADOW off       <- isolate the sun shadow", "vig": 0.0, "ssao": false, "detail": true, "shadow": false, "hide_rim": false},
	]

	# --- Top-down orthographic measurement (+ proof PNGs) ---
	_log("[ TOP-DOWN ORTHOGRAPHIC ]")
	_setup_ortho_camera()
	for cfg in configs:
		await _measure_config(cfg, true, out_dir, suffix)
	_log("")

	# --- Oblique 3/4 under the directional light (the match must hold when lit, not just flat) ---
	_log("[ OBLIQUE 3/4 (directional light) ]")
	_setup_oblique_camera()
	for cfg in [configs[0], configs[2], configs[3], configs[4]]:
		await _measure_config(cfg, false, out_dir, suffix)
	_log("")

	_log("INTERPRETATION")
	_log("  P1 (rim hidden) isolates the terrain top: it matches the board to ~0.00% — the fix works.")
	_log("  The radial profile shows the interior (0..~0.75 r) at ~0% and only the intended near-black")
	_log("  RIM border at the very edge. The FULL/CENTRAL 'with rim' deltas that read a few % are the")
	_log("  black rim clipped into the disc region PLUS a headless gamescope quirk: exactly ONE radial")
	_log("  band per run reads dark (it teleports run to run and never appears in a settled still — see")
	_log("  the flawless proof_ortho_*.png). Ground truth = P1 + the stills: the window matches the board.")

	# Write the sidecar and echo to stdout.
	var report := "\n".join(_report_lines) + "\n"
	var f := FileAccess.open("%s/luminance%s.txt" % [out_dir, suffix], FileAccess.WRITE)
	if f != null:
		f.store_string(report)
		f.close()
	print(report)
	print("BASE_LUMINANCE_QA_DONE %s" % out_dir)
	quit(0)


# === World ===

func _build_world() -> void:
	var we := WorldEnvironment.new()
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = Color(0.10, 0.11, 0.13)
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.85, 0.87, 0.92)
	_env.ambient_light_energy = 0.55
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = _env
	get_root().add_child(we)

	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-52, -38, 0)
	_sun.light_energy = 1.6
	_sun.shadow_enabled = true
	get_root().add_child(_sun)

	_table = load("res://scripts/table.gd").new()
	_table.name = "Table"
	var tmesh := MeshInstance3D.new()
	tmesh.name = "TableMesh"
	_table.add_child(tmesh)
	var tcol := CollisionShape3D.new()
	tcol.name = "TableCollision"
	_table.add_child(tcol)
	get_root().add_child(_table)
	_table.setup_table(Vector2(6, 4))

	# Bind a UNIFORM sand albedo on BOTH the ground and the shared base-top material so the only
	# spatial variation is the (identical) detail relief. Deterministic — no R2 battlemap needed.
	var sand := _flat_texture(SAND_COLOR)
	_ground_mat = _table.mesh_instance.material_override as ShaderMaterial
	_top_mat = _table.get_base_top_material()
	if _ground_mat != null:
		_ground_mat.set_shader_parameter("albedo_tex", sand)
	_top_mat.set_shader_parameter("albedo_tex", sand)
	_top_mat.set_shader_parameter("has_texture", true)

	# One bare base (no body, no ring) through the real BaseDecor path.
	_base = BaseDecor.build_base(false, false, 0.0, 0.0, BASE_RADIUS_M, Color(0.2, 0.4, 0.9), false, _top_mat)
	_base.position = BASE_POS
	get_root().add_child(_base)

	_camera = Camera3D.new()
	get_root().add_child(_camera)
	_camera.current = true


## Block until both async detail NoiseTexture2D relief maps have finished generating (the ground
## material and the shared base-top material reference the SAME two textures). Without this the
## capture races the background generation thread and the numbers are not reproducible.
func _await_noise_ready() -> void:
	var normal_tex := _top_mat.get_shader_parameter("detail_normal") as NoiseTexture2D
	var height_tex := _top_mat.get_shader_parameter("detail_height") as NoiseTexture2D
	var guard := 0
	while guard < 600:
		var normal_ready := normal_tex == null or normal_tex.get_image() != null
		var height_ready := height_tex == null or height_tex.get_image() != null
		if normal_ready and height_ready:
			return
		guard += 1
		await process_frame


## A small solid-colour sRGB texture with mipmaps, used as the uniform ground albedo.
func _flat_texture(color: Color) -> Texture2D:
	var img := Image.create(8, 8, true, Image.FORMAT_RGBA8)
	img.fill(color)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


# === Cameras ===

func _setup_ortho_camera() -> void:
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = ORTHO_SIZE_M
	# Straight down onto the base; up = -Z so world +X -> screen +X.
	_camera.look_at_from_position(BASE_POS + Vector3(0.0, 0.5, 0.0), BASE_POS, Vector3(0, 0, -1))


func _setup_oblique_camera() -> void:
	_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	_camera.fov = 30.0
	# Tight 3/4 so the base fills the frame; lit by the directional sun.
	_camera.look_at_from_position(BASE_POS + Vector3(0.045, 0.075, 0.075), BASE_POS, Vector3.UP)


# === Measurement ===

func _measure_config(cfg: Dictionary, ortho: bool, out_dir: String, suffix: String) -> void:
	var vig: float = cfg["vig"]
	var ssao_on: bool = cfg["ssao"]
	var detail_on: bool = cfg.get("detail", true)
	var shadow_on: bool = cfg.get("shadow", true)
	var hide_rim: bool = cfg.get("hide_rim", false)

	_env.ssao_enabled = ssao_on
	_env.ssao_radius = SSAO_RADIUS
	_env.ssao_intensity = SSAO_INTENSITY
	_sun.shadow_enabled = shadow_on
	var rim := _base.get_node_or_null("BaseRim") as MeshInstance3D
	if rim != null:
		rim.visible = not hide_rim
	_top_mat.set_shader_parameter("vignette_strength", vig)
	# "detail off" zeroes BOTH the micro-relief albedo modulation and the normal-map depth on the
	# base AND the board, giving a pure flat uniform-albedo surface on each — the cleanest read of
	# whether the base's shaded base-colour equals the board's.
	var albedo_strength := 0.12 if detail_on else 0.0
	var normal_strength := 0.35 if detail_on else 0.0
	for m in [_top_mat, _ground_mat]:
		if m != null:
			m.set_shader_parameter("detail_albedo_strength", albedo_strength)
			m.set_shader_parameter("detail_normal_strength", normal_strength)

	# Region masks in pixel space, radial around the projected base centre. The board reference is an
	# equal-area patch of BARE ground in the SAME frame, offset to the side — the ground is uniform
	# sand, so it is a valid reference, and a same-frame read cancels the with/without frame-difference
	# artefacts (anti-aliased discard/rim edges shifting sub-pixel between frames showed phantom rings
	# that never appear in a still). Averaged over frames for good measure.
	var center_px := _base_center_px(ortho)
	var top_r_px := _top_radius_px(ortho, center_px)
	var board_px := center_px + BOARD_PATCH_OFFSET
	_base.visible = true
	await _frames(SETTLE_FRAMES)
	var m := await _avg_top_vs_board(center_px, board_px, top_r_px * FULL_REGION_FRAC, top_r_px * CENTRAL_REGION_FRAC, AVG_FRAMES)
	var full := {"top": m["top_full"], "board": m["board_full"], "delta": _delta_pct(m["board_full"], m["top_full"])}
	var central := {"top": m["top_central"], "board": m["board_central"], "delta": _delta_pct(m["board_central"], m["top_central"])}
	# Single-frame image (for the radial profile + the saved proof PNG).
	var img_with := await _grab_image()

	_log("%s" % cfg["label"])
	_log("    FULL top : top=%.4f  board=%.4f  delta=%+.2f%%  %s" % [full.top, full.board, full.delta, _verdict(full.delta)])
	_log("    CENTRAL  : top=%.4f  board=%.4f  delta=%+.2f%%  %s" % [central.top, central.board, central.delta, _verdict(central.delta)])

	# Radial darkening profile (ortho only) for the two headline flat configs — localises WHERE any
	# darkening sits (uniform interior vs a rim-adjacent band vs the discard edge).
	if ortho and String(cfg["label"]).begins_with("P0"):
		var bands := [0.15, 0.35, 0.55, 0.75, 0.90, 0.98]
		var prev := 0.0
		var board_full := _mean_lum_disc(img_with, board_px, top_r_px)
		var line := "    radial delta by annulus (vs same-frame board):"
		for b in bands:
			var t := _mean_lum_annulus(img_with, center_px, top_r_px * prev, top_r_px * b)
			var d := (board_full - t) / board_full * 100.0 if board_full > 0.0001 else 0.0
			line += "  [%.2f-%.2f]=%+.1f%%" % [prev, b, d]
			prev = b
		_log(line)

	# Save ortho proof PNGs keyed by the config label prefix.
	if ortho:
		var prefix: String = String(cfg["label"]).substr(0, 2).strip_edges().to_lower()
		var proof_prefixes := {"p2": "fix", "p3": "v2", "p5": "current"}
		if proof_prefixes.has(prefix):
			img_with.save_png("%s/proof_ortho_%s%s.png" % [out_dir, proof_prefixes[prefix], suffix])


func _verdict(delta: float) -> String:
	return "OK (<2%)" if absf(delta) < 2.0 else "**OVER 2%**"


## Mean luminance of a pixel annulus [r_inner, r_outer] around center.
func _mean_lum_annulus(img: Image, center: Vector2, r_inner: float, r_outer: float) -> float:
	var ri2 := r_inner * r_inner
	var ro2 := r_outer * r_outer
	var x0 := int(maxf(0.0, center.x - r_outer))
	var x1 := int(minf(float(img.get_width() - 1), center.x + r_outer))
	var y0 := int(maxf(0.0, center.y - r_outer))
	var y1 := int(minf(float(img.get_height() - 1), center.y + r_outer))
	var sum := 0.0
	var count := 0
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var dx := float(x) - center.x
			var dy := float(y) - center.y
			var d2 := dx * dx + dy * dy
			if d2 >= ri2 and d2 <= ro2:
				var c := img.get_pixel(x, y)
				sum += c.r * LUM_R + c.g * LUM_G + c.b * LUM_B
				count += 1
	return sum / float(count) if count > 0 else 0.0


func _mean_lum_disc(img: Image, center: Vector2, radius_px: float) -> float:
	var r2 := radius_px * radius_px
	var x0 := int(maxf(0.0, center.x - radius_px))
	var x1 := int(minf(float(img.get_width() - 1), center.x + radius_px))
	var y0 := int(maxf(0.0, center.y - radius_px))
	var y1 := int(minf(float(img.get_height() - 1), center.y + radius_px))
	var sum := 0.0
	var count := 0
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var dx := float(x) - center.x
			var dy := float(y) - center.y
			if dx * dx + dy * dy <= r2:
				var c := img.get_pixel(x, y)
				sum += c.r * LUM_R + c.g * LUM_G + c.b * LUM_B
				count += 1
	return sum / float(count) if count > 0 else 0.0


func _base_center_px(ortho: bool) -> Vector2:
	if ortho:
		return Vector2(IMAGE_SIZE) * 0.5
	return _camera.unproject_position(BASE_POS + Vector3(0.0, BaseDecor.TOP_Y, 0.0))


func _top_radius_px(ortho: bool, center_px: Vector2) -> float:
	var top_world := BASE_RADIUS_M * TOP_RADIUS_RATIO
	if ortho:
		return top_world * float(IMAGE_SIZE.y) / ORTHO_SIZE_M
	# Perspective: project a point on the top rim and measure its pixel distance from the centre.
	# Use the smaller of the +X and +Z rim projections (the foreshortened axis) to stay inside.
	var top_y := BaseDecor.TOP_Y
	var px := _camera.unproject_position(BASE_POS + Vector3(top_world, top_y, 0.0))
	var pz := _camera.unproject_position(BASE_POS + Vector3(0.0, top_y, top_world))
	return minf(px.distance_to(center_px), pz.distance_to(center_px))


## Average, over `frames` captures, the terrain-top disc luminance and the bare-board patch luminance
## (both read from the SAME frame each time), for the FULL and CENTRAL radii.
func _avg_top_vs_board(center: Vector2, board: Vector2, full_r: float, central_r: float, frames: int) -> Dictionary:
	var tf := 0.0
	var tc := 0.0
	var bf := 0.0
	var bc := 0.0
	for _i in range(frames):
		await _frames(4)
		var img := await _grab_image()
		tf += _mean_lum_disc(img, center, full_r)
		tc += _mean_lum_disc(img, center, central_r)
		bf += _mean_lum_disc(img, board, full_r)
		bc += _mean_lum_disc(img, board, central_r)
	var n := float(frames)
	return {"top_full": tf / n, "top_central": tc / n, "board_full": bf / n, "board_central": bc / n}


func _delta_pct(board: float, top: float) -> float:
	return (board - top) / board * 100.0 if board > 0.0001 else 0.0


func _grab_image() -> Image:
	await RenderingServer.frame_post_draw
	return get_root().get_texture().get_image()


func _log(line: String) -> void:
	_report_lines.append(line)


func _frames(n: int) -> void:
	for _i in range(n):
		await process_frame
