extends GdUnitTestSuite
## Rules 3.6 wave, row AI-G3F9a: the arena capture's terrain stash for moves.json. Since the AI climbs
## (SoloController.climb_on, epoch 70) a container edge is a ledge a model may climb over, but the stash only
## exported it as a wall, so the offline wall audit flagged a legal climb onto a container as a clip through a
## wall. The stash now also exports every ledge as [[ax, az], [bx, bz], dy_in], snapped like the walls, while
## climbing is on; the walls themselves stay as they were (a ledge is still a wall for a move that does not
## climb). Capture tooling only: it reads the climb flag, it gates on no new rules epoch.

const ArenaMatch := preload("res://tools/arena_match.gd")
const OverlayScript := preload("res://scripts/terrain_overlay.gd")

## One container footprint, corners chosen off the 0.0001 m grid so the snapping is visible.
const CORNERS := [Vector2(0.123456, 0.200004), Vector2(0.523456, 0.200004),
	Vector2(0.523456, 0.400004), Vector2(0.123456, 0.400004)]

var _epoch_before := 0


func before_test() -> void:
	_epoch_before = AiActRecorder.rules_epoch


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch_before


## The real terrain overlay (never added to the tree) holding the given container edges.
func _overlay(corners: Array) -> Node3D:
	var ovl: Node3D = auto_free(OverlayScript.new())
	var edges: Array = []
	for i in range(corners.size()):
		edges.append([corners[i], corners[(i + 1) % corners.size()]])
	ovl.set("_blocker_edges", edges)
	return ovl


## The stash through the script's method list, so a missing helper fails on an assertion, not on parsing.
func _stash(ovl: Node) -> Dictionary:
	for m in ArenaMatch.get_script_method_list():
		if str(m["name"]) == "trail_terrain":
			return ArenaMatch.call("trail_terrain", ovl)
	return {}


func _snap(v: Vector2) -> Array:
	return [snappedf(v.x, 0.0001), snappedf(v.y, 0.0001)]


func test_one_container_exports_its_four_edges_as_ledges_and_keeps_them_as_walls_at_epoch_72_and_73() -> void:
	for epoch in [AiActRecorder.EPOCH_72_PLAYTEST_RULES, AiActRecorder.EPOCH_73_V36]:
		AiActRecorder.rules_epoch = epoch
		var stash := _stash(_overlay(CORNERS))
		var walls: Array = stash.get("walls", [])
		var ledges: Array = stash.get("ledges", [])
		assert_int(ledges.size()) \
			.override_failure_message("epoch %d: the stash must carry the container's 4 ledges, got %s" % [epoch, stash]) \
			.is_equal(4)
		assert_int(walls.size()) \
			.override_failure_message("epoch %d: the 4 container edges must stay walls, got %s" % [epoch, stash]) \
			.is_equal(4)
		if ledges.size() != 4 or walls.size() != 4:
			return
		for i in range(4):
			var a := _snap(CORNERS[i])
			var b := _snap(CORNERS[(i + 1) % 4])
			assert_array(walls[i] as Array).is_equal([a, b])
			assert_array((ledges[i] as Array).slice(0, 2)).is_equal(walls[i] as Array)
			assert_float(float((ledges[i] as Array)[2])).is_equal_approx(TerrainRules.CONTAINER_HEIGHT_INCHES, 0.0001)


func test_a_board_without_containers_exports_an_empty_ledge_list_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var stash := _stash(_overlay([]))
	assert_bool(stash.has("ledges")) \
		.override_failure_message("climbing is on: the stash must carry a ledges key, got %s" % [stash]) \
		.is_true()
	assert_array(stash.get("ledges", [0]) as Array).is_empty()
	assert_array(stash.get("walls", [0]) as Array).is_empty()


func test_climbing_off_exports_the_walls_and_no_ledges_key_at_epoch_69() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_70_TRAY_EXACT - 1
	var stash := _stash(_overlay(CORNERS))
	assert_int((stash.get("walls", []) as Array).size()) \
		.override_failure_message("climbing off: the 4 container edges are walls, got %s" % [stash]) \
		.is_equal(4)
	assert_bool(stash.has("ledges")) \
		.override_failure_message("climbing off: no ledges key, got %s" % [stash]) \
		.is_false()
