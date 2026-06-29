extends GdUnitTestSuite
## Regiment pooled-wound counter (integrative): OPRArmyManager.apply_regiment_wounds
## recomputes model alive/wounds state from the counter (back rank dies first,
## AoF:R v3.5.1 p.9), re-ranks the block, and shows the counter label.
## regiment_take_casualty / regiment_revive_casualty wrap it with clamps + undo.
## No network (single-player path); MP is exercised by the soak harness.

const CELL := 0.025
const OPRArmyManagerScript = preload("res://scripts/opr_army_manager.gd")


func _fps(n: int) -> Array:
	var a: Array = []
	for i in range(n):
		a.append(Vector2(CELL, CELL))
	return a


## Build a GameUnit of `n` models, each with the given Tough value (wounds_max).
func _game_unit(n: int, tough: int, unit_id: String = "test_reg") -> GameUnit:
	var gu := GameUnit.new()
	gu.unit_id = unit_id
	gu.unit_properties = {"base_width_mm": 25, "base_depth_mm": 25, "regiment_mode": true}
	for i in range(n):
		var mi := ModelInstance.new()
		var node := Node3D.new()
		add_child(node)
		auto_free(node)
		mi.node = node
		mi.is_alive = true
		mi.wounds_max = tough
		mi.wounds_current = tough
		mi.properties["tough"] = tough
		mi.unit = gu
		gu.models.append(mi)
	return gu


func _tray() -> RegimentTray:
	var t := RegimentTray.new()
	add_child(t)
	return auto_free(t)


func _army_manager() -> OPRArmyManager:
	var om: Node3D = auto_free(Node3D.new())
	om.name = "ObjectManager"
	add_child(om)
	var am: OPRArmyManager = auto_free(OPRArmyManagerScript.new())
	am.name = "OPRArmyManager"
	om.add_child(am)
	am.object_manager = om
	return am


func _formed_regiment(am: OPRArmyManager, gu: GameUnit, frontage: int = 5) -> RegimentTray:
	var members := RegimentTray.collect_members(gu)
	var tray := _tray()
	tray.form(members.nodes, members.footprints, frontage)
	var regiment := Regiment.new(gu, tray, frontage)
	tray.set_meta("regiment", regiment)
	gu.unit_properties["frontage"] = frontage
	am.regiments[gu.unit_id] = regiment
	return tray


# ===== apply_regiment_wounds =====


func test_apply_tough1_two_wounds_kills_back_two_models() -> void:
	var am := _army_manager()
	var gu := _game_unit(10, 1)
	var tray := _formed_regiment(am, gu, 5)
	var regiment: Regiment = tray.get_meta("regiment")

	am.apply_regiment_wounds(regiment, 2)

	assert_int(regiment.wounds_taken).is_equal(2)
	assert_int(gu.get_alive_count()).is_equal(8)
	# Back two models (index 8, 9) dead, front 8 alive.
	assert_bool(gu.models[9].is_alive).is_false()
	assert_bool(gu.models[8].is_alive).is_false()
	assert_bool(gu.models[7].is_alive).is_true()
	assert_bool(gu.models[0].is_alive).is_true()
	# Dead models' nodes are hidden.
	assert_bool(gu.models[9].node.visible).is_false()
	assert_int(int(gu.unit_properties["regiment_wounds_taken"])).is_equal(2)


func test_apply_tough2_three_wounds_kills_one_wounds_next() -> void:
	var am := _army_manager()
	var gu := _game_unit(10, 2)
	var tray := _formed_regiment(am, gu, 5)
	var regiment: Regiment = tray.get_meta("regiment")

	am.apply_regiment_wounds(regiment, 3)

	# Tough(2) x10: pool 20, 3 wounds -> model[9] dead (2 wounds), model[8] wounded (1/2).
	assert_int(gu.get_alive_count()).is_equal(9)
	assert_bool(gu.models[9].is_alive).is_false()
	assert_bool(gu.models[8].is_alive).is_true()
	assert_int(gu.models[8].wounds_current).is_equal(1)  # 2 tough - 1 wound


func test_apply_zero_wounds_all_alive() -> void:
	var am := _army_manager()
	var gu := _game_unit(10, 1)
	var tray := _formed_regiment(am, gu, 5)
	var regiment: Regiment = tray.get_meta("regiment")

	am.apply_regiment_wounds(regiment, 0)
	assert_int(gu.get_alive_count()).is_equal(10)
	assert_int(regiment.wounds_taken).is_equal(0)


func test_apply_full_pool_all_dead() -> void:
	var am := _army_manager()
	var gu := _game_unit(5, 1)
	var tray := _formed_regiment(am, gu, 5)
	var regiment: Regiment = tray.get_meta("regiment")

	am.apply_regiment_wounds(regiment, 5)
	assert_int(gu.get_alive_count()).is_equal(0)


