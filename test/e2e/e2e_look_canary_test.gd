extends GdUnitTestSuite
## The canary of CI's LOOK short run (tools/ci_path_classes.py CANARY; PLAN_CI_THROUGHPUT step 7).
##
## A PR that changes only board-look files runs only the class suites and THIS suite. So this suite must see what a
## class suite cannot: that the real game still boots (a class file that breaks scripts/main.gd through its one door does
## not compile it), and that no board-look code has switched itself on in a game nobody asked it to. Real: scenes/main.tscn.
##
## Not named here on purpose: the class's symbols and its env flag (tools/ci_path_classes.py --check keeps them out of
## every file outside the class); the checks go by node name prefix, group, collider and the ground probe instead.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func test_the_real_game_boots_and_no_board_look_is_on_the_table() -> void:
	assert_object(_main).is_not_null()
	assert_object(_main.object_manager).is_not_null()
	# (1) no board-look node anywhere in the running game
	var named: Array = []
	for n in _main.find_children("Boardgen*", "", true, false):
		named.append(str(n.get_path()))
	assert_array(named).override_failure_message("a board-look node is on the table of a plain game: %s" % [named]).is_empty()
	# (2) nothing in the group the table keeps through a resize carries a collider (the board look builds ground colliders)
	var armed: Array = []
	for n in get_tree().get_nodes_in_group("table_overlay"):
		if n is CollisionObject3D:
			armed.append(str(n.get_path()))
		for c in n.find_children("*", "CollisionObject3D", true, false):
			armed.append(str(c.get_path()))
	assert_array(armed).override_failure_message("a table_overlay member carries colliders: %s" % [armed]).is_empty()
	# (3) the ground a model is set down on is the bare table across the board's whole footprint (object_manager probes the
	# same physics layer the board look would fill with solid boxes)
	var risen: Array = []
	for ix in range(-3, 4):
		for iz in range(-3, 4):
			var y: float = _main.object_manager._surface_y_under(Vector3(ix * 0.18, 0.0, iz * 0.18))
			if y > 0.005:
				risen.append("%d,%d -> %.3f" % [ix, iz, y])
	assert_array(risen).override_failure_message("the ground is not the bare table: %s" % [risen]).is_empty()
