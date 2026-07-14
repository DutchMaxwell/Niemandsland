class_name MoveTrails
extends Node3D
## "Path painting" P2 — visible chalk trails: the model IS the brush. While a player
## drags, the traversed path paints itself BEHIND the model as a ribbon exactly as wide
## as the base (outer edge = the binding geometry rule); on drop the trail commits with
## a subtle inch stamp of the measured arc. Committed trails persist until the END OF
## THE UNIT'S ACTIVATION (MoveLedger.note_commit / note_activation_done / round advance),
## then fade. Clicking a trail surfaces its proof ("Unit — X.X\" moved").
##
## Mirrors the system-owner overlay pattern (PinnedRulers / SeparationVisualizer): a
## direct child of /root/Main holding pure visuals — no colliders, no physics, never in
## the selection path. Trails are SESSION-ONLY (like pinned rulers, they are not saved).
##
## The ribbon geometry (mitred base-width band + stadium end caps + two outer base-edge
## lines) is PORTED from the solo branch's AI move-corridor renderer, so human and AI
## moves share ONE visual language — here it is pooled (acquire/release) because human
## drags repaint live at ~15 Hz and commit a mesh per moved model.
##
## Ownership colour: trails render in the owning ARMY's player colour (chalk-tinted),
## matching the PinnedRulers palette, so the opponent can read whose proof they see.

# ===== Constants (heights/shape shared with the solo corridor renderer) =====

## Height offsets keeping trails just above the table without z-fighting (metres).
const TRAIL_Y_M := 0.012
const TRAIL_EDGE_Y_M := 0.015
## Inch-stamp / proof label heights (metres).
const TRAIL_STAMP_Y_M := 0.03
const PROOF_LABEL_Y_M := 0.06
## Semicircle end-cap resolution (segments per 180 degrees).
const CAP_SEGS := 8
## Corner-miter width clamp — bounds the spike a hairpin corner can produce.
const MITER_MIN := 0.35

## Chalk look: the owner colour lifted toward white, translucent fill + brighter edges.
const CHALK_LERP := 0.45
const FILL_ALPHA := 0.16
const EDGE_ALPHA := 0.7

## Fade timings (seconds): activation end, round sweep, click-proof display.
const FADE_S := 1.2
const ROUND_FADE_S := 0.6
const PROOF_S := 2.5

## Extra pick margin (metres) past the ribbon's half-width for the click-proof.
const PROOF_PICK_MARGIN_M := 0.01

## Pool cap — beyond this, released ribbons/labels are freed instead of parked.
const POOL_MAX := 48

# ===== State =====

## P1 data layer: recording + the activation-end clearing rules (pure, tested).
var ledger := MoveLedger.new()

## Committed trails: {unit, owner, name, mesh, label, inches, points, radius_m,
## fading, pulse (Tween|null), fade (Tween|null)}.
var _trails: Array[Dictionary] = []

## Live (in-drag) ribbons: {offset, radius_m, fill, edge, mesh}.
var _live: Array[Dictionary] = []

var _mesh_pool: Array = []
var _label_pool: Array = []

## VISIBILITY CONTROL — two independent gates over the CHALK only (the ledger records
## regardless, so the MP proof-of-movement data always survives):
##   user_show_trails : the player's persisted preference (GraphicsSettings.show_move_trails,
##     default on) — the T hotkey and the Settings toggle flip it; drives `visible`.
##   _deployment_active : the deployment PHASE gate — while deploying, no chalk paints or
##     shows (placement isn't movement-proof). Derived from the deployment-zones state.
## Trails are only PAINTED (live + committed visuals) when both allow it; the ledger's
## record()/note_commit() run unconditionally.
var user_show_trails: bool = true
var _deployment_active: bool = false


func _ready() -> void:
	# Load the persisted preference (default on). GraphicsSettings is an always-present
	# autoload; guarded so headless/test contexts without it still work.
	if Engine.has_singleton("GraphicsSettings") or get_node_or_null("/root/GraphicsSettings") != null:
		user_show_trails = bool(GraphicsSettings.show_move_trails)
	_apply_visibility()


