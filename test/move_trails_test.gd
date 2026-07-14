extends GdUnitTestSuite
## Tests for MoveTrails visibility control — the two independent gates over the CHALK,
## proving the design's hard rule: the move LEDGER records the proof-of-movement data
## UNCONDITIONALLY, and only the visible chalk follows the deployment phase / user
## preference. (The ribbon geometry itself is covered indirectly; here we assert the
## record-vs-paint split and the derived node visibility.)

const INCH := 0.0254   # metres per inch


func _mt() -> MoveTrails:
	var t := MoveTrails.new()
	add_child(t)   # in-tree so pooled child meshes/labels attach cleanly
	return auto_free(t)


func _line(points_in: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in points_in:
		out.append((p as Vector2) * INCH)
	return out


# ===== The ledger always records (MP proof survives any visual suppression) =====

func test_ledger_records_during_deployment_without_painting() -> void:
	var t := _mt()
	t.set_deployment_active(true)
	t.commit_trail(1, "u1", "Unit 1", 7, _line([Vector2(0, 0), Vector2(6, 0)]), 0.02, 1, 100)
	# Data survives (proof-of-movement)...
	assert_int(t.ledger.entries.size()).is_equal(1)
	assert_float(float(t.ledger.entries[0]["inches"])).is_equal_approx(6.0, 0.05)
	# ...but no chalk was built during deployment (nothing pops in when play begins).
	assert_int(t._trails.size()).is_equal(0)


func test_ledger_records_with_visuals_preference_off() -> void:
	var t := _mt()
	t.user_show_trails = false
	t._apply_visibility()
	assert_bool(t.visible).is_false()
	t.commit_trail(1, "u1", "Unit 1", 7, _line([Vector2(0, 0), Vector2(6, 0)]), 0.02, 1, 100)
	# The ledger still records...
	assert_int(t.ledger.entries.size()).is_equal(1)
	# ...and the trail is built HIDDEN (movement phase) so toggling visuals on reveals it.
	assert_int(t._trails.size()).is_equal(1)


# ===== Derived visibility from the two gates =====

func test_movement_phase_with_preference_on_paints_and_shows() -> void:
	var t := _mt()
	t.user_show_trails = true
	t.set_deployment_active(false)
	t._apply_visibility()
	assert_bool(t.visible).is_true()
	t.commit_trail(2, "u2", "Unit 2", 3, _line([Vector2(0, 0), Vector2(4, 0)]), 0.02, 1, 200)
	assert_int(t._trails.size()).is_equal(1)


func test_deployment_gate_hides_and_restores_node() -> void:
	var t := _mt()
	t.user_show_trails = true
	t.set_deployment_active(true)
	assert_bool(t.visible).is_false()   # deploying → no chalk shows
	t.set_deployment_active(false)
	assert_bool(t.visible).is_true()    # play begins → chalk returns


func test_preference_gate_drives_visibility() -> void:
	var t := _mt()
	t.set_deployment_active(false)
	t.set_user_show_trails(true)
	assert_bool(t.visible).is_true()
	t.set_user_show_trails(false)
	assert_bool(t.visible).is_false()
	# Restore the shared persisted preference so the test leaves no side effect.
	t.set_user_show_trails(true)


func test_live_painting_suppressed_during_deployment() -> void:
	var t := _mt()
	t.set_deployment_active(true)
	t.begin_live([{"offset": Vector2.ZERO, "radius_m": 0.02, "owner": 1}])
	assert_int(t._live.size()).is_equal(0)   # no live ribbons while deploying