func test_apply_overkill_clamps_to_pool() -> void:
	var am := _army_manager()
	var gu := _game_unit(3, 1)
	var tray := _formed_regiment(am, gu, 3)
	var regiment: Regiment = tray.get_meta("regiment")

	am.apply_regiment_wounds(regiment, 99)
	assert_int(regiment.wounds_taken).is_equal(3)
	assert_int(gu.get_alive_count()).is_equal(0)


# ===== take / revive casualty (clamps + state) =====


func test_take_casualty_increments_and_kills_back_model() -> void:
	var am := _army_manager()
	var gu := _game_unit(10, 1)
	var tray := _formed_regiment(am, gu, 5)

	var taken: int = am.regiment_take_casualty(tray)
	assert_int(taken).is_equal(1)
	assert_int(gu.get_alive_count()).is_equal(9)
	assert_bool(gu.models[9].is_alive).is_false()


func test_take_casualty_clamps_at_pool_max() -> void:
	var am := _army_manager()
	var gu := _game_unit(3, 1)
	var tray := _formed_regiment(am, gu, 3)

	am.regiment_take_casualty(tray)
	am.regiment_take_casualty(tray)
	am.regiment_take_casualty(tray)
	assert_int(gu.get_alive_count()).is_equal(0)
	# A fourth take is a no-op (clamped).
	var taken: int = am.regiment_take_casualty(tray)
	assert_int(taken).is_equal(3)


func test_revive_casualty_decrements_and_restores_model() -> void:
	var am := _army_manager()
	var gu := _game_unit(10, 1)
	var tray := _formed_regiment(am, gu, 5)
	am.regiment_take_casualty(tray)
	am.regiment_take_casualty(tray)
	assert_int(gu.get_alive_count()).is_equal(8)

	var taken: int = am.regiment_revive_casualty(tray)
	assert_int(taken).is_equal(1)
	assert_int(gu.get_alive_count()).is_equal(9)
	# At wounds_taken=1 the rearmost model (Tough(1)) is still dead (1 wound on it);
	# the revived model is models[8] (the second-rearmost, now alive again).
	assert_bool(gu.models[9].is_alive).is_false()
	assert_bool(gu.models[8].is_alive).is_true()


func test_revive_casualty_clamps_at_zero() -> void:
	var am := _army_manager()
	var gu := _game_unit(10, 1)
	var tray := _formed_regiment(am, gu, 5)

	var taken: int = am.regiment_revive_casualty(tray)
	assert_int(taken).is_equal(0)
	assert_int(gu.get_alive_count()).is_equal(10)


# ===== wound readout (for the menu label) =====


func test_wound_readout_at_full_strength() -> void:
	var am := _army_manager()
	var gu := _game_unit(10, 1)
	var tray := _formed_regiment(am, gu, 5)

	var r: Dictionary = am.regiment_wound_readout(tray)
	assert_int(r["remaining"]).is_equal(10)
	assert_int(r["pool_max"]).is_equal(10)


func test_wound_readout_after_casualties() -> void:
	var am := _army_manager()
	var gu := _game_unit(10, 2)
	var tray := _formed_regiment(am, gu, 5)
	am.regiment_take_casualty(tray)  # 1 wound -> 19/20 remaining
	am.regiment_take_casualty(tray)  # 2 wounds -> still 19 (one Tough(2) model not dead yet)
	am.regiment_take_casualty(tray)  # 3 wounds -> model dead, 17/20 remaining

	var r: Dictionary = am.regiment_wound_readout(tray)
	assert_int(r["remaining"]).is_equal(17)
	assert_int(r["pool_max"]).is_equal(20)


# ===== RegimentWoundAction (undo/redo) =====


func test_wound_action_undo_restores_models() -> void:
	var am := _army_manager()
	var gu := _game_unit(10, 1)
	var tray := _formed_regiment(am, gu, 5)
	var regiment: Regiment = tray.get_meta("regiment")

	var action := UndoManager.RegimentWoundAction.new(regiment, 0, 3, am, null, 0)
	action.redo()
	assert_int(gu.get_alive_count()).is_equal(7)
	action.undo()
	assert_int(gu.get_alive_count()).is_equal(10)
	assert_int(regiment.wounds_taken).is_equal(0)


func test_wound_action_redo_reapplies_state() -> void:
	var am := _army_manager()
	var gu := _game_unit(10, 1)
	var tray := _formed_regiment(am, gu, 5)
	var regiment: Regiment = tray.get_meta("regiment")

	var action := UndoManager.RegimentWoundAction.new(regiment, 0, 2, am, null, 0)
	action.redo()
	assert_int(gu.get_alive_count()).is_equal(8)
	action.undo()
	assert_int(gu.get_alive_count()).is_equal(10)
	action.redo()
	assert_int(gu.get_alive_count()).is_equal(8)
	assert_bool(gu.models[9].is_alive).is_false()