## May chalk be drawn right now? (Live ribbons + committed visuals — NOT the ledger.)
func _painting_allowed() -> bool:
	return user_show_trails and not _deployment_active


## Recompute the node's visibility from the two gates. During deployment nothing shows;
## with the preference off nothing shows; otherwise trails are visible.
func _apply_visibility() -> void:
	visible = user_show_trails and not _deployment_active


# ===== Visibility control (persisted preference + deployment phase) =====

## Set the persisted "show move trails" preference (T hotkey + Settings toggle). Writes it
## through to GraphicsSettings so it sticks across sessions, and re-applies visibility.
func set_user_show_trails(on: bool) -> void:
	user_show_trails = on
	if get_node_or_null("/root/GraphicsSettings") != null:
		GraphicsSettings.show_move_trails = on
		GraphicsSettings.save_settings()
	_apply_visibility()


## Deployment PHASE gate: while true, no chalk paints or shows (the ledger keeps recording).
## Driven by the deployment-zones-visible state (see main._sync_move_trails_deployment).
func set_deployment_active(active: bool) -> void:
	if _deployment_active == active:
		return
	_deployment_active = active
	_apply_visibility()


# ===== Live painting (during the drag) =====

## Begin painting for one drag. `specs`: one entry per painted mover —
## {offset: Vector2 (mover start - anchor start, XZ), radius_m: float, owner: int}.
## No-op while chalk is suppressed (deployment / preference off) — the drop still records.
func begin_live(specs: Array) -> void:
	end_live()
	if not _painting_allowed():
		return
	for spec in specs:
		var d := spec as Dictionary
		var radius: float = float(d.get("radius_m", 0.0))
		if radius <= 0.0:
			continue
		var chalk := _chalk_color(int(d.get("owner", 0)))
		_live.append({
			"offset": d.get("offset", Vector2.ZERO),
			"radius_m": radius,
			"fill": Color(chalk.r, chalk.g, chalk.b, FILL_ALPHA),
			"edge": Color(chalk.r, chalk.g, chalk.b, EDGE_ALPHA),
			"mesh": _acquire_ribbon(),
		})


## Repaint every live ribbon from the anchor's sampled polyline + the anchor's CURRENT
## position (the bit of path since the last sample) — called at the drag throttle.
func update_live(anchor_points: PackedVector2Array, anchor_tail: Vector2) -> void:
	for entry in _live:
		var e := entry as Dictionary
		var pts := MoveLedger.translated(anchor_points, e["offset"] as Vector2)
		var tail: Vector2 = anchor_tail + (e["offset"] as Vector2)
		if pts.is_empty() or pts[pts.size() - 1].distance_to(tail) > 0.0005:
			pts.append(tail)
		_rebuild_ribbon(e["mesh"] as MeshInstance3D, pts, float(e["radius_m"]),
				e["fill"] as Color, e["edge"] as Color)


## Drop the live ribbons (drag ended or cancelled) — committed trails replace them.
func end_live() -> void:
	for entry in _live:
		_release_ribbon((entry as Dictionary)["mesh"] as MeshInstance3D)
	_live.clear()


# ===== Committed trails =====

