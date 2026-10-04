extends GdUnitTestSuite
const RULES := preload("res://scripts/solo/jump_rules.gd")

func test_empty_path_and_six_inch_world_coordinate() -> void:
	var surface := func(_p: Vector2) -> float: return 0.0
	var height := Vector3(0, 6.0 * 0.0254, 0).y
	var drops: Array = RULES.drops(PackedVector2Array([Vector2.ZERO, Vector2.ONE]), surface, height)
	assert_int(RULES.drop_kind(drops[0].dy_in)).is_equal(RULES.DropKind.JUMP)
	assert_int(RULES.jump_dice(drops[0].dy_in)).is_equal(3)
	assert_array(RULES.drops(PackedVector2Array(), surface, 0.0)).is_empty()

func test_drop_probe_finds_the_foot_before_the_drag_endpoint() -> void:
	var surface := func(p: Vector2) -> float: return 0.1016 if p.x < 0.0254 else 0.0
	var drops: Array = RULES.drops(PackedVector2Array([Vector2.ZERO, Vector2(0.2, 0)]), surface, 0.1016)
	assert_int(drops.size()).is_equal(1)
	assert_float(drops[0].dy_in).is_equal_approx(4.0, 0.001)
	assert_float(drops[0].foot.x).is_between(0.0254, 0.0318)

func test_drop_boundaries() -> void:
	for height in [0.0, 1.0, 3.0]:
		assert_int(RULES.drop_kind(height)).is_equal(RULES.DropKind.FREE)
	for height in [3.01, 4.0, 6.0]:
		assert_int(RULES.drop_kind(height)).is_equal(RULES.DropKind.JUMP)
	assert_int(RULES.drop_kind(6.01)).is_equal(RULES.DropKind.IMPASSABLE)

func test_book_example_four_inches_needs_two_dice() -> void:
	assert_int(RULES.jump_dice(4.0)).is_equal(2)
	assert_int(RULES.jump_dice(5.99)).is_equal(2)
	assert_int(RULES.jump_dice(6.0)).is_equal(3)

func test_targets_and_flying_auto_pass() -> void:
	assert_int(RULES.jump_target()).is_equal(3)
	assert_int(RULES.jump_target(true)).is_equal(2)
	assert_int(RULES.jump_target(false, true)).is_equal(0)
	assert_int(RULES.jump_target(true, true)).is_equal(0)

func test_fall_hit_threshold_and_ap() -> void:
	assert_int(RULES.fall_hit_ap(1.99)).is_equal(-1)
	assert_int(RULES.fall_hit_ap(2.0)).is_equal(0)
	assert_int(RULES.fall_hit_ap(2.99)).is_equal(0)
	assert_int(RULES.fall_hit_ap(3.0)).is_equal(1)
	assert_int(RULES.fall_hit_ap(4.0)).is_equal(1)
	assert_int(RULES.fall_hit_ap(6.0)).is_equal(2)
