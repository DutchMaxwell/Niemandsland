extends GdUnitTestSuite
## Reference vegetation must remain visual: saved forest members and selection colliders
## survive dressing, while replacement trees and young growth travel with their movable base.

const Forest = preload("res://scripts/visual/reference_biome_forest.gd")
const Overlay = preload("res://scripts/terrain_overlay.gd")

class Library extends RefCounted:
	var scene: PackedScene
	func get_model_scene(_key: String) -> PackedScene:
		return scene

class OverlayFixture extends Node3D:
	var _trees_library: Library
	func _model_space_aabb(node: Node3D) -> AABB:
		return Overlay._model_space_aabb(node)

class MainFixture extends Node:
	var terrain_overlay: OverlayFixture

class PresentationFixture extends Node3D:
	var _ground := ShaderMaterial.new()


func test_movable_forest_keeps_saved_members_and_colliders() -> void:
	for biome in ["frozen_tundra", "arid_desert"]:
		var main: MainFixture = auto_free(MainFixture.new())
		var overlay: OverlayFixture = auto_free(OverlayFixture.new())
		main.terrain_overlay = overlay
		overlay._trees_library = Library.new()
		var source := MeshInstance3D.new()
		source.mesh = BoxMesh.new()
		var source_material := StandardMaterial3D.new()
		var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
		image.fill(Color.DARK_GREEN)
		source_material.albedo_texture = ImageTexture.create_from_image(image)
		source.mesh.material = source_material
		var packed := PackedScene.new()
		packed.pack(source)
		source.free()
		overlay._trees_library.scene = packed
		var presentation: PresentationFixture = auto_free(PresentationFixture.new())
		presentation._ground.shader = preload("res://shaders/visual/reference_ground.gdshader")
		var forest: Node3D = auto_free(Forest.new())
		add_child(forest)
		forest._main = main
		forest._presentation = presentation
		forest._biome = biome
		forest._rng.seed = 210921
		var group: TerrainGroupBase = auto_free(TerrainGroupBase.new())
		group.configure("forest_large", TerrainGroupBase.KIND_FOREST, Vector2(12, 10))
		add_child(group)
		group.build(12345, null)
		group.biome_prefix = "tundra_" if biome == "frozen_tundra" else "desert_"
		group.position = Vector3(0.4, 0.02, -0.3)
		group.rotation.y = 0.7
		var saved := group.member_states().duplicate(true)
		var original_children := group.get_children()
		var collider: CollisionShape3D = group.find_children("*", "CollisionShape3D", true, false)[0]
		var shape := collider.shape
		var collider_transform := collider.transform
		assert_int(forest._dress_groups()).is_equal(saved.size())
		assert_int(forest._young_growth()).is_greater(0)
		assert_array(group.member_states()).is_equal(saved)
		assert_object(collider.shape).is_same(shape)
		assert_bool(collider.transform == collider_transform).is_true()
		assert_int(group.collision_layer).is_equal(TerrainGroupBase.MOVABLE_TERRAIN_COLLISION_LAYER)
		assert_int(group.find_children("*", "CollisionShape3D", true, false).size()).is_equal(1)
		var replacements: Array[Node3D] = []
		var local_transforms: Array[Transform3D] = []
		for child in group.get_children():
			if child is Node3D and not original_children.has(child):
				replacements.append(child)
				local_transforms.append(child.transform)
				assert_bool(child.has_meta(TerrainGroupBase.MEMBER_META)).is_false()
		assert_int(replacements.size()).is_greater(saved.size())
		group.position += Vector3(0.2, 0.0, 0.1)
		group.rotation.y += 0.5
		for i in replacements.size():
			assert_bool(replacements[i].global_transform.is_equal_approx(group.global_transform * local_transforms[i])).is_true()
		assert_array(group.member_states()).is_equal(saved)
		var unchanged: MeshInstance3D = auto_free(packed.instantiate())
		assert_object(unchanged.mesh.material).is_same(source_material)
		assert_object(unchanged.get_surface_override_material(0)).is_null()
		# Remove from the tree now so the next biome fixture is independent.
		remove_child(group)
		remove_child(forest)
