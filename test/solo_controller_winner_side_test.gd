extends GdUnitTestSuite
## SoloController.winner_side — the ONE mission-referee read the finale lesson verdict (main.gd:2754)
## and the game summary (main.gd:2801) share, so the two can never name different winners. The
## extraction is behaviour-preserving; these tests pin the two branches of the helper:
##   • a live controller exists  -> its end_verdict (which folds the role missions and the progressive
##     VP ledger) is authoritative;
##   • no controller             -> BattleSim's pure referee for the room that never built one.


## Stands in for the live controller at the seam: winner_side only reads end_verdict.
class FakeController:
	extends RefCounted
	var verdict: String = ""
	func end_verdict(_owners: Array, _alive1: int, _alive2: int) -> String:
		return verdict


func test_winner_side_reads_the_live_controller_when_there_is_one() -> void:
	var ctl := FakeController.new()
	ctl.verdict = "p2"
	assert_str(SoloController.winner_side(ctl, [], 5, 2)) \
		.override_failure_message("the live controller's end_verdict must be authoritative") \
		.is_equal("p2")


func test_winner_side_falls_back_to_the_pure_referee_without_a_controller() -> void:
	var saved := SoloController.mission_scoring
	SoloController.mission_scoring = "end"
	# Owners [1,1,1] is a decisive board: the pure referee names p1.
	assert_str(SoloController.winner_side(null, [1, 1, 1], 0, 0)) \
		.override_failure_message("with no controller the helper must read BattleSim's pure referee") \
		.is_equal("p1")
	SoloController.mission_scoring = saved
