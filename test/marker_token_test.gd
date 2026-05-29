extends GdUnitTestSuite
## End-to-end test: dialog markers render as orbit tokens via the unified token
## engine (RadialMenuController), carrying the marker's color, and are removed
## cleanly. Reuses the same _update_token path as the built-in status tokens.


func _controller() -> RadialMenuController:
	# Not added to the tree, so _ready() (radial menu scene load) is skipped;
	# the marker-token methods don't need it.
	return auto_free(RadialMenuController.new())


func _model_in_unit() -> ModelInstance:
	var node: Node3D = auto_free(Node3D.new())
	add_child(node)  # token tween creation needs the node in the tree
	var unit := GameUnit.new()
	unit.unit_properties = {"base_size_round": 32}
	var model := ModelInstance.new()
	model.node = node
	model.unit = unit
	unit.models.append(model)
	return model


func test_dialog_marker_renders_token_with_its_color() -> void:
	var controller := _controller()
	var model := _model_in_unit()

	controller._render_marker_token(model, model.unit, "Pinned", Color(0.2, 0.5, 0.9), true)

	var token = model.node.get_node_or_null(controller._marker_token_name("Pinned"))
	assert_object(token).is_not_null()
	var disc = token.get_node_or_null("Disc") as MeshInstance3D
	assert_object(disc).is_not_null()
	var material = disc.material_override as StandardMaterial3D
	assert_float(material.albedo_color.b).is_equal_approx(0.9, 0.01)


func test_dialog_marker_removed_cleanly() -> void:
	var controller := _controller()
	var model := _model_in_unit()

	var token_name := controller._marker_token_name("Pinned")
	controller._render_marker_token(model, model.unit, "Pinned", Color.RED, true)
	assert_object(model.node.get_node_or_null(token_name)).is_not_null()

	controller._render_marker_token(model, model.unit, "Pinned", Color.RED, false)
	assert_object(model.node.get_node_or_null(token_name)).is_null()


func test_special_char_marker_creates_single_valid_token() -> void:
	var controller := _controller()
	# A name with characters illegal in node names must still produce one valid token.
	var model := _model_in_unit()
	controller._render_marker_token(model, model.unit, "On fire!", Color.ORANGE, true)
	var dlg_tokens := 0
	for child in model.node.get_children():
		if child.name.begins_with("DlgMarker_"):
			dlg_tokens += 1
	assert_int(dlg_tokens).is_equal(1)


func test_distinct_marker_texts_get_distinct_tokens() -> void:
	# Regression: under validate_node_name() "Aura: Fear" and "Aura/Fear" both
	# collapsed to one node; the hash-based name must keep them separate.
	var controller := _controller()
	var model := _model_in_unit()
	controller._render_marker_token(model, model.unit, "Aura: Fear", Color.RED, true)
	controller._render_marker_token(model, model.unit, "Aura/Fear", Color.BLUE, true)

	var dlg_tokens := 0
	for child in model.node.get_children():
		if child.name.begins_with("DlgMarker_"):
			dlg_tokens += 1
	assert_int(dlg_tokens).is_equal(2)


func test_readding_marker_recolors_disc() -> void:
	var controller := _controller()
	var model := _model_in_unit()
	controller._render_marker_token(model, model.unit, "Buff", Color(0.1, 0.1, 0.1), true)
	controller._render_marker_token(model, model.unit, "Buff", Color(0.9, 0.1, 0.1), true)

	var token = model.node.get_node_or_null(controller._marker_token_name("Buff"))
	var disc = token.get_node_or_null("Disc") as MeshInstance3D
	var material = disc.material_override as StandardMaterial3D
	assert_float(material.albedo_color.r).is_equal_approx(0.9, 0.01)
