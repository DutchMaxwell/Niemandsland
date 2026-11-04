extends GdUnitTestSuite
## G4 round 3, row C-BLAST-CAP-GROUPS (lead ruling D2): a volley fires simultaneously (ruling O1), so Blast's model
## cap is read when the volley STARTS, for every weapon group. The table used to read the target's live models when
## each Blast resolved, so a Deadly weapon (sorted first) that killed a model shrank the cap of the next weapon's
## Blast; the core reads the count at the volley's start. From EPOCH_73_V36 the table takes the snapshot too (AI and
## human volley); EPOCH_72_PLAYTEST_RULES keeps the live read so recorded games replay unchanged.

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


func _unit(pid: int, unit_name: String, positions: Array, weapons: Array) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, positions)
	for i in u.models.size():
		(u.models[i] as ModelInstance).model_index = i
	var src := OPRApiClient.OPRUnit.new()
	src.weapons.assign(weapons)
	u.source_type = "opr"
	u.source_data = src
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## The parity act's shape: a Fusion-style Deadly rifle (sorted first) and a Blast(3) mortar fired at three models.
## The rifle's one die kills one model before the mortar's Blast multiplies; Defense 6 and AP(4) leave no save.
func _fixture() -> Dictionary:
	var rifle := _weapon("Test Fusion Rifle", 24, 1, ["AP(4)", "Deadly(3)"])
	var mortar := _weapon("Test Mortar", 24, 6, ["AP(4)", "Blast(3)"])
	var tank := _unit(1, "Test Tank", [Vector3.ZERO], [rifle, mortar])
	tank.unit_properties["quality"] = 2
	var squad := _unit(2, "Test Scouts", [Vector3(8.0 * INCH, 0, 0), Vector3(8.0 * INCH, 0, 0.02),
		Vector3(8.0 * INCH, 0, 0.04)], [])
	squad.unit_properties["defense"] = 6
	return {"tank": tank, "squad": squad, "rifle": rifle, "mortar": mortar}


func _ai_volley(epoch: int) -> String:
	AiActRecorder.rules_epoch = epoch
	var f := _fixture()
	var shots: Array = []
	for p in AiShooting.profiles_in_range([f["rifle"], f["mortar"]], 0.0):
		shots.append({"member": f["tank"], "quality": 2, "alive": 1, "max": 1, "reach": 24, "profile": p})
	_main.seed_tray_rng(SEED)
	await _main._solo_resolve_ai_volley(f["tank"], f["squad"], shots)
	var text := _log_text()
	await E2EBoot.settle(get_tree())
	return text


func _human_volley(epoch: int) -> String:
	AiActRecorder.rules_epoch = epoch
	var f := _fixture()
	_main.seed_tray_rng(SEED)
	await _main._run_human_shooting(f["tank"], f["squad"])
	var text := _log_text()
	await E2EBoot.settle(get_tree())
	return text


const SEED := 7


## EPOCH_72 leg (declared first: gdUnit drops tests declared after a failing one): the live read stays — the rifle
## killed one of the three models, so the mortar's Blast is capped by the two that are left.
func test_blast_is_capped_by_the_live_models_at_epoch_72(timeout := 120000) -> void:
	var text: String = await _ai_volley(AiActRecorder.EPOCH_72_PLAYTEST_RULES)
	assert_str(text).override_failure_message("fixture: the rifle must land a Deadly wound (log: %s)" % text).contains("Deadly(3):")
	assert_str(text).override_failure_message("EPOCH_72 keeps the live cap (log: %s)" % text).contains("capped by 2 models in target")


## EPOCH_73 AI volley: the three models standing at the volley's start cap the Blast, whatever the rifle killed first.
func test_ai_blast_reads_the_models_at_the_volley_start_at_epoch_73(timeout := 120000) -> void:
	var text: String = await _ai_volley(AiActRecorder.EPOCH_73_V36)
	assert_str(text).override_failure_message("fixture: the rifle must land a Deadly wound (log: %s)" % text).contains("Deadly(3):")
	assert_str(text) \
		.override_failure_message("C-BLAST-CAP-GROUPS — Blast must read the 3 models of the volley's start (log: %s)" % text) \
		.not_contains("capped by 2 models in target")
	var re := RegEx.create_from_string("Blast\\(3\\): \\d+ hits? ×3 ")
	assert_object(re.search(text)).override_failure_message("Blast(3) must multiply ×3 (log: %s)" % text).is_not_null()


## EPOCH_73 human volley: the same snapshot, the same line (the human path runs the same _solo_hits).
func test_human_blast_reads_the_models_at_the_volley_start_at_epoch_73(timeout := 120000) -> void:
	var text: String = await _human_volley(AiActRecorder.EPOCH_73_V36)
	assert_str(text).override_failure_message("fixture: the rifle must land a Deadly wound (log: %s)" % text).contains("Deadly(3):")
	assert_str(text) \
		.override_failure_message("C-BLAST-CAP-GROUPS — the human volley's Blast must read the volley's start (log: %s)" % text) \
		.not_contains("capped by 2 models in target")
	var re := RegEx.create_from_string("Blast\\(3\\): \\d+ hits? ×3 ")
	assert_object(re.search(text)).override_failure_message("Blast(3) must multiply ×3 (log: %s)" % text).is_not_null()
