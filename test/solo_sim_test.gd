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


# === Movement spacing (GF v3.5.1 p.7: stay over 1" from other units, except when charging) ===

func test_non_charge_move_stops_clear_of_another_unit() -> void:
	# A unit advancing straight at a stationary unit 10" away must stop at the separation threshold
	# (base contact CONTACT_IN + the 1" rule), never intermingling — this is the maintainer's overlap bug.
	var mover: Dictionary = SoloSim.make_unit("Mover", 0, 4, 4, 1, [{"name": "CCW", "range_value": 0, "attacks": 1, "count": 1, "special_rules": []}])
	mover["pos"] = Vector2(24, 10)
	mover["model_pos"] = [Vector2(24, 10)]
	var block: Dictionary = SoloSim.make_unit("Block", 1, 4, 4, 1, [])
	block["pos"] = Vector2(24, 20)
	block["model_pos"] = [Vector2(24, 20)]
	# Request a 12" step north (toward the blocker) → clamp so the model stops at the 3" separation.
	SoloSim._terrain_move(mover, Vector2(0, 12), {}, RandomNumberGenerator.new(), [], [], [mover, block])
	var gap: float = (mover["model_pos"][0] as Vector2).distance_to(Vector2(24, 20))
	assert_float(gap).is_equal_approx(SoloSim.CONTACT_IN + SoloSim.SPACING_IN, 0.05)   # stopped exactly clear


func test_charge_ignores_spacing_and_closes_to_contact() -> void:
	# The SAME approach taken as a Charge (allow_contact) is exempt from the 1" rule — it closes inside it to
	# base contact, so it ends nearer than the spacing-limited non-charge move.
	var walk: Dictionary = SoloSim.make_unit("Walk", 0, 4, 4, 1, [{"name": "CCW", "range_value": 0, "attacks": 1, "count": 1, "special_rules": []}])
	walk["pos"] = Vector2(24, 10); walk["model_pos"] = [Vector2(24, 10)]
	var charge: Dictionary = SoloSim.make_unit("Charge", 0, 4, 4, 1, [{"name": "CCW", "range_value": 0, "attacks": 1, "count": 1, "special_rules": []}])
	charge["pos"] = Vector2(24, 10); charge["model_pos"] = [Vector2(24, 10)]
	var block: Dictionary = SoloSim.make_unit("Block", 1, 4, 4, 1, [])
	block["pos"] = Vector2(24, 20); block["model_pos"] = [Vector2(24, 20)]
	var rng := RandomNumberGenerator.new()
	SoloSim._terrain_move(walk, Vector2(0, 9), {}, rng, [], [], [walk, block], false)     # non-charge → clamped
	SoloSim._terrain_move(charge, Vector2(0, 9), {}, rng, [], [], [charge, block], true)  # charge → exempt
	var walk_gap: float = (walk["model_pos"][0] as Vector2).distance_to(Vector2(24, 20))
	var charge_gap: float = (charge["model_pos"][0] as Vector2).distance_to(Vector2(24, 20))
	assert_float(walk_gap).is_greater_equal(SoloSim.CONTACT_IN + SoloSim.SPACING_IN - 0.01)   # walk kept clear
	assert_float(charge_gap).is_less(walk_gap)                                                # charge closed nearer


# === M2 combat rules: melee 2" reach · split fire · overlays · Deadly · Relentless · Medic ===

