extends GdUnitTestSuite
## Rules 3.6 wave, row MEL-08: strike reach. From EPOCH_73_V36 a model strikes when it stands within 3" of an
## enemy model across the table and within 3" up or down; the 3.5 records (epoch 72 and below) keep 2" across
## and 4" up. Both legs are pinned on every path that counts strikers: the table's base-edge count, its
## centre-space twin and the solo sim's point-model count.

const INCH: float = SoloController.INCHES_TO_METERS
const BASES_M := 0.025   # two 25 mm round bases: centre distance = edge gap + 25 mm

var _saved_epoch: int


func before_test() -> void:
	_saved_epoch = AiActRecorder.rules_epoch


func after_test() -> void:
	AiActRecorder.rules_epoch = _saved_epoch


func _unit(pid: int, pos: Vector3) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = "mel08_p%d" % pid
	u.unit_properties = {"player_id": pid, "name": "U%d" % pid, "quality": 4, "defense": 4, "base_size_round": 25}
	var m := ModelInstance.new()
	m.is_alive = true
	var n := Node3D.new()
	add_child(n)
	n.global_position = pos
	m.node = n
	m.unit = u
	u.models.append(m)
	return u


## The table's real-game count (base edge to base edge) for one striker `edge_gap_in` across and
## `height_in` above one enemy model.
func _table_strikers(edge_gap_in: float, height_in: float) -> int:
	var solo: SoloController = auto_free(SoloController.new())
	add_child(solo)
	var striker := _unit(1, Vector3(0.0, height_in * INCH, 0.0))
	var enemy := _unit(2, Vector3(edge_gap_in * INCH + BASES_M, 0.0, 0.0))
	return solo.striking_models_for(striker, enemy)


func test_a_model_2_5in_from_the_enemy_base_strikes_at_epoch_73_not_at_epoch_72() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	assert_int(_table_strikers(2.5, 0.0)) \
		.override_failure_message("epoch 72 keeps the 2\" reach: a model 2.5\" away does not strike") \
		.is_equal(0)
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	assert_int(_table_strikers(2.5, 0.0)) \
		.override_failure_message("epoch 73 reaches 3\": a model 2.5\" away strikes") \
		.is_equal(1)


func test_a_model_3_5in_above_the_enemy_strikes_at_epoch_72_not_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	assert_int(_table_strikers(0.0, 3.5)) \
		.override_failure_message("epoch 72 keeps the 4\" vertical reach: a model 3.5\" above strikes") \
		.is_equal(1)
	assert_bool(SoloController.within_melee_height(0.0, 3.5 * INCH)).is_true()
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	assert_int(_table_strikers(0.0, 3.5)) \
		.override_failure_message("epoch 73 reaches 3\" up: a model 3.5\" above does not strike") \
		.is_equal(0)
	assert_bool(SoloController.within_melee_height(0.0, 3.5 * INCH)).is_false()
	assert_bool(SoloController.within_melee_height(0.0, 3.0 * INCH)).is_true()


## The centre-space twin folds the 1" base contact onto the reach: 3.5" centre to centre is 2.5" out.
func test_the_centre_space_count_reaches_2_5in_at_epoch_73_not_at_epoch_72() -> void:
	var striker := [Vector3(3.5 * INCH, 0.0, 0.0)]
	var enemy := [Vector3(0.0, 0.0, 0.0)]
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	assert_int(SoloController.striking_models(striker, enemy)).is_equal(0)
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	assert_int(SoloController.striking_models(striker, enemy)).is_equal(1)


## The solo sim's points sit CONTACT_IN apart at base contact: 2.5" past contact strikes only under 3.6.
func test_the_solo_sim_reaches_2_5in_at_epoch_73_not_at_epoch_72() -> void:
	var striker: Dictionary = SoloSim.make_unit("Mob", 0, 4, 4, 1, [])
	var defender: Dictionary = SoloSim.make_unit("Foe", 1, 4, 4, 1, [])
	defender["model_pos"] = [Vector2(20, 20)]
	striker["model_pos"] = [Vector2(20, 20.0 - (SoloSim.CONTACT_IN + 2.5))]
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	assert_int(SoloSim._striking_models(striker, defender)).is_equal(0)
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	assert_int(SoloSim._striking_models(striker, defender)).is_equal(1)
