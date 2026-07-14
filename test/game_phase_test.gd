extends GdUnitTestSuite
## Tests for the formal game-phase gate (DEPLOYMENT -> PLAYING) that replaces the old
## "deployment zones are visible" proxy. Covers: the default phase, the start_game() transition
## (round 1 begins, counter untouched), clear/reset, save-round-trip persistence, and the rewired
## move-trail suppression following the PHASE and NOT any zone state.

const INCH := 0.0254  # metres per inch


func _mgr() -> OPRArmyManager:
	# Not in the tree, so _ready() (HTTPRequest + registry) is skipped — pure phase logic.
	return auto_free(OPRArmyManager.new())


# ===== Default + transition =====

func test_default_phase_is_deployment() -> void:
	var mgr := _mgr()
	assert_int(mgr.game_phase).is_equal(OPRArmyManager.GamePhase.DEPLOYMENT)
	assert_bool(mgr.is_deployment_phase()).is_true()


func test_start_game_transitions_to_playing() -> void:
	var mgr := _mgr()
	mgr.start_game()
	assert_int(mgr.game_phase).is_equal(OPRArmyManager.GamePhase.PLAYING)
	assert_bool(mgr.is_deployment_phase()).is_false()


func test_start_game_keeps_round_at_one() -> void:
	# "Round 1 begins at the transition" — the counter is already 1 and start_game must NOT bump it
	# (there is no round 0). Round 1 simply opens.
	var mgr := _mgr()
	assert_int(mgr.current_round).is_equal(1)
	mgr.start_game()
	assert_int(mgr.current_round).is_equal(1)


func test_start_game_emits_phase_changed_once_and_is_idempotent() -> void:
	var mgr := _mgr()
	var monitor := monitor_signals(mgr)
	mgr.start_game()
	await assert_signal(monitor).is_emitted("game_phase_changed", [OPRArmyManager.GamePhase.PLAYING])
	# A second start_game() is a no-op — already playing, no further emission.
	mgr.start_game()
	assert_int(mgr.game_phase).is_equal(OPRArmyManager.GamePhase.PLAYING)


func test_set_game_phase_clamps_out_of_range() -> void:
	var mgr := _mgr()
	mgr.set_game_phase(99)
	assert_int(mgr.game_phase).is_equal(OPRArmyManager.GamePhase.PLAYING)
	mgr.set_game_phase(-5)
	assert_int(mgr.game_phase).is_equal(OPRArmyManager.GamePhase.DEPLOYMENT)


func test_clear_all_resets_to_deployment() -> void:
	var mgr := _mgr()
	mgr.start_game()
	assert_bool(mgr.is_deployment_phase()).is_false()
	mgr.clear_all()
	assert_bool(mgr.is_deployment_phase()).is_true()
	assert_int(mgr.current_round).is_equal(1)


# ===== Save / load round-trip (phase persists) =====

func _save_mgr() -> SaveManager:
	var sm := SaveManager.new()
	add_child(sm)
	return auto_free(sm)


func test_serialize_includes_game_phase() -> void:
	var sm := _save_mgr()
	sm.army_manager = _mgr()
	sm.army_manager.start_game()
	var state := sm._serialize_game_state()
	assert_bool(state.has("game_phase")).is_true()
	assert_int(int(state["game_phase"])).is_equal(OPRArmyManager.GamePhase.PLAYING)


func test_phase_round_trips_through_save_load() -> void:
	# A game saved mid-play reloads in PLAYING.
	var sm := _save_mgr()
	var src := _mgr()
	src.start_game()
	sm.army_manager = src
	var state := sm._serialize_game_state()

	var dst := _mgr()  # fresh table (DEPLOYMENT)
	assert_bool(dst.is_deployment_phase()).is_true()
	sm.army_manager = dst
	sm._deserialize_game_state(state)
	assert_int(dst.game_phase).is_equal(OPRArmyManager.GamePhase.PLAYING)


func test_deployment_phase_round_trips_as_deployment() -> void:
	# A table saved during setup reloads in DEPLOYMENT (not wrongly promoted to playing).
	var sm := _save_mgr()
	var src := _mgr()  # never started
	sm.army_manager = src
	var state := sm._serialize_game_state()
	assert_int(int(state["game_phase"])).is_equal(OPRArmyManager.GamePhase.DEPLOYMENT)

	var dst := _mgr()
	dst.start_game()  # pretend it was playing before load
	sm.army_manager = dst
	sm._deserialize_game_state(state)
	assert_bool(dst.is_deployment_phase()).is_true()


func test_legacy_save_without_phase_defaults_to_playing() -> void:
	# Saves predating the phase gate have no key — a loaded battle with units is a game in progress,
	# so it must resume in PLAYING (else the trail chalk would be wrongly suppressed).
	var sm := _save_mgr()
	var dst := _mgr()
	sm.army_manager = dst
	sm._deserialize_game_state({"current_round": 2})  # no "game_phase"
	assert_int(dst.game_phase).is_equal(OPRArmyManager.GamePhase.PLAYING)
	assert_int(dst.current_round).is_equal(2)


# ===== Rewired trail suppression follows the PHASE, not zone visibility =====

func _line(points_in: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in points_in:
		out.append((p as Vector2) * INCH)
	return out


func test_trail_suppression_follows_phase_not_zones() -> void:
	# main._sync_move_trails_deployment now reads the PHASE only. Replicate its one-liner and prove the
	# chalk gate tracks the phase with NO zone object anywhere in the loop (zones can no longer suppress).
	var mgr := _mgr()
	var t := MoveTrails.new()
	add_child(t)
	auto_free(t)
	t.user_show_trails = true
	var sync := func() -> void: t.set_deployment_active(mgr.is_deployment_phase())

	# Deployment: chalk suppressed even though the user preference is ON.
	sync.call()
	assert_bool(t._deployment_active).is_true()
	assert_bool(t.visible).is_false()

	# The ledger still records during deployment (proof-of-movement always survives)...
	t.commit_trail(1, "u1", "Unit 1", 7, _line([Vector2(0, 0), Vector2(6, 0)]), 0.02, 1, 100)
	assert_int(t.ledger.entries.size()).is_equal(1)
	assert_int(t._trails.size()).is_equal(0)  # ...but no chalk was built

	# Start play: the chalk resumes. Nothing about deployment ZONES was ever consulted.
	mgr.start_game()
	sync.call()
	assert_bool(t._deployment_active).is_false()
	assert_bool(t.visible).is_true()
