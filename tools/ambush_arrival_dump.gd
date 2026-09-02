extends SceneTree
## S4 oracle dump for `deployment::arrive_one` (SPEC_rule_ambush_arrival_2026-09-02.md §4 S4).
## READ-ONLY: boots the REAL res://scenes/main.tscn (harness_mode, the same seam
## test/e2e/e2e_boot.gd and tools/tutorial_smoke.gd use) and calls the table's ALREADY-SHIPPED
## `SoloController.arrive_one_ambush_unit` — nothing under scripts/ is edited.
##
## Cases are assembled the way test/e2e/e2e_ambush_variants_test.gd:101-178,243-258,320-323
## does (GameUnits built directly, not imported): the "existing pregame fixture armies"
## (tools/arena_match.gd's tutorial_army_p1/p2 defaults) carry zero Ambush/Infiltrate/Repel
## Ambushers units (SPEC §0 finding 1) and importing them needs the army-forge API/network
## (tools/arena_match.gd:940-962) — neither gives a deterministic offline ambush corpus, so this
## dump follows the e2e suite's own construction instead, on the real booted board/table size.
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

const OUT_DEFAULT := "res://core/nml-core/tests/fixtures/ambush_arrival.json"
const BOOT_FRAMES := 40
const ROUND_NO := 2   # base Ambush's earliest round (p.13) — every case is eligible, none held by timing

var _out_path := OUT_DEFAULT
var _main: Node
var _solo: SoloController
var _uid := 0
var _spawned: Array = []   # Node3D model nodes added to the tree — freed before quit (hygiene)
var _units: Array = []     # every GameUnit this run made — cycle-broken before quit (hygiene)


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2 and kv[0] == "out":
			_out_path = kv[1]
	ProjectSettings.set_setting("niemandsland/harness_mode", true)
	change_scene_to_file("res://scenes/main.tscn")
	_drive.call_deferred()


func _drive() -> void:
	for _i in BOOT_FRAMES:
		await process_frame
	_main = current_scene
	if _main == null:
		printerr("AMBUSH_DUMP FATAL: main.tscn never mounted")
		quit(1)
		return
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main._solo_batch = true
	_solo = _main.solo_controller
	var zone := _zone()

	var cases: Array = []
	cases.append(_case_plain_ambush(zone))
	cases.append(_case_infiltrate(zone))
	cases.append(_case_infiltrate_vs_repel(zone))
	cases.append(_case_ambush_vs_repel(zone))
	cases.append(_case_ambush_two_enemies_mixed(zone))
	cases.append(_case_infiltrate_multi_enemy(zone))
	cases.append(_case_ambush_pre_occupied(zone))
	cases.append(_case_ambush_wide_footprint(zone))
	cases.append(_case_infiltrate_small_base(zone))
	cases.append(_case_ambush_large_base(zone))
	cases.append(_case_ambush_strider(zone))
	cases.append(_case_infiltrate_objective_pull(zone))
	cases.append(_case_held_fully_occupied(zone))
	cases.append(_case_held_wide_unit_occupied(zone))

	var held := 0
	for c in cases:
		if c["spot"] == null:
			held += 1
	var out := {"schema": 1, "tool": "ambush_arrival_dump", "beacon_cases": 0,
		"table_size_ft": [_main.table.table_size.x, _main.table.table_size.y], "cases": cases}
	DirAccess.make_dir_recursive_absolute(_out_path.get_base_dir())
	var f := FileAccess.open(_out_path, FileAccess.WRITE)
	if f == null:
		printerr("AMBUSH_DUMP FATAL: cannot write %s" % _out_path)
		quit(1)
		return
	f.store_string(JSON.stringify(out, "  "))
	f.close()
	printerr("AMBUSH_DUMP %d cases (%d held) -> %s" % [cases.size(), held, _out_path])
	print("AMBUSH_ARRIVAL_DUMP %d %d OK" % [cases.size(), held])
	# Hygiene: GameUnit.models <-> ModelInstance.unit is a reference cycle (each ModelInstance
	# holds its owning GameUnit, which owns the ModelInstance array back) — plain refcounting
	# never collects that on its own, so every unit this run made must be broken by hand,
	# on top of clearing the army_manager/reserve lists that also hold them.
	_main.opr_army_manager.game_units.clear()
	_solo.ambush_reserve.clear()
	for u in _units:
		for m in (u as GameUnit).models:
			(m as ModelInstance).unit = null
		(u as GameUnit).models.clear()
	for n in _spawned:
		if is_instance_valid(n):
			n.free()
	quit(0)


