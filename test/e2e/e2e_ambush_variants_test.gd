extends GdUnitTestSuite
## E2E — the three Ambush variants (army-book rules, wave 1), driven on the REAL main.tscn:
##
##   • Ambush Beacon      "Friendly units using Ambush may ignore distance restrictions from enemies
##                         if they are deployed within 6" of this model."
##   • Rapid Ambush       "Counts as having Ambush, but may be deployed at the start of any round,
##                         including the first."
##   • Ambush Re-Deployment
##                        "Once per game, when a unit where all models have this rule ends its
##                         activation, you may immediately remove it from the table (dropping any
##                         objectives it might hold within 1"), and deploy it as if it had Ambush at
##                         the beginning of the next round."
##
## MAINTAINER RULINGS under test: the beacon waiver also beats Repel Ambushers' 12" ("distance
## restrictions", plural), and the AI's Rapid Ambush may land in round 1.
##
## Every core claim carries its ROT case — the same machinery must REFUSE one step away (no beacon,
## no Rapid Ambush, use already spent, a joined hero without the rule). No assertion sits behind a
## dice roll: the arrivals and the withdrawal are deterministic placement/state code.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254
const TRAY := Vector3(5.0, 0.0, 0.0)   # far outside any table rect — the reserve tray side

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
	_main._solo_batch = true   # no dialogs, no physics tray in a headless sweep


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _reg(u: GameUnit) -> GameUnit:
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


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


## The whole 4x4 ft table as the arrival zone (the same rect main builds from table.table_size).
func _zone() -> Rect2:
	return Rect2(Vector2(-0.61, -0.61), Vector2(1.22, 1.22))


## Enemy no-go entries exactly as _solo_ambush_enemy_positions builds them (per model, edge-true).
func _enemy_entries(enemy: GameUnit, repel: bool = false) -> Array:
	var out: Array = []
	for m in enemy.get_alive_models():
		var mi := m as ModelInstance
		out.append({"pos": Vector2(mi.node.global_position.x, mi.node.global_position.z),
			"min_dist_m": (12.0 * INCH if repel else 0.0),
			"pad_m": SoloController.model_base_radius_m(mi)})
	return out


# === 1. Ambush Beacon =========================================================================

## The waiver itself: an AI ambusher lands next to a human enemy because a friendly beacon stands
## there — and the same arrival, with the beacon removed, is refused at that spot.
func test_beacon_lets_an_arrival_land_next_to_the_enemy_and_says_so() -> void:
	var solo = _main.solo_controller
	# The whole legal ground is ONE small pocket around the origin: an enemy sits at the centre, so
	# without the beacon the 9" ring covers the entire pocket and nothing can land inside it.
	var enemy := _reg(E2EBoot.make_unit(_main, 1, "Watchers", [Vector3.ZERO]))
	var beacon := _reg(E2EBoot.make_unit(_main, 2, "Relay", [Vector3(4.0 * INCH, 0, 0)]))
	beacon.unit_properties["special_rules"] = ["Ambush Beacon"]
	var ambusher := _reg(E2EBoot.make_unit(_main, 2, "Infiltrators", [TRAY]))
	ambusher.unit_properties["special_rules"] = ["Ambush"]
	ambusher.unit_properties["ambush_reserve"] = true
	solo.ambush_reserve = [ambusher]
	solo._deploy_objectives = [Vector2.ZERO]   # pull the search straight at the enemy

	var beacons: Array = solo.beacon_points(2)
	assert_int(beacons.size()) \
		.override_failure_message("fixture: the beacon carrier must project its circle") \
		.is_equal(1)
	var arrived: GameUnit = solo.arrive_one_ambush_unit(_zone(), _enemy_entries(enemy), [], 2, beacons)
	assert_object(arrived).is_equal(ambusher)
	var c: Vector3 = solo.unit_centre(ambusher)
	var gap_in: float = Vector2(c.x, c.z).length() / INCH
	assert_float(gap_in) \
		.override_failure_message("the beacon drop must actually be INSIDE the 9\" ring — otherwise nothing was waived") \
		.is_less(9.0)
	assert_float(Vector2(c.x, c.z).distance_to(Vector2(4.0 * INCH, 0.0)) / INCH) \
		.override_failure_message("the drop must lie within the beacon's 6\"") \
		.is_less_equal(6.01)
	assert_str(str(solo.last_arrival_note)) \
		.override_failure_message("rules-must-log: the applied waiver needs its own line") \
		.contains("Ambush Beacon: Infiltrators lands")
	assert_str(str(solo.last_arrival_note)).contains("distance restrictions waived (within 6\" of Relay)")


