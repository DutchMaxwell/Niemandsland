extends GdUnitTestSuite
## A FORMED Age of Fantasy: Regiments block must survive a save/load and the host -> guest full-state
## sync. Forming reparents every member model under the RegimentTray, so the object serializer has to
## descend into the tray: the tray itself has no object record (it is rebuilt from the unit's
## "regiment" block), and a model that is not serialized comes back as a null node in an empty tray.
## Both paths run SaveManager.serialize_game_state() / _deserialize_objects().

const MODEL_COUNT := 6
const UNIT_ID := "regiment_unit_1"
const SAVE_PATH := "user://_test_regiment_roundtrip.nml"
const APPROX := Vector3(0.001, 0.001, 0.001)


## One table: a SaveManager + OPRArmyManager sharing a fresh ObjectManager.
func _table() -> Dictionary:
	var save_manager := SaveManager.new()
	var army_manager := OPRArmyManager.new()
	var object_manager := ObjectManager.new()
	add_child(object_manager)
	add_child(army_manager)
	add_child(save_manager)
	auto_free(object_manager)
	auto_free(army_manager)
	auto_free(save_manager)
	army_manager.object_manager = object_manager
	save_manager.army_manager = army_manager
	save_manager.object_manager = object_manager
	return {"save": save_manager, "army": army_manager, "objects": object_manager}


func _regiment_unit() -> GameUnit:
	var unit := GameUnit.new()
	unit.unit_id = UNIT_ID
	unit.source_type = "opr"
	unit.unit_properties = {
		"name": "Test Spearmen", "custom_name": "", "size": MODEL_COUNT, "quality": 4, "defense": 4,
		"cost": 100, "special_rules": [], "base_size_round": 25, "base_is_oval": false,
		"base_width_mm": 25, "base_depth_mm": 25, "player_id": 1, "faction_folder": "",
		"display_suffix": "", "attached_heroes": [], "attached_to": null, "regiment_mode": true,
	}
	for i in range(MODEL_COUNT):
		var m := ModelInstance.new()
		m.unit = unit
		m.model_index = i
		m.wounds_current = 1
		m.wounds_max = 1
		m.is_alive = true
		m.properties = {"weapons": [], "equipment": [], "special_rules": []}
		unit.models.append(m)
	return unit


## Spawn the unit's models loose on `table`, register it, form the regiment, then turn and shift the
## whole block (the models follow their tray rigidly) so a lost facing shows up in the round trip.
func _formed_regiment(table: Dictionary) -> GameUnit:
	var army: OPRArmyManager = table["army"]
	var unit := _regiment_unit()
	for i in range(MODEL_COUNT):
		var node: Node3D = army.create_model_from_properties(unit.unit_properties, 0, "")
		table["objects"].add_child(node)
		node.global_position = Vector3(float(i) * 0.05, 0.0, 0.0)
		node.set_meta("network_id", 7000 + i)
		node.set_meta("game_unit", unit)
		node.set_meta("model_instance", unit.models[i])
		node.set_meta("model_index", i)
		unit.models[i].node = node
	army.game_units[unit.unit_id] = unit
	var regiment := army.form_regiment(unit)
	assert_object(regiment).is_not_null()
	regiment.tray.global_position += Vector3(0.4, 0.0, -0.3)
	regiment.tray.rotation.y = 0.8
	return unit


## The world transforms of the unit's model nodes, by model index.
func _world_transforms(unit: GameUnit) -> Array:
	var result: Array = []
	for m in unit.models:
		result.append(m.node.global_transform)
	return result


func _tray_of(table: Dictionary) -> RegimentTray:
	for child in table["objects"].get_children():
		if child is RegimentTray:
			return child
	return null


func _opr_unit_records(state: Dictionary) -> Array:
	return (state["objects"] as Array).filter(func(o): return o.get("type", "") == "opr_unit")


