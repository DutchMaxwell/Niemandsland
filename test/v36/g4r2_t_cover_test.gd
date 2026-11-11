extends GdUnitTestSuite
## G4R2 F-T-COVER (PARITY_DIAG_1104_R2_SHOOT 2.9, sibling of G4-T2): when every HOST model of a joined
## unit is dead and the attached hero still stands, the hero is the unit — so the Cover rule (+1 Defense
## against shooting for a unit standing in cover) must read the HERO's square. Before this row the table
## read the dead host (no living model -> "not in cover") and the hero saved one point worse than the core
## says. Both live shooting paths (the AI volley and the human volley) take their Cover from the same
## `_solo_cover_defense`, so both are driven here over scenes/main.tscn with a REAL forest cell under the
## hero. Below EPOCH_73_V36 the old host read stands: the epoch-72 control must stay green.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")

## A point far enough from the shooter to leave room for a forest cell under the hero only.
const HERO_POS := Vector3(0.0, 0.0, 0.5)

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


## The joined chain: a host whose models are ALL dead (Defense 6+) and a living one-model hero attached
## to it (Defense 5+) who stands on a painted forest cell. The chain still stands because the hero holds
## the models, and the hero is the one in cover.
func _chain() -> Dictionary:
	var host := E2EBoot.make_unit(_main, 2, "Host", [HERO_POS])
	host.unit_properties["defense"] = 6
	for m in host.models:
		(m as ModelInstance).is_alive = false
	var hero := E2EBoot.make_unit(_main, 2, "Hero", [HERO_POS])
	hero.unit_properties["defense"] = 5
	host.unit_properties["attached_heroes"] = [hero]
	hero.unit_properties["attached_to"] = host
	_main.opr_army_manager.game_units[host.unit_id] = host
	_main.opr_army_manager.game_units[hero.unit_id] = hero
	var o: Node3D = _main.terrain_overlay
	o.grid_cells[o.world_to_cell(HERO_POS)] = o.TerrainType.FOREST
	assert_bool(_main._solo_majority_in_cover(hero)) \
		.override_failure_message("fixture: the hero must stand in cover").is_true()
	return {"host": host, "hero": hero}


func _shots(shooter: GameUnit) -> Array:
	var profiles := AiShooting.profiles_in_range([_gun()], 0.0)
	assert_int(profiles.size()).is_equal(1)
	return [{"member": shooter, "quality": shooter.get_quality(), "alive": shooter.get_alive_count(),
		"max": shooter.models.size(), "reach": 24, "profile": profiles[0]}]


# ===== the predicate itself =====

func test_a_dead_host_reads_the_living_heros_square_for_cover() -> void:
	var chain := _chain()
	assert_bool(_main._solo_majority_in_cover(chain["host"])) \
		.override_failure_message("a dead host with a living hero in cover counts as in cover").is_true()


# ===== the AI shooting path =====

func test_the_ai_volley_at_a_dead_host_gives_the_hero_in_cover_the_cover_save() -> void:
	var shooter := _shooter()
	var chain := _chain()
	_main.seed_tray_rng(7)
	await _main._solo_resolve_ai_volley(shooter, chain["host"], _shots(shooter))
	var text := _log_text()
	assert_str(text) \
		.override_failure_message("the hero's Defense 5 plus Cover saves on 4+ (log: %s)" % text.strip_edges()) \
		.contains("Hero saves on 4+")
	assert_str(text) \
		.override_failure_message("the applied Cover rule names itself and the hero (log: %s)" % text.strip_edges()) \
		.contains("Hero is in cover: +1 Defense (saves on 4+)")
	await E2EBoot.settle(get_tree())


# ===== the human shooting path (same composition, its own entry point) =====

func test_the_human_volley_at_a_dead_host_gives_the_hero_in_cover_the_cover_save() -> void:
	var shooter := _shooter()
	var chain := _chain()
	_main.seed_tray_rng(7)
	await _main._run_human_shooting(shooter, chain["host"])
	var text := _log_text()
	assert_str(text) \
		.override_failure_message("the human path must read the hero's cover too (log: %s)" % text.strip_edges()) \
		.contains("Hero saves on 4+")
	assert_str(text) \
		.override_failure_message("the applied Cover rule names itself and the hero (log: %s)" % text.strip_edges()) \
		.contains("Hero is in cover: +1 Defense (saves on 4+)")
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
		.contains("Host saves on 6+")
	assert_str(text).not_contains("is in cover")
	await E2EBoot.settle(get_tree())