## The whole table as the arrival zone — main.gd:10428-10431's own construction, off the REAL
## booted table_size (not a guessed constant).
func _zone() -> Rect2:
	var w: float = _main.table.table_size.x * 0.3048
	var d: float = _main.table.table_size.y * 0.3048
	return Rect2(Vector2(-w / 2.0, -d / 2.0), Vector2(w, d))


## test/e2e/e2e_boot.gd's make_unit, reimplemented here so tools/ carries no dependency on
## test/ — a model per position, registered with the real army manager so beacon_points()/
## repel_ambush_dist_m() (which read army_manager) see it exactly as the table does.
func _unit(pid: int, name: String, positions: Array, base_mm: int = 32) -> GameUnit:
	var u := GameUnit.new()
	_uid += 1
	u.unit_id = "dump_%d" % _uid
	u.unit_properties = {"player_id": pid, "name": name, "quality": 4, "defense": 4,
		"network_id": u.unit_id, "base_size_round": base_mm}   # round base — separation_checker.gd:275
	for p in positions:
		var m := ModelInstance.new()
		m.is_alive = true
		m.unit = u
		var n := Node3D.new()
		n.name = "%s_m%d" % [name, u.models.size()]
		n.set_meta("game_unit", u)
		_main.add_child(n)
		_spawned.append(n)
		n.global_position = p
		m.node = n
		u.models.append(m)
	_main.opr_army_manager.game_units[u.unit_id] = u
	_units.append(u)
	return u


## _enemy_entries (e2e_ambush_variants_test.gd:74-81), per model, edge-true.
func _enemy_entries(enemy: GameUnit) -> Array:
	var out: Array = []
	for m in enemy.get_alive_models():
		var mi := m as ModelInstance
		out.append({"pos": Vector2(mi.node.global_position.x, mi.node.global_position.z),
			"min_dist_m": SoloController.repel_ambush_dist_m(enemy),
			"pad_m": SoloController.model_base_radius_m(mi)})
	return out


## Run one arrival and record the ARRIVAL gate's case shape (SPEC §4 S4).
func _record(name: String, unit: GameUnit, zone: Rect2, objectives: Array, occupied: Array,
		enemies: Array) -> Dictionary:
	_solo.ambush_reserve = [unit]
	_solo._deploy_objectives = objectives
	var arrived: GameUnit = _solo.arrive_one_ambush_unit(zone, enemies, occupied.duplicate(true), ROUND_NO, [])
	var spot = null
	if arrived == unit:
		var c: Vector3 = _solo.unit_centre(unit)
		spot = [snappedf(c.x, 0.0001), snappedf(c.z, 0.0001)]
	return {
		"case": name,
		"zone": [zone.position.x, zone.position.y, zone.size.x, zone.size.y],
		"objectives": objectives.map(func(o): return [(o as Vector2).x, (o as Vector2).y]),
		"occupied": occupied.map(func(o): return {
			"pos": [((o as Dictionary)["pos"] as Vector2).x, ((o as Dictionary)["pos"] as Vector2).y],
			"radius": float((o as Dictionary)["radius"])}),
		"enemies": enemies.map(func(e): return {
			"pos": [((e as Dictionary)["pos"] as Vector2).x, ((e as Dictionary)["pos"] as Vector2).y],
			"min_dist_m": float((e as Dictionary)["min_dist_m"]),
			"pad_m": float((e as Dictionary)["pad_m"])}),
		"own_ring_m": snappedf(_solo._reserve_min_enemy_dist_m(unit), 0.0001),
		"footprint": _solo._deploy_footprint_offsets(unit).map(
			func(v): return [snappedf((v as Vector2).x, 0.0001), snappedf((v as Vector2).y, 0.0001)]),
		"base_r": snappedf(_solo._deploy_base_radius(_solo._deploy_models(unit)), 0.0001),
		"flying": unit.has_special_rule("Strider") or unit.has_special_rule("Flying"),
		"spot": spot,
	}


# === Cases ======================================================================================