## ROT case for the case above: the SAME position, the SAME search — without a beacon the arrival is
## pushed out beyond the 9" ring. (Proves the waiver, not the placement search, did the work.)
func test_without_a_beacon_the_same_arrival_stays_outside_nine_inches() -> void:
	var solo = _main.solo_controller
	var enemy := _reg(E2EBoot.make_unit(_main, 1, "Watchers", [Vector3.ZERO]))
	var ambusher := _reg(E2EBoot.make_unit(_main, 2, "Infiltrators", [TRAY]))
	ambusher.unit_properties["special_rules"] = ["Ambush"]
	ambusher.unit_properties["ambush_reserve"] = true
	solo.ambush_reserve = [ambusher]
	solo._deploy_objectives = [Vector2.ZERO]
	var arrived: GameUnit = solo.arrive_one_ambush_unit(_zone(), _enemy_entries(enemy), [], 2, [])
	assert_object(arrived).is_equal(ambusher)
	var c: Vector3 = solo.unit_centre(ambusher)
	assert_float(Vector2(c.x, c.z).length() / INCH) \
		.override_failure_message("no beacon = the plain p.13 arrival: strictly more than 9\" from the enemy") \
		.is_greater(9.0)
	assert_str(str(solo.last_arrival_note)).is_empty()


## Maintainer ruling: "distance restrictions" is PLURAL — the beacon also beats an enemy's Repel
## Ambushers ("Enemy units using Ambush must be set up over 12" away from this model's unit").
func test_the_beacon_beats_repel_ambushers_twelve_inches() -> void:
	var solo = _main.solo_controller
	var enemy := _reg(E2EBoot.make_unit(_main, 1, "Wardens", [Vector3.ZERO]))
	enemy.unit_properties["special_rules"] = ["Repel Ambushers"]
	var beacon := _reg(E2EBoot.make_unit(_main, 2, "Relay", [Vector3(10.0 * INCH, 0, 0)]))
	beacon.unit_properties["special_rules"] = ["Ambush Beacon"]
	var ambusher := _reg(E2EBoot.make_unit(_main, 2, "Infiltrators", [TRAY]))
	ambusher.unit_properties["special_rules"] = ["Ambush"]
	ambusher.unit_properties["ambush_reserve"] = true
	solo.ambush_reserve = [ambusher]
	solo._deploy_objectives = [Vector2.ZERO]
	var arrived: GameUnit = solo.arrive_one_ambush_unit(_zone(), _enemy_entries(enemy, true), [], 2, solo.beacon_points(2))
	assert_object(arrived).is_equal(ambusher)
	var c: Vector3 = solo.unit_centre(ambusher)
	var gap_in: float = Vector2(c.x, c.z).length() / INCH
	assert_float(gap_in) \
		.override_failure_message("the beacon must waive the Repel Ambushers 12\" too, not only the base 9\"") \
		.is_less(12.0)
	assert_float(Vector2(c.x, c.z).distance_to(Vector2(10.0 * INCH, 0.0)) / INCH).is_less_equal(6.01)
	assert_str(str(solo.last_arrival_note)).contains("distance restrictions waived")


## Rules-must-log, the other direction: a beacon that stood close by and did NOT apply is named.
## The circle is deliberately unusable (a 7" no-go blob over it), so the beacon pass finds nothing and
## the normal search takes the spot 9" away — near enough that silence would look like a bug.
func test_a_beacon_that_did_not_apply_is_named() -> void:
	var solo = _main.solo_controller
	var enemy := _reg(E2EBoot.make_unit(_main, 1, "Watchers", [Vector3(0.5, 0, 0.5)]))
	var beacon := _reg(E2EBoot.make_unit(_main, 2, "Relay", [Vector3.ZERO]))
	beacon.unit_properties["special_rules"] = ["Ambush Beacon"]
	var ambusher := _reg(E2EBoot.make_unit(_main, 2, "Infiltrators", [TRAY]))
	ambusher.unit_properties["special_rules"] = ["Ambush"]
	ambusher.unit_properties["ambush_reserve"] = true
	solo.ambush_reserve = [ambusher]
	solo._deploy_objectives = [Vector2(9.0 * INCH, 0.0)]
	var occupied: Array = [{"pos": Vector2.ZERO, "radius": 7.0 * INCH}]   # nothing fits inside the circle
	var arrived: GameUnit = solo.arrive_one_ambush_unit(_zone(), _enemy_entries(enemy), occupied, 2, solo.beacon_points(2))
	assert_object(arrived).is_equal(ambusher)
	var c: Vector3 = solo.unit_centre(ambusher)
	var dist_in: float = Vector2(c.x, c.z).distance_to(Vector2.ZERO) / INCH
	assert_float(dist_in) \
		.override_failure_message("fixture: the blob must push the drop OUT of the 6\" circle") \
		.is_greater(6.0)
	assert_float(dist_in).is_less_equal(12.0)
	assert_str(str(solo.last_arrival_note)) \
		.override_failure_message("a beacon within 12\" that did not apply must be NAMED, not silent") \
		.contains("Ambush Beacon: not used")
	assert_str(str(solo.last_arrival_note)).contains("Relay")


