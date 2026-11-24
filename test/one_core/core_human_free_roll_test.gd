extends GdUnitTestSuite
## A player's shot the rules core cannot resolve becomes a free dice roll: one battle-log line names the reason, nothing is
## rolled for the player (the dice tray is theirs), nobody is hurt by the engine, and the activation completes as after any
## attack. The GDScript table resolver no longer runs for a player's shot (the Auto verbs' shot keeps it until the Auto-verb step).
## Real: the main scene, NmlCore, the human session ("Activate"), `_run_human_attack` (Fire!) and
## `_solo_split_commit` (the declared split's Fire!), the live deny slice.
## Constructed: a 3-model rifle unit and a target carrying Grounded Protection (the shoot slice refuses it) 10" away (a second one 14" away for the split).
## RED (on main): the table resolves the volley - the tray rolls dice, no free-roll line.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")
const SIDE := {"quality": 3, "defense": 4, "tough": 1, "z_step_in": 1.5, "game_system": "gf",
	"faction_folder": "custodian_brothers", "rules": []}
const RIFLE := {"name": "Rifle", "range_in": 24, "attacks": 4, "count": 3, "rules": []}
const REFUSED := "Grounded Protection"

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


func _foe(unit_name: String, x_in: float) -> GameUnit:
	var foe := ParityTable._make_unit(_main, SIDE.merged({"player": 2, "name": unit_name, "models": 5, "x_in": x_in,
		"faction_folder": "robot_legions", "rules": [REFUSED]}, true), {})
	foe.is_activated = true   # no AI reply
	return foe


## Runs `shot` and returns the battle-log text it wrote, the tray's RNG state before and after.
func _run(shot: Callable) -> Dictionary:
	var lines: Array = []
	var tap := func(e: Dictionary) -> void: lines.append(str(e["text"]))
	_main.battle_log.entry_added.connect(tap)
	_main.seed_tray_rng(3)
	var rng0: int = _main._tray_rng.state
	await shot.call()
	_main.battle_log.entry_added.disconnect(tap)
	return {"text": "\n".join(lines), "rng0": rng0, "rng1": int(_main._tray_rng.state)}


func _assert_free_roll(r: Dictionary, att: GameUnit, foes: Array, why: String) -> void:
	var text: String = r["text"]
	assert_str(text).override_failure_message("one line names the free roll and its reason:\n%s" % text) \
		.contains("Gunners fires at %s: the rules core cannot resolve this shot (" % (foes[0] as GameUnit).get_name()) \
		.contains(why).contains("free roll: roll it in the dice tray and apply the wounds by hand")
	assert_int(int(r["rng1"])).override_failure_message("the table rolled a die for the player:\n%s" % text).is_equal(int(r["rng0"]))
	for f in foes:
		assert_int((f as GameUnit).get_alive_count()).override_failure_message("the engine hurt %s:\n%s" % [f, text]).is_equal(5)
	assert_str(text).override_failure_message("the activation completes:\n%s" % text).contains("Gunners activated (you)")
	assert_int(int(att.unit_properties.get("shot_round", -1))).override_failure_message("the shot is stamped:\n%s" % text).is_equal(1)


@warning_ignore('unused_parameter')
func test_a_shot_the_core_refuses_is_a_free_roll_with_its_reason(timeout := 300000,
		do_skip := not ClassDB.class_exists("NmlCore"), skip_reason := "no NmlCore") -> void:
	var att := _shooter()
	var foe := _foe("Marked", 10.0)
	assert_bool(_main.core_activation_start(att)).override_failure_message("no Start").is_true()
	var r := await _run(func() -> void: await _main._run_human_attack(att, foe, false))
	_assert_free_roll(r, att, [foe], "the target's " + REFUSED)


## The declared split's Fire! at two targets the core refuses: one free roll, then the activation completes once.
@warning_ignore('unused_parameter')
func test_a_split_the_core_refuses_is_a_free_roll(timeout := 300000,
		do_skip := not ClassDB.class_exists("NmlCore"), skip_reason := "no NmlCore") -> void:
	var att := _shooter()
	var a := _foe("Marked", 10.0)
	var b := _foe("Flagged", 14.0)
	assert_bool(_main.core_activation_start(att)).override_failure_message("no Start").is_true()
	_main._solo_target_mode = {"unit": att, "split_first": a, "split_second": b, "split_b_names": ["Rifle"]}
	var r := await _run(func() -> void: await _main._solo_split_commit())
	_assert_free_roll(r, att, [a, b], "the target's " + REFUSED)