func _case_plain_ambush(zone: Rect2) -> Dictionary:
	var arriver := _unit(2, "Shadows", [Vector3(5.0, 0, 0)])
	arriver.unit_properties["special_rules"] = ["Ambush"]
	arriver.unit_properties["ambush_reserve"] = true
	var enemy := _unit(1, "Watchers", [Vector3(0.05, 0, 0.05)])
	return _record("ambush_single_enemy_centre", arriver, zone, [Vector2(0.3, 0.2)], [], _enemy_entries(enemy))


func _case_infiltrate(zone: Rect2) -> Dictionary:
	var arriver := _unit(2, "Infiltrators", [Vector3(5.1, 0, 0)])
	arriver.unit_properties["special_rules"] = ["Infiltrate"]
	arriver.unit_properties["ambush_reserve"] = true
	var enemy := _unit(1, "Watchers2", [Vector3(0.05, 0, -0.05)])
	return _record("infiltrate_single_enemy_centre", arriver, zone, [Vector2(-0.2, 0.1)], [], _enemy_entries(enemy))


func _case_infiltrate_vs_repel(zone: Rect2) -> Dictionary:
	var arriver := _unit(2, "Infiltrators2", [Vector3(5.2, 0, 0)])
	arriver.unit_properties["special_rules"] = ["Infiltrate"]
	arriver.unit_properties["ambush_reserve"] = true
	var enemy := _unit(1, "Wardens", [Vector3.ZERO])
	enemy.unit_properties["special_rules"] = ["Repel Ambushers"]
	return _record("infiltrate_vs_repel_ambushers", arriver, zone, [Vector2(0.4, -0.3)], [], _enemy_entries(enemy))


func _case_ambush_vs_repel(zone: Rect2) -> Dictionary:
	var arriver := _unit(2, "Shadows2", [Vector3(5.3, 0, 0)])
	arriver.unit_properties["special_rules"] = ["Ambush"]
	arriver.unit_properties["ambush_reserve"] = true
	var enemy := _unit(1, "Wardens2", [Vector3(0.1, 0, 0.1)])
	enemy.unit_properties["special_rules"] = ["Repel Ambushers"]
	return _record("ambush_vs_repel_ambushers", arriver, zone, [Vector2(-0.4, -0.2)], [], _enemy_entries(enemy))


func _case_ambush_two_enemies_mixed(zone: Rect2) -> Dictionary:
	var arriver := _unit(2, "Shadows3", [Vector3(5.4, 0, 0)])
	arriver.unit_properties["special_rules"] = ["Ambush"]
	arriver.unit_properties["ambush_reserve"] = true
	var near := _unit(1, "Line1", [Vector3(0.2, 0, 0.1)])
	var far := _unit(1, "Line2", [Vector3(-0.5, 0, -0.3)])
	far.unit_properties["special_rules"] = ["Repel Ambushers"]
	return _record("ambush_two_enemies_mixed", arriver, zone, [Vector2(0.0, 0.4)], [],
		_enemy_entries(near) + _enemy_entries(far))


func _case_infiltrate_multi_enemy(zone: Rect2) -> Dictionary:
	var arriver := _unit(2, "Infiltrators3", [Vector3(5.5, 0, 0)])
	arriver.unit_properties["special_rules"] = ["Infiltrate"]
	arriver.unit_properties["ambush_reserve"] = true
	var e1 := _unit(1, "Line3", [Vector3(0.15, 0, -0.1)])
	var e2 := _unit(1, "Line4", [Vector3(-0.2, 0, 0.15)])
	return _record("infiltrate_multi_enemy_no_repel", arriver, zone, [Vector2(0.5, 0.5)], [],
		_enemy_entries(e1) + _enemy_entries(e2))


func _case_ambush_pre_occupied(zone: Rect2) -> Dictionary:
	var arriver := _unit(2, "Shadows4", [Vector3(5.6, 0, 0)])
	arriver.unit_properties["special_rules"] = ["Ambush"]
	arriver.unit_properties["ambush_reserve"] = true
	var enemy := _unit(1, "Watchers3", [Vector3.ZERO])
	var occupied := [{"pos": Vector2(0.5, 0.3), "radius": 0.3}]
	return _record("ambush_pre_occupied", arriver, zone, [Vector2(0.5, 0.3)], occupied, _enemy_entries(enemy))


