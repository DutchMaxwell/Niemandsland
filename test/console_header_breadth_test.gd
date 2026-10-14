extends GdUnitTestSuite
## The "opponent: erlkoenig" console line must print the breadth that reaches the core
## (the brain_breadth stamp, 128 on planner_v0), not the unrelated AiPlanner._tk static (10).


func test_header_prints_stamped_breadth_when_brain_is_wired() -> void:
	var diff := SoloDifficulty.for_grade("planner_v0", 1)
	AiPlanner.set_search_budget(SoloDifficulty.SHIP_SEARCH_TOP_K, SoloDifficulty.SHIP_SEARCH_HORIZON)
	if OS.get_environment("NML_BRAIN_BREADTH") == "":
		assert_int(AiPlanner.top_k_default()).is_equal(10)   # what the old header printed
		assert_int(SoloController.header_top_k(diff, true)).is_equal(128)


func test_header_keeps_the_live_default_without_a_brain() -> void:
	var diff := SoloDifficulty.for_grade("planner_v0", 1)
	if OS.get_environment("NML_BRAIN_BREADTH") == "":
		assert_int(SoloController.header_top_k(diff, false)).is_equal(AiPlanner.top_k_default())
