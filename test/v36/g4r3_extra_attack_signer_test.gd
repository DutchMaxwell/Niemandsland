extends GdUnitTestSuite
## G4 round 3, row H-EXTRA-ATTACK-SIGNER: the extra attack a rule generates ("1 extra attack from unmodified 6s",
## Bloodborn / Primal) is rolled by the firing member, like every other die of its shot — the core signs it with the
## member. The AI volley signed it with the host unit, so a joined hero's extra die carried the host's label
## (gf_003/21, gf_004/20, gf_034/28, gf_035/11). From EPOCH_73_V36 the extra die carries the firing member's label;
## EPOCH_72_PLAYTEST_RULES keeps the host label so recorded games replay unchanged. The labels are read from the
## dice dump (AiDiceRecorder), the table's own per-roll record.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254
const SEED := 21
const _DUMP_DIR := "user://g4r3_extra_attack_signer_test_tmp"

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
	_main.opr_army_manager.current_round = 1
	_main._solo_batch = true
	DirAccess.make_dir_recursive_absolute(_DUMP_DIR)
	AiDiceRecorder._checked = false
	AiDiceRecorder._stream = null
	AiDiceRecorder._count = 0
	OS.set_environment("NML_DICE_DUMP", ProjectSettings.globalize_path(_DUMP_DIR))


func after_test() -> void:
	CoreActivation.reset_all(_main)
	CoreActivation._env = -1
	AiDiceRecorder.close()
	OS.set_environment("NML_DICE_DUMP", "")
	var d := DirAccess.open(_DUMP_DIR)
	if d != null:
		for f in d.get_files():
			d.remove(f)
	DirAccess.remove_absolute(_DUMP_DIR)
	AiActRecorder.rules_epoch = _epoch_before
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _log_text() -> String:
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


## The owner labels of every roll the dump holds, in order.
func _owners() -> Array:
	var out: Array = []
	var f := FileAccess.open(_DUMP_DIR.path_join("dice.jsonl"), FileAccess.READ)
	if f == null:
		return out
	while not f.eof_reached():
		var line := f.get_line()
		if line != "":
			out.append(str((JSON.parse_string(line) as Dictionary).get("owner", "")))
	f.close()
	return out


## A host squad (seat `seat`) with a Bloodborn hero joined to it, and a squad of the other seat to shoot at. The hero's
## pistol (Quality 2+, 12 dice) is the shot; the volley's attacker is the host, the firing member is the hero - the
## parity acts' shape.
func _fixture(seat: int) -> Dictionary:
	var host := E2EBoot.make_unit(_main, seat, "Test Squad", [Vector3.ZERO])
	(host.models[0] as ModelInstance).model_index = 0
	var hero := E2EBoot.make_unit(_main, seat, "Test Hero", [Vector3(0, 0, 0.02)])
	(hero.models[0] as ModelInstance).model_index = 0
	hero.unit_properties["game_system"] = "gf"
	hero.unit_properties["faction_folder"] = "blood_brothers"
	hero.unit_properties["special_rules"] = ["Bloodborn"]
	(hero.models[0] as ModelInstance).properties["special_rules"] = ["Bloodborn"]
	hero.unit_properties["quality"] = 2
	_main.opr_army_manager.game_units[host.unit_id] = host
	_main.opr_army_manager.game_units[hero.unit_id] = hero
	EquipmentDistributor.attach_hero_to_unit(hero, host)
	var pistol := OPRApiClient.OPRWeapon.new()
	pistol.name = "Hero Pistol"
	pistol.range_value = 12
	pistol.attacks = 12
	pistol.count = 1
	var src := OPRApiClient.OPRUnit.new()
	src.weapons.assign([pistol])
	hero.source_type = "opr"
	hero.source_data = src
	var squad := E2EBoot.make_unit(_main, 3 - seat, "Test Scouts", [Vector3(5.0 * INCH, 0, 0), Vector3(5.0 * INCH, 0, 0.02)])
	squad.unit_properties["defense"] = 6
	_main.opr_army_manager.game_units[squad.unit_id] = squad
	return {"host": host, "hero": hero, "squad": squad, "pistol": pistol}


