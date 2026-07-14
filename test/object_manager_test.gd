extends GdUnitTestSuite
## Headless regression tests for ObjectManager's core table-object lifecycle:
## spawning (miniature / terrain), network-id identity, selection, teardown, and the
## pure base-footprint / arrange-spacing / cursor helpers. The drag / box-select /
## raw-input paths need a live camera + viewport and are exercised manually; this
## suite locks down the non-input logic that carries the most refactor risk.
##
## object_manager.gd has no class_name, so _om is typed Node3D and its dynamic
## methods need explicit result types (not :=).

const ObjectManagerScript = preload("res://scripts/object_manager.gd")

var _om: Node3D


func before_test() -> void:
	# Added to the tree so _ready runs and spawn_*'s add_child() has a valid parent.
	# No NetworkManager sibling exists here, so broadcasts no-op (we also pass false).
	_om = auto_free(ObjectManagerScript.new())
	add_child(_om)


func _unit_node(props: Dictionary) -> Node3D:
	var node: Node3D = auto_free(Node3D.new())
	add_child(node)
	var unit := GameUnit.new()
	unit.unit_properties = props
	node.set_meta("game_unit", unit)
	return node


# ===== Spawning + network-id identity =====

func test_spawn_miniature_adds_grouped_child_with_network_id() -> void:
	var m: Node3D = _om.spawn_miniature(Vector3(0.1, 0, 0.2), false)
	assert_that(m).is_not_null()
	assert_bool(m.is_in_group("selectable")).is_true()
	assert_bool(m.is_in_group("miniature")).is_true()
	assert_bool(m.has_meta("network_id")).is_true()
	assert_bool(m.get_parent() == _om).is_true()


func test_spawn_miniature_assigns_unique_ids_and_names() -> void:
	var a: Node3D = _om.spawn_miniature(Vector3.ZERO, false)
	var b: Node3D = _om.spawn_miniature(Vector3.ZERO, false)
	assert_int(int(a.get_meta("network_id"))).is_not_equal(int(b.get_meta("network_id")))
	assert_str(a.name).is_not_equal(b.name)


func test_spawn_miniature_honours_explicit_network_id() -> void:
	var m: Node3D = _om.spawn_miniature(Vector3.ZERO, false, 42)
	assert_int(int(m.get_meta("network_id"))).is_equal(42)


func test_spawn_terrain_is_terrain_grouped_with_offset_id() -> void:
	var t: Node3D = _om.spawn_terrain(Vector3.ZERO, false)
	assert_bool(t.is_in_group("terrain")).is_true()
	assert_bool(t.is_in_group("selectable")).is_true()
	# Auto terrain ids are offset (+10000) so they never collide with miniature ids.
	assert_int(int(t.get_meta("network_id"))).is_greater(9999)


func test_find_by_network_id() -> void:
	var m: Node3D = _om.spawn_miniature(Vector3.ZERO, false, 7)
	assert_bool(_om.find_by_network_id(7) == m).is_true()
	assert_that(_om.find_by_network_id(-1)).is_null()
	assert_that(_om.find_by_network_id(9999)).is_null()


# ===== Selection =====

func test_select_then_deselect() -> void:
	var a: Node3D = _om.spawn_miniature(Vector3.ZERO, false)
	var b: Node3D = _om.spawn_miniature(Vector3(0.05, 0, 0), false)
	_om.select_objects([a, b])
	assert_int(_om.get_selected_objects().size()).is_equal(2)
	_om.deselect_all()
	assert_int(_om.get_selected_objects().size()).is_equal(0)


func test_select_ignores_invalid_entries() -> void:
	var a: Node3D = _om.spawn_miniature(Vector3.ZERO, false)
	_om.select_objects([a, null])
	assert_int(_om.get_selected_objects().size()).is_equal(1)


func test_select_emits_selection_changed() -> void:
	var a: Node3D = _om.spawn_miniature(Vector3.ZERO, false)
	var seen := [0]
	_om.selection_changed.connect(func(_objs): seen[0] += 1)
	_om.select_objects([a])
	assert_int(seen[0]).is_greater(0)


# ===== Teardown =====

func test_clear_all_objects_resets_state() -> void:
	_om.spawn_miniature(Vector3.ZERO, false)
	_om.spawn_miniature(Vector3.ZERO, false)
	var a: Node3D = _om.spawn_miniature(Vector3.ZERO, false)
	_om.select_objects([a])
	_om.clear_all_objects(false)
	assert_int(_om.get_selected_objects().size()).is_equal(0)
	# queue_free() is deferred — children clear out on the next frame.
	await get_tree().process_frame
	assert_int(_om.get_child_count()).is_equal(0)


# ===== Pure helpers: base footprint / arrange spacing / cursor =====

func test_base_footprint_round() -> void:
	var fp: Vector2 = _om._base_footprint(_unit_node({"base_size_round": 40}))
	assert_float(fp.x).is_equal_approx(0.040, 0.0001)
	assert_float(fp.y).is_equal_approx(0.040, 0.0001)


