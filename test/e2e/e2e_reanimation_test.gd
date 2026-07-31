extends GdUnitTestSuite
## E2E — Reanimation (army-book, Robot Legions 3.5.2: "When a unit where all models have this rule is
## activated, roll as many dice as the max. number of models/wounds it could restore. For each 5+ you
## may restore one model/wound. Note that new models may only be restored if they can be placed in
## coherency with non-restored models."). The rule reaches the table only through the hero upgrade
## "Reanimation Aura" ("This model and its unit get Reanimation").
##
## The suite drives the REAL main.tscn flow: the activation trigger, the round stamp that keeps the
## human side's many activation doors to ONE roll, the Shaken refusal, the aura ending with its
## carrier, and the coherency gate that lets a success expire. The dice themselves are the only part
## a test cannot pin, so the roll and the allocation are separate functions and every log line is
## asserted with fixed successes.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	# Batch dice: _solo_tray_roll draws faces from the RNG instead of awaiting the physics tray,
	# which headless would never settle.
	_main._solo_batch = true


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _log_text() -> String:
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


func _count(needle: String) -> int:
	var n := 0
	for e in _main.battle_log.entries():
		if str((e as Dictionary)["text"]).contains(needle):
			n += 1
	return n


func _reg(u: GameUnit) -> GameUnit:
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## A reanimating unit: `count` models on a 0.5" line, the trailing `dead` of them fallen.
func _bots(unit_name: String, count: int, dead: int, tough: int = 1) -> GameUnit:
	var spots: Array = []
	for i in count:
		spots.append(Vector3(float(i) * 0.5 * INCH, 0, 0))
	var u := _reg(E2EBoot.make_unit(_main, 2, unit_name, spots))
	u.unit_properties["special_rules"] = ["Reanimation"]
	u.unit_properties["faction_folder"] = "robot_legions"
	for i in count:
		var m := u.models[i] as ModelInstance
		m.model_index = i
		m.wounds_max = tough
		m.wounds_current = tough
		if i >= count - dead:
			m.wounds_current = 0
			m.is_alive = false
	return u


func test_activation_rolls_the_missing_wounds_and_stamps_the_round() -> void:
	var u := _bots("Bots", 4, 2)
	await _main._solo_try_reanimation(u)
	assert_int(int(u.unit_properties.get("reanimated_round", -1))) \
		.override_failure_message("the activation trigger must burn its once-per-round stamp") \
		.is_equal(_main.opr_army_manager.current_round)
	assert_str(_log_text()) \
		.override_failure_message("every applied rule needs its battle-log line:\n%s" % _log_text()) \
		.contains("Reanimation: Bots rolls 2 dice (5+)")
	# ROT-Fall (1): a second door in the SAME round must not roll again — the stamp is the guard.
	await _main._solo_try_reanimation(u)
	assert_int(_count("Reanimation: Bots rolls")) \
		.override_failure_message("only the FIRST activation door may roll") \
		.is_equal(1)
	# A new round re-arms it. Re-open the pool first: the round-1 roll may have HEALED the
	# deficit (5+ luck), and a whole unit legitimately does not roll — which is not what
	# this case tests (CI flake: the assert below raced the dice).
	_main.opr_army_manager.current_round += 1
	var m0 := u.models[3] as ModelInstance
	m0.wounds_current = 0
	m0.is_alive = false
	await _main._solo_try_reanimation(u)
	assert_int(_count("Reanimation: Bots rolls")).is_greater(1)


func test_successes_bring_models_back_in_coherency_and_log_the_line() -> void:
	var u := _bots("Bots", 4, 2)
	_main._solo_resolve_reanimation(u, 2, 5, 2)
	assert_int(u.get_alive_count()) \
		.override_failure_message("two successes must return both casualties") \
		.is_equal(4)
	for i in 4:
		assert_bool((u.models[i] as ModelInstance).is_alive).is_true()
	# Wound currency: a returned model stands up with exactly the ONE wound its success bought.
	assert_int((u.models[3] as ModelInstance).wounds_current).is_equal(1)
	assert_str(_log_text()).contains("2 model(s), 0 wound(s) restored")
	# Coherency: every returned model touches a survivor (1" base edge to base edge).
	var result := CoherencyChecker.check_unit_coherency(u)
	assert_bool(result.valid) \
		.override_failure_message("restored models must stand in coherency with the unit") \
		.is_true()


func test_living_wounds_are_topped_up_before_the_dead_come_back() -> void:
	var u := _bots("Elites", 3, 1, 3)
	(u.models[0] as ModelInstance).wounds_current = 1   # 2 wounds missing on a living Tough(3)
	assert_int(SoloController.reanimation_pool(u)).is_equal(2 + 3)
	_main._solo_resolve_reanimation(u, 5, 5, 2)
	assert_int((u.models[0] as ModelInstance).wounds_current) \
		.override_failure_message("living wounded are filled first (v1 automatic allocation)") \
		.is_equal(3)
	assert_bool((u.models[2] as ModelInstance).is_alive).is_false()
	assert_str(_log_text()).contains("0 model(s), 2 wound(s) restored")


