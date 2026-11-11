extends RefCounted
## Table half of the table-vs-core parity gate (shoot lane). Builds the two units of a neutral scenario
## (schema nml-scenario-v1, inches), runs one AI volley per seed through main's real _solo_resolve_ai_volley and
## writes one JSONL record per seed: {"seed","epoch","def_alive","rolls":[{kind,count,target,faces,owner}]}.
## The faces are the ones the table's own dice recorder (NML_DICE_DUMP) wrote for that seed.
## (run() follows in the next PR of the stack.)
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
