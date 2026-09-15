extends GdUnitTestSuite
## D-STEALTH (decided 15.09.) — the Stealth family's terrain-conditional alias
## reads the book wording on the table too: Grounded Stealth's -1 to be hit
## applies per model within the entry's own `terrain_within_in` (1") of ANY
## terrain — the same per-model predicate Grounded Speed's verdict answers
## over the #969 id-rail (`TerrainRules.base_in_terrain_id`, class ANY) — and
## the majority-in-cover-CELL approximation (RUINS/FOREST cells only) is
## dropped from the alias walk in `_solo_hit_mod_info`.
##
## The sampler Callable is built HERE (an instance context — no Callable is
## constructed inside a static context; the crash note on terrain_rules.gd
## holds) and handed to the static read, which stays pure given a unit and a
## sampler. RED before the fix: the walk consulted `_solo_majority_in_cover`,
## whose bare-instance read is honest false — the within-1" leg fails.

const MainScript := preload("res://scripts/main.gd")


func _unit(rules: Array, positions: Array) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = "gs_unit"
	u.unit_properties = {"player_id": 2, "name": "Squad", "quality": 4, "defense": 4,
		"special_rules": rules, "game_system": "gf", "faction_folder": "machine_cults"}
	for p in positions:
		var m := ModelInstance.new()
		m.is_alive = true
		var n := Node3D.new()
		add_child(n)
		n.global_position = p
		m.node = n
		u.models.append(m)
	return u


## The patch the book's wording must see and the cover-CELL approximation
## never could: DANGEROUS ground is terrain (any cell but NONE — the core's
## terrain::is_any) but gives no cover, so a carrier standing on it was
## denied the -1 the rule prints.
func _dangerous_patch_sampler() -> Callable:
	var f := func(p: Vector3) -> int:
		return TerrainRules.TerrainType.DANGEROUS if Vector2(p.x, p.z).length() < 0.5 else TerrainRules.TerrainType.NONE
	return f


func _bare_main(sampler: Callable) -> Node3D:
	var main: Node3D = auto_free(MainScript.new())
	var solo: SoloController = auto_free(SoloController.new())
	solo.terrain_type_at = sampler
	main.solo_controller = solo
	return main


## THE port: the carrier stands ON dangerous ground (in terrain, not in a
## cover cell) — the alias fires (RED before the fix: the cover-cell
## approximation answered false and the -1 never applied).
func test_carrier_on_dangerous_ground_within_one_inch_of_terrain_gets_minus_one() -> void:
	var main := _bare_main(_dangerous_patch_sampler())
	var target := _unit(["Grounded Stealth"], [Vector3.ZERO])
	var info: Dictionary = main._solo_hit_mod_info(null, target, 12.0, false)
	assert_int(int(info["mod"])) \
		.override_failure_message("within 1\" of terrain: Grounded Stealth's -1 to be hit") \
		.is_equal(-1)
	assert_str(str(info.get("note", ""))).contains("Grounded Stealth")


## The SAME carrier in the open: no -1 (RED stays green — the open read is
## unchanged by the port).
func test_carrier_in_the_open_gets_no_minus_one() -> void:
	var main := _bare_main(_dangerous_patch_sampler())
	var target := _unit(["Grounded Stealth"], [Vector3(10.0, 0.0, 10.0)])
	var info: Dictionary = main._solo_hit_mod_info(null, target, 12.0, false)
	assert_int(int(info["mod"])) \
		.override_failure_message("in the open: no -1 to hit") \
		.is_equal(0)


## Per model, MAJORITY verdict: two of three models within 1" of terrain and
## the unit keeps the -1; one of three loses it. The old cover-cell read
## keyed on the CELL majority — the new one keys on the per-model proximity.
func test_majority_of_models_near_terrain_decides_the_verdict() -> void:
	var main := _bare_main(_dangerous_patch_sampler())
	var covered := _unit(["Grounded Stealth"], [Vector3.ZERO, Vector3(0.1, 0, 0), Vector3(5, 0, 5)])
	assert_int(int(main._solo_hit_mod_info(null, covered, 12.0, false)["mod"])).is_equal(-1)
	var open := _unit(["Grounded Stealth"], [Vector3(5, 0, 5), Vector3(5.1, 0, 5), Vector3.ZERO])
	assert_int(int(main._solo_hit_mod_info(null, open, 12.0, false)["mod"])).is_equal(0)


## No board (an invalid sampler): the condition honestly fails without
## terrain — the Grounded Speed verdict's own absent-board shape.
func test_no_terrain_reads_an_honest_false() -> void:
	var main := _bare_main(Callable())
	var target := _unit(["Grounded Stealth"], [Vector3.ZERO])
	assert_int(int(main._solo_hit_mod_info(null, target, 12.0, false)["mod"])).is_equal(0)


## The plain Stealth name keeps its own over-9" leg byte-exact — the alias
## gate must not touch the literal rule.
func test_plain_stealth_keeps_its_over_nine_leg() -> void:
	var main := _bare_main(_dangerous_patch_sampler())
	var target := _unit(["Stealth"], [Vector3.ZERO])
	assert_int(int(main._solo_hit_mod_info(null, target, 12.0, false)["mod"])) \
		.is_equal(-1)