func _case_ambush_wide_footprint(zone: Rect2) -> Dictionary:
	var positions: Array = []
	for i in range(5):
		positions.append(Vector3(5.7 + float(i) * 0.1, 0, 0))
	var arriver := _unit(2, "WideSquad", positions)
	arriver.unit_properties["special_rules"] = ["Ambush"]
	arriver.unit_properties["ambush_reserve"] = true
	var enemy := _unit(1, "Watchers4", [Vector3(0.1, 0, -0.2)])
	return _record("ambush_five_model_wide_footprint", arriver, zone, [Vector2(-0.3, 0.3)], [], _enemy_entries(enemy))


func _case_infiltrate_small_base(zone: Rect2) -> Dictionary:
	var arriver := _unit(2, "SoloScout", [Vector3(5.8, 0, 0)], 25)
	arriver.unit_properties["special_rules"] = ["Infiltrate"]
	arriver.unit_properties["ambush_reserve"] = true
	var enemy := _unit(1, "Watchers5", [Vector3(-0.1, 0, 0.05)])
	return _record("infiltrate_single_model_small_base", arriver, zone, [Vector2(0.2, -0.4)], [], _enemy_entries(enemy))


func _case_ambush_large_base(zone: Rect2) -> Dictionary:
	var arriver := _unit(2, "Behemoth", [Vector3(5.9, 0, 0)], 60)
	arriver.unit_properties["special_rules"] = ["Ambush"]
	arriver.unit_properties["ambush_reserve"] = true
	var enemy := _unit(1, "Watchers6", [Vector3(0.2, 0, 0.2)])
	return _record("ambush_large_base_unit", arriver, zone, [Vector2(-0.5, -0.1)], [], _enemy_entries(enemy))


func _case_ambush_strider(zone: Rect2) -> Dictionary:
	var arriver := _unit(2, "Walkers", [Vector3(6.0, 0, 0)])
	arriver.unit_properties["special_rules"] = ["Ambush", "Strider"]
	arriver.unit_properties["ambush_reserve"] = true
	var enemy := _unit(1, "Watchers7", [Vector3(-0.15, 0, -0.15)])
	return _record("ambush_strider_flag", arriver, zone, [Vector2(0.6, 0.0)], [], _enemy_entries(enemy))


func _case_infiltrate_objective_pull(zone: Rect2) -> Dictionary:
	var arriver := _unit(2, "Infiltrators4", [Vector3(6.1, 0, 0)])
	arriver.unit_properties["special_rules"] = ["Infiltrate"]
	arriver.unit_properties["ambush_reserve"] = true
	var enemy := _unit(1, "Watchers8", [Vector3.ZERO])
	return _record("infiltrate_objective_pull", arriver, zone, [Vector2(0.8, 0.55)], [], _enemy_entries(enemy))


func _case_held_fully_occupied(zone: Rect2) -> Dictionary:
	var arriver := _unit(2, "Trapped1", [Vector3(6.2, 0, 0)])
	arriver.unit_properties["special_rules"] = ["Ambush"]
	arriver.unit_properties["ambush_reserve"] = true
	var enemy := _unit(1, "Watchers9", [Vector3(1.0, 0, 1.0)])   # off the table — the blocker alone must hold the arrival
	var occupied := [{"pos": Vector2.ZERO, "radius": 2.0}]   # > the zone's half-diagonal — covers every cell
	return _record("held_fully_occupied", arriver, zone, [Vector2.ZERO], occupied, _enemy_entries(enemy))


func _case_held_wide_unit_occupied(zone: Rect2) -> Dictionary:
	var positions: Array = []
	for i in range(4):
		positions.append(Vector3(6.3 + float(i) * 0.1, 0, 0))
	var arriver := _unit(2, "Trapped2", positions, 40)
	arriver.unit_properties["special_rules"] = ["Infiltrate"]
	arriver.unit_properties["ambush_reserve"] = true
	var enemy := _unit(1, "Watchers10", [Vector3(1.0, 0, 1.0)])
	var occupied := [{"pos": Vector2.ZERO, "radius": 2.0}]
	return _record("held_wide_unit_occupied", arriver, zone, [Vector2.ZERO], occupied, _enemy_entries(enemy))
