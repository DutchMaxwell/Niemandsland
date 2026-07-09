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
	mine["model_pos"] = [Vector2(24, 24)]     # one model sitting on the objective
	var foe: Dictionary = SoloSim.make_unit("B", 1, 4, 4, 5, [])
	foe["model_pos"] = [Vector2(0, 0)]        # far away
	# Uncontested → player 0 seizes.
	SoloSim._seize_objectives([mine, foe], objs, owner, [])
	assert_int(int(owner[0])).is_equal(0)
	# STAYS seized after the unit walks away (persistent).
	mine["model_pos"] = [Vector2(0, 47)]
	SoloSim._seize_objectives([mine, foe], objs, owner, [])
	assert_int(int(owner[0])).is_equal(0)
	# Both sides within 3" → contested → neutral.
	mine["model_pos"] = [Vector2(24, 24)]
	foe["model_pos"] = [Vector2(25, 24)]
	SoloSim._seize_objectives([mine, foe], objs, owner, [])
	assert_int(int(owner[0])).is_equal(-1)
	# A Shaken unit cannot seize: only a Shaken player-0 unit present → stays neutral.
	foe["model_pos"] = [Vector2(0, 0)]
	mine["shaken"] = true
	SoloSim._seize_objectives([mine, foe], objs, owner, [])
	assert_int(int(owner[0])).is_equal(-1)


func test_a_single_edge_model_holds_the_objective_even_if_centre_is_far() -> void:
	# Per-model control: the formation centre is 5" from the marker (out of 3"), but a front model reaches it.
	var objs := [Vector2(24, 24)]
	var owner := [-1]
	var u: Dictionary = SoloSim.make_unit("Edge", 0, 4, 4, 5, [])
	u["pos"] = Vector2(24, 19)
	u["model_pos"] = [Vector2(24, 19), Vector2(24, 24)]   # front model ON the marker
	var foe: Dictionary = SoloSim.make_unit("F", 1, 4, 4, 5, [])
	foe["model_pos"] = [Vector2(0, 0)]
	SoloSim._seize_objectives([u, foe], objs, owner, [])
	assert_int(int(owner[0])).is_equal(0)


func test_shaken_unit_spends_activation_idle_and_recovers() -> void:
	# OPR v3.5.1 p.10: a Shaken unit that activates stays idle and clears Shaken at the end — it does NOT
	# move or shoot. Placed on an objective while Shaken, it must not seize it either.
	var objs := [Vector2(24, 24)]
	var owner := [-1]
	var shaken: Dictionary = SoloSim.make_unit("S", 0, 4, 4, 5, [{"name": "Rifle", "range_value": 24, "attacks": 1, "count": 5, "special_rules": []}])
	shaken["shaken"] = true
	shaken["pos"] = Vector2(24, 24)
	shaken["model_pos"] = [Vector2(24, 24)]
	var foe: Dictionary = SoloSim.make_unit("F", 1, 4, 4, 5, [])
	foe["pos"] = Vector2(24, 12)   # 12" away — in rifle range, but the Shaken unit won't shoot
	foe["model_pos"] = [Vector2(24, 12)]
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


func test_unit_stops_on_objective_and_does_not_overshoot() -> void:
	# A shooter 4" south of an uncontrolled objective, enemy far away → it moves TO the marker and stays
	# within 3" (secures it), instead of marching the full move distance past it (the maintainer's bug).
	var objs := [Vector2(24, 24)]
	var owner := [-1]
	var u: Dictionary = SoloSim.make_unit("Sh", 0, 4, 4, 5, [{"name": "Rifle", "range_value": 24, "attacks": 1, "count": 5, "special_rules": []}])
	u["pos"] = Vector2(24, 20)
	var foe: Dictionary = SoloSim.make_unit("F", 1, 4, 4, 5, [])
	foe["pos"] = Vector2(2, 44)   # >30" away so it Rushes to the objective rather than advance+shoot
	SoloSim._activate(u, [u, foe], RandomNumberGenerator.new(), [], 1, owner, objs, [])
	assert_float((u["pos"] as Vector2).distance_to(Vector2(24, 24))).is_less_equal(3.0)


func test_same_weapon_types_combine_into_one_group() -> void:
	# OPR p.8: two Heavy Machineguns (same type) become ONE group rolled together, not two separate rolls.
	var data := {"units": [{"name": "Support", "size": 3, "quality": 3, "defense": 3, "rules": [],
		"loadout": [
			{"name": "Heavy Machinegun", "range": 30, "attacks": 3, "count": 1, "specialRules": [{"name": "AP", "rating": 1}]},
			{"name": "Heavy Machinegun", "range": 30, "attacks": 3, "count": 1, "specialRules": [{"name": "AP", "rating": 1}]},
			{"name": "CCW", "range": 0, "attacks": 1, "count": 3, "specialRules": []},
		]}]}
	var u: Dictionary = SoloSim.units_from_opr_json(data, 0)[0]
	var weapons: Array = u["weapons"]
	# One HMG group (count 2) + one CCW group — not two HMG entries.
	var hmgs := weapons.filter(func(w): return str(w["name"]) == "Heavy Machinegun")
	assert_int(hmgs.size()).is_equal(1)
	assert_int(int(hmgs[0]["count"])).is_equal(2)   # both HMGs summed → rolled together


