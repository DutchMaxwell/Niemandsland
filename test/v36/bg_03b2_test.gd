extends GdUnitTestSuite
## Rules 3.6 row BG-03b2: from EPOCH_73_V36 a ruin is Cover + Unstable and see-through, so a sight
## line may pass through it. Forests keep the Dense rule (see in and out, not through) and containers
## still hard-block. Below 73 the table keeps the old area-terrain block unchanged.

const OverlayScript := preload("res://scripts/terrain_overlay.gd")
const K := OverlayScript.INCHES_TO_METERS
const TABLE := Vector2(6, 4)
const MID := Vector2i(15, 15)

var _epoch0: int


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0   # statics leak across gdUnit tests - restore


func _overlay() -> Node3D:
	var o: Node3D = auto_free(OverlayScript.new())
	o.table_size_feet = TABLE
	return o


func _centre(o: Node3D, cell: Vector2i) -> Vector2:
	var dims: Vector2i = o._calculate_grid_dims(TABLE)
	var w: Vector3 = o._cell_to_world(float(cell.x), float(cell.y), dims,
		OverlayScript.GRID_SIZE_INCHES * K, deg_to_rad(o.grid_rotation_degrees))
	return Vector2(w.x, w.z)


func _paint(o: Node3D, cells: Array, terrain_type: int) -> void:
	var data := {}
	for c: Vector2i in cells:
		data[c] = terrain_type
	o.update_overlay(data, TABLE, 0.0)


## A model as the sight truth sees it: base footprint extruded to its own height, in inches.
func _model(x_in: float, z_in: float) -> Dictionary:
	var h := VolumetricLos.height_in_for_base_mm(32.0)
	return {"c": Vector2(x_in, z_in) * K, "r": 32.0 * 0.5 * 0.001,
		"y0": 0.0, "y1": h * K}


func _sees_through_ruin(epoch: int) -> bool:
	AiActRecorder.rules_epoch = epoch
	var o := _overlay()
	_paint(o, [MID], OverlayScript.TerrainType.RUINS)
	var c_in: Vector2 = _centre(o, MID) / K
	return VolumetricLos.has_los(_model(c_in.x - 8.0, c_in.y),
		_model(c_in.x + 8.0, c_in.y), o.los_volumes())


func test_overlay_ruins_predicate_is_blocking_at_epoch_72_and_clear_at_epoch_73() -> void:
	var o := _overlay()
	var T := OverlayScript.TerrainType
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	assert_bool(o.terrain_blocks_los(T.RUINS)).is_true()
	assert_bool(o.terrain_blocks_los(T.FOREST)).is_true()
	assert_bool(o.terrain_blocks_los(T.CONTAINER)).is_true()
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	assert_bool(o.terrain_blocks_los(T.RUINS)).is_false()
	assert_bool(o.terrain_blocks_los(T.FOREST)).is_true()
	assert_bool(o.terrain_blocks_los(T.CONTAINER)).is_true()


func test_terrain_rules_ruins_predicate_is_blocking_at_epoch_72_and_clear_at_epoch_73() -> void:
	var T := TerrainRules.TerrainType
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	assert_bool(TerrainRules.blocks_los(T.RUINS)).is_true()
	assert_bool(TerrainRules.blocks_los(T.FOREST)).is_true()
	assert_bool(TerrainRules.blocks_los(T.CONTAINER)).is_true()
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	assert_bool(TerrainRules.blocks_los(T.RUINS)).is_false()
	assert_bool(TerrainRules.blocks_los(T.FOREST)).is_true()
	assert_bool(TerrainRules.blocks_los(T.CONTAINER)).is_true()


func test_sight_through_a_ruin_zone_opens_at_epoch_73() -> void:
	assert_bool(_sees_through_ruin(AiActRecorder.EPOCH_72_PLAYTEST_RULES)).is_false()
	assert_bool(_sees_through_ruin(AiActRecorder.EPOCH_73_V36)).is_true()


func test_cached_ruin_sight_volumes_rebuild_on_epoch_change_at_epoch_73() -> void:
	var o := _overlay()
	_paint(o, [MID], OverlayScript.TerrainType.RUINS)
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	assert_int((o.los_volumes() as Array).size()).is_equal(1)
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	assert_int((o.los_volumes() as Array).size()).is_equal(0)


func test_sim_ruin_volumes_follow_the_epoch_at_epoch_73() -> void:
	var ruin := {Vector2i(5, 5): TerrainRules.TerrainType.RUINS}
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	assert_int(SoloSim.terrain_los_volumes(ruin.duplicate()).size()).is_equal(1)
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	assert_int(SoloSim.terrain_los_volumes(ruin.duplicate()).size()).is_equal(0)
	assert_bool(SoloSim.terrain_has_los(ruin, Vector2(10, 16.5), Vector2(25, 16.5))).is_true()


func test_school_ruin_centre_line_opens_at_epoch_73() -> void:
	var n := 30
	var cell := Vector2i(15, 15)
	var world := {"cells": {cell: TerrainRules.TerrainType.RUINS}, "n": n}
	var c := SchoolTerrain.cell_centre_in(cell, n)
	var a := Vector3((c.x - 12.0) * SchoolTerrain.IN2M, 0, c.y * SchoolTerrain.IN2M)
	var b := Vector3((c.x + 12.0) * SchoolTerrain.IN2M, 0, c.y * SchoolTerrain.IN2M)
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	assert_bool(SchoolTerrain.los_blocked(world, a, b)).is_true()
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	assert_bool(SchoolTerrain.los_blocked(world, a, b)).is_false()
