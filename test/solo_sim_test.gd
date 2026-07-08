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


func test_units_from_opr_json_parses_stats_weapons_and_tough() -> void:
	var data := {
		"name": "Test List",
		"units": [{
			"name": "Squad", "size": 5, "quality": 3, "defense": 3,
			"rules": [{"name": "Tough", "rating": 3}, {"name": "Fearless"}],
			"loadout": [
				{"name": "Rifle", "range": 24, "attacks": 1, "count": 4, "specialRules": [{"name": "AP", "rating": 1}]},
				{"name": "CCW", "range": 0, "attacks": 1, "count": 5, "specialRules": []},
				{"name": "Backpack", "specialRules": []},   # wargear (no attacks) → skipped
			],
		}],
	}
	var units: Array = SoloSim.units_from_opr_json(data, 0)
	assert_int(units.size()).is_equal(1)
	var u: Dictionary = units[0]
	assert_int(int(u["quality"])).is_equal(3)
	assert_int(int(u["defense"])).is_equal(3)
	assert_int(int(u["tough"])).is_equal(3)
	assert_int(int(u["max_models"])).is_equal(5)
	# Two weapons (the wargear entry with no attacks is skipped).
	assert_int((u["weapons"] as Array).size()).is_equal(2)
	var rifle: Dictionary = (u["weapons"] as Array)[0]
	assert_int(int(rifle["count"])).is_equal(4)              # per-weapon model count
	assert_int(int(rifle["range_value"])).is_equal(24)
	assert_array(rifle["special_rules"]).contains(["AP(1)"])


func test_default_objectives_are_two_symmetric_centre_markers() -> void:
	var objs: Array = SoloSim.default_objectives()
	assert_int(objs.size()).is_equal(2)
	# Both on the centre line (z = 24 on a 48" table) → equidistant from both 12" deploy edges.
	assert_float((objs[0] as Vector2).y).is_equal_approx(24.0, 0.001)
	assert_float((objs[1] as Vector2).y).is_equal_approx(24.0, 0.001)
	# Mirror-symmetric in x about the board centre.
	assert_float((objs[0] as Vector2).x + (objs[1] as Vector2).x).is_equal_approx(48.0, 0.001)


func test_objective_seize_persists_contests_and_shaken_cannot_seize() -> void:
	var objs := [Vector2(24, 24)]
	var owner := [-1]
	var mine: Dictionary = SoloSim.make_unit("A", 0, 4, 4, 5, [])
	mine["pos"] = Vector2(24, 24)     # sitting on the objective
	var foe: Dictionary = SoloSim.make_unit("B", 1, 4, 4, 5, [])
	foe["pos"] = Vector2(0, 0)        # far away
	# Uncontested → player 0 seizes.
	SoloSim._seize_objectives([mine, foe], objs, owner, [])
	assert_int(int(owner[0])).is_equal(0)
	# STAYS seized after the unit walks away (persistent).
	mine["pos"] = Vector2(0, 47)
	SoloSim._seize_objectives([mine, foe], objs, owner, [])
	assert_int(int(owner[0])).is_equal(0)
	# Both sides within 3" → contested → neutral.
	mine["pos"] = Vector2(24, 24)
	foe["pos"] = Vector2(25, 24)
	SoloSim._seize_objectives([mine, foe], objs, owner, [])
	assert_int(int(owner[0])).is_equal(-1)
	# A Shaken unit cannot seize: only a Shaken player-0 unit present → stays neutral.
	foe["pos"] = Vector2(0, 0)
	mine["shaken"] = true
	SoloSim._seize_objectives([mine, foe], objs, owner, [])
	assert_int(int(owner[0])).is_equal(-1)


func test_shaken_unit_spends_activation_idle_and_recovers() -> void:
	# OPR v3.5.1 p.10: a Shaken unit that activates stays idle and clears Shaken at the end — it does NOT
	# move or shoot. Placed on an objective while Shaken, it must not seize it either.
	var objs := [Vector2(24, 24)]
	var owner := [-1]
	var shaken: Dictionary = SoloSim.make_unit("S", 0, 4, 4, 5, [{"name": "Rifle", "range_value": 24, "attacks": 1, "count": 5, "special_rules": []}])
	shaken["shaken"] = true
	shaken["pos"] = Vector2(24, 24)
	var foe: Dictionary = SoloSim.make_unit("F", 1, 4, 4, 5, [])
	foe["pos"] = Vector2(24, 12)   # 12" away — in rifle range, but the Shaken unit won't shoot
	var start_pos: Vector2 = shaken["pos"]
	SoloSim._activate(shaken, [shaken, foe], RandomNumberGenerator.new(), [])
	assert_bool(bool(shaken["shaken"])).is_false()               # recovered
	assert_vector(shaken["pos"] as Vector2).is_equal(start_pos)   # did not move
	assert_int(int(foe["wounds_pool"])).is_equal(0)              # did not shoot
	# And while it was Shaken it could not have seized the objective it stands on.
	shaken["shaken"] = true
	SoloSim._seize_objectives([shaken, foe], objs, owner, [])
	assert_int(int(owner[0])).is_equal(-1)


func test_pick_target_prefers_not_yet_activated() -> void:
	var me: Dictionary = SoloSim.make_unit("Me", 0, 4, 4, 5, [])
	me["pos"] = Vector2(24, 24)
	# A CLOSE already-activated enemy and a FARTHER un-activated one.
	var near_done: Dictionary = SoloSim.make_unit("NearDone", 1, 4, 4, 5, [])
	near_done["pos"] = Vector2(24, 27); near_done["activated"] = true
	var far_fresh: Dictionary = SoloSim.make_unit("FarFresh", 1, 4, 4, 5, [])
	far_fresh["pos"] = Vector2(24, 34); far_fresh["activated"] = false
	var units := [me, near_done, far_fresh]
	# Priority: the FARTHER un-activated unit wins over the closer activated one.
	assert_str((SoloSim._pick_target(me, units, INF) as Dictionary)["name"]).is_equal("FarFresh")
	# If every enemy has activated, fall back to the nearest.
	far_fresh["activated"] = true
	assert_str((SoloSim._pick_target(me, units, INF) as Dictionary)["name"]).is_equal("NearDone")
	# Range limit: only the far one is un-activated but it's out of a 6" range → the near (activated) one.
	far_fresh["activated"] = false
	assert_str((SoloSim._pick_target(me, units, 6.0) as Dictionary)["name"]).is_equal("NearDone")
