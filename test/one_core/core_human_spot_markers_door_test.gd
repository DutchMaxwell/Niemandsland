extends GdUnitTestSuite
## A human attacker at the door picks how many Precision Spotter markers to remove from its target, with the table's own marker
## dialog (`_solo_ask_spot_markers`), and the core removes that many (NeedChoice `spot_markers:<shooter>:<target>`, options
## "0".."N"; no answer takes them all, as the AI does). Before, only the table's `_solo_offer_spot_markers` asked - removing the
## table's volley would have taken the choice away from the player.
## Real: the main scene, NmlCore, the door's driver and choice plumbing, the table's dialog. Constructed: a 3-model gf rifle unit and
## a 5-model foe 12" away carrying 3 spot markers.
## RED (on main): no `spot_markers` probe for the human shooter, and the owner's answer path returns "" without a dialog.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")
const SIDE := {"quality": 4, "defense": 4, "tough": 1, "z_step_in": 1.5, "game_system": "gf",
	"faction_folder": "battle_brothers", "rules": []}
const RIFLE := {"name": "Rifle", "range_in": 24, "attacks": 2, "count": 3, "rules": []}
const MARKERS := 3

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	SoloHarness.start(_main, [2], 1)
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	SoloHarness.instant(_main)
	CoreActivation._env = 1


func after_test() -> void:
	SoloHarness.instant(_main)
	CoreActivation.reset_all(_main)
	CoreActivation._env = -1
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _pair(player: int, markers: int = MARKERS) -> Array:
	var att := ParityTable._make_unit(_main, SIDE.merged({"player": player, "name": "Gunners", "models": 3, "x_in": 0.0}, true), RIFLE)
	var foe := ParityTable._make_unit(_main, SIDE.merged({"player": 3 - player, "name": "Foe", "models": 5, "x_in": 12.0}, true), {})
	foe.unit_properties["spot_markers"] = markers
	return [att, foe]


func _intent(units: Array) -> Array:
	return [{"t": "begin"}, {"t": "intent", "kind": AiDecision.Action.HOLD, "shoot": (units[1] as GameUnit).unit_id}]


func _free(units: Array) -> void:
	for u in units:
		_main.opr_army_manager.game_units.erase((u as GameUnit).unit_id)
		for m in (u as GameUnit).models:
			if (m as ModelInstance).node != null and is_instance_valid((m as ModelInstance).node):
				(m as ModelInstance).node.free()
	CoreActivation.reset_all(_main)


func test_the_door_probes_the_markers_of_a_human_shooter_only() -> void:
	var human := _pair(1)
	var id := "spot_markers:%s:%s" % [(human[0] as GameUnit).unit_id, (human[1] as GameUnit).unit_id]
	assert_array(CoreActivation.pending_choices(_main, human[0], _intent(human))).override_failure_message("the human attacker is asked") \
		.contains([id])
	_free(human)
	var bare := _pair(1, 0)
	assert_bool(CoreActivation.pending_choices(_main, bare[0], _intent(bare)).any(func(x: String) -> bool: return x.begins_with("spot_markers:"))) \
		.override_failure_message("a target without markers asks nothing").is_false()
	_free(bare)
	var ai := _pair(2)
	assert_bool(CoreActivation.pending_choices(_main, ai[0], _intent(ai)).any(func(x: String) -> bool: return x.begins_with("spot_markers:"))) \
		.override_failure_message("an AI attacker keeps the core's take-all").is_false()


## The owner's answer: the table's marker dialog; the stepper's count is one of the core's options.
func test_the_owner_answers_with_the_tables_marker_dialog() -> void:
	var units := _pair(1)
	var att: GameUnit = units[0]
	SoloHarness.instant(_main, false)   # the dialog is asked as on the table (the headless batch keeps the take-all)
	var out := {}
	var ask := func() -> void: out["option"] = await _main._solo_choice_local(att,
		"spot_markers:%s:%s" % [att.unit_id, (units[1] as GameUnit).unit_id], ["0", "1", "2", "3"])
	ask.call()
	var card: PromptCard = null
	for _i in 300:
		for n in _main.get_children():
			if n is InterferenceDialog:
				for c in n.get_children():
					card = c if c is PromptCard and (c as PromptCard).title == "Spotted target!" else card
		if card != null or out.has("option"):
			break
		await get_tree().process_frame
	assert_object(card).override_failure_message("no marker dialog was shown (%s)" % [out]).is_not_null()
	if card == null:
		return
	card.resolve(2)
	for _i in 300:
		if out.has("option"):
			break
		await get_tree().process_frame
	assert_str(str(out.get("option", "still waiting"))).is_equal("2")


## The core removes the count the player picked; the rest stay on the target.
func test_the_core_removes_the_markers_the_player_picked() -> void:
	for take in [0, 2]:
		var units := _pair(1)
		var att: GameUnit = units[0]
		var foe: GameUnit = units[1]
		_main.seed_tray_rng(5)
		var from: int = _main.battle_log.entries().size()
		var t: Array = _intent(units) + [{"t": "choice", "id": "spot_markers:%s:%s" % [att.unit_id, foe.unit_id], "option": str(take)}]
		var r: Dictionary = await CoreActivation.drive(_main, CoreActivation.capture(_main), att, t, false)
		assert_str(str(r["step"])).override_failure_message("%d: %s" % [take, r]).is_equal("done")
		assert_int(int(foe.unit_properties.get("spot_markers", -1))).override_failure_message("%d removed: markers left" % take) \
			.is_equal(MARKERS - take)
		var lines: Array = _main.battle_log.entries().slice(from).map(func(e: Dictionary) -> String: return str(e["text"]))
		var said: int = lines.filter(func(l: String) -> bool: return l.begins_with("Precision Spotter: %d marker" % take)).size()
		assert_int(said).override_failure_message("%d: the removal line (%s)" % [take, lines]).is_equal(1 if take > 0 else 0)
		_free(units)
