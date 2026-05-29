extends GdUnitTestSuite
## Tests for UnitUtils - object/unit detection and GameUnit lookups via groups
## and node metadata.


# ===== Helpers =====

func _node(groups: Array) -> Node3D:
	var node: Node3D = auto_free(Node3D.new())
	add_child(node)
	for group in groups:
		node.add_to_group(group)
	return node


# ===== Type detection =====

func test_is_unit_detects_groups() -> void:
	assert_bool(UnitUtils.is_unit(_node(["opr_unit"]))).is_true()
	assert_bool(UnitUtils.is_unit(_node(["wgs_unit"]))).is_true()
	assert_bool(UnitUtils.is_unit(_node(["terrain"]))).is_false()
	assert_bool(UnitUtils.is_unit(null)).is_false()


func test_get_unit_type() -> void:
	assert_int(UnitUtils.get_unit_type(_node(["opr_unit"]))).is_equal(UnitUtils.UnitType.GAME_UNIT)
	assert_int(UnitUtils.get_unit_type(_node(["miniature"]))).is_equal(UnitUtils.UnitType.GENERIC_UNIT)
	assert_int(UnitUtils.get_unit_type(_node(["terrain"]))).is_equal(UnitUtils.UnitType.NONE)
	assert_int(UnitUtils.get_unit_type(null)).is_equal(UnitUtils.UnitType.NONE)


func test_proxy_unit_type() -> void:
	var node := _node([])
	node.set_meta("proxy_unit", true)
	assert_int(UnitUtils.get_unit_type(node)).is_equal(UnitUtils.UnitType.PROXY_UNIT)


func test_is_terrain_and_dice() -> void:
	assert_bool(UnitUtils.is_terrain(_node(["terrain_piece"]))).is_true()
	assert_bool(UnitUtils.is_dice(_node(["dice"]))).is_true()
	assert_bool(UnitUtils.is_dice(_node(["unit"]))).is_false()


# ===== Player id =====

func test_get_player_id_from_game_unit() -> void:
	var unit := GameUnit.new()
	unit.unit_properties = {"player_id": 2}
	var node := _node(["opr_unit"])
	node.set_meta("game_unit", unit)
	assert_int(UnitUtils.get_player_id(node)).is_equal(2)


func test_get_player_id_legacy_meta() -> void:
	var node := _node(["opr_unit"])
	node.set_meta("opr_player_id", 3)
	assert_int(UnitUtils.get_player_id(node)).is_equal(3)


# ===== Selection helpers =====

func test_is_same_unit() -> void:
	var unit_a := GameUnit.new()
	var first := _node([])
	first.set_meta("game_unit", unit_a)
	var second := _node([])
	second.set_meta("game_unit", unit_a)
	assert_bool(UnitUtils.is_same_unit([first, second])).is_true()

	var unit_b := GameUnit.new()
	var third := _node([])
	third.set_meta("game_unit", unit_b)
	assert_bool(UnitUtils.is_same_unit([first, third])).is_false()
	assert_bool(UnitUtils.is_same_unit([])).is_false()


func test_get_unique_units() -> void:
	var unit_a := GameUnit.new()
	var unit_b := GameUnit.new()
	var first := _node([])
	first.set_meta("game_unit", unit_a)
	var second := _node([])
	second.set_meta("game_unit", unit_a)
	var third := _node([])
	third.set_meta("game_unit", unit_b)
	assert_int(UnitUtils.get_unique_units([first, second, third]).size()).is_equal(2)