## Commit one model's executed move: ALWAYS records to the ledger (unit, model, net
## polyline, measured arc — the MP proof-of-movement data, kept whether or not chalk is
## drawn), then paints the persistent trail UNLESS chalk is suppressed. Called for local
## drops (main) AND for received MP trails (network_manager) — drop_id travels with the
## message so both sides fade identically.
func commit_trail(owner: int, unit_key: String, unit_name: String, model_id: int,
		points: PackedVector2Array, radius_m: float, round_num: int, drop_id: int) -> void:
	if points.size() < 2 or radius_m <= 0.0:
		return
	# Activation bookkeeping + the ledger record run UNCONDITIONALLY (proof always survives).
	for ended in ledger.note_commit(owner, unit_key, drop_id):
		fade_unit(ended)
	var entry := ledger.record(owner, unit_key, unit_name, model_id, points, round_num)
	# DEPLOYMENT = record-only: no chalk is built, so nothing pops in when play begins.
	# (The preference-off case still builds hidden, so toggling on reveals the activation.)
	if _deployment_active:
		return
	var chalk := _chalk_color(owner)
	var fill := Color(chalk.r, chalk.g, chalk.b, FILL_ALPHA)
	var edge := Color(chalk.r, chalk.g, chalk.b, EDGE_ALPHA)
	var mesh := _acquire_ribbon()
	_rebuild_ribbon(mesh, points, radius_m, fill, edge)
	var label := _acquire_label()
	label.text = "%.1f\"" % float(entry["inches"])
	label.modulate = Color(chalk.r, chalk.g, chalk.b, 0.9)
	var mid := points[points.size() >> 1]
	label.global_position = Vector3(mid.x, TRAIL_STAMP_Y_M, mid.y)
	_trails.append({
		"unit": unit_key,
		"owner": owner,
		"name": unit_name,
		"mesh": mesh,
		"label": label,
		"inches": float(entry["inches"]),
		"points": points,
		"radius_m": radius_m,
		"fading": false,
		"pulse": null,
		"fade": null,
	})


## Fade every visible trail of one unit (its activation ended).
func fade_unit(unit_key: String, duration: float = FADE_S) -> void:
	for rec in _trails:
		if str(rec["unit"]) == unit_key and not bool(rec["fading"]):
			_fade_record(rec, duration)


## A unit was marked Activated (local toggle or MP sync): its activation is done.
func on_activation_done(unit_key: String) -> void:
	ledger.note_activation_done(unit_key)
	fade_unit(unit_key)


## Round advance: every activation ends — sweep the whole table clean (quick fade).
func on_round_advance() -> void:
	ledger.note_round_advance()
	for rec in _trails:
		if not bool(rec["fading"]):
			_fade_record(rec, ROUND_FADE_S)


## Remove every trail immediately (Shift+T) — visuals only; ledger entries persist.
func clear_all() -> void:
	ledger.clear_active()
	for rec in _trails:
		_kill_record_tweens(rec)
		_release_ribbon(rec["mesh"] as MeshInstance3D)
		_release_label(rec["label"] as Label3D)
	_trails.clear()


## Hide/show all trails (T hotkey + Settings toggle) — the "don't nag" switch from the
## design. Flips the PERSISTED preference so the choice sticks across sessions.
func toggle_trails_visible() -> void:
	set_user_show_trails(not user_show_trails)


# ===== Click-proof =====

## A click landed on the empty table at `world_pos`: if a committed trail is under it
## (within its half-width + margin), pulse the ribbon and show the proof label
## ("Unit — X.X\" moved"). Returns whether a trail answered.
func try_proof_at(world_pos: Vector3) -> bool:
	if not visible:
		return false
	var p := Vector2(world_pos.x, world_pos.z)
	var best: Dictionary = {}
	var best_d := INF
	for rec in _trails:
		if bool(rec["fading"]):
			continue
		var d := MoveLedger.distance_to_polyline_m(p, rec["points"] as PackedVector2Array)
		if d <= float(rec["radius_m"]) + PROOF_PICK_MARGIN_M and d < best_d:
			best_d = d
			best = rec
	if best.is_empty():
		return false
	# Pulse the ribbon (brighten and settle back).
	var mat := (best["mesh"] as MeshInstance3D).material_override as StandardMaterial3D
	if mat != null:
		if best["pulse"] is Tween and (best["pulse"] as Tween).is_valid():
			(best["pulse"] as Tween).kill()
		mat.albedo_color = Color(1, 1, 1, 1)
		var tw := create_tween()
		tw.tween_property(mat, "albedo_color", Color(2.2, 2.2, 2.2, 1.0), 0.15)
		tw.tween_property(mat, "albedo_color", Color(1, 1, 1, 1), 0.45)
		best["pulse"] = tw
	# Transient proof label above the click point (allocated, not pooled — user-paced).
	var chalk := _chalk_color(int(best["owner"]))
	var label := _make_label()
	label.pixel_size = 0.0007
	label.text = "%s — %.1f\" moved" % [str(best["name"]), float(best["inches"])]
	label.modulate = Color(chalk.r, chalk.g, chalk.b, 1.0)
	add_child(label)
	label.global_position = Vector3(world_pos.x, PROOF_LABEL_Y_M, world_pos.z)
	var lt := label.create_tween()
	lt.tween_interval(PROOF_S)
	lt.tween_property(label, "modulate:a", 0.0, 0.4)
	lt.tween_callback(label.queue_free)
	return true


