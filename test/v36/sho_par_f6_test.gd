extends GdUnitTestSuite
## SHO-PAR-F6 (lane L-SHOOT, lead ruling O1): all weapons of a volley fire together, so which target models
## a weapon can reach is fixed when the volley is declared. The AI volley used to recount every weapon's
## models in range and sight AFTER the earlier weapons' wounds had landed: a Deadly missile (sorted first)
## that killed every model inside a flamer's short reach left the flamer silent ("no models in range or
## sight"), while the core still fired it. From EPOCH_73_V36 the table fixes every shot before the first
## die; EPOCH_72_PLAYTEST_RULES keeps the old recount so recorded games replay unchanged.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _epoch_before: int


func before_test() -> void:
	_epoch_before = AiActRecorder.rules_epoch
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


func _weapon(weapon_name: String, range_in: int, attacks: int, rules: Array) -> OPRApiClient.OPRWeapon:
	var w := OPRApiClient.OPRWeapon.new()
	w.name = weapon_name
	w.range_value = range_in
	w.attacks = attacks
	w.count = 1
	var typed: Array[String] = []
	for r in rules:
		typed.append(str(r))
	w.special_rules = typed
	return w


func _one_model(pid: int, unit_name: String, pos: Vector3, weapons: Array) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, [pos])
	(u.models[0] as ModelInstance).model_index = 0
	var src := OPRApiClient.OPRUnit.new()
	src.weapons.assign(weapons)
	u.source_type = "opr"
	u.source_data = src
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## The parity act's shape: a one-model squad 4" away (inside the flamer's 6" reach) and its joined hero 14"
## away (missile reach only; Tough enough that the missile's spare wounds never kill him). The Deadly missile
## resolves first and wipes the squad; the flamer was declared while the squad stood in its reach.
func _volley_after_the_squad_dies(epoch: int) -> Dictionary:
	AiActRecorder.rules_epoch = epoch
	var missile := _weapon("Test Missile", 24, 4, ["AP(4)", "Deadly(3)"])
	var flamer := _weapon("Test Flamer", 6, 3, [])
	var tank := _one_model(1, "Test Tank", Vector3.ZERO, [missile, flamer])
	var squad := _one_model(2, "Test Scouts", Vector3(4.0 * INCH, 0, 0), [])
	squad.unit_properties["defense"] = 6
	var hero := _one_model(2, "Test Warden", Vector3(0, 0, 14.0 * INCH), [])
	var hm := hero.models[0] as ModelInstance
	hm.wounds_max = 40
	hm.wounds_current = 40
	EquipmentDistributor.attach_hero_to_unit(hero, squad)
	var shots: Array = []
	for p in AiShooting.profiles_in_range([missile, flamer], 0.0):
		var pd := p as Dictionary
		shots.append({"member": tank, "quality": 2, "alive": 1, "max": 1,
			"reach": 24 if str(pd["name"]) == "Test Missile" else 6, "profile": pd})
	_main.seed_tray_rng(7)
	await _main._solo_resolve_ai_volley(tank, squad, shots)
	var out := {"text": _log_text(), "squad": squad.get_alive_count(), "hero": hero.get_alive_count()}
	await E2EBoot.settle(get_tree())
	return out


## EPOCH_72 leg (declared first: gdUnit drops tests declared after a failing one): the old recount stays —
## the squad is gone when the flamer's turn comes, the hero stands beyond 6", so the flamer is silent.
func test_flamer_stays_silent_after_the_wipe_at_epoch_72(timeout := 120000) -> void:
	var r: Dictionary = await _volley_after_the_squad_dies(AiActRecorder.EPOCH_72_PLAYTEST_RULES)
	var text := str(r["text"])
	assert_int(int(r["squad"])).override_failure_message("fixture: the missile must wipe the squad (log: %s)" % text).is_equal(0)
	assert_int(int(r["hero"])).override_failure_message("fixture: the hero must survive (log: %s)" % text).is_equal(1)
	assert_str(text) \
		.override_failure_message("EPOCH_72 must keep the per-weapon recount (log: %s)" % text) \
		.contains("Test Flamer silent — no models in range or sight")
	assert_str(text).not_contains("Simultaneous fire")


## EPOCH_73 leg: the flamer's reach was fixed at declaration, so it still rolls its dice, never claims it had
## no models in range or sight, and the battle log names why (rules-must-log).
func test_flamer_still_fires_after_the_wipe_at_epoch_73(timeout := 120000) -> void:
	var r: Dictionary = await _volley_after_the_squad_dies(AiActRecorder.EPOCH_73_V36)
	var text := str(r["text"])
	assert_int(int(r["squad"])).override_failure_message("fixture: the missile must wipe the squad (log: %s)" % text).is_equal(0)
	assert_int(int(r["hero"])).override_failure_message("fixture: the hero must survive (log: %s)" % text).is_equal(1)
	assert_str(text) \
		.override_failure_message("SHO-PAR-F6 — the flamer lost its declared targets to the missile's casualties (log: %s)" % text) \
		.not_contains("Test Flamer silent")
	assert_str(text) \
		.override_failure_message("SHO-PAR-F6 — the flamer must roll its declared dice (log: %s)" % text) \
		.contains("Test Tank fires Test Flamer at Test Scouts")
	assert_str(text) \
		.override_failure_message("rules-must-log — the fixed declaration must name itself (log: %s)" % text) \
		.contains("Simultaneous fire: Test Tank fires Test Flamer as declared")
