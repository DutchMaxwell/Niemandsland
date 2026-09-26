extends GdUnitTestSuite
## D15 / Q6 — GF/AoF v3.5.1 p.11 "COVER TERRAIN": "If the majority of models in a unit are FULLY inside a piece of
## cover terrain (for multi-model units), or … MOSTLY inside cover terrain (for single-model units), they get +1 to
## Defense rolls when blocking hits from shooting attacks." The readers used to probe the model CENTRE only, so a base
## straddling a wood's rim counted as fully inside. Now a multi-model unit's model counts only when its whole base
## stands on cover terrain; a single-model unit (and Takedown's unit of [1]) keeps the centre probe, which IS
## "mostly inside" against a straight edge (centre inside <=> at least half the base inside).
##
## The shared terrain shape: a straight wood edge at x = 0 (forest for x < 0). A default base is 0.016 m in radius.
## Control tests are declared FIRST: gdUnit drops tests declared after a failing one.

const T := TerrainRules.TerrainType
const WELL_INSIDE := -0.2     # the whole 0.016 m base is far inside the wood
const STRADDLING := -0.004    # centre in the wood, the base's outer rim crosses the edge


func _edge_forest(p: Vector3) -> int:
	return int(T.FOREST) if p.x < 0.0 else int(T.NONE)


func _unit(pid: int, positions: Array) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = "p%d_%d" % [pid, positions.size()]
	u.unit_properties = {"player_id": pid, "name": "U%d" % pid, "quality": 4, "defense": 4}
	for p in positions:
		var m := ModelInstance.new()
		m.is_alive = true
		var n := Node3D.new()
		add_child(n)
		n.global_position = p
		m.node = n
		u.models.append(m)
	return u


func _solo(unit: GameUnit) -> SoloController:
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {unit.unit_id: unit}
	var solo: SoloController = auto_free(SoloController.new())
	add_child(solo)
	solo.setup(army, null, null, 1, 2)
	solo.terrain_type_at = Callable(self, "_edge_forest")
	return solo


func test_a_squad_well_inside_the_wood_still_gets_cover() -> void:
	var squad := _unit(1, [Vector3(WELL_INSIDE, 0, 0), Vector3(WELL_INSIDE, 0, 0.1), Vector3(WELL_INSIDE, 0, 0.2)])
	assert_bool(_solo(squad).majority_in_cover(squad)).is_true()


func test_a_single_model_unit_straddling_the_edge_is_mostly_inside() -> void:
	# "mostly inside" for single-model units: the centre probe stays (a straight edge: centre in => >= half the base in).
	var hero := _unit(1, [Vector3(STRADDLING, 0, 0)])
	var solo := _solo(hero)
	assert_bool(solo.majority_in_cover(hero)).is_true()
	assert_bool(solo.model_in_cover(hero.models[0])).is_true()
	# ... and a lone model whose centre is OUT of the wood is not mostly inside.
	var outside := _unit(1, [Vector3(0.004, 0, 0)])
	assert_bool(_solo(outside).majority_in_cover(outside)).is_false()


func test_takedowns_unit_of_one_keeps_the_single_model_reading() -> void:
	# Takedown resolves as a unit of [1] (p.14): the picked model straddling the rim is "mostly inside" on its own,
	# even though the same model would not count as FULLY inside for the squad's majority.
	var squad := _unit(1, [Vector3(STRADDLING, 0, 0), Vector3(STRADDLING, 0, 0.1), Vector3(STRADDLING, 0, 0.2)])
	assert_bool(_solo(squad).model_in_cover(squad.models[1])).is_true()


func test_base_fully_in_cover_probes_the_whole_base() -> void:
	var probe := Callable(self, "_edge_forest")
	assert_bool(TerrainRules.base_fully_in_cover(Vector3(WELL_INSIDE, 0, 0), 0.016, probe)).is_true()
	assert_bool(TerrainRules.base_fully_in_cover(Vector3(STRADDLING, 0, 0), 0.016, probe)).is_false()
	assert_bool(TerrainRules.base_fully_in_cover(Vector3(0.05, 0, 0), 0.016, probe)).is_false()
	# radius 0 = a point: the centre decides (the single-model reading).
	assert_bool(TerrainRules.base_fully_in_cover(Vector3(STRADDLING, 0, 0), 0.0, probe)).is_true()


func test_a_squad_straddling_the_edge_gets_no_cover() -> void:
	# Every model's CENTRE is in the wood, none is FULLY in: the old centre probe said cover, the book says no.
	var squad := _unit(1, [Vector3(STRADDLING, 0, 0), Vector3(STRADDLING, 0, 0.1), Vector3(STRADDLING, 0, 0.2)])
	assert_bool(_solo(squad).majority_in_cover(squad)) \
		.override_failure_message("D15 — a squad whose bases all straddle the wood's edge got the +1 Defense (centre probe)") \
		.is_false()


func test_the_majority_counts_fully_inside_models_only() -> void:
	# 3 models: two well inside + one straddling -> 2 of 3 fully inside = strict majority; one well inside + two
	# straddling -> 1 of 3 fully inside = no majority (the centre probe counted all three as in cover).
	var two_in := _unit(1, [Vector3(WELL_INSIDE, 0, 0), Vector3(WELL_INSIDE, 0, 0.1), Vector3(STRADDLING, 0, 0.2)])
	assert_bool(_solo(two_in).majority_in_cover(two_in)).is_true()
	var one_in := _unit(2, [Vector3(WELL_INSIDE, 0, 0), Vector3(STRADDLING, 0, 0.1), Vector3(STRADDLING, 0, 0.2)])
	assert_bool(_solo(one_in).majority_in_cover(one_in)) \
		.override_failure_message("D15 — 1 model fully inside + 2 straddling is NOT a majority of fully-inside models") \
		.is_false()


func test_a_survivor_of_a_squad_still_needs_to_be_fully_inside() -> void:
	# A multi-model unit stays multi-model after casualties: the last survivor straddling the rim is not "fully inside".
	var squad := _unit(1, [Vector3(WELL_INSIDE, 0, 0), Vector3(WELL_INSIDE, 0, 0.1), Vector3(STRADDLING, 0, 0.2)])
	squad.models[0].is_alive = false
	squad.models[1].is_alive = false
	assert_bool(_solo(squad).majority_in_cover(squad)) \
		.override_failure_message("D15 — a squad's straddling last survivor was read as a single-model unit") \
		.is_false()
