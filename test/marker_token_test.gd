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


func test_counter_marker_renders_number_label() -> void:
	# A counter marker (value stored on the model) renders a NumberLabel showing
	# the value, not a letter label.
	var controller := _controller()
	var model := _model_in_unit()
	model.add_marker("Havoc")
	model.set_marker_value("Havoc", 3)

	controller._render_marker_token(model, model.unit, "Havoc", Color.RED, true)

	var token = model.node.get_node_or_null(controller._marker_token_name("Havoc"))
	assert_object(token).is_not_null()
	var number := token.get_node_or_null("NumberLabel") as Label3D
	assert_object(number).is_not_null()
	assert_str(number.text).is_equal("3")
	assert_object(token.get_node_or_null("LetterLabel")).is_null()


func test_counter_value_change_updates_number_label() -> void:
	var controller := _controller()
	var model := _model_in_unit()
	model.add_marker("Havoc")
	model.set_marker_value("Havoc", 1)
	controller._render_marker_token(model, model.unit, "Havoc", Color.RED, true)

	# Player increments the counter
	model.set_marker_value("Havoc", 2)
	controller._render_marker_token(model, model.unit, "Havoc", Color.RED, true)

	var token = model.node.get_node_or_null(controller._marker_token_name("Havoc"))
	var number := token.get_node_or_null("NumberLabel") as Label3D
	assert_str(number.text).is_equal("2")


func _multi_model_unit(count: int) -> GameUnit:
	var unit := GameUnit.new()
	unit.unit_id = "u_multi"
	unit.unit_properties = {"base_size_round": 32}
	for i in range(count):
		var node: Node3D = auto_free(Node3D.new())
		add_child(node)
		var m := ModelInstance.new()
		m.node = node
		m.model_index = i
		m.unit = unit
		unit.models.append(m)
	return unit


func test_unit_wide_token_renders_once_not_per_model() -> void:
	# A token on EVERY model is unit-wide -> one token on the unit node (like the
	# activation/shaken tokens), not one disc per model.
	var controller := _controller()
	var unit := _multi_model_unit(3)
	for m in unit.models:
		m.add_marker("Havoc")

	controller._render_token_for_unit_scoped(unit, "Havoc")

	var node_name := controller._marker_token_name("Havoc")
	# Without a boundary visualizer the unit node is the first model's node.
	assert_object(unit.models[0].node.get_node_or_null(node_name)).is_not_null()
	assert_object(unit.models[1].node.get_node_or_null(node_name)).is_null()
	assert_object(unit.models[2].node.get_node_or_null(node_name)).is_null()


func test_partial_token_renders_per_model() -> void:
	var controller := _controller()
	var unit := _multi_model_unit(3)
	unit.models[1].add_marker("Mark")  # only one model carries it

	controller._render_token_for_unit_scoped(unit, "Mark")

	var node_name := controller._marker_token_name("Mark")
	assert_object(unit.models[0].node.get_node_or_null(node_name)).is_null()
	assert_object(unit.models[1].node.get_node_or_null(node_name)).is_not_null()
	assert_object(unit.models[2].node.get_node_or_null(node_name)).is_null()


func test_dialog_marker_shows_name_curved_on_rim() -> void:
	# The token name is written small around the rim (like "ACTIVATED" on the
	# activation token), laid out as per-character TokenChar nodes.
	var controller := _controller()
	var model := _model_in_unit()
	controller._render_marker_token(model, model.unit, "+1 to hit", Color.RED, true)

	var token = model.node.get_node_or_null(controller._marker_token_name("+1 to hit"))
	var reconstructed := ""
	var i := 0
	while true:
		var ch = token.get_node_or_null("TokenChar%d" % i) as Label3D
		if not ch:
			break
		reconstructed += ch.text
		i += 1
	assert_str(reconstructed).is_equal("+1 to hit")


func test_library_color_takes_precedence_over_model_color() -> void:
	var controller := _controller()
	var model := _model_in_unit()
	controller.token_library.define("Havoc", Color.RED, false, "")
	model.marker_colors["Havoc"] = Color.BLUE  # stale per-model color

	var color := controller._resolve_marker_color("Havoc", model)
	assert_float(color.r).is_equal_approx(1.0, 0.01)
	assert_float(color.b).is_equal_approx(0.0, 0.01)


func test_edit_renames_token_across_all_instances() -> void:
	var controller := _controller()
	var am: OPRArmyManager = auto_free(OPRArmyManager.new())
	controller.army_manager = am

	var unit := GameUnit.new()
	unit.unit_id = "u1"
	unit.unit_properties = {"base_size_round": 32}
	for i in range(2):
		var node: Node3D = auto_free(Node3D.new())
		add_child(node)
		var m := ModelInstance.new()
		m.node = node
		m.model_index = i
		m.unit = unit
		unit.models.append(m)
	am.game_units["u1"] = unit

	controller.token_library.define("Havoc", Color.RED, true, "old effect")
	for m in unit.models:
		m.add_marker("Havoc")
		m.set_marker_value("Havoc", 2)
		controller._render_marker_token(m, unit, "Havoc", Color.RED, true)

	# Rename + recolor + new effect, applied to every instance
	controller.apply_token_edit("Havoc", "Surge", Color(0.1, 0.8, 0.1), "new effect", false)

	for m in unit.models:
		assert_bool(m.has_marker("Surge")).is_true()
		assert_bool(m.has_marker("Havoc")).is_false()
		assert_int(m.get_marker_value("Surge")).is_equal(2)

	assert_bool(controller.token_library.has("Surge")).is_true()
	assert_bool(controller.token_library.has("Havoc")).is_false()
	assert_str(controller.token_library.get_effect("Surge")).is_equal("new effect")

	# Token node was renamed (old removed, new present)
	var old_node := controller._marker_token_name("Havoc")
	var new_node := controller._marker_token_name("Surge")
	assert_object(unit.models[0].node.get_node_or_null(new_node)).is_not_null()
	assert_object(unit.models[0].node.get_node_or_null(old_node)).is_null()
