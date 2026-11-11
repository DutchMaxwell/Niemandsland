extends GdUnitTestSuite
## Rules 3.6 row UX-20: Dangerous terrain. One affected model is enough - a model of the unit or of a hero
## joined to it that moves into or through the field, or is activated standing in it - and then the WHOLE
## joined unit takes ONE test. Each model still adds its Tough value in dice here; the wounds-left count is
## the next row (UX-21). The table rolls what these counts say (report["dangerous_dice"] and the transport
## spill both end in main._run_ai_dangerous). Every case pins one epoch: 72 keeps one test per affected
## model, 73 is new.

const IN2M := 0.0254

var _mgr: OPRArmyManager
var _solo: SoloController
var _epoch0: int


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch
	_mgr = auto_free(OPRArmyManager.new())
	_solo = auto_free(SoloController.new())
	add_child(_solo)
	_solo.army_manager = _mgr
	_solo.human_slot = 1
	_solo.ai_slot = 2
	# The field is everything at or left of x = 0: a base centred on that line stands in it.
	_solo.terrain_type_at = func(p: Vector3) -> int:
		return TerrainRules.TerrainType.DANGEROUS if p.x <= 0.0 else TerrainRules.TerrainType.NONE


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0   # statics leak across gdUnit tests - restore


## `n` models of Tough `tough` in a row along x, 1.5" apart from x = `x0_in`, at z = 0.
func _unit(id: String, n: int, x0_in: float, tough: int = 1) -> GameUnit:
	var u: GameUnit = auto_free(GameUnit.new())
	u.unit_id = id
	u.unit_properties = {"player_id": 2, "special_rules": [], "name": id, "quality": 4, "defense": 4}
	for i in range(n):
		var m := ModelInstance.new()
		m.unit = u
		m.is_alive = true
		m.wounds_max = tough
		m.wounds_current = tough
		m.node = auto_free(Node3D.new())
		add_child(m.node)
		m.node.global_position = Vector3((x0_in + float(i) * 1.5) * IN2M, 0, 0)
		u.models.append(m)
	_mgr.game_units[id] = u
	return u


## Ten one-wound models; only the first one stands in the field.
func _ten_one_clipping() -> GameUnit:
	return _unit("Ten", 10, 0.0)


## Ten one-wound models all clear of the field, and a Tough(3) hero joined to them that alone stands in it.
func _host_with_hero_clipping() -> GameUnit:
	var host := _unit("Host", 10, 1.5)
	var hero := _unit("Hero", 1, 0.0, 3)
	host.unit_properties["attached_heroes"] = [hero]
	hero.unit_properties["attached_to"] = host
	return host


## The dice of the activated-in-it test (a unit that holds or idles where it stands).
func _standing_dice(unit: GameUnit, epoch: int) -> int:
	AiActRecorder.rules_epoch = epoch
	return int(_solo._dangerous_standing_counts(unit)["dice"])


## The dice of a 6" move away from the field, the first model starting in it.
func _move_dice(unit: GameUnit, epoch: int) -> int:
	AiActRecorder.rules_epoch = epoch
	_solo._execute_move(unit, Vector3(6.75 * IN2M, 0, 12.0 * IN2M), 6.0, false)
	return _solo.last_dangerous_dice


func test_one_clipping_model_of_ten_rolls_its_own_die_at_epoch_72() -> void:
	assert_int(_standing_dice(_ten_one_clipping(), AiActRecorder.EPOCH_72_PLAYTEST_RULES)).is_equal(1)


func test_one_clipping_model_of_ten_makes_the_whole_unit_test_at_epoch_73() -> void:
	assert_int(_standing_dice(_ten_one_clipping(), AiActRecorder.EPOCH_73_V36)) \
		.override_failure_message("one model in the field: the whole ten-model unit tests once") \
		.is_equal(10)


func test_one_clipping_model_of_ten_on_the_move_rolls_its_own_die_at_epoch_72() -> void:
	assert_int(_move_dice(_ten_one_clipping(), AiActRecorder.EPOCH_72_PLAYTEST_RULES)).is_equal(1)


func test_one_clipping_model_of_ten_on_the_move_makes_the_whole_unit_test_at_epoch_73() -> void:
	assert_int(_move_dice(_ten_one_clipping(), AiActRecorder.EPOCH_73_V36)) \
		.override_failure_message("one model crossing the field: the whole ten-model unit tests once") \
		.is_equal(10)


func test_a_joined_hero_alone_in_it_tests_on_its_own_at_epoch_72() -> void:
	assert_int(_standing_dice(_host_with_hero_clipping(), AiActRecorder.EPOCH_72_PLAYTEST_RULES)).is_equal(3)


func test_a_joined_hero_alone_in_it_makes_the_joined_unit_test_at_epoch_73() -> void:
	assert_int(_standing_dice(_host_with_hero_clipping(), AiActRecorder.EPOCH_73_V36)) \
		.override_failure_message("the hero is part of the unit: host ten + hero three in one test") \
		.is_equal(13)


func test_a_wrecked_transports_cargo_tests_without_its_joined_hero_at_epoch_72() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	assert_int(OPRArmyManager.dangerous_dice_for(_host_with_hero_clipping())).is_equal(10)


func test_a_wrecked_transports_cargo_tests_as_one_joined_unit_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	assert_int(OPRArmyManager.dangerous_dice_for(_host_with_hero_clipping())) \
		.override_failure_message("the spilled unit tests with its joined hero, in one test") \
		.is_equal(13)
