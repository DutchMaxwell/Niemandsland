extends GdUnitTestSuite
## #3090 part 2 (PENDING_EPOCH_DANGER_AVOID): the AI steps into Dangerous ground it could skirt. A plain move reads the
## Dangerous exception on the unit's GOAL (not one model's rigid corner) and, when the plan still crosses, re-plans with
## the goal shifted sideways, else stops short when the toll outweighs the distance, and logs it. Core twins in mv::step:
## `a_line_sidesteps_a_dangerous_patch_mid_route`, `one_clipped_corner_no_longer_switches_avoidance_off`,
## `a_big_unit_stops_short_of_a_patch_it_cannot_skirt` (same geometry).

const IN2M := 0.0254

var _mgr: OPRArmyManager
var _solo: SoloController
var _epoch0: int
var _fast0: bool
var _rect := Rect2()   # inches: x0, z0, w, h


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch
	# The precise planner, as the other solo planner suites pin it: an earlier suite in the shard (main.gd's solo
	# setup) can leave the static fast planner on, and the geometry below is measured on the precise one.
	_fast0 = MovementPlanner.fast_planner
	MovementPlanner.fast_planner = false
	_mgr = auto_free(OPRArmyManager.new())
	_solo = auto_free(SoloController.new())
	add_child(_solo)
	_solo.army_manager = _mgr
	_solo.human_slot = 1
	_solo.ai_slot = 2
	_solo.terrain_type_at = func(p: Vector3) -> int:
		return TerrainRules.TerrainType.DANGEROUS if _rect.has_point(Vector2(p.x / IN2M, p.z / IN2M)) \
			else TerrainRules.TerrainType.NONE


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0   # statics leak across gdUnit tests - restore
	MovementPlanner.fast_planner = _fast0


## `n` models in rows of 5 (1.5" apart, rows 1.5" back, 32 mm bases) from z 0 move `inches` toward (0, goal_z);
## answers the Dangerous model count.
func _line_move(tag: String, epoch: int, patch: Rect2, goal_z: float, inches: float, n: int = 5) -> int:
	AiActRecorder.rules_epoch = epoch
	_rect = patch
	_solo.board_clamp_notes = []
	var u: GameUnit = auto_free(GameUnit.new())
	u.unit_id = tag
	u.unit_properties = {"player_id": 2, "special_rules": [], "name": tag, "quality": 4, "defense": 4}
	for i in range(n):
		var m := ModelInstance.new()
		m.unit = u
		m.is_alive = true
		m.wounds_max = 1
		m.wounds_current = 1
		m.node = auto_free(Node3D.new())
		add_child(m.node)
		m.node.global_position = Vector3((float(i % 5) - 2.0) * 1.5 * IN2M, 0, -floorf(i / 5.0) * 1.5 * IN2M)
		u.models.append(m)
	_mgr.game_units[tag] = u
	return _solo._execute_move(u, Vector3(0, 0, goal_z * IN2M), inches, false)


func test_a_line_sidesteps_a_patch_mid_route_and_logs_it() -> void:
	var patch := Rect2(2.5, 4.0, 3.0, 4.0)
	assert_int(_line_move("Old", 91, patch, 14.0, 12.0)).is_greater(0)
	assert_array(_solo.board_clamp_notes).is_empty()
	assert_int(_line_move("New", AiActRecorder.PENDING_EPOCH_DANGER_AVOID, patch, 14.0, 12.0)).is_equal(0)
	assert_str(str(_solo.board_clamp_notes)).contains("New sidesteps Dangerous ground (")


func test_one_clipped_corner_no_longer_switches_avoidance_off() -> void:
	var patch := Rect2(2.5, 10.0, 3.0, 4.0)
	assert_int(_line_move("Old", 91, patch, 14.0, 12.0)).is_greater(0)
	assert_int(_line_move("New", AiActRecorder.PENDING_EPOCH_DANGER_AVOID, patch, 14.0, 12.0)).is_equal(0)


func test_a_big_unit_stops_short_of_a_patch_it_cannot_skirt() -> void:
	var patch := Rect2(-1.5, 4.0, 3.0, 4.0)
	assert_int(_line_move("Old", 91, patch, 14.0, 12.0, 10)).is_greater(0)
	assert_int(_line_move("Big", AiActRecorder.PENDING_EPOCH_DANGER_AVOID, patch, 14.0, 12.0, 10)).is_equal(0)
	var front := -INF
	for m in (_mgr.game_units["Big"] as GameUnit).models:
		front = maxf(front, (m as ModelInstance).node.global_position.z / IN2M)
	assert_float(front).is_less(4.0)
	assert_str(str(_solo.board_clamp_notes)).contains("Big stops short of Dangerous ground (")


func test_an_advance_that_stops_short_of_the_patch_is_unchanged() -> void:
	assert_int(_line_move("Adv", AiActRecorder.PENDING_EPOCH_DANGER_AVOID, Rect2(2.5, 10.0, 3.0, 4.0), 8.0, 6.0)).is_equal(0)
	assert_array(_solo.board_clamp_notes).is_empty()


func test_a_player_order_is_never_re_aimed() -> void:
	_solo._player_move = true
	var dang := _line_move("Mine", AiActRecorder.PENDING_EPOCH_DANGER_AVOID, Rect2(2.5, 4.0, 3.0, 4.0), 14.0, 12.0)
	_solo._player_move = false
	assert_int(dang).is_greater(0)
	assert_array(_solo.board_clamp_notes).is_empty()
