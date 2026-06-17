extends GdUnitTestSuite
## Pure tests for RadialMenu's context-menu construction — the per-object-type item
## sets that radial_menu_controller dispatches on. The builders are static and pure;
## the interactive draw/hover/select wheel needs a rendered Control and stays manual.

# RadialMenuItem is an inner class of RadialMenu.


func _ids(items: Array) -> Array:
	var out: Array = []
	for it in items:
		out.append(it.id)
	return out


# ===== terrain menu =====

func test_terrain_menu_is_just_delete() -> void:
	var items := RadialMenu.create_terrain_menu()
	assert_int(items.size()).is_equal(1)
	assert_str(items[0].id).is_equal("delete_terrain")
	assert_str(items[0].label).is_equal("Delete")


# ===== unit menu =====

func test_unit_menu_core_items() -> void:
	var unit := GameUnit.new()
	var ids := _ids(RadialMenu.create_unit_menu(unit))
	assert_bool(ids.has("toggle_activate")).is_true()
	assert_bool(ids.has("toggle_fatigued")).is_true()
	assert_bool(ids.has("toggle_shaken")).is_true()
	assert_bool(ids.has("add_marker")).is_true()
	assert_bool(ids.has("delete_unit")).is_true()
	# A plain (non-caster) unit shows no caster-points entry.
	assert_bool(ids.has("casts")).is_false()


# ===== model menu =====

func test_model_menu_tough_model_shows_wounds() -> void:
	var m := ModelInstance.new()
	m.wounds_max = 3
	m.wounds_current = 2
	# No owning GameUnit -> no unit-wide activate/fatigue/shaken entries.
	var ids := _ids(RadialMenu.create_model_menu(m))
	assert_bool(ids.has("wounds")).is_true()
	assert_bool(ids.has("add_marker")).is_true()
	assert_bool(ids.has("select_unit")).is_true()
	assert_bool(ids.has("delete_model")).is_true()
	assert_bool(ids.has("toggle_activate")).is_false()


func test_model_menu_single_wound_hides_wounds() -> void:
	var m := ModelInstance.new()
	m.wounds_max = 1
	m.wounds_current = 1
	var ids := _ids(RadialMenu.create_model_menu(m))
	assert_bool(ids.has("wounds")).is_false()
	assert_bool(ids.has("delete_model")).is_true()


# ===== RadialMenuItem =====

func test_menu_item_tooltip_defaults_to_label() -> void:
	var item := RadialMenu.RadialMenuItem.new("x", "My Label")
	assert_str(item.tooltip).is_equal("My Label")
	assert_bool(item.enabled).is_true()
