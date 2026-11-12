extends GdUnitTestSuite
## E3 (EPOCH_76_MOVE_FIXES): Grounded Speed (aof volcanic_dwarves, +2"/+4" while most of the unit stands within 1"
## of terrain at activation) asks the MAJORITY of the unit, as the core does (sim.rs grounded_speed_bonus_in). The
## table's AI used to build the board from its first alive model alone, so whenever that model and the majority
## disagreed the AI moved 2"/4" more or less than the core. Below 76 the first model still decides (replays).

const MovementScript := preload("res://scripts/movement_range_controller.gd")

var _epoch0 := 0


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0


## A three-model Grounded Speed unit on 25 mm bases at the given x (metres); terrain fills x >= 0.03 m, so a model
## at 0 reaches it with its base plus the rule's 1" and a model at -0.2 or below does not.
func _bands(xs: Array, epoch: int) -> Dictionary:
	AiActRecorder.rules_epoch = epoch
	var u := GameUnit.new()
	u.unit_id = "dwarves"
	u.unit_properties = {"player_id": 2, "name": "Dwarves", "game_system": "aof", "faction_folder": "volcanic_dwarves",
		"special_rules": ["Grounded Speed"], "base_size_round": 25}
	for x in xs:
		var m := ModelInstance.new()
		m.is_alive = true
		m.wounds_current = 1
		m.unit = u
		var n: Node3D = auto_free(Node3D.new())
		add_child(n)
		n.global_position = Vector3(float(x), 0.0, 0.0)
		n.set_meta("game_unit", u)
		m.node = n
		u.models.append(m)
	var mrc: MovementRangeController = auto_free(MovementScript.new())
	add_child(mrc)
	mrc._terrain_at = func(p: Vector3) -> int: return TerrainRules.TerrainType.RUINS if p.x >= 0.03 else TerrainRules.TerrainType.NONE
	return SoloController.move_bands_for_unit(u, mrc)


func test_one_of_three_near_terrain_is_no_majority_from_epoch_76() -> void:
	var b := _bands([0.0, -0.2, -0.4], AiActRecorder.EPOCH_76_MOVE_FIXES)
	assert_int(int(b["advance"])) \
		.override_failure_message("only the first of three models is near terrain, yet the unit got +%d\"" % (int(b["advance"]) - 6)) \
		.is_equal(6)
	assert_int(int(b["rush"])).is_equal(12)


func test_two_of_three_near_terrain_get_the_bonus_from_epoch_76() -> void:
	var b := _bands([-0.4, 0.0, 0.005], AiActRecorder.EPOCH_76_MOVE_FIXES)
	assert_int(int(b["advance"])).is_equal(8)
	assert_int(int(b["rush"])).is_equal(16)


## The below-76 leg (passes before and after the fix): a record stamped 75 lets the first alive model decide.
func test_at_epoch_75_the_first_model_decides() -> void:
	var first_near := _bands([0.0, -0.2, -0.4], AiActRecorder.EPOCH_76_MOVE_FIXES - 1)
	assert_int(int(first_near["advance"])).is_equal(8)
	assert_int(int(first_near["rush"])).is_equal(16)
	var first_far := _bands([-0.4, 0.0, 0.005], AiActRecorder.EPOCH_76_MOVE_FIXES - 1)
	assert_int(int(first_far["advance"])).is_equal(6)
	assert_int(int(first_far["rush"])).is_equal(12)
