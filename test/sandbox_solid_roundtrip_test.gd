extends GdUnitTestSuite
## The free solid survives a save round-trip and reaches a peer with its kind: after SaveManager serialises and
## restores it at 45 degrees, kind 3 (CONTAINER rules), footprint, position and yaw come back equal; a multiplayer
## spawn broadcasts kind 3, so the peer builds the same solid and not a ruin.

const SOLID_ID := "blocker_6x3"


class StubNet extends Node:
	var spawns: Array = []

	func is_multiplayer_active() -> bool:
		return true

	func broadcast_sandbox_terrain_spawn(prop_id: String, kind: int, pos: Vector3, object_id: int) -> void:
		spawns.append([prop_id, kind, pos, object_id])


func _om() -> ObjectManager:
	var om: ObjectManager = auto_free(ObjectManager.new())
	add_child(om)
	return om


func _solid_by_net_id(net_id: int) -> Node3D:
	for n in ObjectManager.sandbox_pieces(get_tree()):
		if is_instance_valid(n) and not n.is_queued_for_deletion() and int(n.get_meta("network_id", -1)) == net_id:
			return n
	return null


func test_the_solid_survives_a_save_round_trip_at_45_degrees() -> void:
	var om := _om()
	var sm: SaveManager = auto_free(SaveManager.new())
	sm.object_manager = om
	add_child(sm)
	var pos := Vector3(0.2, 0.0, -0.1)
	var solid := om.spawn_sandbox_terrain(SOLID_ID, ObjectManager.SandboxPropKind.BLOCKER, pos, false, 7301)
	solid.rotation_degrees.y = 45.0
	var data: Dictionary = sm._serialize_object(solid)
	assert_str(String(data.get("type", ""))).is_equal("sandbox_terrain")
	assert_int(int(data.get("prop_kind", -1))).is_equal(ObjectManager.SandboxPropKind.BLOCKER)
	solid.free()
	assert_bool(await sm._deserialize_object(data)).is_true()
	var back := _solid_by_net_id(7301)
	assert_object(back).is_instanceof(SandboxSolidProp)
	if back == null:
		return
	assert_int(ObjectManager.sandbox_terrain_type(int(back.get("prop_kind")))).is_equal(TerrainRules.TerrainType.CONTAINER)
	assert_vector(Vector2(back.get("footprint_inches"))).is_equal(Vector2(6, 3))
	assert_vector(back.global_position).is_equal_approx(pos, Vector3.ONE * 0.0001)
	assert_float(back.rotation_degrees.y).is_equal_approx(45.0, 0.001)


func test_a_multiplayer_spawn_broadcasts_the_solid_kind() -> void:
	var om := _om()
	var net: StubNet = auto_free(StubNet.new())
	om._network_manager = net
	om.spawn_sandbox_terrain(SOLID_ID, ObjectManager.SandboxPropKind.BLOCKER, Vector3(0.3, 0.0, 0.2), true, 7302)
	assert_int(net.spawns.size()).is_equal(1)
	assert_array(net.spawns[0].slice(0, 2)).is_equal([SOLID_ID, ObjectManager.SandboxPropKind.BLOCKER])
	assert_int(int(net.spawns[0][3])).is_equal(7302)
