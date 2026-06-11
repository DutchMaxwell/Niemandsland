extends GdUnitTestSuite
## Tests the war-torn ruin-fire placement logic in terrain_overlay.gd: deterministic
## per-segment picks from synced wall data, a sane burn rate, and — critically — that
## the fire pick NEVER disturbs the panel RNG (windows/doorways must stay identical;
## HANDOFF_RUIN_WALLS.md §6 gotcha #5).

const OverlayScript = preload("res://scripts/terrain_overlay.gd")


func _overlay() -> Node3D:
	# Not added to the tree on purpose: these helpers are pure and must not need _ready().
	return auto_free(OverlayScript.new())


func _segment(x: int, y: int, side: int) -> Dictionary:
	return {"edge_cell": Vector2i(x, y), "edge_side": side, "role": "full"}


func test_fire_pick_is_deterministic() -> void:
	# Walls rebuild locally on every client: the same synced segment must always give
	# the same answer (simulating "two clients" via repeated static calls).
	for x in range(10):
		for side in range(4):
			var seg := _segment(x, 17 - x, side)
			var first: bool = OverlayScript.segment_has_fire(seg)
			for _run in range(5):
				assert_bool(OverlayScript.segment_has_fire(seg)).is_equal(first)


func test_burn_rate_is_near_the_configured_chance() -> void:
	var burning := 0
	var total := 0
	for x in range(50):
		for y in range(10):
			for side in range(4):
				total += 1
				if OverlayScript.segment_has_fire(_segment(x, y, side)):
					burning += 1
	var rate := float(burning) / float(total)
	assert_float(rate).is_greater_equal(0.15)
	assert_float(rate).is_less_equal(0.30)


func test_fire_pick_does_not_disturb_panel_picks() -> void:
	# Regression guard: the fire RNG is a FRESH salted generator. If it ever consumed
	# draws from the panel RNG sequence, every window/doorway on every map would change.
	var overlay := _overlay()
	var picks_before: Array[String] = []
	for x in range(20):
		var seg := _segment(x, 5, x % 4)
		picks_before.append(overlay._panel_for_segment(seg))
	for x in range(20):
		OverlayScript.segment_has_fire(_segment(x, 5, x % 4))
	for x in range(20):
		var seg := _segment(x, 5, x % 4)
		assert_str(overlay._panel_for_segment(seg)).is_equal(picks_before[x])


func test_fire_and_panel_picks_use_distinct_sequences() -> void:
	# The salt must actually decorrelate the fire pick from the panel pick: across many
	# segments, both "window panel + fire" and "window panel + no fire" must occur.
	var overlay := _overlay()
	var window_with_fire := 0
	var window_without_fire := 0
	for x in range(60):
		for y in range(60):
			var seg := _segment(x, y, (x + y) % 4)
			if overlay._panel_for_segment(seg) == "window":
				if OverlayScript.segment_has_fire(seg):
					window_with_fire += 1
				else:
					window_without_fire += 1
	assert_int(window_with_fire).is_greater(0)
	assert_int(window_without_fire).is_greater(0)