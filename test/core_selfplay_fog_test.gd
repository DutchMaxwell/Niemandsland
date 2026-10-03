extends GdUnitTestSuite
## D12c follow-up (R9a): tools/core_selfplay.gd plans BOTH seats on one captured state, so an AI seat
## could read the secret markers. Each seat now plans on its own `_seat_view`: the attacker's view of an
## unrevealed secret marker carries no `secret` / `carry` / `carried_by` (BattleSim.mask_secret_for), the
## defender's view keeps them, and a game without secret markers is handed the SAME dict, untouched.

const CoreSelfplayScript := preload("res://tools/core_selfplay.gd")


func after_test() -> void:
	SoloController.mission_reset("end", {})


func _state() -> Dictionary:
	return {"round": 1, "markers_meta": [
		{"secret": "relic", "revealed": false, "carry": true, "carried_by": ""},
		{"secret": "trap", "revealed": false}]}


func test_the_attacker_seat_cannot_read_a_hidden_marker() -> void:
	var sp = CoreSelfplayScript.new()
	SoloController.mission_roles = {"attacker": 1, "defender": 2}
	var state := _state()
	var view: Dictionary = sp._seat_view(state, 1)
	for mk in view["markers_meta"]:
		for key in ["secret", "carry", "carried_by"]:
			assert_bool((mk as Dictionary).has(key)).is_false()
	assert_str(String(state["markers_meta"][0]["secret"])).is_equal("relic")   # the shared state is untouched
	sp.free()


func test_the_defender_seat_keeps_its_secrets() -> void:
	var sp = CoreSelfplayScript.new()
	SoloController.mission_roles = {"attacker": 1, "defender": 2}
	var view: Dictionary = sp._seat_view(_state(), 2)
	assert_str(String(view["markers_meta"][0]["secret"])).is_equal("relic")
	assert_str(String(view["markers_meta"][1]["secret"])).is_equal("trap")
	sp.free()


func test_a_game_without_secret_markers_gets_the_same_dict() -> void:
	var sp = CoreSelfplayScript.new()
	var plain := {"round": 1, "markers_meta": [{"carry": true, "carried_by": ""}]}
	assert_bool(is_same(sp._seat_view(plain, 1), plain)).is_true()
	var none := {"round": 1}
	assert_bool(is_same(sp._seat_view(none, 2), none)).is_true()
	sp.free()
