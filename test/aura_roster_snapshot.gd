extends RefCounted
## Test helper: offline production import, hero attachment and aura expansion.


static func capture(parent: Node, path: String) -> Dictionary:
	var dir := DirAccess.open(path)
	if dir == null:
		return {}
	var client := OPRApiClient.new()
	var files := dir.get_files()
	files.sort()
	var rows: Array = []
	var total_units := 0
	for file in files:
		if not file.ends_with(".json") or file.begins_with("_"):
			continue
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path.path_join(file)))
		if not data is Dictionary:
			client.free()
			return {}
		var army := client.build_army_offline(data)
		if army == null or army.units.is_empty():
			client.free()
			return {}
		var by_unit := {}
		var nodes: Array[Node3D] = []
		for unit in army.units:
			var models: Array[Node3D] = []
			for index in range(maxi(unit.size, 1)):
				var node := Node3D.new()
				parent.add_child(node)
				models.append(node)
				nodes.append(node)
			by_unit[unit] = EquipmentDistributor.create_from_opr_unit(unit, models, 1)
		OPRArmyManager.attach_joined_heroes_of(army.units, by_unit)
		OPRArmyManager.expand_auras_of(army.units, by_unit)
		var units: Array = []
		for unit in army.units:
			var game_unit: GameUnit = by_unit[unit]
			var rules := PackedStringArray(game_unit.get_special_rules())
			rules.sort()
			var grants := PackedStringArray(game_unit.unit_properties.get("aura_granted", []))
			grants.sort()
			units.append({"selection": unit.selection_id, "rules": rules, "aura_granted": grants})
			total_units += 1
		rows.append({"roster": file, "units": units, "sha256": JSON.stringify(units).sha256_text()})
		for node in nodes:
			node.free()
	client.free()
	return {"lists": rows.size(), "units": total_units, "sha256": JSON.stringify(rows).sha256_text()}
