extends GdUnitTestSuite
## Rules 3.6 wave, row UX-19 (F10, ruling D-PERMODEL): the Hit & Run family's post-attack step needs EVERY
## model of the activating unit to carry the rule, joined heroes included. Below EPOCH_73_V36 the host's own
## rules decide alone, exactly as before. A unit where only some models carry it stays put and leaves one
## battle-log line naming the rule (SoloController.last_hit_and_run_note, which main.gd logs). The core's
## twin is core/nml-core/src/tests/sim/v36_ux.rs.

var _epoch0: int


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch
	MovementPlanner.fast_planner = false
	MovementPlanner.fast_planner_guard = MovementPlanner.FAST_PLANNER_GUARD


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0   # statics leak across gdUnit tests - restore


## A gf/orc_marauders unit (the book fields Hit & Run, so the registry gate answers yes).
func _unit(pid: int, positions: Array, rules: Array) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = "p%d_%d" % [pid, positions.size()]
	u.unit_properties = {"player_id": pid, "name": "U%d" % pid, "quality": 4, "defense": 4,
		"special_rules": rules, "game_system": "gf", "faction_folder": "orc_marauders"}
	for p in positions:
		var m := ModelInstance.new()
		m.is_alive = true
		var n := Node3D.new()
		add_child(n)
		n.global_position = p
		m.node = n
		u.models.append(m)
	return u


## An AI host of two models with a joined hero, 0.5 m from one human unit. Returns [solo, host, hero].
func _joined(host_rules: Array, hero_rules: Array) -> Array:
	var human := _unit(1, [Vector3(0, 0, 0)], [])
	var host := _unit(2, [Vector3(0.5, 0, 0), Vector3(0.53, 0, 0)], host_rules)
	host.unit_id = "host"
	host.unit_properties["name"] = "Raiders"
	var hero := _unit(2, [Vector3(0.56, 0, 0)], ["Hero"] + hero_rules)
	hero.unit_id = "hero"
	EquipmentDistributor.attach_hero_to_unit(hero, host)
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {human.unit_id: human, host.unit_id: host, hero.unit_id: hero}
	army.current_round = 1
	var solo: SoloController = auto_free(SoloController.new())
	add_child(solo)
	solo.setup(army, null, null, 1, 2)
	return [solo, host, hero]


## The refusal line, read by name so this suite also runs where the field does not exist yet.
func _note(solo: SoloController) -> String:
	var note: Variant = solo.get("last_hit_and_run_note")
	return note if note is String else ""


func test_host_with_hit_and_run_and_a_joined_hero_without_it_still_steps_at_epoch_72() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var j := _joined(["Hit & Run"], [])
	assert_bool((j[0] as SoloController).hit_and_run_move(j[1], true)) \
		.override_failure_message("below the 3.6 epoch the host alone decides, as before").is_true()
	assert_str(_note(j[0])).is_empty()


func test_host_with_hit_and_run_and_a_joined_hero_without_it_stays_put_and_says_why_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var j := _joined(["Hit & Run"], [])
	var hero := j[2] as GameUnit
	var hero_at: Vector3 = hero.models[0].node.global_position
	assert_bool((j[0] as SoloController).hit_and_run_move(j[1], true)) \
		.override_failure_message("the hero lacks the rule, so the unit may not step").is_false()
	assert_vector(hero.models[0].node.global_position).is_equal(hero_at)
	assert_int(int((j[1] as GameUnit).unit_properties.get("hit_and_run_round", -1))).is_equal(-1)
	assert_str(_note(j[0])).is_equal("Hit & Run: Raiders stays put - not every model in the unit has the rule")


func test_hit_and_run_on_the_joined_hero_alone_stays_silent_at_epoch_72() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var j := _joined([], ["Hit & Run"])
	assert_bool((j[0] as SoloController).hit_and_run_move(j[1], true)).is_false()
	assert_str(_note(j[0])).is_empty()


func test_hit_and_run_on_the_joined_hero_alone_stays_put_and_says_why_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var j := _joined([], ["Hit & Run"])
	assert_bool((j[0] as SoloController).hit_and_run_move(j[1], true)).is_false()
	assert_str(_note(j[0])) \
		.override_failure_message("rules-must-log: one carrier among the models leaves no line today") \
		.is_equal("Hit & Run: Raiders stays put - not every model in the unit has the rule")


func test_hit_and_run_steps_when_every_model_carries_it_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var j := _joined(["Hit & Run"], ["Hit & Run"])
	var hero := j[2] as GameUnit
	var hero_at: Vector3 = hero.models[0].node.global_position
	assert_bool((j[0] as SoloController).hit_and_run_move(j[1], true)).is_true()
	assert_float(hero.models[0].node.global_position.distance_to(hero_at)).is_greater(0.001)
	assert_str(_note(j[0])).is_empty()
