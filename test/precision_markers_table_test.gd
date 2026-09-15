extends GdUnitTestSuite
## Wave 6 — the Precision markers' TABLE PLACEMENT RECORD (act_recorder.gd
## `_ledger_of`). A table-side placement is only real if a replayed act sees
## it: the two marker pools (Spotter's `spot_markers`, Tag's `tag_markers`),
## the spotter's once-per-activation round stamp and the once-per-game
## latches must ride the act ledger the same way vengeance_markers does —
## without them the core replays every act unmarked (the recorded-corpus
## divergence shape the Vengeance port closed).

func _unit(unit_name: String) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = "p_1"
	u.unit_properties = {"player_id": 1, "name": unit_name}
	return u


func test_the_precision_marker_pools_and_latches_ride_the_placement_record() -> void:
	var spotter := _unit("Eyes")
	spotter.unit_properties["spotted_round"] = 3
	spotter.unit_properties["precision_tag_used"] = true
	var marked := _unit("Marked")
	marked.unit_properties["spot_markers"] = 2
	marked.unit_properties["tag_markers"] = 3
	marked.unit_properties["precision_target_used"] = true

	var spot_ledger: Dictionary = AiActRecorder._ledger_of(spotter)
	assert_int(int(spot_ledger.get("spot_round", -1))) \
		.override_failure_message("the spotter's round stamp must ride the act") \
		.is_equal(3)
	assert_array((spot_ledger.get("precision_used", []) as Array)) \
		.override_failure_message("the once-per-game latches ride as the DISPLAY names") \
		.contains(["Precision Tag"])

	var marked_ledger: Dictionary = AiActRecorder._ledger_of(marked)
	assert_int(int(marked_ledger.get("spot_markers", 0))) \
		.override_failure_message("the Spotter pool rides the act (the vengeance_markers shape)") \
		.is_equal(2)
	assert_int(int(marked_ledger.get("tag_markers", 0))) \
		.override_failure_message("the Tag pool rides the act") \
		.is_equal(3)
	assert_array((marked_ledger.get("precision_used", []) as Array)) \
		.override_failure_message("the Target's latch rides under its own name") \
		.contains(["Precision Target"])

	# The control: an unmarked unit carries none of the keys, so an older
	# corpus (recorded before the trio existed) replays 0/-1/empty — the
	# byte-exact old leg.
	var plain_ledger: Dictionary = AiActRecorder._ledger_of(_unit("Plain"))
	assert_bool(plain_ledger.has("spot_markers")) \
		.override_failure_message("no pool, no key — the old-corpus replay stays byte-exact") \
		.is_false()
	assert_bool(plain_ledger.has("tag_markers")).is_false()
	assert_bool(plain_ledger.has("spot_round")).is_false()
	assert_bool(plain_ledger.has("precision_used")).is_false()
