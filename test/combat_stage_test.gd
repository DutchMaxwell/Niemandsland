extends GdUnitTestSuite
## Pacing grill 2026-07-31 — the combat stage widget: collects rule lines, closes them into
## phase cards at the boundaries, HOLDS there (skippable, pausable), browses the running
## activation. Headless is inert unless forced (force_for_tests) — batch always inert.


func _stage(hold: float = 0.05) -> CombatStage:
	var st: CombatStage = auto_free(CombatStage.new())
	st.force_for_tests = true
	st.hold_s = hold
	add_child(st)
	return st


func test_inert_when_disabled_batch_or_plain_headless() -> void:
	var st: CombatStage = auto_free(CombatStage.new())
	add_child(st)
	assert_bool(st.active()) \
		.override_failure_message("plain headless must be inert — e2e volleys elsewhere would stall") \
		.is_false()
	st.force_for_tests = true
	assert_bool(st.active()).is_true()
	# Batch (selfplay) is inert — force is a TEST-only override and may beat it.
	st.force_for_tests = false
	st.batch = true
	assert_bool(st.active()).is_false()
	st.batch = false
	st.enabled = false
	st.force_for_tests = true
	assert_bool(st.active()) \
		.override_failure_message("the settings toggle must win even over a test force") \
		.is_false()
	# Inert stage: begin/collect/phase are no-ops that return immediately.
	st.activation_begin("X fires at Y")
	st.collect("a line")
	await st.phase("Declaration")
	assert_array(st._phases).is_empty()


func test_phase_groups_collected_lines_into_a_card() -> void:
	var st := _stage()
	st.activation_begin("Tank fires at Grunts")
	st.collect("Tank: 3/3 models with line of sight + range")
	st.collect("Artillery: +1 to hit (target over 9\" away)")
	await st.phase("Declaration")
	assert_int(st._phases.size()).is_equal(1)
	var ph := st._phases[0] as Dictionary
	assert_str(str(ph["title"])).is_equal("Declaration")
	assert_int((ph["lines"] as Array).size()).is_equal(2)
	# The card renders headline + phase + lines.
	assert_str(st._head_label.text).is_equal("Tank fires at Grunts")
	assert_str(st._lines_label.text).contains("Artillery: +1 to hit")


func test_empty_phase_is_no_beat() -> void:
	var st := _stage(100.0)
	st.activation_begin("X fires at Y")
	await st.phase("Nothing happened")   # would hang for 100 s if it held on an empty card
	assert_array(st._phases).is_empty()


func test_skip_advances_a_holding_phase_immediately() -> void:
	var st := _stage(100.0)
	st.activation_begin("X fires at Y")
	st.collect("one line")
	st.phase("To hit")   # fire-and-forget: runs to its first await and holds
	await get_tree().process_frame
	await get_tree().process_frame
	assert_bool(st._holding) \
		.override_failure_message("the phase must HOLD — pacing is the whole point") \
		.is_true()
	st.skip()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_bool(st._holding).is_false()


func test_pause_keeps_holding_beyond_the_beat() -> void:
	var st := _stage(0.01)
	st.activation_begin("X fires at Y")
	st.collect("one line")
	st.toggle_pause()
	st.phase("To hit")
	for i in range(5):
		await get_tree().process_frame
	assert_bool(st._holding) \
		.override_failure_message("SPACE-pause must hold the card past the beat") \
		.is_true()
	st.toggle_pause()
	for i in range(5):
		await get_tree().process_frame
	assert_bool(st._holding).is_false()


func test_browse_walks_the_running_activation() -> void:
	var st := _stage(0.0)
	st.activation_begin("X fires at Y")
	st.collect("decl")
	await st.phase("Declaration")
	st.collect("hits")
	await st.phase("Rifle")
	st.browse(-1)
	assert_int(st._view).is_equal(0)
	assert_str(st._phase_label.text).contains("Declaration")
	st.browse(1)   # back at the newest = live again
	assert_int(st._view).is_equal(-1)