func _volley(epoch: int) -> void:
	AiActRecorder.rules_epoch = epoch
	var f := _fixture(1)
	var shots: Array = []
	for p in AiEv.stamp_sergeant(AiShooting.profiles_in_range([f["pistol"]], 0.0), f["hero"]):
		shots.append({"member": f["hero"], "quality": 2, "alive": 1, "max": 1, "reach": 12, "profile": p})
	_main.seed_tray_rng(SEED)
	await _main._solo_resolve_ai_volley(f["host"], f["squad"], shots)
	await E2EBoot.settle(get_tree())


## The game's own call: the core door takes the host's volley (both seats AI), the joined hero fires its pistol in it.
func _door_volley(epoch: int) -> void:
	AiActRecorder.rules_epoch = epoch
	_main.solo_ai_slots = {1: true, 2: true}
	_main.solo_controller.ai_slot = 2
	_main.solo_controller.human_slot = 1
	CoreActivation._env = 1
	var f := _fixture(2)
	var host: GameUnit = f["host"]
	var host_src := OPRApiClient.OPRUnit.new()   # the host fires nothing itself: only the hero's pistol rolls dice
	host.source_type = "opr"
	host.source_data = host_src
	_main.seed_tray_rng(SEED)
	var runs := CoreActivation.ai_runs
	_main._solo_core_ai_h = CoreActivation.capture(_main)
	await _main._run_ai_shooting({"unit": host, "moved": false, "action": AiDecision.Action.HOLD})
	assert_int(CoreActivation.ai_runs).override_failure_message("the core did not take the volley (the table shot it)") \
		.is_equal(runs + 1)
	if _main._solo_core_ai_h != 0:
		_main.solo_controller._core_node_ready().release(_main._solo_core_ai_h)
	_main._solo_core_ai_h = 0
	await E2EBoot.settle(get_tree())


func _assert_extra_die_rolled() -> void:
	var text := _log_text()
	assert_str(text).override_failure_message("fixture: the hero's sixes must spawn extra attacks (log: %s)" % text) \
		.contains("Bloodborn:")
	assert_str(text).contains("extra attack")


## EPOCH_72 leg (declared first: gdUnit drops tests declared after a failing one): the extra die keeps the host's label.
func test_the_extra_die_is_signed_by_the_host_at_epoch_72(timeout := 120000) -> void:
	await _volley(AiActRecorder.EPOCH_72_PLAYTEST_RULES)
	_assert_extra_die_rolled()
	assert_array(_owners()).override_failure_message("EPOCH_72 keeps the host's label").contains(["AI (Test Squad)"])


## EPOCH_73: the extra die carries the firing hero's label, like the hero's own attack dice.
func test_the_extra_die_is_signed_by_the_firing_member_at_epoch_73(timeout := 120000) -> void:
	await _door_volley(AiActRecorder.EPOCH_73_V36)
	var owners := _owners()
	# The door's log names no "Bloodborn:" line (the table writes one), so the extra die is counted in the dice record
	# instead: the hero's pistol batch plus the extra die = two rolls signed by the hero.
	assert_int(owners.count("AI (Test Hero)")) \
		.override_failure_message("fixture: the hero's sixes must spawn an extra attack die (owners: %s, log: %s)" % [owners, _log_text()]) \
		.is_greater_equal(2)
	assert_array(owners).override_failure_message("fixture: the hero must sign its attack dice (owners: %s)" % [owners]) \
		.contains(["AI (Test Hero)"])
	assert_array(owners) \
		.override_failure_message("H-EXTRA-ATTACK-SIGNER — no die of the hero's shot may carry the host's label (owners: %s)" % [owners]) \
		.not_contains(["AI (Test Squad)"])
