extends GdUnitTestSuite
## AI ARENA margins: the result JSON reports how badly each side lost — points_start / points_alive /
## models_start per side and the round a side was wiped out in. Hand-built board state, no game boot: the
## rules live in tools/arena_match.gd as pure statics (margin_rows / side_margins / latch_eliminations).

const ArenaMatch := preload("res://tools/arena_match.gd")


## A unit of `models` models, each with `tough` wounds, costing `cost` points.
func _unit(cost: int, models: int, tough: int = 1) -> GameUnit:
	var u := GameUnit.new()
	u.unit_properties = {"cost": cost, "player_id": 1}
	for i in range(models):
		var m := ModelInstance.new()
		m.wounds_max = tough
		m.wounds_current = tough
		u.models.append(m)
	return u


func _kill(u: GameUnit, count: int) -> void:
	for i in range(count):
		u.models[i].apply_damage(u.models[i].wounds_max)


# === points_start / points_alive / models_start ===

func test_points_alive_counts_survivors_by_fraction_and_tough_wounds() -> void:
	var full := _unit(100, 5)          # untouched squad
	var dead := _unit(100, 5)          # one of the two 100-pt units, wiped out
	var half := _unit(80, 4)           # squad down to 1 of 4 models
	var hero := _unit(60, 1, 3)        # lone Tough(3) hero, joined to `full` but scored on its own
	# The snapshot is taken at game start, with everybody standing.
	var rows: Array = ArenaMatch.margin_rows([full, dead, half, hero])
	var start: Dictionary = ArenaMatch.side_margins(rows)
	assert_int(int(start["points_start"])).is_equal(340)
	assert_int(int(start["models_start"])).is_equal(15)
	assert_float(float(start["points_alive"])).is_equal_approx(340.0, 0.001)   # nobody has died yet

	_kill(dead, 5)
	_kill(half, 3)
	hero.models[0].apply_damage(2)     # Tough(3) at 1 wound left
	var now: Dictionary = ArenaMatch.side_margins(rows)
	assert_int(int(now["points_start"])).is_equal(340)                 # the START value never moves
	# 100 (full) + 0 (dead) + 80 x 1/4 = 20 (half) + 60 x 1/3 = 20 (hero at 1 of 3 wounds)
	assert_float(float(now["points_alive"])).is_equal_approx(140.0, 0.001)


func test_a_dead_lone_model_scores_zero_and_a_unit_created_later_never_counts() -> void:
	var squad := _unit(100, 5)
	var hero := _unit(60, 1, 3)
	var rows: Array = ArenaMatch.margin_rows([squad, hero])
	_kill(hero, 1)
	var summoned := _unit(999, 3)      # Reinforcement / Spawn: exists after the snapshot, so it is not in `rows`
	assert_bool(summoned.get_alive_count() == 3).is_true()
	var m: Dictionary = ArenaMatch.side_margins(rows)
	assert_int(int(m["points_start"])).is_equal(160)
	assert_float(float(m["points_alive"])).is_equal_approx(100.0, 0.001)


func test_an_empty_roster_is_all_zero_and_does_not_divide() -> void:
	var m: Dictionary = ArenaMatch.side_margins([])
	assert_int(int(m["points_start"])).is_equal(0)
	assert_int(int(m["models_start"])).is_equal(0)
	assert_float(float(m["points_alive"])).is_equal_approx(0.0, 0.001)


# === eliminated_round ===

func test_elimination_latches_the_first_round_a_side_is_at_zero() -> void:
	var latched := {}
	ArenaMatch.latch_eliminations(latched, {1: 4, 2: 3}, 1)
	assert_bool(latched.is_empty()).is_true()                          # both standing -> null for both
	ArenaMatch.latch_eliminations(latched, {1: 4, 2: 0}, 2)
	assert_int(int(latched[2])).is_equal(2)
	assert_bool(latched.has(1)).is_false()
	ArenaMatch.latch_eliminations(latched, {1: 0, 2: 0}, 3)            # a later check must not move round 2
	assert_int(int(latched[2])).is_equal(2)
	assert_int(int(latched[1])).is_equal(3)