## Every model of `unit` on the loaded `table` must be a live node in the rebuilt tray, at the
## saved world transform, with no stray duplicate left loose or doubled in the subtree.
func _assert_regiment_restored(table: Dictionary, expected: Array, unit_id: String) -> void:
	var loaded: GameUnit = table["army"].game_units.get(unit_id)
	assert_object(loaded).override_failure_message("unit %s was not restored at all" % unit_id).is_not_null()
	var tray := _tray_of(table)
	assert_object(tray).override_failure_message("no RegimentTray on the loaded table").is_not_null()
	if loaded == null or tray == null:
		return
	assert_int(loaded.models.size()).is_equal(MODEL_COUNT)
	for i in range(MODEL_COUNT):
		var node: Node3D = loaded.models[i].node
		assert_bool(is_instance_valid(node)).override_failure_message("model %d has no node after load" % i).is_true()
		if not is_instance_valid(node):
			continue
		assert_object(node.get_parent()).override_failure_message("model %d is not under the tray" % i).is_equal(tray)
		assert_bool(node.is_in_group("opr_unit")).is_true()
		var want: Transform3D = expected[i]
		assert_vector(node.global_position).is_equal_approx(want.origin, APPROX)
		# A dead member is hidden, and revive re-lays the block out (rotation reset), so only the
		# facing of the living ones is part of the contract.
		if loaded.models[i].is_alive:
			assert_vector(node.global_transform.basis.z).is_equal_approx(want.basis.z, APPROX)
	var in_tree := 0
	for n in table["objects"].find_children("*", "StaticBody3D", true, false):
		if n.is_in_group("opr_unit"):
			in_tree += 1
	assert_int(in_tree).override_failure_message("model nodes in the loaded table").is_equal(MODEL_COUNT)


func test_serialized_objects_include_every_regiment_model() -> void:
	var src := _table()
	var unit := _formed_regiment(src)
	var records := _opr_unit_records(src["save"].serialize_game_state())

	assert_int(records.size()).is_equal(MODEL_COUNT)
	var indices: Array = records.map(func(o): return int(o["model_index"]))
	indices.sort()
	assert_array(indices).is_equal(range(MODEL_COUNT))
	for r in records:
		assert_str(r["game_unit_id"]).is_equal(unit.unit_id)


func test_saved_regiment_loads_with_every_model() -> void:
	var src := _table()
	var unit := _formed_regiment(src)
	var expected := _world_transforms(unit)
	assert_int(src["save"].save_state_to_file(src["save"].serialize_game_state(), SAVE_PATH)).is_equal(OK)

	var dst := _table()
	var err: int = await dst["save"].load_game(SAVE_PATH)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))

	assert_int(err).is_equal(OK)
	_assert_regiment_restored(dst, expected, unit.unit_id)


func test_full_state_sync_delivers_every_regiment_model() -> void:
	var host := _table()
	var unit := _formed_regiment(host)
	var expected := _world_transforms(unit)
	# The host -> guest push is serialize_game_state() sent as a Dictionary; the guest replays the
	# same deserialize sequence as main.gd::_rpc_sync_game_state.
	var state: Dictionary = host["save"].serialize_game_state()

	var guest := _table()
	var guest_save: SaveManager = guest["save"]
	guest_save._deserialize_game_units(state["game_units"])
	await guest_save._deserialize_objects(state["objects"])
	guest_save._restore_regiments_after_load()

	_assert_regiment_restored(guest, expected, unit.unit_id)


func test_wounded_regiment_keeps_its_dead_models_and_gaps() -> void:
	var src := _table()
	var unit := _formed_regiment(src)
	src["army"].apply_regiment_wounds(src["army"].regiments[unit.unit_id], 2)
	var expected := _world_transforms(unit)
	var state: Dictionary = src["save"].serialize_game_state()

	var dst := _table()
	var dst_save: SaveManager = dst["save"]
	dst_save._deserialize_game_units(state["game_units"])
	await dst_save._deserialize_objects(state["objects"])
	dst_save._restore_regiments_after_load()

	_assert_regiment_restored(dst, expected, unit.unit_id)
	var loaded: GameUnit = dst["army"].game_units.get(unit.unit_id)
	if loaded == null:
		return
	assert_int(loaded.get_alive_models().size()).is_equal(MODEL_COUNT - 2)
	for i in range(MODEL_COUNT):
		if is_instance_valid(loaded.models[i].node):
			assert_bool(loaded.models[i].node.visible).is_equal(loaded.models[i].is_alive)
