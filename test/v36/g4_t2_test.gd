extends GdUnitTestSuite
## G4-T2 (lead ruling O2, PARITY_DIAG_1104 F-T2): a joined unit is a chain — host plus attached
## heroes. When every HOST model is dead and an attached hero still stands, the chain's models are
## the hero's, so the save must read the HERO's Defense and sign the save as the hero. Before this
## row the table read the host's Defense and logged the host's label. Both live shooting paths (the
## AI volley and the human volley) resolve saves through the same composition, so both are driven
## here over scenes/main.tscn. Below EPOCH_73_V36 the old host read stands: the epoch-72 control
## must stay green (a red control means the gate is wrong, not the control).

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
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main._solo_batch = true


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch_before
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


func _shots(shooter: GameUnit) -> Array:
	var profiles := AiShooting.profiles_in_range([_gun()], 0.0)
	assert_int(profiles.size()).is_equal(1)
	return [{"member": shooter, "quality": shooter.get_quality(), "alive": shooter.get_alive_count(),
		"max": shooter.models.size(), "reach": 24, "profile": profiles[0]}]


# ===== the AI shooting path =====

func test_the_ai_volley_at_a_dead_host_saves_on_the_living_heros_defense() -> void:
	var shooter := _shooter()
	var chain := _chain()
	_main.seed_tray_rng(7)
	await _main._solo_resolve_ai_volley(shooter, chain["host"], _shots(shooter))
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
	await _main._run_human_shooting(shooter, chain["host"])
	var text := _log_text()
	assert_str(text) \
		.override_failure_message("the human path must read the hero's 4+ too (log: %s)" % text.strip_edges()) \
		.contains("Hero saves on 4+")
	assert_str(text) \
		.override_failure_message("the dead host must not sign the human volley's save (log: %s)" % text.strip_edges()) \
		.not_contains("Host saves on")
	await E2EBoot.settle(get_tree())


# ===== epoch-72 control: the old host read stands =====

func test_the_epoch_72_control_keeps_the_host_read() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var shooter := _shooter()
	var chain := _chain()
	_main.seed_tray_rng(7)
	await _main._solo_resolve_ai_volley(shooter, chain["host"], _shots(shooter))
	var text := _log_text()
	assert_str(text) \
		.override_failure_message("below 73 the recorded corpus replays the old host read (log: %s)" % text.strip_edges()) \
		.contains("Host saves on 5+")
	await E2EBoot.settle(get_tree())
