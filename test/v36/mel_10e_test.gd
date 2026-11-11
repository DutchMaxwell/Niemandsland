extends GdUnitTestSuite
## Rules 3.6 wave, row MEL-10e: the AI's melee-morale ESTIMATE (BattleSim) twin of MEL-10. From
## EPOCH_73_V36 the loser is the side that TOOK more wounds over the whole activation: the enemy's
## strikes, the enemy's Fear(X) (which rides the ENEMY's tally) and the charger's own charge-move
## wounds. Below 73 the side that dealt fewer loses and self-wounds are ignored. The core twin is
## core/nml-core/src/tests/sim/v36_melee_rows/mel_10e.rs.

var _epoch0: int


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0   # statics leak across gdUnit tests — restore


func _unit(uid: String, fear: int) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = uid
	# Quality 6 fails the 50 % estimate, so the loser ROUTS and `alive` marks it.
	u.unit_properties = {"player_id": 2, "name": uid, "quality": 6, "defense": 4,
		"special_rules": (["Fear(%d)" % fear] if fear > 0 else [])}
	return u


func _snapshot(u: GameUnit) -> Dictionary:
	return {"unit": u, "alive": 1, "wounds": [10], "positions": [], "shaken": false}


## The side the estimate sent to test: 0 = charger, 1 = defender, -1 = nobody (a live tie).
func _loser(charger_fear: int, defender_fear: int, self_wounds: int, epoch: int) -> int:
	AiActRecorder.rules_epoch = epoch
	var su := _snapshot(_unit("Charger", charger_fear))
	var tu := _snapshot(_unit("Defender", defender_fear))
	BattleSim._expected_melee_morale(su, 10, tu, 10, self_wounds)
	if int(su["alive"]) <= 0:
		return 0
	if int(tu["alive"]) <= 0:
		return 1
	return -1


func test_the_chargers_own_self_wounds_count_as_taken_at_epoch_73() -> void:
	assert_int(_loser(0, 0, 2, AiActRecorder.EPOCH_73_V36)).is_equal(0)


func test_the_chargers_own_self_wounds_are_ignored_at_epoch_72() -> void:
	assert_int(_loser(0, 0, 2, AiActRecorder.EPOCH_72_PLAYTEST_RULES)).is_equal(-1)


## The row's different-loser case: a Fear(2) charger that took 2 self-wounds. At 73 the defender
## took 2 (the charger's Fear) against the charger's 2 — a tie, nobody tests. At 72 the Fear counted
## as 2 DEALT against 0, so the defender lost.
func test_a_fear_chargers_self_wounds_tie_the_enemys_fear_tally_at_epoch_73() -> void:
	assert_int(_loser(2, 0, 2, AiActRecorder.EPOCH_73_V36)).is_equal(-1)
	assert_int(_loser(2, 0, 2, AiActRecorder.EPOCH_72_PLAYTEST_RULES)).is_equal(1)


## A pure Fear case with no self-wounds: the two readings agree — the enemy of a Fear(2) unit took 2,
## so the plain unit is the loser at both epochs.
func test_a_pure_fear_case_reads_the_same_loser_at_both_epochs() -> void:
	assert_int(_loser(2, 0, 0, AiActRecorder.EPOCH_72_PLAYTEST_RULES)).is_equal(1)
	assert_int(_loser(2, 0, 0, AiActRecorder.EPOCH_73_V36)).is_equal(1)


func test_defender_fear_still_counts_against_the_charger_at_both_epochs() -> void:
	assert_int(_loser(0, 2, 0, AiActRecorder.EPOCH_72_PLAYTEST_RULES)).is_equal(0)
	assert_int(_loser(0, 2, 0, AiActRecorder.EPOCH_73_V36)).is_equal(0)
