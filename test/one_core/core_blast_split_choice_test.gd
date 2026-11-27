extends GdUnitTestSuite
## Plan step 29c (D-29-R1, "defender picks how"): an AI Blast volley at a human-owned skirmish unit asks its owner which
## of its units take the even split's remainder (the core's `blast_split:<shooter>:<target>`), one button per option;
## "Automatic" keeps the core's own (target first). An AI-owned target is never asked.
## Real: the main scene, NmlCore, the AI's step driver, the owner-choice door, the prompt card.
const INCH := 0.0254
const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _epoch_before: int
var _lines: Array = []


func before_test() -> void:
	_epoch_before = AiActRecorder.rules_epoch
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	SoloHarness.start(_main, [2], 1)
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	SoloHarness.instant(_main, false)   # the owner's prompt is asked off the headless batch, as the wound allocation's
	SoloHarness.fast(_main)
	SoloHarness.auto_saves(_main)
	SoloHarness.lesson_paused(_main)
	AiActRecorder.rules_epoch = 108   # the core's PENDING_EPOCH_BLAST_EVEN
	_lines = []
	_main.battle_log.entry_added.connect(_tap)


func after_test() -> void:
	_main.battle_log.entry_added.disconnect(_tap)
	CoreActivation.reset_all(_main)
	CoreActivation._env = -1
	AiActRecorder.rules_epoch = _epoch_before
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _tap(e: Dictionary) -> void:
	_lines.append(str(e["text"]))


func _unit(player: int, name: String, x_in: float, z_in: float, weapon: Dictionary) -> GameUnit:
	var u := ParityTable._make_unit(_main, {"player": player, "name": name, "models": 2, "x_in": 0.0, "z_step_in": 0.0,
		"quality": 2, "defense": 6, "tough": 1, "game_system": "gff", "faction_folder": "robot_legions", "rules": []}, weapon)
	for k in u.models.size():
		(u.models[k] as ModelInstance).node.global_position = Vector3(x_in * INCH, 0, (z_in + k * 1.5) * INCH)
	return u


## The AI's Blast(3) shot at Squad (2 models) beside Mates (2 models, 1 in off): 1 hit -> 3 hits, 1 + 1 and one extra.
## `pick` answers the prompt ("mates" = Mates' key, "" = Automatic). Returns the core's Blast line.
func _volley(pick: String) -> String:
	var gun := {"name": "Mortar", "range_in": 24, "attacks": 1, "count": 1, "rules": ["Blast(3)"]}
	var ai := _unit(2, "Gunner", 0.0, 0.0, gun)
	var squad := _unit(1, "Squad", 12.0, 0.0, {})
	var mates := _unit(1, "Mates", 12.0, 4.0, {})
	CoreActivation._env = 1
	var h := CoreActivation.capture(_main, true)
	var done := [null]
	var go := func() -> void:
		done[0] = await CoreActivation.drive(_main, h, ai, [{"t": "begin"}, {"t": "intent", "kind": 0, "shoot": squad.unit_id},
			{"t": "faces", "faces": [6]}], true)   # the hit rides in the transcript: no seed decides the fixture
	go.call()
	var asked := false
	var until := Time.get_ticks_msec() + 20000   # a time budget: the prompts wait on real-time pacing, not on frames
	while Time.get_ticks_msec() < until:
		if done[0] != null:
			break
		for c in _main.find_children("*", "PromptCard", false, false):
			if str((c as PromptCard).title) == "Blast split" and not asked:
				asked = true
				(c as PromptCard).resolve(mates.unit_id if pick == "mates" else pick)

		await get_tree().process_frame
	assert_bool(asked).override_failure_message("the owner was asked: %s" % [_lines]).is_true()
	var blast: Array = _lines.filter(func(l: String) -> bool: return l.begins_with("Blast(3):"))
	return str(blast[0]) if not blast.is_empty() else "no Blast line: %s" % [_lines]


@warning_ignore('unused_parameter')
func test_the_owner_puts_the_extra_hit_on_its_other_unit(do_skip := not ClassDB.class_exists("NmlCore"),
		skip_reason := "NmlCore extension not loaded") -> void:
	assert_str(await _volley("mates")).is_equal("Blast(3): 1 hit -> 1 on Squad, 2 on units within reach, 0 lost")


@warning_ignore('unused_parameter')
func test_automatic_keeps_the_extra_hit_on_the_target(do_skip := not ClassDB.class_exists("NmlCore"),
		skip_reason := "NmlCore extension not loaded") -> void:
	assert_str(await _volley("")).is_equal("Blast(3): 1 hit -> 2 on Squad, 1 on units within reach, 0 lost")


func test_an_ai_owned_target_is_never_probed() -> void:
	var shooter := _unit(1, "Shooter", 0.0, 0.0, {"name": "Mortar", "range_in": 24, "attacks": 1, "count": 1, "rules": ["Blast(3)"]})
	var foe := _unit(2, "Foe", 12.0, 0.0, {})
	var human := _unit(1, "Friend", 12.0, 8.0, {})
	var ids := CoreActivation.pending_choices(_main, shooter, [{"t": "begin"}, {"t": "intent", "kind": 0, "shoot": foe.unit_id}])
	assert_bool(ids.any(func(i: String) -> bool: return i.begins_with("blast_split:"))).override_failure_message("AI target: %s" % [ids]).is_false()
	var raider := _unit(2, "Raider", 0.0, 20.0, {})
	ids = CoreActivation.pending_choices(_main, raider, [{"t": "begin"}, {"t": "intent", "kind": 0, "shoot": human.unit_id}])
	assert_bool(ids.has("blast_split:%s:%s" % [raider.unit_id, human.unit_id])).override_failure_message("human target: %s" % [ids]).is_true()