## The human side: the >9" honour-system warning must NOT fire inside a friendly beacon circle — it
## says the waiver applied instead.
func test_the_human_proximity_warning_yields_to_the_beacon() -> void:
	var arrived := _reg(E2EBoot.make_unit(_main, 1, "Yours", [Vector3.ZERO]))
	var foe := _reg(E2EBoot.make_unit(_main, 2, "Watcher", [Vector3(4.0 * INCH, 0, 0)]))
	assert_object(foe).is_not_null()
	# ROT case first: no beacon → the warning is exactly the shipped one.
	_main._solo_warn_ambush_proximity(arrived)
	assert_str(_log_text()).contains("Ambush arrivals must be >9")
	# Now a friendly beacon 3" away covers it: the warning gives way to the waiver line.
	var beacon := _reg(E2EBoot.make_unit(_main, 1, "Relay", [Vector3(3.0 * INCH, 0, 0)]))
	beacon.unit_properties["special_rules"] = ["Ambush Beacon"]
	_main._solo_warn_ambush_proximity(arrived)
	assert_int(_count("Ambush arrivals must be >9")) \
		.override_failure_message("inside the beacon circle the 9\" complaint must not fire again") \
		.is_equal(1)
	assert_str(_log_text()).contains("Ambush Beacon: Yours lands")
	assert_str(_log_text()).contains("distance restrictions waived (within 6\" of Relay)")


## …and a beacon that stood close but did not reach is named IN the warning — out of range reads
## differently from broken.
func test_a_beacon_out_of_reach_is_named_in_the_warning() -> void:
	var arrived := _reg(E2EBoot.make_unit(_main, 1, "Yours", [Vector3.ZERO]))
	_reg(E2EBoot.make_unit(_main, 2, "Watcher", [Vector3(4.0 * INCH, 0, 0)]))
	var beacon := _reg(E2EBoot.make_unit(_main, 1, "Relay", [Vector3(-9.0 * INCH, 0, 0)]))
	beacon.unit_properties["special_rules"] = ["Ambush Beacon"]
	_main._solo_warn_ambush_proximity(arrived)
	assert_str(_log_text()) \
		.override_failure_message("9\" is outside the 6\" circle — the warning must stand:\n%s" % _log_text()) \
		.contains("Ambush arrivals must be >9")
	assert_str(_log_text()) \
		.override_failure_message("a beacon within 12\" that did not reach must be named, not silent") \
		.contains("Ambush Beacon not used: Relay is 9.0\" away")


# === 2. Rapid Ambush ==========================================================================

