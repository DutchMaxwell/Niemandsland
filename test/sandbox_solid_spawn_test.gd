extends GdUnitTestSuite
## ObjectManager.spawn_sandbox_terrain routes the free solid's kind to a SandboxSolidProp: CONTAINER rules, 6x3"
## footprint, standing where it was dropped, carrying its network id. Saves, the MP spawn RPC and (later) the shelf
## all go through this one choke point.

const SOLID_ID := "blocker_6x3"


func _om() -> ObjectManager:
	var om: ObjectManager = auto_free(ObjectManager.new())
	add_child(om)
	return om


func test_spawn_routes_the_solid_kind_to_a_solid_prop() -> void:
	var pos := Vector3(0.1, 0.0, -0.2)
	var spawned := _om().spawn_sandbox_terrain(SOLID_ID, ObjectManager.SandboxPropKind.BLOCKER, pos, false, 7101)
	assert_object(spawned).is_instanceof(SandboxSolidProp)
	if spawned == null:
		return
	assert_vector(Vector2(spawned.get("footprint_inches"))).is_equal(Vector2(6, 3))
	assert_int(ObjectManager.sandbox_terrain_type(int(spawned.get("prop_kind")))).is_equal(TerrainRules.TerrainType.CONTAINER)
	assert_vector(spawned.global_position).is_equal_approx(pos, Vector3.ONE * 0.0001)
	assert_int(int(spawned.get_meta("network_id"))).is_equal(7101)   # move/rotate sync finds it by this id
