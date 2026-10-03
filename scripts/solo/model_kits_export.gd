class_name ModelKitsExport
## Tray-exact S3-1 (variant b, lead GO 03.10.): the TABLE's own per-model loadout for an
## Army-Forge list, so the trainer reads it instead of porting EquipmentDistributor — exact by
## construction. The import is the four calls OPRArmyManager.spawn_army makes, the same ones
## tools/core_selfplay.gd makes (OPRApiClient.build_army_offline, EquipmentDistributor.
## create_from_opr_unit, attach_joined_heroes_of, expand_auras_of); each model's kit is
## BattleSim._model_kit, the very read BattleSim.capture writes (#1446).
## Keys "<index>_<list id>": the import's deterministic unit id without the seat prefix
## (core_selfplay.gd "p<player>_<index>_<id>"); selfplay.kits_sidecar maps them back per seat.

const FORMAT := "nml-kits-v1"


## {"format", "units": {"<index>_<id>": [kit per model, model order]}}, or {} when the list does
## not import. Model nodes are bare Node3Ds parented under `parent`; the caller frees it.
static func kits_of_list(data: Dictionary, parent: Node) -> Dictionary:
	var client := OPRApiClient.new()
	var army: OPRApiClient.OPRArmy = client.build_army_offline(data)
	client.free()
	if army == null:
		return {}
	var by_unit := {}
	var order: Array = []
	for ou: OPRApiClient.OPRUnit in army.units:
		var nodes: Array[Node3D] = []
		for _m in range(maxi(ou.size, 1)):
			var n := Node3D.new()
			parent.add_child(n)
			nodes.append(n)
		var gu := EquipmentDistributor.create_from_opr_unit(ou, nodes, 1)
		by_unit[ou] = gu
		order.append([ou, gu])
	OPRArmyManager.attach_joined_heroes_of(army.units, by_unit)
	OPRArmyManager.expand_auras_of(army.units, by_unit)
	var units := {}
	for i in range(order.size()):
		var kits: Array = []
		for m in (order[i][1] as GameUnit).models:
			kits.append(BattleSim._model_kit(m as ModelInstance))
		units["%d_%s" % [i, str((order[i][0] as OPRApiClient.OPRUnit).id)]] = kits
	return {"format": FORMAT, "units": units}