## The carrier arrives in round 1; a base Ambusher in the SAME reserve does not.
func test_rapid_ambush_arrives_in_round_one_and_plain_ambush_does_not() -> void:
	var solo = _main.solo_controller
	var enemy := _reg(E2EBoot.make_unit(_main, 1, "Line", [Vector3(0.5, 0, 0.5)]))
	var rapid := _reg(E2EBoot.make_unit(_main, 2, "Shadows", [TRAY]))
	rapid.unit_properties["special_rules"] = ["Rapid Ambush"]
	rapid.unit_properties["ambush_reserve"] = true
	var plain := _reg(E2EBoot.make_unit(_main, 2, "Latecomers", [TRAY + Vector3(0.1, 0, 0)]))
	plain.unit_properties["special_rules"] = ["Ambush"]
	plain.unit_properties["ambush_reserve"] = true
	solo.ambush_reserve = [plain, rapid]   # the plain one FIRST — the gate must skip it, not stop
	solo._deploy_objectives = [Vector2(0.3, 0.3)]

	assert_int(solo.ambush_reserve_ready(1)) \
		.override_failure_message("only the Rapid Ambush carrier is eligible in round 1") \
		.is_equal(1)
	var arrived: GameUnit = solo.arrive_one_ambush_unit(_zone(), _enemy_entries(enemy), [], 1)
	assert_object(arrived) \
		.override_failure_message("Rapid Ambush: 'may be deployed at the start of any round, INCLUDING THE FIRST'") \
		.is_equal(rapid)
	assert_bool(bool(rapid.unit_properties.get("ambush_reserve", false))).is_false()
	assert_int(int(rapid.unit_properties.get("ambush_arrived_round", -1))) \
		.override_failure_message("the objective lock is stamped for a round-1 arrival too (p.13)") \
		.is_equal(1)
	# ROT case: the base Ambusher stayed put — and a second call in round 1 brings nobody.
	assert_bool(bool(plain.unit_properties.get("ambush_reserve", false))).is_true()
	assert_object(solo.arrive_one_ambush_unit(_zone(), _enemy_entries(enemy), [], 1)).is_null()
	# Round 2 re-opens it for the plain Ambusher.
	assert_object(solo.arrive_one_ambush_unit(_zone(), _enemy_entries(enemy), [], 2)).is_equal(plain)


## The round-1 beat itself, on the real flow: the exception is announced and the arrival logged.
func test_the_round_one_beat_runs_and_logs_the_exception() -> void:
	var solo = _main.solo_controller
	_reg(E2EBoot.make_unit(_main, 1, "Line", [Vector3(0.5, 0, 0.5)]))
	var rapid := _reg(E2EBoot.make_unit(_main, 2, "Shadows", [TRAY]))
	rapid.unit_properties["special_rules"] = ["Rapid Ambush"]
	rapid.unit_properties["ambush_reserve"] = true
	solo.ambush_reserve = [rapid]
	solo._deploy_objectives = [Vector2(0.3, 0.3)]
	_main._solo_ai_took_last_activation = false   # the AI activates next → it opens the alternation
	await _main._solo_rapid_ambush_round_one()
	assert_str(_log_text()) \
		.override_failure_message("the round-1 exception must be named:\n%s" % _log_text()) \
		.contains("Rapid Ambush: Shadows arrives at the start of round 1 (base Ambush allows round 2+)")
	assert_bool(bool(rapid.unit_properties.get("ambush_reserve", false))).is_false()


## ROT case for the beat: with nobody carrying Rapid Ambush the round-1 beat never opens.
func test_the_round_one_beat_stays_shut_without_a_carrier() -> void:
	var solo = _main.solo_controller
	var plain := _reg(E2EBoot.make_unit(_main, 2, "Latecomers", [TRAY]))
	plain.unit_properties["special_rules"] = ["Ambush"]
	plain.unit_properties["ambush_reserve"] = true
	solo.ambush_reserve = [plain]
	_main._solo_begin_rapid_ambush_round_one()
	assert_bool(_main._solo_ai_busy) \
		.override_failure_message("no carrier = no beat: the pump must not be blocked") \
		.is_false()
	assert_int(_count("Rapid Ambush")).is_equal(0)
	assert_bool(bool(plain.unit_properties.get("ambush_reserve", false))).is_true()


# === 3. Ambush Re-Deployment ==================================================================

