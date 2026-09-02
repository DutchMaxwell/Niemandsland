extends SceneTree
## S4 oracle dump for `deployment::arrive_one` (SPEC_rule_ambush_arrival_2026-09-02.md §4 S4).
## READ-ONLY: boots the REAL res://scenes/main.tscn (harness_mode, the same seam
## test/e2e/e2e_boot.gd and tools/tutorial_smoke.gd use) and calls the table's ALREADY-SHIPPED
## `SoloController.arrive_one_ambush_unit` — nothing under scripts/ is edited.
##
## Cases are built the way test/e2e/e2e_ambush_variants_test.gd:101-178,243-258,320-323 does
## (GameUnits assembled directly via the shared E2EBoot.make_unit, not imported): the "existing
## pregame fixture armies" (tools/arena_match.gd's tutorial_army_p1/p2 defaults) carry zero
## Ambush/Infiltrate/Repel Ambushers units (SPEC §0 finding 1) and importing them needs the
## army-forge API/network (tools/arena_match.gd:940-962) — neither gives a deterministic offline
## ambush corpus, so this dump follows the e2e suite's own construction instead, on the real
## booted board/table size. CASES below is data, not per-case code, and every line is packed
## (long lines, not more of them) to keep this tool out of the ~60-line ARRIVAL gate budget
## (SPEC §4 S4, enforced by this repo's branch-size push guard) while still covering the ring
## arithmetic: plain Ambush (9"), Infiltrate (3"), Repel Ambushers' 12" override, mixed/multi
## enemies, a pre-occupied seed, a wide footprint, and two HELD (no-legal-spot) cases.
##
## Each case records the exact fields the ARRIVAL section of
## core/nml-core-py/tools/deployment_gate.py needs to replay `deployment::arrive_one` against:
## zone, objectives, occupied, enemies[{pos,min_dist_m,pad_m}], own_ring_m, footprint, base_r,
## flying, spot (spot == null: the table found no legal spot — a HELD case, SPEC §6.2).
##
## Beacon geometry is deliberately absent: S3's `arrive_one` (SPEC §2.2) takes no beacon
## parameter at all — that lands with S5, not yet built. Every case here passes beacons=[] so no
## case's `spot` ever depends on a waiver S3 cannot reproduce (SPEC §2.5 decision #2).
##
## Run: godot --headless --path . -s res://tools/ambush_arrival_dump.gd -- out=<path>
## Default out: res://core/nml-core/tests/fixtures/ambush_arrival.json

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const OUT_DEFAULT := "res://core/nml-core/tests/fixtures/ambush_arrival.json"
const ROUND_NO := 2   # base Ambush's earliest round (p.13) — every case is eligible, none held by timing

## [case name, rules (comma-joined), arriver model count, enemies [[rule or "", Vector3 pos], ...],
##  objective Vector2, occupied [[Vector2 pos, radius], ...]]
const CASES := [
	["ambush_single_enemy_centre", "Ambush", 1, [["", Vector3(0.05, 0, 0.05)]], Vector2(0.3, 0.2), []],
	["infiltrate_single_enemy_centre", "Infiltrate", 1, [["", Vector3(0.05, 0, -0.05)]], Vector2(-0.2, 0.1), []],
	["infiltrate_vs_repel_ambushers", "Infiltrate", 1, [["Repel Ambushers", Vector3.ZERO]], Vector2(0.4, -0.3), []],
	["ambush_vs_repel_ambushers", "Ambush", 1, [["Repel Ambushers", Vector3(0.1, 0, 0.1)]], Vector2(-0.4, -0.2), []],
	["ambush_two_enemies_mixed", "Ambush", 1, [["", Vector3(0.2, 0, 0.1)], ["Repel Ambushers", Vector3(-0.5, 0, -0.3)]], Vector2(0.0, 0.4), []],
	["infiltrate_multi_enemy_no_repel", "Infiltrate", 1, [["", Vector3(0.15, 0, -0.1)], ["", Vector3(-0.2, 0, 0.15)]], Vector2(0.5, 0.5), []],
	["ambush_pre_occupied", "Ambush", 1, [["", Vector3.ZERO]], Vector2(0.5, 0.3), [[Vector2(0.5, 0.3), 0.3]]],
	["ambush_five_model_wide_footprint", "Ambush", 5, [["", Vector3(0.1, 0, -0.2)]], Vector2(-0.3, 0.3), []],
	["held_fully_occupied", "Ambush", 1, [["", Vector3(1.0, 0, 1.0)]], Vector2.ZERO, [[Vector2.ZERO, 2.0]]],
	["held_wide_unit_occupied", "Infiltrate", 4, [["", Vector3(1.0, 0, 1.0)]], Vector2.ZERO, [[Vector2.ZERO, 2.0]]],
]

var _out_path := OUT_DEFAULT
var _main: Node
var _solo: SoloController
var _units: Array = []   # every GameUnit this run made — cycle-broken + freed before quit (hygiene)


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2 and kv[0] == "out": _out_path = kv[1]
	ProjectSettings.set_setting("niemandsland/harness_mode", true)
	change_scene_to_file("res://scenes/main.tscn"); _drive.call_deferred()