func test_a_shaken_unit_does_not_reanimate_and_says_so() -> void:
	# ROT-Fall (3): the Shaken activation stays idle (GF v3.5.1 p.10) — that includes this trigger.
	var u := _bots("Shaky", 4, 2)
	u.is_shaken = true
	await _main._solo_try_reanimation(u)
	assert_int(u.get_alive_count()).is_equal(2)
	assert_str(_log_text()).contains("Reanimation: Shaky does not reanimate — Shaken (activation stays idle)")
	assert_int(_count("Reanimation: Shaky rolls")) \
		.override_failure_message("a Shaken unit may not roll at all") \
		.is_equal(0)


func test_the_aura_ends_with_its_carrier_and_a_prefix_lookalike_never_fires() -> void:
	# ROT-Fall (2): the unit carries "Reanimation" only because the import expanded the hero's aura.
	var host := _bots("Legion", 4, 2)
	host.unit_properties["aura_granted"] = ["Reanimation"]
	var hero := _reg(E2EBoot.make_unit(_main, 2, "ReAnimator", [Vector3(-0.5 * INCH, 0, 0)]))
	hero.unit_properties["special_rules"] = ["Hero", "Reanimation Aura", "Reanimation"]
	hero.unit_properties["aura_granted"] = ["Reanimation"]
	hero.unit_properties["faction_folder"] = "robot_legions"
	host.unit_properties["attached_heroes"] = [hero]
	await _main._solo_try_reanimation(host)
	assert_int(_count("Reanimation: Legion rolls")) \
		.override_failure_message("a living Re-Animator projects the rule over his unit") \
		.is_equal(1)
	# The Re-Animator falls. GameUnit.has_special_rule would STILL answer true for "Reanimation"
	# (prefix match on his own "Reanimation Aura"); the exact gate must close anyway.
	(hero.models[0] as ModelInstance).is_alive = false
	(hero.models[0] as ModelInstance).wounds_current = 0
	assert_bool(hero.has_special_rule("Reanimation")).is_true()   # fixture check: the prefix trap
	_main.opr_army_manager.current_round += 1
	await _main._solo_try_reanimation(host)
	assert_int(_count("Reanimation: Legion rolls")) \
		.override_failure_message("an aura-granted rule must not outlive its carrier") \
		.is_equal(1)
	assert_str(_log_text()).contains("Reanimation Aura ends — ReAnimator has fallen; Legion loses Reanimation")
	# The notice is a once-per-unit line, not a per-activation nag.
	_main.opr_army_manager.current_round += 1
	await _main._solo_try_reanimation(host)
	assert_int(_count("Reanimation Aura ends")).is_equal(1)


func test_a_success_with_nowhere_legal_to_stand_expires_with_its_line() -> void:
	# ROT-Fall (4): "new models may only be restored if they can be placed in coherency with
	# non-restored models" — a casualty whose whole 1" neighbourhood is occupied stays down.
	var u := _bots("Boxed", 2, 1)
	# The casualty fell exactly onto its surviving comrade, and every ring position the placer would
	# try is taken by other bases: nowhere legal is left.
	(u.models[1] as ModelInstance).node.global_position = (u.models[0] as ModelInstance).node.global_position
	var anchor: Vector3 = (u.models[0] as ModelInstance).node.global_position
	var wall_spots: Array = []
	for ring in 2:
		var dist: float = 0.034 + float(ring) * (INCH * 0.5)
		for k in 16:
			var ang: float = TAU * float(k) / 16.0
			wall_spots.append(Vector3(anchor.x + cos(ang) * dist, anchor.y, anchor.z + sin(ang) * dist))
	_reg(E2EBoot.make_unit(_main, 1, "Wall", wall_spots))
	_main._solo_resolve_reanimation(u, 1, 5, 1)
	assert_bool((u.models[1] as ModelInstance).is_alive) \
		.override_failure_message("no coherent spot → the model stays down") \
		.is_false()
	assert_str(_log_text()).contains(
		"Reanimation: 1 successes but only 0 models placeable — coherency to non-restored models missing")


func test_a_full_strength_unit_rolls_nothing_at_all() -> void:
	var u := _bots("Intact", 3, 0)
	await _main._solo_try_reanimation(u)
	assert_int(_count("Reanimation: Intact")) \
		.override_failure_message("no shortfall = no dice and no log noise") \
		.is_equal(0)
	assert_int(int(u.unit_properties.get("reanimated_round", -1))).is_equal(-1)


func test_the_ai_pick_is_peeked_once_and_then_consumed() -> void:
	# The AI's trigger runs BEFORE the decision tree, so main peeks the pick. The peek must not
	# consume a second draw — otherwise every AI activation would skip a unit.
	var human := _reg(E2EBoot.make_unit(_main, 1, "Humans", [Vector3(20.0 * INCH, 0, 0)]))
	var ai := _bots("Bots", 3, 1)
	assert_object(human).is_not_null()
	var solo = _main.solo_controller
	var peeked = solo.peek_next_ai_unit()
	assert_object(peeked).is_equal(ai)
	assert_object(solo.peek_next_ai_unit()) \
		.override_failure_message("a repeated peek must return the SAME cached pick") \
		.is_equal(ai)
	assert_object(solo.activate_next_ai_unit()).is_equal(ai)
	assert_object(solo.activate_next_ai_unit()) \
		.override_failure_message("the peeked pick may only be activated once") \
		.is_null()
