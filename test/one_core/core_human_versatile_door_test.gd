extends GdUnitTestSuite
## PLAN_FIRST_DELETION step 22b (OD-2: a player's own pick is asked through the core): a human Versatile Attack shooter at the door
## is asked for the mode with the table's own prompt (`_solo_prompt_versatile`), and the core rolls the mode the player picked
## (22a, #3432: NeedChoice `versatile_mode:<unit>`, options `ap` / `hit`). Before, only `_run_human_shooting` asked - the deletion
## would have taken the choice away from the player.
## Real: the main scene, NmlCore, the door's driver and choice plumbing, the table's prompt card. Constructed: a 3-model gf unit with
## Versatile Attack and a rifle, a foe 12" away (over 9": the rule's window).
## RED (on main): no `versatile_mode` probe for the human shooter, and the owner's answer path returns "" without a card.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")
const SIDE := {"quality": 4, "defense": 4, "tough": 1, "z_step_in": 1.5, "game_system": "gf",
	"faction_folder": "battle_brothers", "rules": []}
const RIFLE := {"name": "Rifle", "range_in": 24, "attacks": 2, "count": 3, "rules": []}

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.solo_controller.ai_slot = 2
	_main.solo_controller.human_slot = 1
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	_main._solo_batch = true
	CoreActivation._env = 1


func after_test() -> void:
	_main._solo_batch = true
	CoreActivation.reset_all(_main)
	CoreActivation._env = -1
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _pair(player: int) -> Array:
	var att := ParityTable._make_unit(_main, SIDE.merged({"player": player, "name": "Vets", "models": 3, "x_in": 0.0,
		"rules": ["Versatile Attack"]}, true), RIFLE)
	var foe := ParityTable._make_unit(_main, SIDE.merged({"player": 3 - player, "name": "Foe", "models": 5, "x_in": 12.0}, true), {})
	return [att, foe]


func test_the_door_probes_the_mode_of_a_human_versatile_shooter_only() -> void:
	var human := _pair(1)
	var t: Array = [{"t": "begin"}, {"t": "intent", "kind": AiDecision.Action.HOLD, "shoot": (human[1] as GameUnit).unit_id}]
	assert_array(CoreActivation.pending_choices(_main, human[0], t)).override_failure_message("the human shooter's mode is asked") \
		.contains(["versatile_mode:%s" % (human[0] as GameUnit).unit_id])
	var ai := _pair(2)
	var t2: Array = [{"t": "begin"}, {"t": "intent", "kind": AiDecision.Action.HOLD, "shoot": (ai[1] as GameUnit).unit_id}]
	assert_bool(CoreActivation.pending_choices(_main, ai[0], t2).any(func(x: String) -> bool: return x.begins_with("versatile_mode:"))) \
		.override_failure_message("an AI shooter keeps the core's own pick").is_false()


## The owner's answer: the table's card, its recommended button first; either button is one of the core's options.
func test_the_owner_answers_the_mode_with_the_tables_prompt() -> void:
	var att: GameUnit = _pair(1)[0]
	_main._solo_batch = false   # the card is asked as on the table (the headless batch keeps the core's pick)
	for take_recommended in [true, false]:
		var out := {}
		var ask := func() -> void: out["option"] = await _main._solo_choice_local(att, "versatile_mode:%s" % att.unit_id, ["ap", "hit"], 0,
			{"weapon": "Rifle", "recommended": {"ap": 1, "hit_mod": 0}})
		ask.call()
		var card: PromptCard = null
		for _i in 300:
			for c in _main.get_children():
				card = c if c is PromptCard and (c as PromptCard).title == "Versatile Attack" else card
			if card != null or out.has("option"):
				break
			await get_tree().process_frame
		assert_object(card).override_failure_message("no Versatile card was shown (%s)" % [out]).is_not_null()
		if card == null:
			return
		card.resolve(take_recommended)
		for _i in 300:
			if out.has("option"):
				break
			await get_tree().process_frame
		assert_str(str(out.get("option", "still waiting"))).is_equal("ap" if take_recommended else "hit")


## The core rolls the player's mode: an answered `versatile_mode` choice lands the pick on the table's latch.
func test_the_core_rolls_the_mode_the_player_picked() -> void:
	for option in ["hit", "ap"]:
		var units := _pair(1)
		var att: GameUnit = units[0]
		_main.seed_tray_rng(5)
		var t: Array = [{"t": "begin"}, {"t": "intent", "kind": AiDecision.Action.HOLD, "shoot": (units[1] as GameUnit).unit_id},
			{"t": "choice", "id": "versatile_mode:%s" % att.unit_id, "option": option}]
		var r: Dictionary = await CoreActivation.drive(_main, CoreActivation.capture(_main), att, t, false)
		assert_str(str(r["step"])).override_failure_message("%s: %s" % [option, r]).is_equal("done")
		var want := {"hit_mod": 1, "ap": 0} if option == "hit" else {"hit_mod": 0, "ap": 1}
		assert_dict(att.unit_properties.get("versatile_pick", {})).override_failure_message("%s: the latch holds the pick" % option).is_equal(want)
		for u in units:
			_main.opr_army_manager.game_units.erase((u as GameUnit).unit_id)
			for m in (u as GameUnit).models:
				if (m as ModelInstance).node != null and is_instance_valid((m as ModelInstance).node):
					(m as ModelInstance).node.free()
		CoreActivation.reset_all(_main)