func _rng(s: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return r


func test_only_models_within_2in_strike_in_melee() -> void:
	# OPR p.9 "Who Can Strike": only models within 2" of an enemy model attack. A 10-model unit with a
	# 5-model front rank in reach and a 5-model rear rank out of reach fights with just 5 models' attacks.
	var striker: Dictionary = SoloSim.make_unit("Mob", 0, 4, 4, 10, [{"name": "CCW", "range_value": 0, "attacks": 1, "count": 10, "special_rules": []}])
	var defender: Dictionary = SoloSim.make_unit("Foe", 1, 4, 4, 5, [])
	defender["model_pos"] = [Vector2(20, 22), Vector2(22, 22), Vector2(24, 22), Vector2(26, 22), Vector2(28, 22)]
	var sm: Array = []
	for i in range(5):
		sm.append(Vector2(20 + 2 * i, 20))   # front rank ~2" from a defender model → in reach
	for i in range(5):
		sm.append(Vector2(20 + 2 * i, 10))   # rear rank ~12" away → out of reach
	striker["model_pos"] = sm
	assert_int(SoloSim._striking_models(striker, defender)).is_equal(5)
	assert_int(SoloSim._effective_melee_attacks(striker, defender, 10)).is_equal(5)   # 10 × 5/10
	# Boundary: a rear model dragged to exactly the reach edge (CONTACT + 2") now also strikes.
	sm[5] = Vector2(20, 22.0 - (SoloSim.CONTACT_IN + SoloSim.MELEE_REACH_IN))
	striker["model_pos"] = sm
	assert_int(SoloSim._striking_models(striker, defender)).is_equal(6)
	# Missing model positions (a focused unit test) → the whole living unit strikes (no crash).
	striker["model_pos"] = []
	assert_int(SoloSim._striking_models(striker, defender)).is_equal(10)


func test_split_fire_sends_weapon_types_to_their_overlay_targets() -> void:
	# Two weapon TYPES split onto two targets: a plain rifle at the nearest soft unit, an AP cannon at the
	# highest-Defense unit (AP overlay), per OPR split-fire (p.8) + Solo overlays (p.2).
	var atk: Dictionary = SoloSim.make_unit("Gunline", 0, 3, 4, 5, [
		{"name": "Rifle", "range_value": 30, "attacks": 2, "count": 5, "special_rules": []},
		{"name": "AP Cannon", "range_value": 30, "attacks": 2, "count": 1, "special_rules": ["AP(3)"]},
	])
	atk["pos"] = Vector2(24, 10); atk["model_pos"] = [Vector2(24, 10)]; atk["_id"] = 0
	var soft: Dictionary = SoloSim.make_unit("Soft", 1, 4, 3, 5, [])    # near, low Defense → rifle's target
	soft["pos"] = Vector2(24, 14); soft["model_pos"] = [Vector2(24, 14)]; soft["_id"] = 1
	var tanky: Dictionary = SoloSim.make_unit("Tanky", 1, 4, 6, 5, [])  # far, high Defense → AP cannon's target
	tanky["pos"] = Vector2(24, 20); tanky["model_pos"] = [Vector2(24, 20)]; tanky["_id"] = 2
	var rolls: Array = []
	SoloSim._resolve_shooting_split(atk, [atk, soft, tanky], _rng(1), [], rolls, {})
	var shot: Dictionary = {}
	for r in rolls:
		if str((r as Dictionary).get("kind", "")) == "shoot":
			shot[str((r as Dictionary)["target"])] = true
	assert_bool(shot.has("Soft")).is_true()    # rifle → nearest
	assert_bool(shot.has("Tanky")).is_true()   # AP cannon → highest Defense (split fire)


func test_deadly_multiplies_applied_wounds_against_tough_target() -> void:
	# Same dice (same seed, same attack count) with and without Deadly(3) vs a Tough(3) target: Deadly triples
	# each unsaved wound (Tough-capped), so it lands exactly 3× the pool damage.
	var plain_w := {"name": "Gun", "range_value": 24, "attacks": 6, "count": 1, "special_rules": []}
	var deadly_w := {"name": "Gun", "range_value": 24, "attacks": 6, "count": 1, "special_rules": ["Deadly(3)"]}
	var tgt_plain: Dictionary = SoloSim.make_unit("T", 1, 4, 5, 10, [], 3)   # Tough(3), Defense 5
	tgt_plain["model_pos"] = [Vector2.ZERO]
	var tgt_deadly: Dictionary = tgt_plain.duplicate(true)
	var atk_plain: Dictionary = SoloSim.make_unit("A", 0, 2, 4, 1, [plain_w])   # Quality 2+ → reliable hits
	var atk_deadly: Dictionary = SoloSim.make_unit("A", 0, 2, 4, 1, [deadly_w])
	SoloSim._resolve_volley(atk_plain, tgt_plain, AiShooting.profiles_in_range([plain_w], 10.0), 10.0, _rng(4), [], [], {})
	SoloSim._resolve_volley(atk_deadly, tgt_deadly, AiShooting.profiles_in_range([deadly_w], 10.0), 10.0, _rng(4), [], [], {})
	assert_int(int(tgt_plain["wounds_pool"])).is_greater(0)
	assert_int(int(tgt_deadly["wounds_pool"])).is_equal(int(tgt_plain["wounds_pool"]) * 3)


func test_regeneration_medic_ignores_wounds_on_5plus() -> void:
	# Regeneration (the Battle Brothers Medical Training / Regeneration Aura, GF p.13): each wound is ignored
	# on a 5+. Every incoming wound rolls one die; survivors = wounds − the 5s/6s.
	var medic: Dictionary = SoloSim.make_unit("Medics", 1, 4, 4, 10, [], 1, ["Regeneration Aura"])
	var rolls: Array = []
	var survived: int = SoloSim._apply_regeneration(medic, 6, _rng(2), [], rolls)
	assert_int(rolls.size()).is_equal(6)   # one regen die per incoming wound
	var ignored := 0
	for r in rolls:
		if int((r as Dictionary)["face"]) >= 5:
			ignored += 1
	assert_int(survived).is_equal(6 - ignored)
	assert_int(survived).is_between(0, 6)
	# A unit without the rule takes every wound and rolls nothing.
	var plain: Dictionary = SoloSim.make_unit("Grunts", 1, 4, 4, 10, [])
	var r2: Array = []
	assert_int(SoloSim._apply_regeneration(plain, 6, _rng(2), [], r2)).is_equal(6)
	assert_int(r2.size()).is_equal(0)


func test_relentless_unit_holds_and_shoots_when_enemy_in_range() -> void:
	# Relentless overlay (Solo rules p.2): with an enemy in range the unit Holds and shoots instead of
	# manoeuvring — so it does NOT move (a plain shooter here would kite backward).
	var relent: Dictionary = SoloSim.make_unit("Gun Team", 0, 3, 4, 3, [{"name": "HMG", "range_value": 30, "attacks": 3, "count": 3, "special_rules": ["Relentless"]}])
	relent["pos"] = Vector2(24, 10); relent["model_pos"] = SoloSim._formation(Vector2(24, 10), 3); relent["_id"] = 0
	var foe: Dictionary = SoloSim.make_unit("Foe", 1, 4, 4, 5, [])
	foe["pos"] = Vector2(24, 20); foe["model_pos"] = [Vector2(24, 20)]; foe["_id"] = 1
	var trace: Array = []
	SoloSim._activate(relent, [relent, foe], _rng(3), [], 1, [], [], trace)
	assert_vector(relent["pos"] as Vector2).is_equal(Vector2(24, 10))   # Held — did not kite
	assert_str(str((trace[trace.size() - 1] as Dictionary)["action"])).contains("holds+shoots")


func test_unmodeled_special_rules_are_logged_once_per_game() -> void:
	# Any rule the combat math doesn't model is logged once (deduped); modelled rules are not flagged.
	var a: Array = [SoloSim.make_unit("A", 0, 4, 4, 3, [{"name": "CCW", "range_value": 0, "attacks": 1, "count": 3, "special_rules": []}], 1, ["Fearless", "Regeneration Aura"])]
	var b: Array = [SoloSim.make_unit("B", 1, 4, 4, 3, [{"name": "CCW", "range_value": 0, "attacks": 1, "count": 3, "special_rules": []}], 1, ["Fearless"])]
	var log: Array = []
	SoloSim.simulate_game(a, b, 11, 1, log)
	var fearless := 0
	var regen := 0
	for line in log:
		if str(line).contains("unmodeled") and str(line).contains("Fearless"):
			fearless += 1
		if str(line).contains("unmodeled") and str(line).contains("Regeneration"):
			regen += 1
	assert_int(fearless).is_equal(1)   # logged once across both units/sides
	assert_int(regen).is_equal(0)      # Regeneration is modelled → never flagged


func test_units_from_opr_json_collects_nested_item_rules_and_weapon_deadly() -> void:
	# The rule footprint must include upgrade/item-granted rules (AF nests them), so the medic's Regeneration
	# Aura and the sniper's Deadly/AP are seen — not just the top-level `rules` list.
	var data := {"units": [{
		"name": "Squad", "size": 5, "quality": 3, "defense": 3, "rules": [{"name": "Fearless"}],
		"selectedUpgrades": [{"option": {"gains": [{"name": "Medical Training", "content": [{"name": "Regeneration Aura"}]}]}}],
		"loadout": [
			{"name": "Sniper", "range": 30, "attacks": 1, "count": 1, "specialRules": [{"name": "Deadly", "rating": 3}, {"name": "AP", "rating": 1}]},
		],
	}]}
	var u: Dictionary = SoloSim.units_from_opr_json(data, 0)[0]
	assert_bool(SoloSim._has_regeneration(u)).is_true()
	assert_array(u["rules"]).contains(["Fearless"])
	var sniper: Dictionary = (u["weapons"] as Array).filter(func(w): return str(w["name"]) == "Sniper")[0]
	assert_array(sniper["special_rules"]).contains(["Deadly(3)", "AP(1)"])
