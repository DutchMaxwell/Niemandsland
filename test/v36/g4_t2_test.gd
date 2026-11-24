extends GdUnitTestSuite
## G4-T2 (lead ruling O2, PARITY_DIAG_1104 F-T2): a joined unit is a chain — host plus attached
## heroes. When every HOST model is dead and an attached hero still stands, the chain's models are
## the hero's, so the save must read the HERO's Defense and sign the save as the hero. Before this
## row the table read the host's Defense and logged the host's label. Both live shooting paths (the
## AI volley and the human volley) resolve saves through the same composition, so both are driven
## here over scenes/main.tscn; the AI case runs the core door (the table's epoch-72 host read and its control left with the
## table resolver).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _epoch_before: int


func before_test() -> void:
	_epoch_before = AiActRecorder.rules_epoch
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	SoloHarness.start(_main, [2], 1)
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	SoloHarness.instant(_main)


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch_before
	CoreActivation.reset_all(_main)
	CoreActivation._env = -1
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _log_text() -> String:
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


func _gun() -> OPRApiClient.OPRWeapon:
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Rifle"
	w.range_value = 24
	w.attacks = 20
	return w


## A 24" gun at Quality 2+, so the volley reliably reaches its save step.
func _shooter() -> GameUnit:
	var u := E2EBoot.make_unit(_main, 1, "Gunners", [Vector3.ZERO])
	u.unit_properties["quality"] = 2
	var opr := OPRApiClient.OPRUnit.new()
	var ws: Array[OPRApiClient.OPRWeapon] = [_gun()]
	opr.weapons = ws
	u.source_type = "opr"
	u.source_data = opr
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## The joined chain: a host whose models are ALL dead (Defense 5+) and a living one-model hero
## attached to it (Defense 4+). The chain still stands because the hero holds the models.
func _chain() -> Dictionary:
	var host := E2EBoot.make_unit(_main, 2, "Host", [Vector3(8.0 * INCH, 0.0, 0.0)])
	host.unit_properties["defense"] = 5
	for m in host.models:
		(m as ModelInstance).is_alive = false
	var hero := E2EBoot.make_unit(_main, 2, "Hero", [Vector3(8.0 * INCH, 0.0, 0.05)])
	hero.unit_properties["defense"] = 4
	host.unit_properties["attached_heroes"] = [hero]
	hero.unit_properties["attached_to"] = host
	_main.opr_army_manager.game_units[host.unit_id] = host
	_main.opr_army_manager.game_units[hero.unit_id] = hero
	return {"host": host, "hero": hero}


## The player's own volley through the core door: the activation is opened first (the Fire! button's path), then the
## door shoots; false from the door would mean the table is left to resolve it.
func _door_fire(attacker: GameUnit, target: GameUnit) -> void:
	AiActRecorder.rules_epoch = _epoch_before   # the live epoch: the core shoots a dead-host chain from EPOCH_83_LONE_HERO_TARGET on
	CoreActivation._env = 1
	assert_bool(CoreActivation.open_session(_main, attacker)).override_failure_message("no activation session for the attacker").is_true()
	var took: bool = await CoreActivation.human_shoot(_main, attacker, target)
	assert_bool(took).override_failure_message("the core door did not take the volley (the table would resolve it)").is_true()
	CoreActivation.close_session(_main, attacker.unit_id)


## The game's own call: the core door takes the volley (the board is captured first), as the lone-hero door suite does.
## The epoch is the live one: the core shoots a chain whose host models are all dead from EPOCH_83_LONE_HERO_TARGET on.
func _door_volley(shooter: GameUnit) -> void:
	AiActRecorder.rules_epoch = _epoch_before
	_main.solo_ai_slots = {1: true, 2: true}   # both seats AI: saves auto-resolve, no dialog
	_main.solo_controller.ai_slot = 1
	_main.solo_controller.human_slot = 2
	_main.opr_army_manager.current_round = 1
	CoreActivation._env = 1
	_main.seed_tray_rng(7)
	var runs := CoreActivation.ai_runs
	_main._solo_core_ai_h = CoreActivation.capture(_main)
	await _main._run_ai_shooting(ActIntent.blank_report(shooter))
	assert_int(CoreActivation.ai_runs).override_failure_message("the core did not take the volley (the table shot it)") \
		.is_equal(runs + 1)
	if _main._solo_core_ai_h != 0:
		_main.solo_controller._core_node_ready().release(_main._solo_core_ai_h)
	_main._solo_core_ai_h = 0


# ===== the AI shooting path =====

func test_the_ai_volley_at_a_dead_host_saves_on_the_living_heros_defense() -> void:
	var shooter := _shooter()
	var chain := _chain()
	await _door_volley(shooter)
	var text := _log_text()
	assert_str(text) \
		.override_failure_message("the chain's models are the hero's, so the save is on the hero's 4+ (log: %s)" % text.strip_edges()) \
		.contains("Hero saves on 4+")
	assert_str(text) \
		.override_failure_message("the dead host must not sign the save (log: %s)" % text.strip_edges()) \
		.not_contains("Host saves on")
	await E2EBoot.settle(get_tree())


# ===== the human shooting path (same composition, its own entry point) =====

func test_the_human_volley_at_a_dead_host_saves_on_the_living_heros_defense() -> void:
	var shooter := _shooter()
	var chain := _chain()
	_main.seed_tray_rng(7)
	await _door_fire(shooter, chain["host"])
	var text := _log_text()
	assert_str(text) \
		.override_failure_message("the human path must read the hero's 4+ too (log: %s)" % text.strip_edges()) \
		.contains("Hero saves on 4+")
	assert_str(text) \
		.override_failure_message("the dead host must not sign the human volley's save (log: %s)" % text.strip_edges()) \
		.not_contains("Host saves on")
	await E2EBoot.settle(get_tree())
