extends GdUnitTestSuite
## Rules 3.6 row UX-21: Dangerous terrain. A price that rolls at 73 rolls one die per WOUND THE WHOLE JOINED
## UNIT HAS LEFT - the sum of every living model's current wounds, host and attached heroes alike - and not
## one die per model's full Tough value any more. Epoch 72 keeps the Tough count. `dangerous_dice_for` is the
## one function the move, the standing activation, the move report and the destroyed-transport spill read.

const IN2M := 0.0254

var _mgr: OPRArmyManager
var _epoch0: int


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch
	_mgr = auto_free(OPRArmyManager.new())


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0   # statics leak across gdUnit tests - restore


## `n` models along x, 1.5" apart from x = `x0_in`, at z = 0. Each model has `tough` max wounds and keeps
## `current` of them.
func _unit(id: String, n: int, x0_in: float, tough: int = 1, current: int = -1) -> GameUnit:
	var u: GameUnit = auto_free(GameUnit.new())
	u.unit_id = id
	u.unit_properties = {"player_id": 2, "special_rules": [], "name": id, "quality": 4, "defense": 4}
	if current < 0:
		current = tough
	for i in range(n):
		var m := ModelInstance.new()
		m.unit = u
		m.is_alive = true
		m.wounds_max = tough
		m.wounds_current = current
		m.node = auto_free(Node3D.new())
		add_child(m.node)
		m.node.global_position = Vector3((x0_in + float(i) * 1.5) * IN2M, 0, 0)
		u.models.append(m)
	_mgr.game_units[id] = u
	return u


## One Tough(6) model that already lost four wounds (two left).
func _hurt_tough_six() -> GameUnit:
	return _unit("Hurt", 1, 0.0, 6, 2)


## Three full-health one-wound models plus a joined Tough(3) hero that lost one wound (two left).
func _host_and_hurt_hero() -> GameUnit:
	var host := _unit("Host", 3, 0.0)
	var hero := _unit("Hero", 1, 6.0, 3, 2)
	host.unit_properties["attached_heroes"] = [hero]
	hero.unit_properties["attached_to"] = host
	return host


func _dice(unit: GameUnit, epoch: int) -> int:
	AiActRecorder.rules_epoch = epoch
	return OPRArmyManager.dangerous_dice_for(unit)


func test_a_hurt_tough_six_model_rolls_six_dice_at_epoch_72() -> void:
	assert_int(_dice(_hurt_tough_six(), AiActRecorder.EPOCH_72_PLAYTEST_RULES)).is_equal(6)


func test_a_hurt_tough_six_model_rolls_its_wounds_left_at_epoch_73() -> void:
	assert_int(_dice(_hurt_tough_six(), AiActRecorder.EPOCH_73_V36)) \
		.override_failure_message("a Tough(6) model with two wounds left rolls two dice at 73") \
		.is_equal(2)


func test_a_joined_hurt_hero_sums_full_tough_at_epoch_72() -> void:
	assert_int(_dice(_host_and_hurt_hero(), AiActRecorder.EPOCH_72_PLAYTEST_RULES)).is_equal(3)


func test_a_joined_hurt_hero_sums_wounds_left_at_epoch_73() -> void:
	assert_int(_dice(_host_and_hurt_hero(), AiActRecorder.EPOCH_73_V36)) \
		.override_failure_message("host three wounds + hero two wounds in one test") \
		.is_equal(5)
