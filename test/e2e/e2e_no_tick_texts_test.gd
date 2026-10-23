extends GdUnitTestSuite
## "No AI without its tick" (#1719), the player-visible texts. On a table with no AI seat — (a) a local
## Automatic table, (b) a ticked game whose tick came off — three texts still spoke "you vs NACHTMAHR":
## the game-over verdict ("You win — NACHTMAHR yields."), the morale roll of a human attack ("AI (X)")
## and the cast step ("NACHTMAHR interferes" — its calculus spent the other player's tokens).
## Real: scenes/main.tscn, the real hotseat round end, _run_human_shooting / _run_human_melee and
## _run_human_cast with the real InterferenceDialog card.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _saved: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_saved = [SoloController.mission_scoring, SoloController.mission_vp.duplicate(),
		SoloController.mission_markers.duplicate(true)]
	SoloController.mission_scoring = ""
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main._solo_batch = true
	_main._solo_auto_saves = true
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.rules_automation = RulesAutomation.Level.AUTOMATIC


func after_test() -> void:
	SoloController.mission_scoring = _saved[0]
	SoloController.mission_vp = _saved[1]
	SoloController.mission_markers = _saved[2]
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _reg(pid: int, unit_name: String, x_in: float, models: int = 1, rules: Array = []) -> GameUnit:
	var at: Array = []
	for i in models:
		at.append(Vector3(x_in * INCH, 0.0, 0.02 * i))
	var u := E2EBoot.make_unit(_main, pid, unit_name, at)
	u.unit_properties["special_rules"] = rules
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## Quality 2+ with 8 attacks — a melee weapon at range 0.
func _armed(unit_name: String, range_in: int) -> GameUnit:
	var u := _reg(1, unit_name, 0.0)
	u.unit_properties["quality"] = 2
	var opr := OPRApiClient.OPRUnit.new()
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Rifle" if range_in > 0 else "Blade"
	w.range_value = range_in
	w.attacks = 8
	var ws: Array[OPRApiClient.OPRWeapon] = [w]
	opr.weapons = ws
	u.source_type = "opr"
	u.source_data = opr
	return u


func _log_from(start: int) -> String:
	var t := ""
	for e in _main.battle_log.entries().slice(start):
		t += str((e as Dictionary)["text"]) + "\n"
	return t


func _assert_no_ai(text: String, what: String) -> void:
	var leak := RegEx.create_from_string("\\bAI\\b|NACHTMAHR|\\bYou\\b|\\byour\\b").search(text)
	assert_object(leak).override_failure_message("%s speaks 'you vs NACHTMAHR' without a tick ('%s'):\n%s" % [
		what, leak.get_string() if leak != null else "", text]).is_null()


func _activate(unit: GameUnit) -> void:
	await _main.radial_menu_controller._toggle_activation({"game_unit": unit})
	await _runner.simulate_frames(4)
	await E2EBoot.settle(get_tree())


func _untick_after_a_ticked_game() -> void:
	_main._on_solo_ai_toggled(true, 2)   # a ticked game earlier in the session builds its controller…
	_main._ensure_solo_controller()
	_main._on_solo_ai_toggled(false, 2)  # …then the tick comes off


# --- 2. The morale roll of a human attack ---

## 11 of 20 models stand, Defense 6+: any wound drops the unit to half, 8 wounds cannot wipe it.
func _assert_morale_by_name(melee: bool) -> void:
	var attacker := _armed("Rifles", 0 if melee else 24)
	var foe := _reg(2, "Raiders", 0.6 if melee else 8.0, 20)
	foe.unit_properties["defense"] = 6
	for i in range(11, 20):
		(foe.models[i] as ModelInstance).is_alive = false   # the far end of the line
	_main._ensure_solo_controller()
	var start: int = _main.battle_log.entries().size()
	if melee:
		await _main._run_human_melee(attacker, foe, true)
	else:
		await _main._run_human_shooting(attacker, foe)
	var text := _log_from(start)
	assert_bool(text.contains("Raiders passes morale") or text.contains("Raiders fails morale")) \
		.override_failure_message("fixture: no morale result:\n%s" % text).is_true()
	_assert_no_ai(text, "the %s morale roll" % ("melee" if melee else "shooting"))


func test_a_volley_morale_roll_names_the_defending_player(timeout := 120000) -> void:
	await _assert_morale_by_name(false)


func test_a_melee_morale_roll_names_the_losing_player(timeout := 120000) -> void:
	await _assert_morale_by_name(true)


# --- 3. The cast step: the opponent decides its own interference ---

func _interference_card() -> PromptCard:
	for n in _main.get_children():
		if n is InterferenceDialog:
			for c in n.get_children():
				if c is PromptCard and (c as PromptCard).title == "Enemy spell!":
					return c
	return null


func test_a_two_human_cast_asks_the_opponent_never_nachtmahr(timeout := 120000) -> void:
	var seer := _reg(1, "Seer", 0.0, 1, ["Caster(2)"])
	seer.casts_current = 2
	var foe := _reg(2, "Raiders", 10.0)
	var witch := _reg(2, "Witch", -6.0, 1, ["Caster(2)"])   # behind the seer: nothing blocks its sight
	witch.casts_current = 2
	_main._ensure_solo_controller()
	var start: int = _main.battle_log.entries().size()
	var done := [false]
	(func() -> void:
		await _main._run_human_cast(seer, seer, {"name": "Bolt", "threshold": 2}, [foe])
		done[0] = true).call()
	var card: PromptCard = null
	for _i in 300:
		card = _interference_card()
		if card != null or done[0]:
			break
		await get_tree().process_frame
	assert_object(card).override_failure_message("P2 was never asked to interfere:\n%s" % _log_from(start)).is_not_null()
	if card != null:
		card.resolve(1)   # P2 spends ONE token — the player's own choice
	for _i in 300:
		if done[0]:
			break
		await get_tree().process_frame
	var text := _log_from(start)
	_assert_no_ai(text, "the two-human cast")
	assert_int(witch.casts_current).override_failure_message("P2's tokens were not spent by P2's choice:\n%s" % text).is_equal(1)
	await E2EBoot.settle(get_tree())


# --- 1. The game-over verdict ---

func _assert_game_over_by_name(path: String) -> void:
	var p1 := _reg(1, "Rifles", -10.0, 3)
	var p2 := _reg(2, "Raiders", 10.0, 2)
	_main.opr_army_manager.current_round = _main._solo_total_rounds()
	_main._solo_game_finished = false
	var start: int = _main.battle_log.entries().size()
	await _activate(p1)
	await _activate(p2)   # both spent in the final round -> the summary
	var text := _log_from(start)
	assert_str(text).override_failure_message("%s: the game did not end:\n%s" % [path, text]).contains("=== GAME OVER")
	assert_str(text).override_failure_message("%s: the verdict names no player:\n%s" % [path, text]).contains("P1 wins")
	_assert_no_ai(text, path + ": the game-over summary")


func test_automatic_table_game_over_names_the_players(timeout := 120000) -> void:
	await _assert_game_over_by_name("(a) Automatic table")


func test_a_removed_tick_game_over_names_the_players(timeout := 120000) -> void:
	_untick_after_a_ticked_game()
	await _assert_game_over_by_name("(b) tick removed")
