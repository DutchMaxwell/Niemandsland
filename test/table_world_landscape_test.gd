extends GdUnitTestSuite
const World := preload("res://scripts/visual/table_world.gd")
const Biomes := preload("res://scripts/visual/reference_biomes.gd")

class Board extends Node3D:
	var table_size := Vector2(12,8)

func test_world_has_a_flat_clearance_and_plinth_for_the_actual_board_size() -> void:
	var world: Node3D = auto_free(World.new())
	assert_bool(world.has_method("_build_landscape")).is_true()
	if not world.has_method("_build_landscape"):
		return
	var main: Node = auto_free(Node.new())
	var table := Board.new()
	table.name = "Table"
	main.add_child(table)
	world.set("_main", main)
	world.set("_profile", Biomes.GRASSLAND)
	world.call("_build_landscape")
	assert_float(world.get("_world_scale")).is_equal_approx(2.0,0.001)
	assert_float(world.call("_height",Vector2(2,1))).is_equal_approx(-0.34,0.001)
	var plinth := world.get_node("WorldPlinth") as MeshInstance3D
	assert_float((plinth.mesh as BoxMesh).size.x).is_greater(12*0.3048)
	assert_float((plinth.mesh as BoxMesh).size.z).is_greater(8*0.3048)
	var ground := world.get_node("WorldGround") as MeshInstance3D
	assert_int(ground.gi_mode).is_equal(GeometryInstance3D.GI_MODE_DISABLED)
	assert_int(world.find_children("*","CollisionObject3D",true,false).size()).is_zero()
