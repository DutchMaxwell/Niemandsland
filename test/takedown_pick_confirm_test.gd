extends GdUnitTestSuite
## NML-1040: a Takedown click that lands on a JOINED HERO's collider must not snipe him outright —
## both match-day takedowns grabbed the hero while the player aimed at a plain trooper. The arm/
## confirm gate is pure state logic (main.gd solo_pick_needs_confirm), tested here without a board:
## true = this click only ARMS the pick, false = the click chooses the model outright.

const MainScript := preload("res://scripts/main.gd")

var _troop: RefCounted
var _hero: RefCounted


func before_test() -> void:
	_troop = RefCounted.new()
	_hero = RefCounted.new()


func _pick(unit: Object, index: int) -> Dictionary:
	return {"unit": unit, "index": index}


func test_click_inside_recommended_unit_picks_at_once() -> void:
	assert_bool(MainScript.solo_pick_needs_confirm(_pick(_troop, 2), {}, _troop, 0)).is_false()


func test_first_click_on_chain_hero_only_arms() -> void:
	assert_bool(MainScript.solo_pick_needs_confirm(_pick(_troop, 2), {}, _hero, 0)).is_true()


func test_second_click_on_the_same_hero_model_confirms() -> void:
	assert_bool(MainScript.solo_pick_needs_confirm(_pick(_troop, 2), _pick(_hero, 0), _hero, 0)).is_false()


func test_click_on_a_different_hero_model_rearms_instead_of_confirming() -> void:
	assert_bool(MainScript.solo_pick_needs_confirm(_pick(_troop, 2), _pick(_hero, 0), _hero, 1)).is_true()


func test_armed_hero_never_blocks_a_recommended_unit_click() -> void:
	assert_bool(MainScript.solo_pick_needs_confirm(_pick(_troop, 2), _pick(_hero, 0), _troop, 1)).is_false()


func test_pick_without_recommendation_stays_one_click() -> void:
	# The wound / Reanimation allocations pass {} as recommendation — no chain-hero hazard there.
	assert_bool(MainScript.solo_pick_needs_confirm({}, {}, _hero, 0)).is_false()
