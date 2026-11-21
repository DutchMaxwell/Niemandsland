extends GdUnitTestSuite
## PLAN_GAME_SYSTEM_SWITCH step 13: a grid blocker (the CONTAINER type) is drawn as a shipping container on a grimdark table and as
## the plain stone solid a free blocker is on a fantasy one - look only: same 6 x 3 x 2.5 in rule box, same collider. The overlay
## asks the table's system when it builds its objects, and a fantasy table never asks for the container panels. Red proof: on main
## a fantasy table asked for them and drew containers.

const OverlayScript := preload("res://scripts/terrain_overlay.gd")
const IN2M := 0.0254


class RecordingContainers extends ContainersLibrary:
	var asked := 0

	func all_panels_cached(_theme_prefix: String = "") -> bool:
		return false

	func ensure_all_panels(_theme_prefix: String = "") -> bool:
		asked += 1
		return false


## A stand-in for /root/Main that only knows the table's system (what the overlay asks for).
class FakeMain extends Node:
	var system := "gf"

	func _table_system() -> String:
		return system


var _fake: FakeMain


func after_test() -> void:
	if is_instance_valid(_fake):
		_fake.get_parent().remove_child(_fake)
		_fake.free()
	_fake = null


func _table(system: String) -> void:
	_fake = FakeMain.new()
	_fake.name = "Main"
	_fake.system = system
	get_tree().root.add_child(_fake)


func _overlay() -> Node3D:
	var overlay: Node3D = auto_free(OverlayScript.new())
	add_child(overlay)
	overlay._containers_library.queue_free()
	overlay._containers_library = RecordingContainers.new()
	overlay.add_child(overlay._containers_library)
	return overlay


func _blockers() -> Array:
	return [{"object_type": "container", "cell": Vector2i(18, 17), "offset": Vector2(0.5, 0.5)}]


func _meshes(body: Node) -> Array:
	return body.find_children("*", "MeshInstance3D", true, false)


func test_a_fantasy_table_draws_the_blocker_as_a_stone_solid_without_container_panels() -> void:
	for system in ["aof", "aofs", "aofr"]:
		_table(system)
		var overlay := _overlay()
		overlay.update_placed_objects(_blockers(), Vector2(6, 4), 0.0)
		assert_int(overlay._object_instances.size()).is_equal(1)
		var body: Node = overlay._object_instances[0]
		assert_bool(body is StaticBody3D).is_true()
		var meshes := _meshes(body)
		assert_int(meshes.size()).override_failure_message("%s: no stone solid" % system).is_equal(1)
		assert_vector((meshes[0].mesh as BoxMesh).size).is_equal_approx(Vector3(6.0, 2.5, 3.0) * IN2M, Vector3.ONE * 0.0001)
		assert_int((overlay._containers_library as RecordingContainers).asked).override_failure_message("%s asked for container panels" % system).is_equal(0)
		var shape: BoxShape3D = (body.find_children("*", "CollisionShape3D", true, false)[0] as CollisionShape3D).shape
		assert_vector(shape.size).is_equal_approx(Vector3(6.0, 2.5, 3.0) * IN2M, Vector3.ONE * 0.0001)   # the rule box
		_fake.get_parent().remove_child(_fake)
		_fake.free()
		_fake = null


func test_a_grimdark_table_still_asks_for_the_container_panels() -> void:
	for system in ["gf", "gff"]:
		_table(system)
		var overlay := _overlay()
		overlay.update_placed_objects(_blockers(), Vector2(6, 4), 0.0)
		assert_int((overlay._containers_library as RecordingContainers).asked).override_failure_message("%s did not ask for panels" % system).is_greater_equal(1)
		_fake.get_parent().remove_child(_fake)
		_fake.free()
		_fake = null


func test_without_a_main_the_look_is_the_grimdark_one() -> void:
	var overlay := _overlay()
	overlay.update_placed_objects(_blockers(), Vector2(6, 4), 0.0)
	assert_int((overlay._containers_library as RecordingContainers).asked).is_greater_equal(1)


func test_the_free_blocker_keeps_its_look_after_the_refactor() -> void:
	var prop: SandboxSolidProp = auto_free(SandboxSolidProp.new())
	prop.configure("blocker_6x3", ObjectManager.SandboxPropKind.BLOCKER, Vector2(6, 3), "plain")
	var boxes := prop.get_children().filter(func(c: Node) -> bool: return c is MeshInstance3D and (c as MeshInstance3D).mesh is BoxMesh)
	assert_int(boxes.size()).is_greater_equal(1)
	assert_vector((boxes[0].mesh as BoxMesh).size).is_equal_approx(Vector3(6.0, 2.5, 3.0) * IN2M, Vector3.ONE * 0.0001)
