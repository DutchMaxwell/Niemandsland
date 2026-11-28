extends GdUnitTestSuite
## PLAN_GAME_SYSTEM_SWITCH step 19: the gate PLAN_HEIGHTFIELD step 23 (the table chooser) asks for generated boards.
## GameSystem.generated_boards(system) = the boards on offer for that system: Tiefwerk for Firefight (gff) only, the ruined
## town for Skirmish (aofs) only (GEN-14: its row is available). gf, aof and aofr get no entry.
## Red proof: on main there is no gate - the chooser would have had to invent one.


func before_test() -> void:
	GameSystem.reset_cache()


func after_test() -> void:
	GameSystem.reset_cache()


func test_only_a_firefight_table_is_offered_tiefwerk() -> void:
	assert_array(GameSystem.generated_boards("gff")).is_equal(["tiefwerk"])
	for system in ["gf", "aof", "aofr", ""]:
		assert_array(GameSystem.generated_boards(system)).override_failure_message("%s was offered a generated board" % system).is_empty()


## GEN-14: the ruined town ships - an AoF: Skirmish table is offered it, and only that one.
func test_aofs_offers_the_ruined_town() -> void:
	assert_array(GameSystem.generated_boards("aofs")).is_equal(["ruined_town"])
