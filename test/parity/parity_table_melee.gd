extends RefCounted
## Table half of the table-vs-core parity gate (melee lane). Per seed: builds the attacker at its post-move position
## (base contact) and the defender (units, weapons and the dice reader come from parity_table.gd), runs main's real
## _run_ai_melee (charge, strikes, strike-back, morale) and writes one JSONL record per seed:
## {"seed","epoch","def_alive","rolls":[{kind,count,target,faces,owner}]}. Both seats are AI-owned (a human seat would
## wait for a save click). `override` replaces table-side rules only (red test): {"weapon_rules": [...],
## "defender_weapon": {field: value}, "per_model_loadout": false (no per-model weapons: the runner before the loadout fix)}.
## Pattern: tools/table_scenario_sweep.gd, test/v36/mel_03_test.gd.

const ParityTable := preload("res://test/parity/parity_table.gd")
const INCH := 0.0254


static func _units(main: Node, sc: Dictionary, override: Dictionary) -> Array:
	var weapon: Dictionary = (sc["weapon"] as Dictionary).duplicate()
	if override.has("weapon_rules"):
		weapon["rules"] = override["weapon_rules"]
	var post: Dictionary = (sc["attacker"] as Dictionary).duplicate()
	post["x_in"] = float(sc["charge"]["dest_x_in"])   # the table's melee path starts after the move
	var def_weapon: Dictionary = (sc["defender_weapon"] as Dictionary).duplicate()
	def_weapon.merge(override.get("defender_weapon", {}), true)
	var out: Array = [ParityTable._make_unit(main, post, weapon), ParityTable._make_unit(main, sc["defender"], def_weapon)]
	if override.get("per_model_loadout", true):
		_equip(out[0], weapon)
		_equip(out[1], def_weapon)
	for i in 2:
		var side: Dictionary = sc["attacker"] if i == 0 else sc["defender"]
		(out[i] as GameUnit).unit_properties["base_size_round"] = roundi(float(side["base_radius_in"]) * 50.8)
	return out


## The per-model loadout EquipmentDistributor writes for a real unit: the first `count` models carry the weapon (a count
## below the model count is a special weapon pinned to specific models), the rest carry none. Without it the table
## scales a strike-back by alive/max while the core counts living bearers, and a unit that lost non-bearers differs.
static func _equip(g: GameUnit, w: Dictionary) -> void:
	for k in mini(int(w["count"]), g.models.size()):
		(g.models[k] as ModelInstance).properties["weapons"] = [{"name": str(w["name"]), "range": int(w["range_in"]),
			"attacks": int(w["attacks"]), "count": int(w["count"]), "specialRules": (w["rules"] as Array).duplicate()}]


## Charge distance both engines read: nearest model pair before the move, base edge to base edge, inches.
static func _charge_from_in(sc: Dictionary) -> float:
	var best := INF
	for a in ParityTable._positions(sc["attacker"]):
		for b in ParityTable._positions(sc["defender"]):
			best = minf(best, (a as Vector3).distance_to(b) / INCH)
	return best - 2.0 * float(sc["attacker"]["base_radius_in"])


## Runs `seeds` seeds of the melee scenario `sc` on the booted `main`; writes the JSONL to `out_path`. Await it.
static func run(main: Node, sc: Dictionary, seeds: int, out_path: String, dump_dir: String,
		override: Dictionary = {}) -> void:
	AiActRecorder.rules_epoch = int(sc["epoch"])
	DirAccess.make_dir_recursive_absolute(dump_dir)
	OS.set_environment("NML_DICE_DUMP", dump_dir)
	AiDiceRecorder._checked = false
	AiDiceRecorder._stream = null
	AiDiceRecorder._count = 0
	var from_in := _charge_from_in(sc)
	var out := FileAccess.open(out_path, FileAccess.WRITE)
	for s in seeds:
		var pair := _units(main, sc, override)
		var att := pair[0] as GameUnit
		var dfn := pair[1] as GameUnit
		main.seed_tray_rng(s)
		await main._run_ai_melee({"unit": att, "target": dfn, "charge_from_in": from_in})
		AiDiceRecorder.close()
		out.store_line(JSON.stringify({"seed": s, "epoch": AiActRecorder.rules_epoch,
			"def_alive": dfn.get_alive_count(), "rolls": ParityTable._read_dice(dump_dir)}, "", true, true))
		for u in pair:
			main.opr_army_manager.game_units.erase((u as GameUnit).unit_id)
			for m in (u as GameUnit).models:
				var nd: Node = (m as ModelInstance).node
				if nd != null and is_instance_valid(nd):
					nd.free()
		await main.get_tree().process_frame
	out.close()
