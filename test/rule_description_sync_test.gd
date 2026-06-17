extends GdUnitTestSuite
## Special-rule descriptions (e.g. "Bloodborn") now ship with the mid-session army broadcast
## (0.3.4.6) — sync_army_complete carries them and _on_remote_army_complete merges them before
## building units. Previously only the late-join state-sync carried them, so a mid-session
## importer's rules showed "Keine Beschreibung verfügbar" on the other client. This covers the
## receiver-side merge + the numbered-rule base-name fallback the whole fix relies on.

const OPRArmyManagerScript = preload("res://scripts/opr_army_manager.gd")


func test_merge_then_numbered_lookup() -> void:
	var mgr = auto_free(OPRArmyManagerScript.new())
	# Simulate what _on_remote_army_complete does with the RPC payload.
	mgr.merge_rule_descriptions({"Bloodborn": "Gains +1 to hit while shaken."})
	# Exact key resolves.
	assert_str(mgr.get_rule_description("Bloodborn")).is_equal("Gains +1 to hit while shaken.")
	# Numbered variant resolves via the base-name fallback.
	assert_str(mgr.get_rule_description("Bloodborn(2)")).is_equal("Gains +1 to hit while shaken.")
	# Unknown rule stays empty (tooltip then shows its fallback text).
	assert_str(mgr.get_rule_description("Unknown")).is_equal("")


func test_merge_is_idempotent() -> void:
	var mgr = auto_free(OPRArmyManagerScript.new())
	mgr.merge_rule_descriptions({"Tough": "Extra wounds."})
	mgr.merge_rule_descriptions({"Tough": "Extra wounds."})
	assert_int(mgr.rule_descriptions.size()).is_equal(1)
	assert_str(mgr.get_rule_description("Tough(3)")).is_equal("Extra wounds.")
