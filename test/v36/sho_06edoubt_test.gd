extends GdUnitTestSuite
## Rules 3.6 row SHO-06e-doubt (audit doubt): the live table's AI must price a MOVED Artillery
## target as moved — `moved_round == current_round` drops the target's -1 — and an unmoved one as
## held. `AiEv.ctx_for` defaults held = true, so before the fix the table never read the move.
## Epoch 72 keeps the old over-9" numbers.

const IN2M := 0.0254

## 10 Quality-4 attacks into Defense 4+.
const FREE := 2.5
const ONE_MINUS := 10.0 / 3.0 * 0.5     # 5+ to hit
const TWO_MINUS := 10.0 / 6.0 * 0.5     # 6+ to hit

var _epoch0: int


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch


func after_test() -> void:
	# statics leak across gdUnit tests — restore
	AiActRecorder.rules_epoch = _epoch0
	RulesRegistry.reset_cache()


func _unit(pid: int, unit_name: String, positions: Array, rules: Array = [],
		weapons: Array = []) -> GameUnit:
	var unit := GameUnit.new()
	unit.unit_id = unit_name.to_lower().replace(" ", "_")
	unit.unit_properties = {"player_id": pid, "name": unit_name, "quality": 4, "defense": 4,
		"special_rules": rules, "game_system": "gf", "faction_folder": "machine_cults"}
	for position in positions:
		var model := ModelInstance.new()
		model.is_alive = true
		model.wounds_current = 1
		model.unit = unit
		var node := Node3D.new()
		add_child(node)
		node.global_position = position
		model.node = node
		unit.models.append(model)
	var opr := OPRApiClient.OPRUnit.new()
	for w in weapons:
		var ow := OPRApiClient.OPRWeapon.new()
		ow.name = str((w as Dictionary).get("name", "W"))
		ow.range_value = int((w as Dictionary).get("range", 0))
		ow.attacks = int((w as Dictionary).get("attacks", 4))
		ow.count = 1
		opr.weapons.append(ow)
	unit.source_type = "opr"
	unit.source_data = opr
	return unit


func _controller(units: Array) -> SoloController:
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	for unit in units:
		army.game_units[(unit as GameUnit).unit_id] = unit
	army.current_round = 1
	var solo: SoloController = auto_free(SoloController.new())
	add_child(solo)
	solo.setup(army, null, null, 1, 2)
	return solo


func _rifle() -> Array:
	return [{"name": "Rifle", "range": 24, "attacks": 10}]


func _gun(unit_name: String, x_in: float) -> GameUnit:
	return _unit(1, unit_name, [Vector3(x_in * IN2M, 0.0, 0.0)], ["Artillery"])


## The table's moved stamp: `moved_round == current_round` (army round 1 here).
func _mark_moved(unit: GameUnit) -> void:
	unit.unit_properties["moved_round"] = 1


func test_an_unmoved_artillery_target_keeps_its_minus_one_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var shooter := _unit(2, "Shooter", [Vector3.ZERO], [], _rifle())
	var unmoved := _gun("Unmoved", 13.0)
	var solo := _controller([shooter, unmoved])
	assert_float(solo._shoot_ev_now(shooter, unmoved, 13.0)) \
		.override_failure_message("an unmoved gun over 12\" takes the 3.6 -1") \
		.is_equal_approx(ONE_MINUS, 0.0001)


func test_a_moved_artillery_target_drops_its_minus_one_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var shooter := _unit(2, "Shooter", [Vector3.ZERO], [], _rifle())
	var moved := _gun("Moved", 13.0)
	_mark_moved(moved)
	var solo := _controller([shooter, moved])
	assert_float(solo._shoot_ev_now(shooter, moved, 13.0)) \
		.override_failure_message("a move takes the target -1 away (the table read held = true)") \
		.is_equal_approx(FREE, 0.0001)


func test_the_ai_target_picker_prefers_a_moved_artillery_target_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var shooter := _unit(2, "Shooter", [Vector3.ZERO], [], _rifle())
	var unmoved := _gun("Unmoved", 13.0)
	var moved := _gun("Moved", -13.0)
	_mark_moved(moved)
	var solo := _controller([shooter, unmoved, moved])
	# Equal official key (same band, not activated, open): the EV tie-break decides, and the
	# moved gun is the easier shot.
	assert_object(solo.best_shoot_target_now(shooter, true)) \
		.override_failure_message("the picker priced the moved gun as held") \
		.is_same(moved)


func test_the_ai_target_picker_keeps_the_first_of_two_unmoved_guns_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var shooter := _unit(2, "Shooter", [Vector3.ZERO], [], _rifle())
	var first := _gun("First", 13.0)
	var second := _gun("Second", -13.0)
	var solo := _controller([shooter, first, second])
	assert_object(solo.best_shoot_target_now(shooter, true)) \
		.override_failure_message("two identical held guns must tie and keep the first") \
		.is_same(first)


func test_epoch_72_keeps_the_old_target_price_for_a_moved_gun() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var shooter := _unit(2, "Shooter", [Vector3.ZERO], [], _rifle())
	var moved := _gun("Moved", 13.0)
	_mark_moved(moved)
	var solo := _controller([shooter, moved])
	assert_float(solo._shoot_ev_now(shooter, moved, 13.0)) \
		.override_failure_message("below 73 the old over-9\" -2 stays byte for byte") \
		.is_equal_approx(TWO_MINUS, 0.0001)