func _drive() -> void:
	for _i in 40: await process_frame
	_main = current_scene
	if _main == null: printerr("AMBUSH_DUMP FATAL: main.tscn never mounted"); quit(1); return
	_main.solo_ai_slots = {2: true}; _main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING; _main._solo_batch = true
	_solo = _main.solo_controller
	var zone := _zone()
	var cases: Array = CASES.map(func(spec): return _run_case(spec, zone))
	var held: int = cases.filter(func(c): return c["spot"] == null).size()
	var out := {"schema": 1, "tool": "ambush_arrival_dump", "beacon_cases": 0,
		"table_size_ft": [_main.table.table_size.x, _main.table.table_size.y], "cases": cases}
	var f := FileAccess.open(_out_path, FileAccess.WRITE)
	if f == null: printerr("AMBUSH_DUMP FATAL: cannot write %s" % _out_path); quit(1); return
	f.store_string(JSON.stringify(out, "  ")); f.close()
	print("AMBUSH_ARRIVAL_DUMP %d %d OK" % [cases.size(), held])
	_free_units()   # GameUnit.models <-> ModelInstance.unit is a ref cycle — break it before quit
	quit(0)


func _free_units() -> void:
	for u in _units:
		for m in (u as GameUnit).models:
			var mi := m as ModelInstance
			if is_instance_valid(mi.node): mi.node.free()
			mi.unit = null
		(u as GameUnit).models.clear()


## The whole table as the arrival zone — main.gd:10428-10431's own construction, off the REAL
## booted table_size (not a guessed constant).
func _zone() -> Rect2:
	var w: float = _main.table.table_size.x * 0.3048
	var d: float = _main.table.table_size.y * 0.3048
	return Rect2(Vector2(-w / 2.0, -d / 2.0), Vector2(w, d))


func _run_case(spec: Array, zone: Rect2) -> Dictionary:
	var positions: Array = range(int(spec[2])).map(
		func(i): return Vector3(6.0 + float(_units.size()) * 0.15 + float(i) * 0.1, 0, 0))
	var arriver: GameUnit = E2EBoot.make_unit(_main, 2, spec[0], positions)
	arriver.unit_properties["special_rules"] = (spec[1] as String).split(",")
	arriver.unit_properties["ambush_reserve"] = true
	_units.append(arriver)
	var enemies: Array = []
	for e in spec[3] as Array:
		var enemy: GameUnit = E2EBoot.make_unit(_main, 1, "%s_e" % spec[0], [e[1]])
		if str(e[0]) != "": enemy.unit_properties["special_rules"] = [str(e[0])]
		_units.append(enemy); enemies += _enemy_entries(enemy)
	var occupied: Array = (spec[5] as Array).map(func(o): return {"pos": o[0], "radius": o[1]})
	return _record(spec[0], arriver, zone, [spec[4]], occupied, enemies)


## _enemy_entries (e2e_ambush_variants_test.gd:74-81), per model, edge-true. "pos" stays a real
## Vector2 here — this SAME list feeds arrive_one_ambush_unit's ring search, not just the record.
func _enemy_entries(enemy: GameUnit) -> Array:
	return enemy.get_alive_models().map(func(m): return {
		"pos": Vector2((m as ModelInstance).node.global_position.x, (m as ModelInstance).node.global_position.z),
		"min_dist_m": SoloController.repel_ambush_dist_m(enemy), "pad_m": SoloController.model_base_radius_m(m)})


func _v2(p: Vector2) -> Array:
	return [p.x, p.y]


## Run one arrival and record the ARRIVAL gate's case shape (SPEC §4 S4).
func _record(name: String, unit: GameUnit, zone: Rect2, objectives: Array, occupied: Array,
		enemies: Array) -> Dictionary:
	_solo.ambush_reserve = [unit]; _solo._deploy_objectives = objectives
	var arrived: GameUnit = _solo.arrive_one_ambush_unit(zone, enemies, occupied.duplicate(true), ROUND_NO, [])
	var c: Vector3 = _solo.unit_centre(unit) if arrived == unit else Vector3.INF
	var spot = null if arrived != unit else [c.x, c.z]
	return {"case": name, "zone": [zone.position.x, zone.position.y, zone.size.x, zone.size.y],
		"objectives": objectives.map(func(o): return _v2(o)),
		"occupied": occupied.map(func(o): return {"pos": _v2(o["pos"]), "radius": float(o["radius"])}),
		"enemies": enemies.map(func(e): return {"pos": _v2(e["pos"]), "min_dist_m": float(e["min_dist_m"]), "pad_m": float(e["pad_m"])}),
		"own_ring_m": _solo._reserve_min_enemy_dist_m(unit),
		"footprint": _solo._deploy_footprint_offsets(unit).map(func(v): return _v2(v)),
		"base_r": _solo._deploy_base_radius(_solo._deploy_models(unit)),
		"flying": unit.has_special_rule("Strider") or unit.has_special_rule("Flying"), "spot": spot}