func test_dead_models_do_not_attack() -> void:
	# A 10-model CCW unit (10 attacks at full strength) reduced to 4 alive rolls ~4 attacks, not 10.
	var u: Dictionary = SoloSim.make_unit("Squad", 0, 4, 4, 10, [{"name": "CCW", "range_value": 0, "attacks": 1, "count": 10, "special_rules": []}])
	assert_int(SoloSim._effective_attacks(u, 10)).is_equal(10)   # full strength
	u["wounds_pool"] = 6                                          # 6 dead → 4 alive
	assert_int(SoloSim.alive_models(u)).is_equal(4)
	assert_int(SoloSim._effective_attacks(u, 10)).is_equal(4)    # only the 4 living models attack
	u["wounds_pool"] = 9                                          # 1 alive
	assert_int(SoloSim._effective_attacks(u, 10)).is_equal(1)


# === Terrain (reuses TerrainRules — the game's terrain model) ===

func test_default_terrain_is_reflection_symmetric() -> void:
	# The generated layout must mirror across the board mid-line, or the mirror-match fairness oracle breaks.
	var terrain: Dictionary = SoloSim.default_terrain(1234)
	assert_int(terrain.size()).is_greater(0)
	var n: int = int(SoloSim.BOARD_IN / TerrainRules.CELL_IN)
	for cell in terrain:
		var mirror := Vector2i((cell as Vector2i).x, n - 1 - (cell as Vector2i).y)
		assert_bool(terrain.has(mirror)).is_true()
		assert_int(int(terrain[mirror])).is_equal(int(terrain[cell]))


func test_line_of_sight_gates_shooting_target() -> void:
	# Shooter and enemy face each other across the mid-line; a container on the line blocks the shot.
	var shooter: Dictionary = SoloSim.make_unit("Gunners", 0, 4, 4, 1, [{"name": "Rifle", "range_value": 48, "attacks": 1, "count": 1, "special_rules": []}])
	shooter["pos"] = Vector2(5, 24)
	var enemy: Dictionary = SoloSim.make_unit("Foe", 1, 4, 4, 1, [{"name": "Rifle", "range_value": 48, "attacks": 1, "count": 1, "special_rules": []}])
	enemy["pos"] = Vector2(43, 24)
	var units := [shooter, enemy]
	var wall := {Vector2i(8, 8): TerrainRules.TerrainType.CONTAINER}   # sits on the line y=24 between them
	assert_object(SoloSim._pick_target(shooter, units, 100.0, wall, true)).is_null()          # LOS blocked
	assert_object(SoloSim._pick_target(shooter, units, 100.0, {}, true)).is_same(enemy)       # open field: seen
	assert_object(SoloSim._pick_target(shooter, units, 100.0, wall, false)).is_same(enemy)    # LOS not required


func test_cover_improves_the_targets_save() -> void:
	# The save target recorded for a volley drops by 1 when the majority of the target sits in cover.
	var attacker: Dictionary = SoloSim.make_unit("Rifles", 0, 4, 4, 1, [{"name": "Rifle", "range_value": 24, "attacks": 1, "count": 1, "special_rules": []}])
	var target: Dictionary = SoloSim.make_unit("Cover Squad", 1, 4, 4, 5, [{"name": "Rifle", "range_value": 24, "attacks": 1, "count": 5, "special_rules": []}])
	target["model_pos"] = [Vector2(16, 16), Vector2(16.5, 16.5), Vector2(17, 17), Vector2(30, 30), Vector2(31, 31)]
	var forest := {Vector2i(5, 5): TerrainRules.TerrainType.FOREST}   # cell (5,5) holds the first 3 models
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var open_rolls: Array = []
	SoloSim._resolve_shooting(attacker, target.duplicate(true), 10.0, rng, [], open_rolls, {})
	var cover_rolls: Array = []
	SoloSim._resolve_shooting(attacker, target.duplicate(true), 10.0, rng, [], cover_rolls, forest)
	assert_int(int(open_rolls[0]["save_target"])).is_equal(4)     # Defense 4, no cover
	assert_int(int(cover_rolls[0]["save_target"])).is_equal(3)    # +1 to block = a 3+ save


func test_difficult_terrain_halves_the_move() -> void:
	var u: Dictionary = SoloSim.make_unit("Walkers", 0, 4, 4, 1, [{"name": "CCW", "range_value": 0, "attacks": 1, "count": 1, "special_rules": []}])
	u["pos"] = Vector2(16.5, 20.0)
	u["model_pos"] = [Vector2(16.5, 20.0)]
	var forest := {Vector2i(5, 5): TerrainRules.TerrainType.FOREST}   # inches [15,18) on both axes
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	SoloSim._terrain_move(u, Vector2(0.0, -6.0), forest, rng, [])   # a 6" move through the forest
	assert_float((u["pos"] as Vector2).y).is_equal_approx(17.0, 0.001)   # halved to 3" (20 → 17), not 14


func test_dangerous_terrain_can_wound() -> void:
	# 60 models all cross a dangerous cell; at 1-in-6 per model the unit is virtually certain to take wounds.
	var u: Dictionary = SoloSim.make_unit("Chargers", 0, 4, 4, 60, [{"name": "CCW", "range_value": 0, "attacks": 1, "count": 60, "special_rules": []}])
	u["pos"] = Vector2(16.5, 20.0)
	var mp: Array = []
	for i in range(60):
		mp.append(Vector2(16.5, 20.0))
	u["model_pos"] = mp
	var danger := {Vector2i(5, 5): TerrainRules.TerrainType.DANGEROUS}
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	SoloSim._terrain_move(u, Vector2(0.0, -6.0), danger, rng, [])   # move through the dangerous cell
	assert_int(SoloSim.alive_models(u)).is_less(60)                 # some models rolled a 1 and died
