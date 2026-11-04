extends GdUnitTestSuite
## G4R3 F-T-SIGHT-LONE (PARITY_DIAG_1104 7.2, acts aof_038/25, aof_010/39, gf_012/20, aof_006/34): when
## every HOST model of a joined unit is dead and a hero still stands, the hero is the unit — the sight
## query and the per-weapon volley assignment must measure it by the HERO's own base radius. The table
## read the host's alive models only (radius 0), so a hero inside the base-edge reach was refused
## ("no volley - no target in range or sight") while the core, asked about the hero's real base, fired.
## Driven through the live AI shooting entry (`_run_ai_shooting`) with a real weapon profile. Below
## EPOCH_73_V36 the old host read stands: the epoch-72 control must stay green.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254
const HERO_BASE_MM := 40   # radius 0.020 m, the lone hero of the recording

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


## A 9" gun at Quality 2+ with many attacks, so a fired volley reliably reaches its save step.
func _gun() -> OPRApiClient.OPRWeapon:
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Rifle"
	w.range_value = 9
	w.attacks = 20
	return w


## The AI's shooter: one model at the origin holding the 9" gun, built the way the live path reads it.
func _shooter() -> GameUnit:
	var u := E2EBoot.make_unit(_main, 2, "Gunners", [Vector3.ZERO])
	u.unit_properties["quality"] = 2
	var opr := OPRApiClient.OPRUnit.new()
	var ws: Array[OPRApiClient.OPRWeapon] = [_gun()]
	opr.weapons = ws
	u.source_type = "opr"
	u.source_data = opr
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## The human chain: a host whose models are ALL dead and a living one-model hero (40 mm base, Defense
## 4+) attached to it. The centre gap is 9" + the shooter's radius + half the hero's radius, so the hero
## is in reach only when its own radius is read (a radius-0 read leaves it half a radius outside).
func _chain(shooter: GameUnit, host_alive: bool = false, hero_mm: int = HERO_BASE_MM) -> Dictionary:
	var shooter_r := SoloController.model_base_radius_m(shooter.models[0])
	var hero_r := float(hero_mm) / 2000.0
	var x := 9.0 * INCH + shooter_r + 0.5 * hero_r
	var host := E2EBoot.make_unit(_main, 1, "Host", [Vector3(x, 0.0, 0.0)])
	host.unit_properties["defense"] = 5
	for m in host.models:
		(m as ModelInstance).is_alive = host_alive
	var hero := E2EBoot.make_unit(_main, 1, "Hero", [Vector3(x, 0.0, 0.05)])
	hero.unit_properties["defense"] = 4
	hero.unit_properties["base_size_round"] = hero_mm
	host.unit_properties["attached_heroes"] = [hero]
	hero.unit_properties["attached_to"] = host
	_main.opr_army_manager.game_units[host.unit_id] = host
	_main.opr_army_manager.game_units[hero.unit_id] = hero
	return {"host": host, "hero": hero}


func _activate(shooter: GameUnit) -> void:
	_main.seed_tray_rng(7)
	await _main._run_ai_shooting({"unit": shooter, "moved": false, "action": AiDecision.Action.HOLD})


# ===== the live volley assignment =====

func test_the_ai_volley_assignment_reaches_a_lone_hero_by_its_own_base() -> void:
	var shooter := _shooter()
	_chain(shooter)
	await _activate(shooter)
	var text := _log_text()
	assert_str(text) \
		.override_failure_message("the lone hero is in reach by its own base, so the weapon gets it as target (log: %s)" % text.strip_edges()) \
		.not_contains("no volley")
	assert_str(text) \
		.override_failure_message("the volley fires at the hero's chain and the hero saves on 4+ (log: %s)" % text.strip_edges()) \
		.contains("Hero saves on 4+")
	await E2EBoot.settle(get_tree())


# ===== the sight query (the count every gate and the assignment share) =====

func test_the_sight_query_counts_the_shooter_when_the_lone_hero_is_in_reach() -> void:
	var shooter := _shooter()
	var chain := _chain(shooter)
	assert_int(_main._solo_sighted_count(shooter, chain["host"], 9)) \
		.override_failure_message("the lone hero's own base (r 0.020 m) puts it in reach of the 9\" gun") \
		.is_equal(1)
	await E2EBoot.settle(get_tree())


func test_the_lone_hero_speaks_for_the_unit_radius_and_height() -> void:
	var shooter := _shooter()
	var chain := _chain(shooter, false, 60)
	assert_float(_main._solo_unit_base_radius_m(chain["host"])) \
		.override_failure_message("a dead host's chain reads the living hero's base radius, not 0") \
		.is_equal_approx(0.030, 0.0001)
	var want_h: float = VolumetricLos.height_in_for_base_mm(60.0) * VolumetricLos.INCHES_TO_METERS
	assert_float(_main._solo_unit_los_height_m(chain["host"])) \
		.override_failure_message("the sight cylinder stands as tall as the hero's base table row") \
		.is_equal_approx(want_h, 0.0001)
	await E2EBoot.settle(get_tree())


# ===== controls: nothing else moves =====

func test_a_living_host_keeps_its_own_radius_even_with_a_wider_hero() -> void:
	var shooter := _shooter()
	var chain := _chain(shooter, true, 60)
	assert_float(_main._solo_unit_base_radius_m(chain["host"])) \
		.override_failure_message("a host with living models is read by those models only, as before") \
		.is_equal_approx(SeparationChecker.DEFAULT_BASE_RADIUS_M, 0.0001)
	await E2EBoot.settle(get_tree())


func test_the_epoch_72_control_keeps_the_host_read() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var shooter := _shooter()
	var chain := _chain(shooter)
	assert_float(_main._solo_unit_base_radius_m(chain["host"])) \
		.override_failure_message("below 73 the recorded corpus replays the host's empty read") \
		.is_equal(0.0)
	await _activate(shooter)
	assert_str(_log_text()) \
		.override_failure_message("below 73 the lone hero stays out of reach, so the table logs no volley") \
		.contains("no volley")
	await E2EBoot.settle(get_tree())
