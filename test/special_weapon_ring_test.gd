extends GdUnitTestSuite
## Tests special-equipment detection (minority weapons/equipment) and the
## segmented base-ring rendering (one labelled segment per special item).

const RadialControllerScript = preload("res://scripts/radial_menu_controller.gd")


func _unit_with_weapons(weapons_per_model: Array) -> GameUnit:
	# weapons_per_model[i] = Array of weapon-name Strings for model i.
	var unit := GameUnit.new()
	unit.unit_properties = {"base_size_round": 32}
	for i in range(weapons_per_model.size()):
		var model := ModelInstance.new()
		model.model_index = i
		model.unit = unit
		var weapons: Array = []
		for wname in weapons_per_model[i]:
			weapons.append({"name": wname, "attacks": 1})
		model.properties["weapons"] = weapons
		unit.models.append(model)
	return unit


func _add_nodes(unit: GameUnit) -> void:
	for model in unit.models:
		var node: Node3D = auto_free(Node3D.new())
		add_child(node)
		model.node = node


func test_detects_single_special_weapon() -> void:
	var unit := _unit_with_weapons([["Rifle", "Plasma"], ["Rifle"], ["Rifle"]])
	assert_array(unit.get_special_equipment_names(unit.models[0])).contains_exactly(["Plasma"])
	assert_array(unit.get_special_equipment_names(unit.models[1])).is_empty()


func test_detects_multiple_special_items_in_order() -> void:
	var unit := _unit_with_weapons([["Rifle", "Shredding Gun", "Gauntlets"], ["Rifle"], ["Rifle"]])
	assert_array(unit.get_special_equipment_names(unit.models[0])).contains_exactly(["Shredding Gun", "Gauntlets"])


func test_shared_weapons_are_not_special() -> void:
	var unit := _unit_with_weapons([["Rifle"], ["Rifle"], ["Rifle"]])
	assert_array(unit.get_special_equipment_names(unit.models[0])).is_empty()


func test_single_model_unit_has_no_special() -> void:
	var unit := _unit_with_weapons([["Rifle", "Plasma"]])
	assert_array(unit.get_special_equipment_names(unit.models[0])).is_empty()


func test_base_weapon_reduced_by_swap_is_not_special() -> void:
	# 9 of 10 carry Rifle (majority base), 1 carries Flamer. The Rifle must NOT be
	# flagged just because a swap reduced its count; only the Flamer is special.
	var per_model: Array = []
	for i in range(9):
		per_model.append(["Rifle"])
	per_model.append(["Flamer"])
	var unit := _unit_with_weapons(per_model)
	assert_array(unit.get_special_equipment_names(unit.models[0])).is_empty()
	assert_array(unit.get_special_equipment_names(unit.models[9])).contains_exactly(["Flamer"])


func test_minority_equipment_is_special() -> void:
	var unit := _unit_with_weapons([["Rifle"], ["Rifle"], ["Rifle"]])
	unit.models[0].properties["equipment"] = ["Banner"]
	assert_array(unit.get_special_equipment_names(unit.models[0])).contains_exactly(["Banner"])
	assert_array(unit.get_special_equipment_names(unit.models[1])).is_empty()


func test_ring_has_one_segment_per_special_item() -> void:
	var controller = auto_free(RadialControllerScript.new())
	var unit := _unit_with_weapons([["Rifle", "Shredding Gun", "Gauntlets"], ["Rifle"], ["Rifle"]])
	_add_nodes(unit)

	controller._render_special_weapon_ring(unit.models[0])

	var ring = unit.models[0].node.get_node_or_null(RadialControllerScript.SPECIAL_WEAPON_RING_NODE)
	assert_object(ring).is_not_null()
	var seg_items: Array = []
	for child in ring.get_children():
		if child.name.begins_with("RingSegment"):
			seg_items.append(child.get_meta("item"))
	assert_array(seg_items).contains_exactly(["Shredding Gun", "Gauntlets"])


func test_no_ring_for_model_without_special() -> void:
	var controller = auto_free(RadialControllerScript.new())
	var unit := _unit_with_weapons([["Rifle", "Plasma"], ["Rifle"], ["Rifle"]])
	_add_nodes(unit)

	controller._render_special_weapon_ring(unit.models[1])  # only carries Rifle
	assert_object(unit.models[1].node.get_node_or_null(RadialControllerScript.SPECIAL_WEAPON_RING_NODE)).is_null()


func test_rerender_replaces_stale_ring() -> void:
	var controller = auto_free(RadialControllerScript.new())
	var unit := _unit_with_weapons([["Rifle", "Plasma"], ["Rifle"], ["Rifle"]])
	_add_nodes(unit)

	controller._render_special_weapon_ring(unit.models[0])
	controller._render_special_weapon_ring(unit.models[0])

	var rings := 0
	for child in unit.models[0].node.get_children():
		if child.name == RadialControllerScript.SPECIAL_WEAPON_RING_NODE:
			rings += 1
	assert_int(rings).is_equal(1)