# ===== Ribbon geometry (ported from the solo AI move-corridor renderer) =====

## Rebuild `mesh_inst`'s ImmediateMesh as the base-width swept ribbon for `path` (world
## XZ, metres): a translucent stadium fill (mitred band + two semicircle end caps) and
## two brighter OUTER BASE-EDGE lines at +/- radius — where the ribbon is, the base
## physically travelled. Degenerate input (fewer than 2 distinct points) clears the mesh.
func _rebuild_ribbon(mesh_inst: MeshInstance3D, path: PackedVector2Array, radius_m: float,
		fill: Color, edge: Color) -> void:
	var im := mesh_inst.mesh as ImmediateMesh
	if im == null:
		return
	im.clear_surfaces()
	# Deduplicate near-identical waypoints (zero legs break the perpendicular math).
	var pts := PackedVector2Array()
	for wp in path:
		if pts.is_empty() or pts[pts.size() - 1].distance_to(wp) > 0.0008:
			pts.append(wp)
	if pts.size() < 2 or radius_m <= 0.0:
		return
	# Per-waypoint mitred left/right offsets: the averaged perpendicular of adjacent
	# legs, widened by 1/dot (clamped) so the ribbon keeps its base width through corners.
	var lefts := PackedVector2Array()
	var rights := PackedVector2Array()
	for i in range(pts.size()):
		var dir_in: Vector2 = (pts[i] - pts[i - 1]).normalized() if i > 0 else Vector2.ZERO
		var dir_out: Vector2 = (pts[i + 1] - pts[i]).normalized() if i < pts.size() - 1 else Vector2.ZERO
		var blend := dir_in + dir_out
		var dir := blend.normalized() if blend.length() > 0.0001 else (dir_in if dir_in != Vector2.ZERO else dir_out)
		var perp := Vector2(-dir.y, dir.x)
		var seg_dir := dir_out if dir_out != Vector2.ZERO else dir_in
		var seg_perp := Vector2(-seg_dir.y, seg_dir.x)
		var widen: float = 1.0 / maxf(MITER_MIN, absf(perp.dot(seg_perp)))
		lefts.append(pts[i] + perp * radius_m * widen)
		rights.append(pts[i] - perp * radius_m * widen)
	# Surface 1: the translucent band between the base edges.
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in range(pts.size()):
		im.surface_set_color(fill)
		im.surface_add_vertex(Vector3(lefts[i].x, TRAIL_Y_M, lefts[i].y))
		im.surface_set_color(fill)
		im.surface_add_vertex(Vector3(rights[i].x, TRAIL_Y_M, rights[i].y))
	im.surface_end()
	# Surfaces 2+3: semicircle end caps — the stadium shape of a base swept along the path.
	_ribbon_cap(im, pts[0], (pts[1] - pts[0]).normalized() * -1.0, radius_m, fill)
	_ribbon_cap(im, pts[pts.size() - 1], (pts[pts.size() - 1] - pts[pts.size() - 2]).normalized(), radius_m, fill)
	# Surfaces 4+5: the two OUTER BASE-EDGE lines — the binding geometry made visible.
	for side in [lefts, rights]:
		im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
		for v in side:
			im.surface_set_color(edge)
			im.surface_add_vertex(Vector3((v as Vector2).x, TRAIL_EDGE_Y_M, (v as Vector2).y))
		im.surface_end()


