extends GdUnitTestSuite
## Tests the ruin shell-wall logic in terrain_overlay.gd: the crumble mirror rule
## (taper_dir vs. the quad's +U direction) and the deterministic per-segment panel pick.
## See docs/HANDOFF_RUIN_WALLS.md §6 (gotchas #1 and #5).

const OverlayScript = preload("res://scripts/terrain_overlay.gd")


func _overlay() -> Node3D:
	# Not added to the tree on purpose: these helpers are pure and must not need
	# _ready() (no RuinsLibrary, no network).
	return auto_free(OverlayScript.new())


func test_crumble_flip_canonical_pairs_unmirrored() -> void:
	# Under this renderer's wall rotations (N=0, E=+90°, S=180°, W=-90°) the quad's +U
	# already points at the free end for every unrotated piece — no mirror needed.
	var overlay := _overlay()
	var pairs := [[0, 1], [1, 0], [2, 3], [3, 2]]  # [edge_side, taper_dir]
	for pair: Array in pairs:
		var seg := {"edge_side": pair[0], "taper_dir": pair[1]}
		assert_bool(overlay._crumble_needs_flip(seg)).is_false()


func test_crumble_flip_rotated_pairs_mirrored() -> void:
	# A 90°-rotated piece pairs e.g. the E side with a S taper — +U then points at the
	# corner instead of the free end, so the panel must mirror.
	var overlay := _overlay()
	var pairs := [[1, 2], [0, 3], [3, 0], [2, 1]]
	for pair: Array in pairs:
		var seg := {"edge_side": pair[0], "taper_dir": pair[1]}
		assert_bool(overlay._crumble_needs_flip(seg)).is_true()


func test_crumble_flip_unknown_taper_is_safe() -> void:
	# Legacy saves / hand-drawn free walls carry no taper_dir -> never mirror.
	var overlay := _overlay()
	assert_bool(overlay._crumble_needs_flip({"edge_side": 0})).is_false()
	assert_bool(overlay._crumble_needs_flip({"edge_side": 2, "taper_dir": -1})).is_false()
	assert_bool(overlay._crumble_needs_flip({"edge_side": 1, "taper_dir": 7})).is_false()


func test_panel_pick_crumble_roles_map_to_their_texture() -> void:
	var overlay := _overlay()
	for role in ["crumble_a", "crumble_b", "crumble_steep"]:
		var seg := {"edge_cell": Vector2i(3, 4), "edge_side": 0, "role": role}
		assert_str(overlay._panel_for_segment(seg)).is_equal(role)


func test_panel_pick_is_deterministic_per_segment() -> void:
	# Walls are rebuilt locally on every client; the same segment must always pick the
	# same "full" panel (multiplayer determinism — never a global RNG).
	var overlay_a := _overlay()
	var overlay_b := _overlay()
	for x in range(8):
		for side in range(4):
			var seg := {"edge_cell": Vector2i(x, 11 - x), "edge_side": side, "role": "full"}
			var pick: String = overlay_a._panel_for_segment(seg)
			assert_str(overlay_b._panel_for_segment(seg)).is_equal(pick)
			assert_str(overlay_a._panel_for_segment(seg)).is_equal(pick)


func test_panel_pick_returns_only_known_panels() -> void:
	var overlay := _overlay()
	var known := ["solid_a", "solid_b", "topdmg_a", "opening_a", "window"]
	for x in range(20):
		for y in range(20):
			var seg := {"edge_cell": Vector2i(x, y), "edge_side": (x + y) % 4, "role": "full"}
			assert_bool(known.has(overlay._panel_for_segment(seg))).is_true()


# === Shell closure: alpha profile + interior openings ========================


## A synthetic RGBA panel: fully opaque stone, optionally with transparent regions.
func _image(w: int, h: int) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.5, 0.5, 0.5, 1.0))
	return img


func test_alpha_profile_full_panel_is_all_one() -> void:
	var profile := OverlayScript._alpha_top_profile(_image(96, 96), 12)
	assert_int(profile.size()).is_equal(12)
	for value in profile:
		assert_float(value).is_equal_approx(1.0, 0.001)


func test_alpha_profile_follows_a_step() -> void:
	# Left half full height, right half cleared down to 50% -> stepped profile.
	var img := _image(96, 96)
	img.fill_rect(Rect2i(48, 0, 48, 48), Color(0, 0, 0, 0))
	var profile := OverlayScript._alpha_top_profile(img, 12)
	assert_float(profile[0]).is_equal_approx(1.0, 0.05)
	assert_float(profile[11]).is_equal_approx(0.5, 0.06)


func test_alpha_profile_rgb_panel_has_no_holes() -> void:
	var img := Image.create(96, 96, false, Image.FORMAT_RGB8)
	img.fill(Color(0.5, 0.5, 0.5))
	var profile := OverlayScript._alpha_top_profile(img, 8)
	for value in profile:
		assert_float(value).is_equal_approx(1.0, 0.001)
	assert_int(OverlayScript._alpha_interior_holes(img).size()).is_equal(0)


func test_interior_holes_finds_centered_opening() -> void:
	var img := _image(128, 128)
	img.fill_rect(Rect2i(48, 48, 32, 32), Color(0, 0, 0, 0))
	var holes: Array[Rect2] = OverlayScript._alpha_interior_holes(img)
	assert_int(holes.size()).is_equal(1)
	var hole := holes[0]
	assert_float(hole.position.x).is_equal_approx(0.375, 0.05)
	assert_float(hole.position.y).is_equal_approx(0.375, 0.05)
	assert_float(hole.size.x).is_equal_approx(0.25, 0.06)
	assert_float(hole.size.y).is_equal_approx(0.25, 0.06)


func test_interior_holes_ignores_border_damage() -> void:
	# A notch open to the top edge is silhouette damage (capped), not an interior hole.
	var img := _image(128, 128)
	img.fill_rect(Rect2i(40, 0, 32, 40), Color(0, 0, 0, 0))
	assert_int(OverlayScript._alpha_interior_holes(img).size()).is_equal(0)


func test_wall_corner_points_bound_each_edge() -> void:
	var cell := Vector2i(4, 7)
	var north: Array[Vector2i] = OverlayScript._wall_corner_points({"edge_cell": cell, "edge_side": 0})
	assert_that(north).is_equal([Vector2i(4, 7), Vector2i(5, 7)] as Array[Vector2i])
	var east: Array[Vector2i] = OverlayScript._wall_corner_points({"edge_cell": cell, "edge_side": 1})
	assert_that(east).is_equal([Vector2i(5, 7), Vector2i(5, 8)] as Array[Vector2i])
	var south: Array[Vector2i] = OverlayScript._wall_corner_points({"edge_cell": cell, "edge_side": 2})
	assert_that(south).is_equal([Vector2i(4, 8), Vector2i(5, 8)] as Array[Vector2i])
	var west: Array[Vector2i] = OverlayScript._wall_corner_points({"edge_cell": cell, "edge_side": 3})
	assert_that(west).is_equal([Vector2i(4, 7), Vector2i(4, 8)] as Array[Vector2i])
