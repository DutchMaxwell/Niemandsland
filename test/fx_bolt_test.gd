extends GdUnitTestSuite
## FxBolt (combat effects): a jagged bolt is an unbroken chain of seven segments from `a` exactly to `b`, its bends come
## from the seed alone (same seed, same bolt; the game's RNG untouched), it is as thin as asked, and an aura's own
## material replaces the default white.

const BoltScript = preload("res://scripts/vfx/fx_bolt.gd")
const A := Vector3(0.0, 0.03, 0.0)
const B := Vector3(0.12, 0.05, 0.04)


func _bolt(s: int, radius := 0.0005, mat: Material = null) -> Node3D:
	var holder := auto_free(Node3D.new()) as Node3D
	add_child(holder)
	BoltScript.jag(holder, A, B, s, radius, 0.01, mat)
	return holder


func _ends(seg: Node3D) -> Array:
	var t := seg.global_transform
	return [t.origin - t.basis.y * 0.5, t.origin + t.basis.y * 0.5]


func test_a_bolt_runs_unbroken_from_a_to_b() -> void:
	var h := _bolt(7)
	assert_int(h.get_child_count()).is_equal(7)
	assert_vector(_ends(h.get_child(0))[0]).is_equal_approx(A, Vector3.ONE * 1e-5)
	assert_vector(_ends(h.get_child(6))[1]).is_equal_approx(B, Vector3.ONE * 1e-5)
	for i in 6:
		assert_vector(_ends(h.get_child(i))[1]).is_equal_approx(_ends(h.get_child(i + 1))[0], Vector3.ONE * 1e-5)
	assert_float((h.get_child(3) as Node3D).global_transform.basis.x.length()).is_equal_approx(0.0005, 1e-7)


func test_the_seed_shapes_the_bolt_and_the_game_rng_stays_alone() -> void:
	seed(5)
	var expected := randi()
	seed(5)
	var a := _bolt(11)
	var b := _bolt(11)
	var c := _bolt(12)
	assert_int(randi()).is_equal(expected)
	assert_vector((a.get_child(3) as Node3D).global_position).is_equal((b.get_child(3) as Node3D).global_position)
	assert_vector((a.get_child(3) as Node3D).global_position).is_not_equal((c.get_child(3) as Node3D).global_position)


func test_an_aura_material_replaces_the_white() -> void:
	var tint := StandardMaterial3D.new()
	assert_object((_bolt(3, 0.0005, tint).get_child(0) as MeshInstance3D).material_override).is_same(tint)
	assert_object((_bolt(3).get_child(0) as MeshInstance3D).material_override).is_null()
