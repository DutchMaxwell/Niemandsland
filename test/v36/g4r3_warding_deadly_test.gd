extends GdUnitTestSuite
## G4 round 3, row C-WARDING-DEADLY (lead ruling D3): the Warding / Knightborn 6+ ignore needs a shot from over 9",
## Deadly-multiplied wounds included. The Deadly landing never handed the shot's distance to the Regeneration
## family, so the table rolled "3 Knightborn dice (6+)" at a target 5" away while the core logged "Warding: no 6+
## ignore". From EPOCH_73_V36 the Deadly landing of an AI and of a human volley carries the shot's distance;
## EPOCH_72_PLAYTEST_RULES keeps the ungated roll so recorded games replay unchanged.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254
const SEED := 11

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


func _lance() -> OPRApiClient.OPRWeapon:
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Test Lance"
	w.range_value = 24
	w.attacks = 6
	w.count = 1
	var rules: Array[String] = ["AP(4)", "Deadly(3)"]
	w.special_rules = rules
	return w


func _unit(pid: int, unit_name: String, positions: Array) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, positions)
	for i in u.models.size():
		(u.models[i] as ModelInstance).model_index = i
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## A Deadly lance (Quality 2+, six dice, no save left at Defense 6+ AP 4) against four Knightborn models `gap_in` away.
func _fixture(gap_in: float) -> Dictionary:
	var tank := _unit(1, "Test Tank", [Vector3.ZERO])
	tank.unit_properties["quality"] = 2
	var src := OPRApiClient.OPRUnit.new()
	src.weapons.assign([_lance()])
	tank.source_type = "opr"
	tank.source_data = src
	var positions: Array = []
	for i in 4:
		positions.append(Vector3(gap_in * INCH, 0, 0.02 * i))
	var squad := _unit(2, "Knight Squad", positions)
	squad.unit_properties["game_system"] = "gf"
	squad.unit_properties["faction_folder"] = "knight_brothers"
	squad.unit_properties["special_rules"] = ["Knightborn"]
	squad.unit_properties["defense"] = 6
	for m in squad.models:
		(m as ModelInstance).properties["special_rules"] = ["Knightborn"]
	return {"tank": tank, "squad": squad}


func _ai_volley(epoch: int, gap_in: float) -> String:
	AiActRecorder.rules_epoch = epoch
	var f := _fixture(gap_in)
	var shots: Array = []
	for p in AiShooting.profiles_in_range([_lance()], 0.0):
		shots.append({"member": f["tank"], "quality": 2, "alive": 1, "max": 1, "reach": 24, "profile": p})
	_main.seed_tray_rng(SEED)
	await _main._solo_resolve_ai_volley(f["tank"], f["squad"], shots)
	var text := _log_text()
	await E2EBoot.settle(get_tree())
	return text


func _human_volley(epoch: int, gap_in: float) -> String:
	AiActRecorder.rules_epoch = epoch
	var f := _fixture(gap_in)
	_main.seed_tray_rng(SEED)
	await _main._run_human_shooting(f["tank"], f["squad"])
	var text := _log_text()
	await E2EBoot.settle(get_tree())
	return text


func _assert_deadly_landed(text: String) -> void:
	assert_str(text).override_failure_message("fixture: the lance must land Deadly wounds (log: %s)" % text).contains("Deadly(3):")


## EPOCH_72 leg (declared first: gdUnit drops tests declared after a failing one): the old ungated roll stays.
func test_deadly_wounds_inside_nine_inches_still_roll_the_ignore_at_epoch_72(timeout := 120000) -> void:
	var text: String = await _ai_volley(AiActRecorder.EPOCH_72_PLAYTEST_RULES, 5.0)
	_assert_deadly_landed(text)
	assert_str(text).override_failure_message("EPOCH_72 keeps the ungated roll (log: %s)" % text).contains("Knightborn di")


## CONTROL: from over 9" the 6+ applies to Deadly wounds, and the gate's verdict is logged under the rule's name.
func test_deadly_wounds_from_over_nine_inches_roll_the_ignore_at_epoch_73(timeout := 120000) -> void:
	var text: String = await _ai_volley(AiActRecorder.EPOCH_73_V36, 16.0)
	_assert_deadly_landed(text)
	assert_str(text).override_failure_message("over 9in the Knightborn dice roll (log: %s)" % text).contains("Knightborn di")
	assert_str(text).override_failure_message("rules-must-log (log: %s)" % text) \
		.contains("Warding: Knight Squad ignores wounds on 6+ (shot from over 9in)")


## AI volley, the parity act's shape: a Deadly shot from within 9" rolls no Warding / Knightborn die.
func test_ai_deadly_wounds_inside_nine_inches_roll_no_ignore_at_epoch_73(timeout := 120000) -> void:
	var text: String = await _ai_volley(AiActRecorder.EPOCH_73_V36, 5.0)
	_assert_deadly_landed(text)
	assert_str(text) \
		.override_failure_message("C-WARDING-DEADLY — no 6+ ignore dice inside 9in, Deadly wounds included (log: %s)" % text) \
		.not_contains("Knightborn di")
	assert_str(text).override_failure_message("rules-must-log (log: %s)" % text) \
		.contains("Warding: no 6+ ignore, Knight Squad was shot from within 9in")


## Human volley: the same Deadly landing, the same gate.
func test_human_deadly_wounds_inside_nine_inches_roll_no_ignore_at_epoch_73(timeout := 120000) -> void:
	var text: String = await _human_volley(AiActRecorder.EPOCH_73_V36, 5.0)
	_assert_deadly_landed(text)
	assert_str(text) \
		.override_failure_message("C-WARDING-DEADLY — the human volley's Deadly wounds roll no 6+ ignore inside 9in (log: %s)" % text) \
		.not_contains("Knightborn di")
