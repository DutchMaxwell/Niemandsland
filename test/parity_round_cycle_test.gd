extends GdUnitTestSuite
## W-P1 round-cycle — what the game refreshes at round start now happens in
## the imagined rounds too: spell tokens refill (Caster Group resets to the
## bearer count, plain casters accumulate to the cap) and Battleborn (or the
## Steadfast alias) clears Shaken for free. One helper serves BOTH the
## rollout's _cross_round and the playout's round loop.


func _su(rules: Array, casts: int, per_round: int, alive := 3, shaken := false) -> Dictionary:
	var u: GameUnit = auto_free(GameUnit.new())
	u.unit_id = "U"
	u.unit_properties = {"player_id": 1, "name": "U", "special_rules": rules,
		"faction_folder": "battle_brothers"}
	u.casts_per_round = per_round
	return {"unit": u, "player": 1, "alive": alive, "activated": true,
		"fatigued": true, "shaken": shaken, "casts": casts}


func test_plain_caster_accumulates_to_the_cap() -> void:
	var su := _su([], 1, 2)
	AiPlanner._round_start_refresh(su)
	assert_int(int(su["casts"])).is_equal(3)
	assert_bool(bool(su["activated"])).is_false()
	assert_bool(bool(su["fatigued"])).is_false()
	# cap: never beyond CASTER_POINTS_CAP
	var full := _su([], GameUnit.CASTER_POINTS_CAP, 2)
	AiPlanner._round_start_refresh(full)
	assert_int(int(full["casts"])).is_equal(GameUnit.CASTER_POINTS_CAP)


func test_caster_group_resets_to_bearer_count() -> void:
	var su := _su(["Caster Group"], 0, 0, 4)
	AiPlanner._round_start_refresh(su)
	assert_int(int(su["casts"])).is_equal(4)
	# and it RESETS (no accumulation): a full pool snaps back to alive count
	var rich := _su(["Caster Group"], 9, 0, 2)
	AiPlanner._round_start_refresh(rich)
	assert_int(int(rich["casts"])).is_equal(2)


func test_battleborn_clears_shaken_plain_does_not() -> void:
	var born := _su(["Battleborn"], 0, 0, 3, true)
	AiPlanner._round_start_refresh(born)
	assert_bool(bool(born["shaken"])).is_false()
	var plain := _su([], 0, 0, 3, true)
	AiPlanner._round_start_refresh(plain)
	assert_bool(bool(plain["shaken"])).is_true()