func test_base_footprint_oval_uses_both_axes() -> void:
	var fp: Vector2 = _om._base_footprint(_unit_node({
		"base_is_oval": true, "base_width_mm": 25, "base_depth_mm": 50,
	}))
	assert_float(fp.x).is_equal_approx(0.025, 0.0001)
	assert_float(fp.y).is_equal_approx(0.050, 0.0001)


func test_base_footprint_defaults_without_unit() -> void:
	var node: Node3D = auto_free(Node3D.new())
	add_child(node)
	var fp: Vector2 = _om._base_footprint(node)
	assert_float(fp.x).is_equal_approx(0.032, 0.0001)
	assert_float(fp.y).is_equal_approx(0.032, 0.0001)


func test_arrange_spacing_empty_returns_default() -> void:
	var s: Vector2 = _om._arrange_spacing([])
	assert_float(s.x).is_equal_approx(0.04, 0.0001)
	assert_float(s.y).is_equal_approx(0.04, 0.0001)


func test_cursor_table_position_without_camera_is_zero() -> void:
	# With no active Camera3D in the test viewport the helper must fall back to
	# Vector3.ZERO rather than crash.
	assert_bool(_om.get_cursor_table_position() == Vector3.ZERO).is_true()


# ===== Auto-face predicate (static, pure) =====
## _should_auto_face decides whether a moved object is auto-faced to its drag
## direction on drop. Regiment movement-tray blocks keep their facing (AoF:R
## v3.5.1, p.8 "Pivoting"); RigidBodies are physics-driven. Pure/static so it
## is testable without a camera or viewport.

func test_should_auto_face_true_for_plain_node3d() -> void:
	var node: Node3D = auto_free(Node3D.new())
	add_child(node)
	assert_bool(ObjectManagerScript._should_auto_face(node)).is_true()


func test_should_auto_face_false_for_rigid_body() -> void:
	var body: Node3D = auto_free(RigidBody3D.new())
	add_child(body)
	assert_bool(ObjectManagerScript._should_auto_face(body)).is_false()


func test_should_auto_face_false_for_regiment_tray() -> void:
	# Regression guard: a RegimentTray must NOT be auto-faced. Previously the tray
	# was rotated to the drag direction, silently overriding its set facing.
	var tray: Node3D = auto_free(RegimentTray.new())
	add_child(tray)
	assert_bool(ObjectManagerScript._should_auto_face(tray)).is_false()


func test_should_auto_face_false_for_null() -> void:
	assert_bool(ObjectManagerScript._should_auto_face(null)).is_false()


# ===== Auto-face-on-drop: regiment facing preservation (integrative) =====

func test_auto_face_preserves_regiment_tray_facing() -> void:
	# A regiment movement-tray block keeps its set facing after a drag (AoF:R
	# v3.5.1, p.8 "Pivoting": facing only changes via an explicit pivot, never
	# implicitly from the drag direction). The tray is selected, grabbed at the
	# origin, and dropped 1 m along +X (well past the auto-face deadzone); its
	# facing must stay where the player set it.
	var tray: Node3D = auto_free(RegimentTray.new())
	add_child(tray)
	tray.global_position = Vector3.ZERO
	tray.rotation.y = 1.0  # arbitrary, non-zero facing (radians)
	var facing_before: float = tray.rotation.y

	_om.select_objects([tray])
	_om._drag_start_positions[tray] = Vector3.ZERO
	tray.global_position = Vector3(1.0, 0.0, 0.0)

	_om._auto_face_moved_models()

	assert_float(tray.rotation.y).is_equal_approx(facing_before, 0.0001)


func test_auto_face_still_turns_loose_models() -> void:
	# A loose (non-regiment) miniature is still auto-faced to its drag direction
	# after a drop — the fix must not suppress the existing playtest behaviour.
	var mini: Node3D = _om.spawn_miniature(Vector3.ZERO, false)
	_om.select_objects([mini])
	_om._drag_start_positions[mini] = Vector3.ZERO
	# Move +Z (north). atan2(moved.x, moved.z) = atan2(0, 1) = 0 -> faces +Z.
	mini.global_position = Vector3(0.0, 0.0, 1.0)

	_om._auto_face_moved_models()

	assert_float(mini.rotation.y).is_equal_approx(0.0, 0.0001)


func test_auto_face_skips_freed_object_without_crash() -> void:
	# A freed object in the selection (e.g. a model destroyed mid-drag) must not
	# crash auto-face — the is_instance_valid guard at the call site short-circuits
	# before the typed _should_auto_face call (a freed object is rejected by the
	# Node3D param at call time). The live co-selection is still auto-faced.
	var mini: Node3D = _om.spawn_miniature(Vector3.ZERO, false)
	var doomed: Node3D = _om.spawn_miniature(Vector3.ZERO, false)
	_om.select_objects([doomed, mini])
	_om._drag_start_positions[doomed] = Vector3.ZERO
	_om._drag_start_positions[mini] = Vector3.ZERO
	doomed.free()  # destroy after registration — simulates a mid-drag kill
	mini.global_position = Vector3(0.0, 0.0, 1.0)  # move the live one +Z

	_om._auto_face_moved_models()  # must not error on the freed co-selection

	# Live model was still auto-faced; the freed one was skipped silently.
	assert_float(mini.rotation.y).is_equal_approx(0.0, 0.0001)