## One semicircular ribbon end cap: a triangle fan around `centre`, opening in `dir`
## (the outward direction at that end of the path), sweeping half a turn.
func _ribbon_cap(im: ImmediateMesh, centre: Vector2, dir: Vector2, radius_m: float, fill: Color) -> void:
	if dir.length() < 0.0001:
		return
	var start := Vector2(-dir.y, dir.x)
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for s in range(CAP_SEGS):
		var a0 := float(s) * PI / float(CAP_SEGS)
		var a1 := float(s + 1) * PI / float(CAP_SEGS)
		var p0 := centre + start.rotated(-a0) * radius_m
		var p1 := centre + start.rotated(-a1) * radius_m
		im.surface_set_color(fill)
		im.surface_add_vertex(Vector3(centre.x, TRAIL_Y_M, centre.y))
		im.surface_set_color(fill)
		im.surface_add_vertex(Vector3(p0.x, TRAIL_Y_M, p0.y))
		im.surface_set_color(fill)
		im.surface_add_vertex(Vector3(p1.x, TRAIL_Y_M, p1.y))
	im.surface_end()


# ===== Pools =====

func _acquire_ribbon() -> MeshInstance3D:
	var mi: MeshInstance3D
	if _mesh_pool.is_empty():
		mi = MeshInstance3D.new()
		mi.mesh = ImmediateMesh.new()
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.vertex_color_use_as_albedo = true
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mi.material_override = mat
		add_child(mi)
	else:
		mi = _mesh_pool.pop_back()
		mi.visible = true
	# Reset the fade/pulse-tweened multiplier (vertex colours carry the real tint).
	(mi.material_override as StandardMaterial3D).albedo_color = Color(1, 1, 1, 1)
	return mi


func _release_ribbon(mi: MeshInstance3D) -> void:
	if mi == null or not is_instance_valid(mi):
		return
	(mi.mesh as ImmediateMesh).clear_surfaces()
	mi.visible = false
	if _mesh_pool.size() < POOL_MAX:
		_mesh_pool.append(mi)
	else:
		mi.queue_free()


func _acquire_label() -> Label3D:
	var label: Label3D
	if _label_pool.is_empty():
		label = _make_label()
		add_child(label)
	else:
		label = _label_pool.pop_back()
		label.visible = true
	label.pixel_size = 0.0004
	label.modulate = Color(1, 1, 1, 1)
	return label


func _release_label(label: Label3D) -> void:
	if label == null or not is_instance_valid(label):
		return
	label.visible = false
	if _label_pool.size() < POOL_MAX:
		_label_pool.append(label)
	else:
		label.queue_free()


## A fresh billboard label in the trail style (subtle inch stamp / proof text).
func _make_label() -> Label3D:
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.pixel_size = 0.0004
	label.outline_size = 8
	return label


# ===== Internals =====

## The owning ARMY's colour (PinnedRulers palette, player slots 1-4) lifted toward
## white — the chalk look, readable in every player's colour on every client.
func _chalk_color(owner: int) -> Color:
	var base: Color = PinnedRulers.OWNER_COLORS.get(owner, PinnedRulers.SOLO_COLOR)
	return base.lerp(Color.WHITE, CHALK_LERP)


func _fade_record(rec: Dictionary, duration: float) -> void:
	rec["fading"] = true
	_kill_record_tweens(rec)
	var mesh := rec["mesh"] as MeshInstance3D
	var label := rec["label"] as Label3D
	var mat: StandardMaterial3D = (mesh.material_override as StandardMaterial3D) if is_instance_valid(mesh) else null
	if mat == null:
		_drop_record(rec)
		return
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(mat, "albedo_color:a", 0.0, duration)
	if is_instance_valid(label):
		tw.tween_property(label, "modulate:a", 0.0, duration)
	tw.set_parallel(false)
	tw.tween_callback(_drop_record.bind(rec))
	rec["fade"] = tw


func _drop_record(rec: Dictionary) -> void:
	_release_ribbon(rec["mesh"] as MeshInstance3D)
	_release_label(rec["label"] as Label3D)
	_trails.erase(rec)


func _kill_record_tweens(rec: Dictionary) -> void:
	for key in ["pulse", "fade"]:
		if rec[key] is Tween and (rec[key] as Tween).is_valid():
			(rec[key] as Tween).kill()
		rec[key] = null
