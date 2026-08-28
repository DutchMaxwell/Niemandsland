extends GdUnitTestSuite
## NML-1088b — the ONE deploy terrain rule: AiDeployment.make_blocked_tests. The interactive game
## (main._on_solo_deploy_pressed) and the arena harness (tools/arena_match.gd) both take their
## blocked-cell tests from here, so this suite pins the rule they share. Before the fix the arena ran
## its own physics-ONLY probe that blanket-blocked FOREST and RUINS and never read the wall DATA —
## it disagreed with the shipped game on exactly the cells asserted below.


## Terrain-overlay stand-in: the three things the rule reads — the terrain class per cell, the
## container/ruin wall segments, and (as a Node3D in the tree) a physics world with no props in it.
class StubOverlay extends Node3D:
	enum TerrainType {NONE = 0, RUINS = 1, FOREST = 2, CONTAINER = 3, DANGEROUS = 4}
	var cells: Dictionary = {}   # Vector2i(x, z) in whole metres -> TerrainType
	var walls: Array = []        # [[Vector2, Vector2], ...] as get_wall_segments_world() returns them

	func get_terrain_at_world_position(p: Vector3) -> int:
		return int(cells.get(Vector2i(roundi(p.x), roundi(p.z)), TerrainType.NONE))

	func get_wall_segments_world() -> Array:
		return walls


func _tests() -> Dictionary:
	var o := StubOverlay.new()
	o.cells = {
		Vector2i(1, 0): StubOverlay.TerrainType.FOREST,
		Vector2i(2, 0): StubOverlay.TerrainType.RUINS,
		Vector2i(3, 0): StubOverlay.TerrainType.DANGEROUS,
		Vector2i(4, 0): StubOverlay.TerrainType.CONTAINER,
	}
	o.walls = [[Vector2(6.0, -1.0), Vector2(6.0, 1.0)]]
	add_child(o)
	return AiDeployment.make_blocked_tests(auto_free(o))


## Deploy doctrine (maintainer + five-game study T1): a wood or a ruin floor is a LEGAL deploy spot —
## this is the half the arena got wrong, and the reason arena boards deployed open-ground-heavy.
func test_forest_and_ruin_floors_are_legal_deploy_spots() -> void:
	var t := _tests()
	assert_bool(t["normal"].call(Vector2(1.0, 0.0))).is_false()
	assert_bool(t["normal"].call(Vector2(2.0, 0.0))).is_false()
	assert_bool(t["flying"].call(Vector2(1.0, 0.0))).is_false()


func test_dangerous_and_container_block_the_walker_container_and_ruins_the_flyer() -> void:
	var t := _tests()
	assert_bool(t["normal"].call(Vector2(3.0, 0.0))).is_true()
	assert_bool(t["normal"].call(Vector2(4.0, 0.0))).is_true()
	assert_bool(t["flying"].call(Vector2(4.0, 0.0))).is_true()
	assert_bool(t["flying"].call(Vector2(2.0, 0.0))).is_true()
	assert_bool(t["flying"].call(Vector2(3.0, 0.0))).is_false()


## The DATA wall test (finding 1): a spawned container/ruin carries wall segments but no grid cell —
## the arena's probe never asked for them, so it happily deployed a base into a wall the game rejects.
func test_a_wall_segment_blocks_where_the_terrain_grid_says_nothing() -> void:
	var t := _tests()
	assert_bool(t["normal"].call(Vector2(6.01, 0.0))).is_true()
	assert_bool(t["flying"].call(Vector2(6.01, 0.0))).is_true()
	assert_bool(t["normal"].call(Vector2(6.5, 0.0))).is_false()
