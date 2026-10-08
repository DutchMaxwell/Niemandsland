extends GdUnitTestSuite
## Pure two-human turn state (plan 2.T1): alternation, TAIL, round end, opener rule, refusal.

const TT := preload("res://scripts/two_human_turn.gd")


func _fresh(opener: int, counts: Dictionary):
	var t = TT.new(1, 2)
	t.start_round(opener, counts)
	return t


func test_alternates_one_two_one_two() -> void:
	var t = _fresh(1, {1: 2, 2: 2})
	assert_int(t.side_on_turn).is_equal(1)
	assert_int(t.after_activation(1, {1: 1, 2: 2})).is_equal(2)
	assert_int(t.after_activation(2, {1: 1, 2: 1})).is_equal(1)
	assert_int(t.after_activation(1, {1: 0, 2: 1})).is_equal(2)


func test_tail_when_other_side_runs_dry() -> void:
	var t = _fresh(1, {1: 3, 2: 1})
	assert_int(t.after_activation(1, {1: 2, 2: 1})).is_equal(2)
	assert_int(t.after_activation(2, {1: 2, 2: 0})).is_equal(1)
	assert_int(t.after_activation(1, {1: 1, 2: 0})).is_equal(1)
	assert_bool(t.can_activate(2)).is_false()


func test_round_over_only_when_both_empty() -> void:
	var t = _fresh(1, {1: 1, 2: 1})
	assert_bool(t.round_over({1: 1, 2: 0})).is_false()
	assert_bool(t.round_over({1: 0, 2: 1})).is_false()
	assert_bool(t.round_over({1: 0, 2: 0})).is_true()
	t.after_activation(1, {1: 0, 2: 1})
	assert_int(t.after_activation(2, {1: 0, 2: 0})).is_equal(TT.NONE)


func test_next_opener_is_side_that_did_not_activate_last() -> void:
	var t = _fresh(1, {1: 1, 2: 2})
	t.after_activation(1, {1: 0, 2: 2})
	t.after_activation(2, {1: 0, 2: 1})
	t.after_activation(2, {1: 0, 2: 0})
	assert_int(t.next_round_opener()).is_equal(1)
	var t2 = _fresh(1, {1: 1, 2: 1})
	t2.after_activation(1, {1: 0, 2: 1})
	t2.after_activation(2, {1: 0, 2: 0})
	assert_int(t2.next_round_opener()).is_equal(1)
	t2.start_round(t2.next_round_opener(), {1: 2, 2: 2})
	assert_int(t2.side_on_turn).is_equal(1)


func test_out_of_turn_activation_is_refused() -> void:
	var t = _fresh(1, {1: 2, 2: 2})
	assert_bool(t.can_activate(2)).is_false()
	assert_int(t.after_activation(2, {1: 2, 2: 1})).is_equal(1)
	assert_int(t.side_on_turn).is_equal(1)
	assert_int(t.next_round_opener()).is_equal(TT.NONE)


func test_wiped_opener_yields() -> void:
	var t = _fresh(1, {1: 0, 2: 2})
	assert_int(t.side_on_turn).is_equal(2)
