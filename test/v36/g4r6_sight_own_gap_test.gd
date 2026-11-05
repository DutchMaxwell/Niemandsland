extends GdUnitTestSuite
## G4R6 F-SIGHT-OWN-GAP (PARITY_DIAG_1105_R6 2.2, act gf_023/28): a joined hero's base does not extend its host's
## weapons. The table measured the shooter's range gap from the host PLUS its joined hero's bases, so a host weapon
## fired because the HERO stood closer to an oval-based target; by the book (Who Can Shoot) every model needs its
## own weapon in range, and the core stays silent. Driven through the live AI shooting entry (`_run_ai_shooting`)
## with real weapon profiles on units built the way the game builds them. Below EPOCH_73_V36 the old fold stands.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254
const BASE_MM := 25            # host and hero: round 25 mm bases (radius 0.0125 m)
const OVAL_W_MM := 35          # the target: a 35 x 60 mm oval, short axis along x
const OVAL_D_MM := 60
const RULE_LINE := "a joined hero's base does not extend its host's weapons"

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
	_main.solo_ai_slots = {1: true, 2: true}   # both seats AI, so the defender auto-rolls its saves (no dialog)
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


## A real unit (opr source, 25 mm round base) at `pos` holding one gun of `range_in` inches (0 = unarmed).
func _armed(pid: int, unit_name: String, pos: Vector3, gun_name: String, range_in: int) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, [pos])
	u.unit_properties["quality"] = 2
	u.unit_properties["base_size_round"] = BASE_MM
	var opr := OPRApiClient.OPRUnit.new()
	var ws: Array[OPRApiClient.OPRWeapon] = []
	if range_in > 0:
		var w := OPRApiClient.OPRWeapon.new()
		w.name = gun_name
		w.range_value = range_in
		w.attacks = 20
		ws.append(w)
	opr.weapons = ws
	u.source_type = "opr"
	u.source_data = opr
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## The recorded geometry on one axis: the oval target stands `host_gap_in` edge to edge from the host (at the
## origin) and `hero_gap_in` from the joined hero, who stands in front of the host inside the same chain.
func _chain(host_gap_in: float, hero_gap_in: float, host_gun: int, hero_gun: int) -> Dictionary:
	var half_w := OVAL_W_MM / 2000.0
	var half_base := BASE_MM / 2000.0
	var tx := host_gap_in * INCH + half_base + half_w
	var hx := tx - half_w - hero_gap_in * INCH - half_base
	var host := _armed(1, "Soldiers", Vector3.ZERO, "Carbine", host_gun)
	var hero := _armed(1, "Leader", Vector3(hx, 0.0, 0.0), "Pistol", hero_gun)
	host.unit_properties["attached_heroes"] = [hero]
	hero.unit_properties["attached_to"] = host
	var target := E2EBoot.make_unit(_main, 2, "Hounds", [Vector3(tx, 0.0, 0.0)])
	target.unit_properties["base_is_oval"] = true
	target.unit_properties["base_width_mm"] = OVAL_W_MM
	target.unit_properties["base_depth_mm"] = OVAL_D_MM
	target.unit_properties["base_size_round"] = 0
	_main.opr_army_manager.game_units[target.unit_id] = target
	return {"host": host, "hero": hero, "target": target}


func _activate(shooter: GameUnit) -> void:
	_main.seed_tray_rng(7)
	await _main._run_ai_shooting({"unit": shooter, "moved": false, "action": AiDecision.Action.HOLD})


# ===== fixture control (green on main) =====

func test_control_the_fixture_is_18_2_inches_for_the_host_and_inside_18_for_the_chain() -> void:
	var c := _chain(18.2, 16.9, 18, 12)
	var tshape := SeparationChecker.shape_for_model(c["target"].models[0] as ModelInstance)
	var host_gap: float = SeparationChecker.edge_distance(SeparationChecker.shape_for_model(c["host"].models[0] as ModelInstance), tshape)
	var hero_gap: float = SeparationChecker.edge_distance(SeparationChecker.shape_for_model(c["hero"].models[0] as ModelInstance), tshape)
	assert_float(host_gap) \
		.override_failure_message("fixture broken: the host stands %.2f\" from the oval edge, not 18.2\"" % host_gap) \
		.is_equal_approx(18.2, 0.02)
	assert_float(hero_gap) \
		.override_failure_message("fixture broken: the hero stands %.2f\" from the oval edge, not 16.9\"" % hero_gap) \
		.is_equal_approx(16.9, 0.02)
	assert_float(_main._solo_shoot_gap_in(c["host"], c["target"], INF)) \
		.override_failure_message("fixture broken: the host+hero fold must read the hero's gap") \
		.is_equal_approx(16.9, 0.02)
	await E2EBoot.settle(get_tree())


# ===== the defect (RED on main: the hero's gap lets the host's 18" carbine fire) =====

func test_a_host_weapon_does_not_fire_because_the_joined_hero_stands_closer(timeout := 60000) -> void:
	var c := _chain(18.2, 16.9, 18, 12)
	await _activate(c["host"])
	var text := _log_text()
	assert_str(text) \
		.override_failure_message("the host's 18\" carbine fired from 18.2\" because the hero stands at 16.9\" (log: %s)" % text.strip_edges()) \
		.not_contains("Hounds saves on")
	assert_str(text) \
		.override_failure_message("a refused shot names its rule once (log: %s)" % text.strip_edges()) \
		.contains(RULE_LINE)
	await E2EBoot.settle(get_tree())


# ===== controls: nothing else moves =====

func test_a_host_weapon_inside_its_own_reach_still_fires(timeout := 60000) -> void:
	var c := _chain(17.5, 16.9, 18, 12)
	await _activate(c["host"])
	var text := _log_text()
	assert_str(text) \
		.override_failure_message("the host's own models are inside 18\", so the carbine fires (log: %s)" % text.strip_edges()) \
		.contains("Hounds saves on")
	assert_str(text) \
		.override_failure_message("a shot the host reaches is not refused (log: %s)" % text.strip_edges()) \
		.not_contains(RULE_LINE)
	await E2EBoot.settle(get_tree())


func test_the_joined_heros_own_gun_still_fires_from_the_heros_own_gap(timeout := 60000) -> void:
	var c := _chain(18.2, 16.9, 0, 18)
	await _activate(c["host"])
	var text := _log_text()
	assert_str(text) \
		.override_failure_message("the hero's 18\" gun is inside its own 16.9\" gap and fires (log: %s)" % text.strip_edges()) \
		.contains("Hounds saves on")
	assert_str(text) \
		.override_failure_message("the hero's own shot is not refused (log: %s)" % text.strip_edges()) \
		.not_contains(RULE_LINE)
	await E2EBoot.settle(get_tree())


func test_the_epoch_72_control_keeps_the_old_fold(timeout := 60000) -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var c := _chain(18.2, 16.9, 18, 12)
	await _activate(c["host"])
	var text := _log_text()
	assert_str(text) \
		.override_failure_message("below 73 the recorded corpus replays the host+hero fold (log: %s)" % text.strip_edges()) \
		.contains("Hounds saves on")
	assert_str(text) \
		.override_failure_message("below 73 the rule line never appears (log: %s)" % text.strip_edges()) \
		.not_contains(RULE_LINE)
	await E2EBoot.settle(get_tree())
