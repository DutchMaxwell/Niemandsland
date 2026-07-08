extends GdUnitTestSuite
## Self-play sim correctness (goal 003 stage 0). The sim shares the real game's pure modules, so these
## prove the SIM ITSELF is sound: deterministic (same seed → same game), terminating, and casualty-bounded.


func _army(player: int) -> Array:
	return [
		SoloSim.make_unit("Shooters", player, 4, 4, 5, [{"name": "Rifle", "range_value": 24, "attacks": 1, "count": 1, "special_rules": []}]),
		SoloSim.make_unit("Fighters", player, 4, 4, 10, [{"name": "CCW", "range_value": 0, "attacks": 2, "count": 1, "special_rules": []}]),
	]


func test_same_seed_gives_identical_game() -> void:
	var r1: Dictionary = SoloSim.simulate_game(_army(0), _army(1), 42)
	var r2: Dictionary = SoloSim.simulate_game(_army(0), _army(1), 42)
	assert_int(int(r1["winner"])).is_equal(int(r2["winner"]))
	assert_int(int(r1["a_alive"])).is_equal(int(r2["a_alive"]))
	assert_int(int(r1["b_alive"])).is_equal(int(r2["b_alive"]))
	assert_int(int(r1["rounds"])).is_equal(int(r2["rounds"]))


func test_different_seeds_can_diverge() -> void:
	# Not a guarantee for any single pair, but across a spread the outcomes must vary (else the RNG is
	# not actually driving combat).
	var alive_counts := {}
	for s in range(20):
		var r: Dictionary = SoloSim.simulate_game(_army(0), _army(1), s)
		alive_counts[int(r["a_alive"])] = true
	assert_int(alive_counts.size()).is_greater(1)


func test_game_terminates_and_is_bounded() -> void:
	var r: Dictionary = SoloSim.simulate_game(_army(0), _army(1), 7, 4)
	assert_int(int(r["rounds"])).is_between(1, 4)
	# Survivors never exceed the starting force; losses never negative.
	assert_int(int(r["a_alive"])).is_between(0, int(r["a_start"]))
	assert_int(int(r["b_alive"])).is_between(0, int(r["b_start"]))
	assert_int(int(r["a_losses"])).is_greater_equal(0)
	assert_int(int(r["activations"])).is_greater(0)


func test_wipe_ends_the_game_early() -> void:
	# One lone weak model vs a strong melee force — the lone model should die, ending on a wipe.
	var weak: Array = [SoloSim.make_unit("Lone", 0, 6, 6, 1, [{"name": "Knife", "range_value": 0, "attacks": 1, "count": 1, "special_rules": []}])]
	var strong: Array = [SoloSim.make_unit("Killers", 1, 3, 3, 10, [{"name": "Axe", "range_value": 0, "attacks": 3, "count": 1, "special_rules": ["AP(2)"]}])]
	var r: Dictionary = SoloSim.simulate_game(weak, strong, 5, 4)
	assert_int(int(r["winner"])).is_equal(1)
	assert_int(int(r["a_alive"])).is_equal(0)