# ===== Cursor-follow facing math (static, pure) =====
## facing_rotation_to returns the rotation.y that aims a piece's +Z forward at a target — the shared
## core of the R-to-cursor rotation (loose models + regiment trays). Convention: +Z faces +Z (rot 0),
## +X faces +X (rot +90°). Pure/static so it needs no camera or viewport.

func test_facing_rotation_target_ahead_is_zero() -> void:
	# Target straight ahead (+Z) → no turn.
	assert_float(ObjectManagerScript.facing_rotation_to(0.0, 0.0, 0.0, 1.0)).is_equal_approx(0.0, 0.0001)


func test_facing_rotation_target_right_is_quarter_turn() -> void:
	# Target to the +X side → +90° (π/2).
	assert_float(ObjectManagerScript.facing_rotation_to(0.0, 0.0, 1.0, 0.0)).is_equal_approx(PI / 2.0, 0.0001)


func test_facing_rotation_target_behind_is_half_turn() -> void:
	# Target directly behind (−Z) → ±180° (π).
	assert_float(absf(ObjectManagerScript.facing_rotation_to(0.0, 0.0, 0.0, -1.0))).is_equal_approx(PI, 0.0001)


func test_facing_rotation_is_relative_to_own_position() -> void:
	# A loose model at (5, 5) with the target at (5, 8) faces straight +Z, independent of world origin
	# (each model pivots around its OWN base, not a shared centre).
	assert_float(ObjectManagerScript.facing_rotation_to(5.0, 5.0, 5.0, 8.0)).is_equal_approx(0.0, 0.0001)


# ===== Strict "dry brush" cap: the band FOLLOWS the selected movement action =====
# (Regression for the refinement: Advance -> Advance band, Rush/Charge -> Rush band, not always Rush.)

const _CAP_INCH := 0.0254   # metres per inch, for the metres assertions


## Minimal stand-in for the movement-range controller (typed Node in ObjectManager): returns
## fixed Advance/Rush bands so the cap resolution can be exercised without a live army / props.
class _BandStub extends Node:
	var bands: Dictionary = {"advance": 6, "rush": 12}
	func bands_for_model(_node) -> Dictionary:
		return bands


func test_cap_band_advance_selection_uses_advance_band() -> void:
	_om.set("_movement_cap", ObjectManager.MovementCap.ADVANCE)
	assert_int(int(_om._cap_band_inches({"advance": 6, "rush": 12}))).is_equal(6)


func test_cap_band_rush_selection_uses_rush_band() -> void:
	_om.set("_movement_cap", ObjectManager.MovementCap.RUSH)
	assert_int(int(_om._cap_band_inches({"advance": 6, "rush": 12}))).is_equal(12)


func test_cap_band_off_falls_back_to_rush_max() -> void:
	_om.set("_movement_cap", ObjectManager.MovementCap.OFF)
	assert_int(int(_om._cap_band_inches({"advance": 6, "rush": 12}))).is_equal(12)


func test_cap_band_follows_fast_modified_bands() -> void:
	# Fast/aura-widened bands flow through unchanged (the controller already folded them in).
	var bands := {"advance": 8, "rush": 16}
	_om.set("_movement_cap", ObjectManager.MovementCap.ADVANCE)
	assert_int(int(_om._cap_band_inches(bands))).is_equal(8)
	_om.set("_movement_cap", ObjectManager.MovementCap.RUSH)
	assert_int(int(_om._cap_band_inches(bands))).is_equal(16)


func test_strict_cap_meters_resolves_per_selected_action() -> void:
	# End-to-end: with enforcement on + a model anchor, the cap METRES follow the selector —
	# Advance caps at the Advance band (6"), Rush/Charge at the Rush band (12").
	var was := GraphicsSettings.enforce_movement_limit
	GraphicsSettings.enforce_movement_limit = true
	var stub: Node = auto_free(_BandStub.new())
	add_child(stub)
	_om.movement_range_controller = stub
	var mini: Node3D = auto_free(Node3D.new())
	add_child(mini)
	mini.add_to_group("miniature")
	_om.set("_drag_anchor_object", mini)

	_om.set("_movement_cap", ObjectManager.MovementCap.ADVANCE)
	assert_float(float(_om._compute_strict_cap_meters())).is_equal_approx(6.0 * _CAP_INCH, 0.0005)

	_om.set("_movement_cap", ObjectManager.MovementCap.RUSH)
	assert_float(float(_om._compute_strict_cap_meters())).is_equal_approx(12.0 * _CAP_INCH, 0.0005)

	GraphicsSettings.enforce_movement_limit = was
