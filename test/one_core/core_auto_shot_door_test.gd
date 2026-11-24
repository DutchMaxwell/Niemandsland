extends GdUnitTestSuite
## The Auto verbs' shot goes through the rules core like a normal Fire!: the engine's Auto move reaches the core as the
## unit's placement (the same check a dragged drop gets, at the verb's movement mode) before the shot, so the core shoots
## from where the models ENDED. A move the core refuses turns the shot into the free dice roll with the core's reason.
## Real: the main scene, NmlCore, the human session ("Activate"), `_run_player_intent` (the Auto verb), the engine's
## move and the core's shot. Constructed: a 3-model 24" rifle unit and a plain target 27" away (out of range from the
## start, in range after the 6" Advance).
## RED (on main): the Auto shot runs the GDScript table resolver ("N/M models with line of sight + range"), never the core.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")
const SIDE := {"quality": 3, "defense": 4, "tough": 1, "z_step_in": 1.5, "game_system": "gf",
	"faction_folder": "custodian_brothers", "rules": []}
const RIFLE := {"name": "Rifle", "range_in": 24, "attacks": 4, "count": 3, "rules": []}
const TABLE_LINE := "models with line of sight + range"

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	SoloHarness.start(_main, [2], 1)
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	SoloHarness.instant(_main)
	MovementPlanner.fast_planner = false   # the deterministic precise planner (as e2e_auto_preview_test.gd)
	CoreActivation._env = 1
	CoreSlice.path_override = ""
	CoreSlice.reset_cache()


func after_test() -> void:
	CoreActivation.reset_all(_main)
	CoreActivation._env = -1
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _shooter() -> GameUnit:
	var att := ParityTable._make_unit(_main, SIDE.merged({"player": 1, "name": "Gunners", "models": 3, "x_in": 0.0}, true), RIFLE)
	for m in att.models:
		m.node.set_meta("network_id", 801 + att.models.find(m))
		m.node.set_meta("model_instance", m)
	return att


func _foe(x_in: float, rules: Array = []) -> GameUnit:
	var foe := ParityTable._make_unit(_main, SIDE.merged({"player": 2, "name": "Targets", "models": 5, "x_in": x_in,
		"faction_folder": "robot_legions", "rules": rules}, true), {})
	foe.is_activated = true   # no AI reply
	return foe


## Runs the Auto Advance & Shoot of `att` at `foe` and returns the battle-log text it wrote.
func _auto_advance(att: GameUnit, foe: GameUnit) -> String:
	var lines: Array = []
	var tap := func(e: Dictionary) -> void: lines.append(str(e["text"]))
	_main.battle_log.entry_added.connect(tap)
	_main.seed_tray_rng(5)
	await SoloHarness.auto_verb(_main, att, AiDecision.Action.ADVANCE, foe)
	await E2EBoot.settle(get_tree())
	_main.battle_log.entry_added.disconnect(tap)
	return "\n".join(lines)


@warning_ignore('unused_parameter')
func test_an_auto_advance_and_shoot_fires_through_the_core_from_the_end_position(timeout := 300000,
		do_skip := not ClassDB.class_exists("NmlCore"), skip_reason := "no NmlCore") -> void:
	var att := _shooter()
	var foe := _foe(27.0)
	var start: Vector3 = _main.solo_controller.unit_centre(att)
	assert_bool(_main.core_activation_start(att)).override_failure_message("no Start").is_true()
	var text := await _auto_advance(att, foe)
	assert_float(_main.solo_controller.unit_centre(att).x - start.x).override_failure_message("the Auto verb did not advance:\n%s" % text) \
		.is_greater(0.05)
	assert_str(text).override_failure_message("the table resolved the Auto shot:\n%s" % text).not_contains(TABLE_LINE)
	assert_str(text).override_failure_message("the Auto shot became a free roll:\n%s" % text).not_contains("free roll")
	assert_str(text).override_failure_message("the core's volley line is missing:\n%s" % text).contains("Gunners fires Rifle at Targets")
	assert_str(text).override_failure_message("no hit die rolled for the Auto shot:\n%s" % text).contains(" hits (3+)")
	assert_str(text).override_failure_message("the activation did not complete:\n%s" % text).contains("Gunners activated (you)")
	assert_bool(CoreActivation.session_open(att.unit_id)).override_failure_message("the session stayed open").is_false()


## The same Auto shot at a target the core refuses (Grounded Protection) is the free dice roll with its reason: no die is
## rolled for the player (no hit roll line) and the activation completes.
@warning_ignore('unused_parameter')
func test_an_auto_shot_the_core_refuses_is_a_free_roll(timeout := 300000,
		do_skip := not ClassDB.class_exists("NmlCore"), skip_reason := "no NmlCore") -> void:
	var att := _shooter()
	var foe := _foe(27.0, ["Grounded Protection"])
	assert_bool(_main.core_activation_start(att)).override_failure_message("no Start").is_true()
	var text := await _auto_advance(att, foe)
	assert_str(text).override_failure_message("the table resolved the Auto shot:\n%s" % text).not_contains(TABLE_LINE)
	assert_str(text).override_failure_message(text).contains("Gunners fires at Targets: the rules core cannot resolve this shot (") \
		.contains("Grounded Protection").contains("free roll: roll it in the dice tray and apply the wounds by hand")
	assert_str(text).override_failure_message("a hit die was rolled for the player:\n%s" % text).not_contains(" hits (3+)")
	assert_int(foe.get_alive_count()).is_equal(5)
	assert_str(text).override_failure_message("the activation did not complete:\n%s" % text).contains("Gunners activated (you)")


## The Auto Rush verb moves its full Rush distance: the core reads the verb as the declared mode, so no Advance refusal
## and the activation completes with the selector on Rush.
@warning_ignore('unused_parameter')
func test_an_auto_rush_moves_past_the_advance_allowance_without_a_refusal(timeout := 300000,
		do_skip := not ClassDB.class_exists("NmlCore"), skip_reason := "no NmlCore") -> void:
	var att := _shooter()
	var foe := _foe(40.0)
	var start: Vector3 = _main.solo_controller.unit_centre(att)
	assert_bool(_main.core_activation_start(att)).override_failure_message("no Start").is_true()
	var lines: Array = []
	var tap := func(e: Dictionary) -> void: lines.append(str(e["text"]))
	_main.battle_log.entry_added.connect(tap)
	await SoloHarness.auto_verb(_main, att, AiDecision.Action.RUSH, foe)
	await E2EBoot.settle(get_tree())
	_main.battle_log.entry_added.disconnect(tap)
	var text := "\n".join(lines)
	var moved_in: float = (_main.solo_controller.unit_centre(att).x - start.x) / 0.0254
	assert_float(moved_in).override_failure_message("the Auto Rush moved %.1f\":\n%s" % [moved_in, text]).is_greater(6.5)
	assert_str(text).override_failure_message("the Auto Rush was refused:\n%s" % text).not_contains("allowance is")
	assert_int(_main.object_manager._movement_cap).is_equal(ObjectManager.MovementCap.RUSH)
	assert_str(text).override_failure_message("the activation did not complete:\n%s" % text).contains("Gunners activated (you)")