## The withdrawal at the end of an activation, the EXACT return round, and the once-per-game lock.
func test_the_unit_leaves_at_the_end_of_its_activation_and_returns_next_round() -> void:
	var solo = _main.solo_controller
	var enemy := _reg(E2EBoot.make_unit(_main, 1, "Hunters", [Vector3(3.0 * INCH, 0, 0)]))
	var jesters := _reg(E2EBoot.make_unit(_main, 2, "Jesters", [Vector3.ZERO, Vector3(0.05, 0, 0)]))
	jesters.unit_properties["special_rules"] = ["Ambush Re-Deployment"]
	solo._deploy_objectives = [Vector2(0.5, 0.5)]   # far away — the unit holds nothing
	_main.opr_army_manager.current_round = 2

	# The AI's heuristic: an enemy 3" away is inside the charge band and no marker is held → leave.
	var decision: Dictionary = solo.ambush_redeploy_ai_decision(jesters)
	assert_bool(bool(decision["use"])).is_true()
	assert_bool(await _main._solo_try_ambush_redeploy(jesters)).is_true()

	assert_bool(SoloController.unit_in_reserve(jesters)).is_true()
	assert_bool(solo.is_eligible(jesters)) \
		.override_failure_message("a withdrawn unit is off the table — it may not be activated") \
		.is_false()
	assert_int(int(jesters.unit_properties.get("ambush_return_round", 0))).is_equal(3)
	assert_str(_log_text()).contains(
		"Ambush Re-Deployment: Jesters leaves the table (once per game) and returns at the start of round 3")

	# The return date is EXACT: not in round 2 any more, not in round 4 — in round 3.
	assert_bool(SoloController.may_arrive_this_round(jesters, 2)).is_false()
	assert_bool(SoloController.may_arrive_this_round(jesters, 4)).is_false()
	assert_object(solo.arrive_one_ambush_unit(_zone(), _enemy_entries(enemy), [], 4)) \
		.override_failure_message("the exact return round must not be a free choice of any later round") \
		.is_null()
	var back: GameUnit = solo.arrive_one_ambush_unit(_zone(), _enemy_entries(enemy), [], 3)
	assert_object(back).is_equal(jesters)
	assert_int(int(jesters.unit_properties.get("ambush_arrived_round", -1))) \
		.override_failure_message("it comes back 'as if it had Ambush' — including the no-seizing stamp") \
		.is_equal(3)
	assert_bool(jesters.unit_properties.has("ambush_return_round")).is_false()

	# ROT case: once per game. The second attempt is refused and says so.
	_main.opr_army_manager.current_round = 3
	assert_bool(SoloController.can_ambush_redeploy(jesters)).is_false()
	assert_bool(await _main._solo_try_ambush_redeploy(jesters)) \
		.override_failure_message("'Once per game' — the second withdrawal must be refused") \
		.is_false()
	assert_int(_count("Jesters leaves the table")).is_equal(1)


## ROT case: a joined hero without the rule breaks "a unit where ALL models have this rule".
func test_a_hero_without_the_rule_locks_the_whole_unit_out() -> void:
	var jesters := _reg(E2EBoot.make_unit(_main, 2, "Jesters", [Vector3.ZERO]))
	jesters.unit_properties["special_rules"] = ["Ambush Re-Deployment"]
	var hero := _reg(E2EBoot.make_unit(_main, 2, "Warden", [Vector3(0.03, 0, 0)]))
	hero.unit_properties["special_rules"] = ["Hero"]
	jesters.unit_properties["attached_heroes"] = [hero]
	hero.unit_properties["attached_to"] = jesters
	_main.opr_army_manager.current_round = 2
	assert_bool(await _main._solo_try_ambush_redeploy(jesters)).is_false()
	assert_bool(SoloController.unit_in_reserve(jesters)).is_false()
	assert_int(_count("Ambush Re-Deployment")) \
		.override_failure_message("a unit that cannot use the rule must not even discuss it") \
		.is_equal(0)
	# With the rule on the hero too the same door opens.
	hero.unit_properties["special_rules"] = ["Hero", "Ambush Re-Deployment"]
	assert_bool(SoloController.can_ambush_redeploy(jesters)).is_true()


## The AI keeps its use when it sits on a marker — and the decision is NAMED (rules-must-log).
func test_the_ai_keeps_its_use_on_an_objective_and_says_why() -> void:
	var solo = _main.solo_controller
	_reg(E2EBoot.make_unit(_main, 1, "Hunters", [Vector3(3.0 * INCH, 0, 0)]))
	var jesters := _reg(E2EBoot.make_unit(_main, 2, "Jesters", [Vector3.ZERO]))
	jesters.unit_properties["special_rules"] = ["Ambush Re-Deployment"]
	solo._deploy_objectives = [Vector2.ZERO]   # standing right on the marker
	_main.opr_army_manager.current_round = 2
	assert_bool(await _main._solo_try_ambush_redeploy(jesters)) \
		.override_failure_message("walking off a held marker throws the mission") \
		.is_false()
	assert_bool(bool(jesters.unit_properties.get("ambush_redeploy_used", false))).is_false()
	assert_str(_log_text()).contains("Ambush Re-Deployment: Jesters keeps its once-per-game use")
	assert_str(_log_text()).contains("holds a marker")
