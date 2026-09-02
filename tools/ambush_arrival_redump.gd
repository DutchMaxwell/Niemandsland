extends SceneTree
## Follow-up on PR #580's S4 gate: the twin's real arrival (S1-S3b) scored the 98 corpus cases
## 16/14/69/1 -- the shape of a RECONSTRUCTION error (median gap 0.222 m), not a doctrine gap,
## because ambush_arrival_corpus.py stored the corpus's own POST-arrival CENTROID as "spot" while
## the table's arrive_one_ambush_unit never settles/repairs after the raw compact-grid placement
## (_finish_reserve_arrival -> _place_unit_at, no contact pass). This re-derives every case's
## "spot" the same way the 2 gap cases already were: build ONE arriving GameUnit matching the
## recorded model count / base radius (base_size_round = round(base_r / 0.0005) -- the corpus's
## three base_r values (0.0125/0.016/0.02 m) are exactly 25/32/40 mm at scale 1, so this inverts
## cleanly) and rule (Infiltrate under 0.15 m own_ring else Ambush, + Strider if flying), then call
## the REAL SoloController.arrive_one_ambush_unit with the case's own recorded
## zone/objectives/occupied/enemies. No settle/repair step exists in this path to expose
## separately (checked solo_controller.gd:10118-10123) -- the corpus centroid is kept alongside as
## a cross-check column (`corpus_centroid` + `corpus_centroid_error_m`) instead.
##
## Run: godot --headless --path . -s res://tools/ambush_arrival_redump.gd -- in=<path> out=<path>

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const ROUND_NO := 2

var _in_path := "res://core/nml-core/tests/fixtures/ambush_arrival.json"
var _out_path := "res://core/nml-core/tests/fixtures/ambush_arrival.json"
var _main: Node; var _solo: SoloController; var _units: Array = []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2 and kv[0] == "in": _in_path = kv[1]
		elif kv.size() == 2 and kv[0] == "out": _out_path = kv[1]
	ProjectSettings.set_setting("niemandsland/harness_mode", true); change_scene_to_file("res://scenes/main.tscn"); _drive.call_deferred()


func _v2(a: Array) -> Vector2:
	return Vector2(a[0], a[1])


func _drive() -> void:
	for _i in 40: await process_frame
	_main = current_scene; _main.solo_ai_slots = {2: true}; _main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING; _main._solo_batch = true
	_solo = _main.solo_controller
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_in_path))
	var cases: Array = (data["cases"] as Array).map(func(c): return _redo(c))
	var f := FileAccess.open(_out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"schema": 1, "tool": "ambush_arrival_redump", "cases": cases}, "  ")); f.close()
	var moved := cases.filter(func(c): return float(c.get("corpus_centroid_error_m", -1.0)) > 0.001).size()
	print("AMBUSH_ARRIVAL_REDUMP %d cases (%d moved off the corpus centroid) -> %s" % [cases.size(), moved, _out_path])
	for u in _units:
		for m in (u as GameUnit).models:
			if is_instance_valid((m as ModelInstance).node): (m as ModelInstance).node.free()
		(u as GameUnit).models.clear()
	quit(0)


func _redo(c: Dictionary) -> Dictionary:
	var n: int = (c["footprint"] as Array).size()
	var positions: Array = range(n).map(func(i): return Vector3(20.0 + float(_units.size()) * 0.2 + float(i) * 0.1, 0, 0))
	var unit: GameUnit = E2EBoot.make_unit(_main, 2, str(c["case"]), positions)
	unit.unit_properties["base_size_round"] = int(round(float(c["base_r"]) / 0.0005))
	var rules: Array = [("Infiltrate" if float(c["own_ring_m"]) < 0.15 else "Ambush")]
	if bool(c["flying"]): rules.append("Strider")
	unit.unit_properties["special_rules"] = rules; unit.unit_properties["ambush_reserve"] = true
	_units.append(unit)
	var zone := Rect2(Vector2(c["zone"][0], c["zone"][1]), Vector2(c["zone"][2], c["zone"][3]))
	var objectives: Array = (c["objectives"] as Array).map(func(o): return _v2(o))
	var occupied: Array = (c["occupied"] as Array).map(func(o): return {"pos": _v2(o["pos"]), "radius": float(o["radius"])})
	var enemies: Array = (c["enemies"] as Array).map(func(e): return {"pos": _v2(e["pos"]), "min_dist_m": float(e["min_dist_m"]), "pad_m": float(e["pad_m"])})
	_solo.ambush_reserve = [unit]; _solo._deploy_objectives = objectives
	var arrived: GameUnit = _solo.arrive_one_ambush_unit(zone, enemies, occupied.duplicate(true), ROUND_NO, [])
	var out := c.duplicate(true)
	out["corpus_centroid"] = c["spot"]
	out["corpus_centroid_error_m"] = -1.0
	out["spot"] = null
	if arrived == unit:
		var ctr: Vector3 = _solo.unit_centre(unit)
		out["spot"] = [ctr.x, ctr.z]
		if c["spot"] != null:
			out["corpus_centroid_error_m"] = Vector2(ctr.x, ctr.z).distance_to(_v2(c["spot"]))
	return out
