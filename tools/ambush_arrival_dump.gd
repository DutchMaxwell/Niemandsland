extends SceneTree
## Gap-filler synthetic cases for the ARRIVAL oracle (SPEC_rule_ambush_arrival_2026-09-02.md §4
## S4, corrected 2026-09-02): the bulk of the oracle now comes from the REAL corpora
## (core/nml-core-py/tools/ambush_arrival_corpus.py — 98 real arrivals, qbg_ref + qag_ref), not a
## synthetic dump. This script supplies only what those corpora do not carry (grepped, zero hits
## in either bundle, see that script's own docstring): Repel Ambushers' 12" ring override, and a
## HELD (no-legal-spot) case — a fully-occupied zone, provably unplaceable by construction, not by
## measurement. READ-ONLY against the shipped `SoloController.arrive_one_ambush_unit`; boots the
## real res://scenes/main.tscn (harness_mode, the seam test/e2e/e2e_boot.gd uses) so the geometry
## primitives (best_spot, footprint_margins) run for real, same as any other Ambush arrival.
##
## Run: godot --headless --path . -s res://tools/ambush_arrival_dump.gd -- out=<path>
## Default out: res://core/nml-core/tests/fixtures/ambush_arrival_gap.json (merged into the
## committed fixture by ambush_arrival_corpus.py's --gap flag).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")

## [case name, arriver's rule, enemies [[rule or "", Vector3 pos], ...], objective Vector2,
##  occupied [[Vector2 pos, radius], ...]]
const CASES := [
	["ambush_vs_repel_ambushers", "Ambush", [["Repel Ambushers", Vector3(0.1, 0, 0.1)]], Vector2(0.1, 0.1), []],
	["held_fully_occupied", "Ambush", [["", Vector3(1.0, 0, 1.0)]], Vector2.ZERO, [[Vector2.ZERO, 2.0]]],
]

var _main: Node; var _solo: SoloController; var _units: Array = []


func _initialize() -> void:
	ProjectSettings.set_setting("niemandsland/harness_mode", true); change_scene_to_file("res://scenes/main.tscn"); _drive.call_deferred()


func _drive() -> void:
	for _i in 40: await process_frame
	_main = current_scene; _main.solo_ai_slots = {2: true}; _main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING; _main._solo_batch = true
	_solo = _main.solo_controller
	var zone := Rect2(Vector2(-0.9144, -0.6096), Vector2(1.8288, 1.2192))   # the DEFAULT_TABLE_SIZE_FEET 6x4ft zone (main.gd:23, :10428-10431)
	var cases: Array = CASES.map(func(spec): return _run_case(spec, zone))
	var f := FileAccess.open("res://core/nml-core/tests/fixtures/ambush_arrival_gap.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"cases": cases}, "  ")); f.close()
	print("AMBUSH_ARRIVAL_GAP %d OK" % cases.size())
	for u in _units:   # models.clear() alone breaks the GameUnit<->ModelInstance cycle
		for m in (u as GameUnit).models:
			if is_instance_valid((m as ModelInstance).node): (m as ModelInstance).node.free()
		(u as GameUnit).models.clear()
	quit(0)


func _run_case(spec: Array, zone: Rect2) -> Dictionary:
	var arriver: GameUnit = E2EBoot.make_unit(_main, 2, spec[0], [Vector3(5.0, 0, 0)])
	arriver.unit_properties["special_rules"] = [spec[1]]; arriver.unit_properties["ambush_reserve"] = true
	_units.append(arriver)
	var enemies: Array = []
	for e in spec[2] as Array:
		var enemy: GameUnit = E2EBoot.make_unit(_main, 1, "%s_e" % spec[0], [e[1]])
		if str(e[0]) != "": enemy.unit_properties["special_rules"] = [str(e[0])]; enemy.unit_properties["faction_folder"] = "eternal_dynasty"   # a real GF faction carrying Repel Ambushers — repel_ambush_dist_m is faction-scoped (rules_registry.gd:59-69)
		_units.append(enemy)
		enemies += enemy.get_alive_models().map(func(m): return {"pos": Vector2((m as ModelInstance).node.global_position.x, (m as ModelInstance).node.global_position.z), "min_dist_m": SoloController.repel_ambush_dist_m(enemy), "pad_m": SoloController.model_base_radius_m(m)})
	var occupied: Array = (spec[4] as Array).map(func(o): return {"pos": o[0], "radius": o[1]})
	_solo.ambush_reserve = [arriver]; _solo._deploy_objectives = [spec[3]]
	var arrived: GameUnit = _solo.arrive_one_ambush_unit(zone, enemies, occupied.duplicate(true), 2, [])
	var c: Vector3 = _solo.unit_centre(arriver) if arrived == arriver else Vector3.INF
	var spot = null if arrived != arriver else [c.x, c.z]
	return {"case": spec[0], "zone": [zone.position.x, zone.position.y, zone.size.x, zone.size.y], "objectives": [[(spec[3] as Vector2).x, (spec[3] as Vector2).y]],
		"occupied": occupied.map(func(o): return {"pos": [(o["pos"] as Vector2).x, (o["pos"] as Vector2).y], "radius": float(o["radius"])}),
		"enemies": enemies.map(func(e): return {"pos": [(e["pos"] as Vector2).x, (e["pos"] as Vector2).y], "min_dist_m": float(e["min_dist_m"]), "pad_m": float(e["pad_m"])}),
		"own_ring_m": _solo._reserve_min_enemy_dist_m(arriver), "footprint": _solo._deploy_footprint_offsets(arriver).map(func(v): return [(v as Vector2).x, (v as Vector2).y]),
		"base_r": _solo._deploy_base_radius(_solo._deploy_models(arriver)), "flying": false, "spot": spot}
