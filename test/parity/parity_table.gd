extends RefCounted
## Table half of the table-vs-core parity gate (shoot lane). Builds the two units of a neutral scenario
## (schema nml-scenario-v1, inches), runs one AI volley per seed through main's real _solo_resolve_ai_volley and
## writes one JSONL record per seed: {"seed","epoch","def_alive","rolls":[{kind,count,target,faces,owner}]}.
## The faces are the ones the table's own dice recorder (NML_DICE_DUMP) wrote for that seed.
## `override` replaces table-side rules only (red test): {"weapon_rules": [...]}.
## Pattern: tools/table_scenario_sweep.gd, test/v36/g4r3_extra_attack_signer_test.gd.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254


static func _positions(u: Dictionary) -> Array:
	var out: Array = []
	for i in int(u["models"]):
		out.append(Vector3(float(u["x_in"]) * INCH, 0.0, float(u["z_step_in"]) * INCH * i))
	return out


static func _make_unit(main: Node, u: Dictionary, weapon: Dictionary) -> GameUnit:
	var g := E2EBoot.make_unit(main, int(u["player"]), str(u["name"]), _positions(u))
	var rules: Array = (u["rules"] as Array).duplicate()
	if int(u["tough"]) > 1:
		rules.append("Tough(%d)" % int(u["tough"]))
	g.unit_properties["quality"] = int(u["quality"])
	g.unit_properties["defense"] = int(u["defense"])
	g.unit_properties["game_system"] = str(u["game_system"])
	g.unit_properties["faction_folder"] = str(u["faction_folder"])
	g.unit_properties["special_rules"] = rules
	for m in g.models:
		(m as ModelInstance).wounds_max = int(u["tough"])
		(m as ModelInstance).wounds_current = int(u["tough"])
		(m as ModelInstance).properties["special_rules"] = rules
	if not weapon.is_empty():
		var w := OPRApiClient.OPRWeapon.new()
		w.name = str(weapon["name"])
		w.range_value = int(weapon["range_in"])
		w.attacks = int(weapon["attacks"])
		w.count = int(weapon["count"])
		w.special_rules.assign(weapon["rules"])
		var src := OPRApiClient.OPRUnit.new()
		src.weapons.assign([w])
		g.source_type = "opr"
		g.source_data = src
	main.opr_army_manager.game_units[g.unit_id] = g
	return g


## The dice file of ONE seed, parsed and deleted (the next seed must never read it).
static func _read_dice(dump_dir: String) -> Array:
	var rolls: Array = []
	var path := dump_dir.path_join("dice.jsonl")
	if not FileAccess.file_exists(path):
		return rolls
	for line in FileAccess.get_file_as_string(path).split("\n", false):
		var r := JSON.parse_string(line) as Dictionary
		var faces: Array = []
		for x in r["faces"]:
			faces.append(int(x))
		rolls.append({"kind": str(r["roll_kind"]), "count": int(r["count"]), "target": int(r["target"]),
			"faces": faces, "owner": str(r["owner"])})
	DirAccess.remove_absolute(path)
	return rolls


## Runs `seeds` seeds of scenario `sc` on the booted `main`; writes the JSONL to `out_path`. Await it.
static func run(main: Node, sc: Dictionary, seeds: int, out_path: String, dump_dir: String,
		override: Dictionary = {}) -> void:
	AiActRecorder.rules_epoch = int(sc["epoch"])
	DirAccess.make_dir_recursive_absolute(dump_dir)
	OS.set_environment("NML_DICE_DUMP", dump_dir)
	AiDiceRecorder._checked = false
	AiDiceRecorder._stream = null
	AiDiceRecorder._count = 0
	var weapon: Dictionary = (sc["weapon"] as Dictionary).duplicate()
	if override.has("weapon_rules"):
		weapon["rules"] = override["weapon_rules"]
	var dist_in := INF
	for a in _positions(sc["attacker"]):
		for b in _positions(sc["defender"]):
			dist_in = minf(dist_in, (a as Vector3).distance_to(b) / INCH)
	var out := FileAccess.open(out_path, FileAccess.WRITE)
	for s in seeds:
		var att := _make_unit(main, sc["attacker"], weapon)
		var dfn := _make_unit(main, sc["defender"], {})
		var wobj: OPRApiClient.OPRWeapon = (att.source_data as OPRApiClient.OPRUnit).weapons[0]
		var shots: Array = []
		var plist: Array = AiShooting.profiles_in_range([wobj], dist_in)
		for p in plist:   # the game's own order (_run_ai_shooting): unit-level Shred stamp, then the sergeant stamp
			main._solo_stamp_unit_shred(p, att, int(weapon["range_in"]))
		for p in AiEv.stamp_sergeant(plist, att):
			shots.append({"member": att, "quality": int(sc["attacker"]["quality"]), "alive": att.get_alive_count(),
				"max": att.models.size(), "reach": float(weapon["range_in"]), "profile": p})
		main.seed_tray_rng(s)
		await main._solo_resolve_ai_volley(att, dfn, shots)
		AiDiceRecorder.close()
		out.store_line(JSON.stringify({"seed": s, "epoch": AiActRecorder.rules_epoch,
			"def_alive": dfn.get_alive_count(), "rolls": _read_dice(dump_dir)}, "", true, true))
		for u in [att, dfn]:
			main.opr_army_manager.game_units.erase((u as GameUnit).unit_id)
			for m in (u as GameUnit).models:
				var nd: Node = (m as ModelInstance).node
				if nd != null and is_instance_valid(nd):
					nd.free()
		await main.get_tree().process_frame
	out.close()
