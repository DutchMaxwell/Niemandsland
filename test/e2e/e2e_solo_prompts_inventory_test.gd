extends GdUnitTestSuite
## E2E — the solo combat prompts, rows 29-37 of the UI inventory (uiprompts step 3: ONE in-viewport prompt
## for all of them, maintainer D98 = a). Pins TODAY's FULL function set before the restyle: each prompt is
## raised by the production function that raises it in play, found by the words the player reads, every
## control is reached by a REAL pointer click, and the answer does what it does today (the return value,
## the battle-log line, the rolled saves, the unit off the table). Shape-blind on purpose: the same cases
## pass on today's native dialogs and on the in-viewport cards that replace them.
## Hero morale rides along: the same yes/no helper asks it, the inventory has no row for it.
## test_the_inventory_check_names_a_removed_control proves the control check can fail.
## Since the restyle: every prompt in CARDS must come up as the house-style PromptCard, answer Enter / Esc
## as the old dialogs did, and keep the table out of reach (clicks and hotkeys).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
## The layer the in-viewport prompts live on (spell picker and interference dialog today).
const PROMPT_LAYER := 90
## The prompts already moved into the in-viewport card (PromptCard, D98 = a); each must come up as one.
const CARDS := ["Incoming fire!", "Strike back?", "Cast window", "Versatile Attack", "Ambush Re-Deployment",
	"Summon Imps", "Hero morale", "Split fire?", "Enemy spell!", "Spotted target!", "Boost your cast?"]

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
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


# === fixtures =================================================================================

func _unit(pid: int, unit_name: String, positions: Array) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, positions)
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## A lone caster hero with spell tokens (orcs, AoF: the registry has their spells).
func _caster(tokens: int) -> GameUnit:
	var u := _unit(1, "Warboss", [Vector3.ZERO])
	u.unit_properties["special_rules"] = ["Caster(2)"]
	u.unit_properties["game_system"] = "aof"
	u.unit_properties["faction_folder"] = "orcs"
	u.casts_current = tokens
	return u


func _log_count() -> int:
	return _main.battle_log.entries().size()


func _log_since(n: int) -> String:
	var text := ""
	var entries: Array = _main.battle_log.entries()
	for i in range(n, entries.size()):
		text += str((entries[i] as Dictionary)["text"]) + "\n"
	return text


## Waits (bounded) until the coroutine started with a result box has put its answer in, and returns
## it — null (a failed check, not a crash) when the caller never returned.
func _answer(out: Array) -> Variant:
	for _i in 300:
		if not out.is_empty():
			return out[0]
		await get_tree().process_frame
	fail("the prompt's caller never returned")
	return null


# === the prompt, shape-blind ==================================================================

## The prompt standing now: a visible native dialog (today) or a CanvasLayer on the prompt layer
## (the in-viewport cards). null = none.
func _prompt() -> Node:
	for n: Node in get_tree().root.find_children("*", "", true, false):
		if n.is_queued_for_deletion():
			continue
		if n is AcceptDialog and (n as AcceptDialog).visible:
			return n
		if n is CanvasLayer and (n as CanvasLayer).layer == PROMPT_LAYER and (n as CanvasLayer).visible \
				and not _buttons(n).is_empty():
			return n
	return null


## Waits for the prompt titled `title` (case-blind: a house header shows its title in capitals).
func _await_prompt(title: String) -> Node:
	for _i in 120:
		var p := _prompt()
		if p != null and _title_of(p).to_lower().contains(title.to_lower()):
			await _runner.simulate_frames(2)
			if CARDS.has(title):
				_assert_house_card(p)
			return p
		await get_tree().process_frame
	fail("no prompt titled '%s' came up (standing: %s)" % [title, _title_of(_prompt()) if _prompt() != null else "none"])
	return null


func _labels(p: Node) -> Array:
	var out: Array = []
	for n: Node in p.find_children("*", "Label", true, false):
		if (n as Label).is_visible_in_tree() and not n.is_queued_for_deletion():
			out.append(n)
	return out


func _title_of(p: Node) -> String:
	if p is AcceptDialog:
		return (p as AcceptDialog).title
	var labels := _labels(p)
	return (labels[0] as Label).text if not labels.is_empty() else ""


## Everything the prompt says, title excluded.
func _text_of(p: Node) -> String:
	var text := (p as AcceptDialog).dialog_text + "\n" if p is AcceptDialog else ""
	var labels := _labels(p)
	for i in labels.size():
		if p is AcceptDialog or i > 0:
			text += (labels[i] as Label).text + "\n"
	return text


## The prompt's visible buttons: a native dialog's OK / Cancel plus its own content, or a card's.
func _buttons(p: Node) -> Array:
	var out: Array = []
	if p is AcceptDialog:
		var dlg := p as AcceptDialog
		for b: Button in [dlg.get_ok_button(), dlg.get_cancel_button() if p is ConfirmationDialog else null]:
			if b != null and b.is_visible_in_tree():
				out.append(b)
	for n: Node in p.find_children("*", "Button", true, false):
		if (n as Button).is_visible_in_tree() and not n.is_queued_for_deletion() and not out.has(n):
			out.append(n)
	return out


func _button(p: Node, text: String) -> Button:
	for b: Button in _buttons(p):
		if b.text == text:
			return b
	fail("the prompt '%s' has no button '%s' (it has %s)" % [_title_of(p), text, _texts(p)])
	return null


func _texts(p: Node) -> Array:
	var out: Array = []
	for b: Button in _buttons(p):
		out.append(b.text)
	return out


## Today's controls the prompt no longer shows ("button: <text>"); empty = all there.
func _missing(p: Node, expected: Array) -> Array:
	var have := _texts(p)
	var out: Array = []
	for t: Variant in expected:
		if not have.has(str(t)):
			out.append("button: %s" % t)
	return out


func _assert_controls(p: Node, expected: Array) -> void:
	assert_array(_missing(p, expected)).override_failure_message(
		"today's controls missing from '%s': %s (it shows %s)" % [_title_of(p), _missing(p, expected), _texts(p)]).is_empty()


## A moved prompt: an in-viewport PromptCard (no OS window), dressed by the house theme alone — OK is the
## gold primary action, cancel a ghost button, the card keeps its fixed width, no control sets its own
## colour or font size.
func _assert_house_card(p: Node) -> void:
	assert_bool(p is PromptCard).override_failure_message("'%s' is still a %s, not the in-viewport card" % [
		_title_of(p), p.get_class()]).is_true()
	if not p is PromptCard:
		return
	var card := p as PromptCard
	assert_object((card.get_node("Shield") as Control).theme).is_same(HouseStyle.theme())
	if card.ok_button != null:
		assert_str(String(card.ok_button.theme_type_variation)).is_equal(String(HouseStyle.PRIMARY))
	if card.cancel_button != null:
		assert_str(String(card.cancel_button.theme_type_variation)).is_equal(String(HouseStyle.BUTTON))
	var panel := card.find_child("Card", true, false) as Control
	assert_float(panel.size.x).override_failure_message("'%s' is %d px wide, the card %d" % [
		_title_of(p), panel.size.x, PromptCard.WIDTH]).is_equal_approx(PromptCard.WIDTH, 0.5)
	var own: Array = []
	for n: Node in card.find_children("*", "Control", true, false):
		var c := n as Control
		if c.has_theme_color_override(&"font_color") or c.has_theme_font_size_override(&"font_size"):
			own.append(c.name)
	assert_array(own).override_failure_message("'%s': own colour / size on %s" % [_title_of(p), own]).is_empty()


## A key down and up, pushed through the table's viewport the way the engine delivers it.
func _key(code: Key) -> void:
	var vp := _main.get_viewport()
	for down: bool in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = down
		vp.push_input(ev)
	await _runner.simulate_frames(2)


## A real click at the centre of `b`. A native dialog is an embedded window: its controls speak its own
## coordinates, so its position on the table canvas is added. A card's button must be the control
## under the pointer — another surface over it would take the click instead.
func _click(b: Button) -> void:
	if b == null:
		return
	var vp := _main.get_viewport()
	var at := b.get_global_rect().get_center()
	var w := b.get_window()
	if w != null and w != vp:
		at += Vector2(w.position)
	E2EBoot.motion_canvas(vp, at)
	if w == vp:
		var under := vp.gui_get_hovered_control()
		assert_bool(under == b or (under != null and b.is_ancestor_of(under))).override_failure_message(
			"'%s' is covered at %s by %s" % [b.text, at, under.get_path() if under != null else "nothing"]).is_true()
	E2EBoot.click_canvas(vp, at, true)
	E2EBoot.click_canvas(vp, at, false)
	await _runner.simulate_frames(3)


# === rows 29-35 + Hero morale: the yes/no questions ===========================================

## Row 29: the most frequent modal in solo. One action, no cancel; the saves roll in the tray and the
## log names the MODIFIED threshold.
func test_incoming_fire_rolls_the_saves_it_names(timeout := 120000) -> void:
	var shooter := _unit(2, "Raiders", [Vector3(0.5, 0, 0)])
	var target := _unit(1, "Guards", [Vector3.ZERO, Vector3(0.05, 0, 0)])
	_main._solo_auto_saves = false
	_main._solo_batch = true   # the tray draws its faces at once (no physics settle headless)
	var n := _log_count()
	var out: Array = []
	(func() -> void: out.append(await _main._solo_prompt_saves(shooter, target, "Rifle", 3, 4, 1))).call()
	var p := await _await_prompt("Incoming fire!")
	assert_str(_text_of(p)).contains("Raiders hits Guards 3 times with Rifle.")
	assert_str(_text_of(p)).contains("Roll your defense saves (AP 1 → save on 5+).")
	_assert_controls(p, ["Roll 3 saves"])
	assert_array(_texts(p)).override_failure_message("saves are not optional: %s" % [_texts(p)]) \
		.not_contains(["Cancel"])
	await _click(_button(p, "Roll 3 saves"))
	var got: Variant = await _answer(out)
	assert_array(got).has_size(3)
	assert_str(_log_since(n)).contains("Guards saves on 5+")
	assert_object(_prompt()).override_failure_message("the prompt must close on its answer").is_null()


## Row 30: two texts (plain / Counter first), two answers, each logged.
func test_strike_back_and_hold_each_answer_and_log(timeout := 120000) -> void:
	var charger := _unit(2, "Raiders", [Vector3(0.05, 0, 0)])
	var defender := _unit(1, "Guards", [Vector3.ZERO])
	var n := _log_count()
	var out: Array = []
	(func() -> void: out.append(await _main._solo_confirm_strike_back(defender, charger, false))).call()
	var p := await _await_prompt("Strike back?")
	assert_str(_text_of(p)).contains("Guards is in melee with Raiders.")
	_assert_controls(p, ["Strike back", "Hold"])
	await _click(_button(p, "Strike back"))
	var got: Variant = await _answer(out)
	assert_bool(got).is_true()
	assert_str(_log_since(n)).contains("Guards strikes back")

	n = _log_count()
	out = []
	(func() -> void: out.append(await _main._solo_confirm_strike_back(defender, charger, true))).call()
	p = await _await_prompt("Strike back?")
	assert_str(_text_of(p)).contains("Raiders charges Guards.")
	assert_str(_text_of(p)).contains("Guards has Counter — its Counter weapons strike FIRST.")
	await _click(_button(p, "Hold"))
	got = await _answer(out)
	assert_bool(got).is_false()
	assert_str(_log_since(n)).contains("Guards holds — no strike back")


## Row 31: asked before the attack while the caster can pay a spell, once per unit per round.
func test_the_cast_window_asks_once_per_round(timeout := 120000) -> void:
	var hero := _caster(2)
	var n := _log_count()
	var out: Array = []
	(func() -> void: out.append(await _main._solo_confirm_cast_first(hero))).call()
	var p := await _await_prompt("Cast window")
	assert_str(_text_of(p)).contains("Warboss can still cast (2 tokens left).")
	assert_str(_text_of(p)).contains("Spells must be cast BEFORE attacking (GF v3.5.1)")
	_assert_controls(p, ["Cast first", "Attack without casting"])
	await _click(_button(p, "Cast first"))
	var got: Variant = await _answer(out)
	assert_bool(got).is_true()
	assert_str(_log_since(n)).contains("Warboss casts before attacking")
	# Once per unit per round: the second ask answers at once, without a prompt.
	assert_bool(await _main._solo_confirm_cast_first(hero)).is_false()
	assert_object(_prompt()).is_null()

	_main.opr_army_manager.current_round += 1
	n = _log_count()
	out = []
	(func() -> void: out.append(await _main._solo_confirm_cast_first(hero))).call()
	p = await _await_prompt("Cast window")
	await _click(_button(p, "Attack without casting"))
	got = await _answer(out)
	assert_bool(got).is_false()
	assert_str(_log_since(n)).contains("Warboss attacks — cast window passed")


## Row 33: both modes are real choices; the EV-recommended one sits on the OK button.
func test_versatile_offers_both_modes_with_the_recommended_one_first(timeout := 120000) -> void:
	var out: Array = []
	(func() -> void: out.append(await _main._solo_prompt_versatile("Chain Gun", {"ap": 1, "hit_mod": 0}))).call()
	var p := await _await_prompt("Versatile Attack")
	assert_str(_text_of(p)).contains("Chain Gun is Versatile (target over 9\").")
	assert_str(_text_of(p)).contains("Choose the mode for this volley:")
	_assert_controls(p, ["AP(+1) — recommended", "+1 to hit"])
	await _click(_button(p, "AP(+1) — recommended"))
	var got: Variant = await _answer(out)
	assert_dict(got).is_equal({"ap": 1, "hit_mod": 0})

	out = []
	(func() -> void: out.append(await _main._solo_prompt_versatile("Chain Gun", {"ap": 0, "hit_mod": 1}))).call()
	p = await _await_prompt("Versatile Attack")
	_assert_controls(p, ["+1 to hit — recommended", "AP(+1)"])
	await _click(_button(p, "AP(+1)"))
	got = await _answer(out)
	assert_dict(got).is_equal({"ap": 1, "hit_mod": 0})


## Row 34: the end-of-activation door — stay (logged, use kept) or withdraw (off the table, back next round).
func test_ambush_redeployment_stays_or_withdraws(timeout := 120000) -> void:
	var jesters := _unit(1, "Jesters", [Vector3.ZERO])
	jesters.unit_properties["special_rules"] = ["Ambush Re-Deployment"]
	_main.opr_army_manager.current_round = 2
	var n := _log_count()
	var out: Array = []
	(func() -> void: out.append(await _main._solo_try_ambush_redeploy(jesters))).call()
	var p := await _await_prompt("Ambush Re-Deployment")
	assert_str(_text_of(p)).contains("Jesters has ended its activation.")
	assert_str(_text_of(p)).contains("bring it back from Ambush at the start of round 3?")
	_assert_controls(p, ["Withdraw", "Stay on the table"])
	await _click(_button(p, "Stay on the table"))
	var got: Variant = await _answer(out)
	assert_bool(got).is_false()
	assert_bool(SoloController.unit_in_reserve(jesters)).is_false()
	assert_str(_log_since(n)).contains("Ambush Re-Deployment: Jesters stays on the table — its once-per-game use is still open")

	out = []
	(func() -> void: out.append(await _main._solo_try_ambush_redeploy(jesters))).call()
	p = await _await_prompt("Ambush Re-Deployment")
	await _click(_button(p, "Withdraw"))
	got = await _answer(out)
	assert_bool(got).is_true()
	assert_bool(SoloController.unit_in_reserve(jesters)).is_true()
	assert_int(int(jesters.unit_properties.get("ambush_return_round", 0))).is_equal(3)


## Row 35: a rule that places units asks under the rule's own name.
func test_rule_placement_asks_under_the_rule_name(timeout := 120000) -> void:
	var out: Array = []
	(func() -> void: out.append(await _main._solo_confirm_rule_unit("Summon Imps", "Imps", 3))).call()
	var p := await _await_prompt("Summon Imps")
	assert_str(_text_of(p)).contains("Place Imps [3]?")
	_assert_controls(p, ["OK", "Cancel"])
	await _click(_button(p, "OK"))
	var got: Variant = await _answer(out)
	assert_bool(got).is_true()

	out = []
	(func() -> void: out.append(await _main._solo_confirm_rule_unit("Summon Imps", "Imps", 3))).call()
	p = await _await_prompt("Summon Imps")
	await _click(_button(p, "Cancel"))
	got = await _answer(out)
	assert_bool(got).is_false()


## Not a row: Hero morale rides on the same helper — asked once per unit, the answer sticks.
func test_hero_morale_is_asked_once_and_the_answer_sticks(timeout := 120000) -> void:
	var guards := _unit(1, "Guards", [Vector3.ZERO])
	var hero := _unit(1, "Captain", [Vector3(0.03, 0, 0)])
	guards.unit_properties["attached_heroes"] = [hero]
	hero.unit_properties["attached_to"] = guards
	var out: Array = []
	(func() -> void:
		await _main._solo_ask_hero_morale_once(guards)
		out.append(true)).call()
	var p := await _await_prompt("Hero morale")
	assert_str(_text_of(p)).contains("Let a living Hero test morale for Guards from now on?")
	_assert_controls(p, ["Use Hero", "Use unit"])
	await _click(_button(p, "Use unit"))
	await _answer(out)
	assert_bool(guards.unit_properties.get("hero_tests_morale")).is_false()
	await _main._solo_ask_hero_morale_once(guards)
	assert_object(_prompt()).override_failure_message("asked once per unit").is_null()


# === row 32: split fire =======================================================================

## One check box per weapon group; the checked ones fire at the second target, "All at" keeps one target.
func test_split_fire_returns_the_checked_weapons(timeout := 120000) -> void:
	var raiders := _unit(2, "Raiders", [Vector3(0.5, 0, 0)])
	var names := ["Rifle", "Pistol", "Grenade"]
	var out: Array = []
	(func() -> void: out.append(await _main._solo_ask_split_fire(raiders, names))).call()
	var p := await _await_prompt("Split fire?")
	assert_str(_text_of(p)).contains("Up to two targets (GF v3.5.1 p.8). Checked weapons fire at a SECOND target:")
	_assert_controls(p, ["Rifle", "Pistol", "Grenade", "Pick 2nd target", "All at Raiders"])
	await _click(_button(p, "Pistol"))
	assert_bool(_button(p, "Pistol").button_pressed).is_true()
	await _click(_button(p, "Pick 2nd target"))
	var got: Variant = await _answer(out)
	assert_array(got).contains_exactly(["Pistol"])

	out = []
	(func() -> void: out.append(await _main._solo_ask_split_fire(raiders, names))).call()
	p = await _await_prompt("Split fire?")
	await _click(_button(p, "Rifle"))
	await _click(_button(p, "All at Raiders"))
	got = await _answer(out)
	assert_array(got).override_failure_message("'All at' keeps every weapon on one target").is_empty()


# === rows 36-37: spell picker, interference / spot / boost ====================================

## Row 36: one button per spell with its cost, the effect under it and in its tooltip; a spell the
## caster cannot pay is disabled; Cancel answers {}.
func test_the_spell_picker_offers_every_spell_and_cancel(timeout := 120000) -> void:
	var entries := [
		{"entry": {"name": "Bolt", "threshold": 1}, "text": "Deal 2 hits.", "enabled": true},
		{"entry": {"name": "Storm", "threshold": 3}, "text": "Deal 6 hits.", "enabled": false}]
	var out: Array = []
	var picker := SpellPickerDialog.new()
	_main.add_child(picker)
	(func() -> void: out.append(await picker.pick("Warboss", 1, entries))).call()
	var p := await _await_prompt("Warboss — cast a spell (1 token)")
	_assert_house_card(p)   # row 36 on the house card (asserted here: its title carries the token count)
	_assert_controls(p, ["Bolt  (1 token)", "Storm  (3 tokens)", "Cancel"])
	assert_str(_text_of(p)).contains("Deal 2 hits.")
	assert_str(_text_of(p)).contains("Deal 6 hits.")
	assert_str(_button(p, "Bolt  (1 token)").tooltip_text).is_equal("Deal 2 hits.")
	assert_bool(_button(p, "Storm  (3 tokens)").disabled).is_true()
	await _click(_button(p, "Bolt  (1 token)"))
	var got: Variant = await _answer(out)
	assert_dict(got).contains_key_value("name", "Bolt")

	out = []
	picker = SpellPickerDialog.new()
	_main.add_child(picker)
	(func() -> void: out.append(await picker.pick("Warboss", 1, entries))).call()
	p = await _await_prompt("Warboss — cast a spell (1 token)")
	await _click(_button(p, "Cancel"))
	got = await _answer(out)
	assert_dict(got).is_empty()


## Row 37, enemy cast: − / + move the token count inside the pool, the preview and the confirm text
## follow it, confirm answers the count, "No interference" answers 0.
func test_interference_counts_tokens_with_a_live_preview(timeout := 120000) -> void:
	var out: Array = []
	var dlg := InterferenceDialog.new()
	_main.add_child(dlg)
	(func() -> void: out.append(await dlg.ask("Shaman", "Fireball", "Guards", 4, 0, 3))).call()
	var p := await _await_prompt("Enemy spell!")
	assert_str(_text_of(p)).contains("Shaman is casting Fireball at Guards.")
	assert_str(_text_of(p)).contains("Spell tokens in 18\" line of sight: 3")
	_assert_controls(p, ["−", "+", "Interfere (-1)", "No interference"])
	assert_str(_text_of(p)).contains("1 token")
	assert_str(_text_of(p)).contains(InterferenceDialog.format_preview(4, 0, 1))
	await _click(_button(p, "+"))
	await _click(_button(p, "+"))
	await _click(_button(p, "+"))   # the pool holds 3: the count stops there
	assert_str(_text_of(p)).contains("3 tokens")
	assert_str(_text_of(p)).contains(InterferenceDialog.format_preview(4, 0, 3))
	await _click(_button(p, "−"))
	await _click(_button(p, "Interfere (-2)"))
	var got: Variant = await _answer(out)
	assert_int(got).is_equal(2)

	out = []
	dlg = InterferenceDialog.new()
	_main.add_child(dlg)
	(func() -> void: out.append(await dlg.ask("Shaman", "Fireball", "Guards", 4, 0, 3))).call()
	p = await _await_prompt("Enemy spell!")
	await _click(_button(p, "−"))
	_assert_controls(p, ["Confirm (no tokens)"])
	await _click(_button(p, "No interference"))
	got = await _answer(out)
	assert_int(got).is_equal(0)


## Row 37, spot markers and the own-cast boost: the same tableau in its two other modes.
func test_spot_and_boost_modes_word_their_choices(timeout := 120000) -> void:
	var out: Array = []
	var dlg := InterferenceDialog.new()
	_main.add_child(dlg)
	(func() -> void: out.append(await dlg.ask("Guards", "", "Raiders", 4, 0, 2, "spot"))).call()
	var p := await _await_prompt("Spotted target!")
	assert_str(_text_of(p)).contains("Guards attacks Raiders.")
	assert_str(_text_of(p)).contains("Spot markers on the target: 2")
	_assert_controls(p, ["Remove 1 (+1 to hit)", "Leave markers"])
	assert_str(_text_of(p)).contains(InterferenceDialog.format_preview_spot(1))
	await _click(_button(p, "−"))
	await _click(_button(p, "Attack without markers"))
	var got: Variant = await _answer(out)
	assert_int(got).is_equal(0)

	out = []
	dlg = InterferenceDialog.new()
	_main.add_child(dlg)
	(func() -> void: out.append(await dlg.ask("Warboss", "Bolt", "Raiders", 4, 0, 2, "boost"))).call()
	p = await _await_prompt("Boost your cast?")
	assert_str(_text_of(p)).contains("Warboss casts Bolt at Raiders.")
	_assert_controls(p, ["Boost (+1)", "No boost"])
	assert_str(_text_of(p)).contains(InterferenceDialog.format_preview_boost(4, 0, 1))
	await _click(_button(p, "Boost (+1)"))
	got = await _answer(out)
	assert_int(got).is_equal(1)


# === the card: the old keys, the board out of reach ===========================================

## Enter takes OK and Esc the cancel button, as at the old dialogs; the saves have no cancel button and
## still answer Esc, so the board never locks (UI audit 2026-07-24). Other keys stop at the card.
func test_enter_and_esc_answer_like_the_old_dialogs(timeout := 120000) -> void:
	var charger := _unit(2, "Raiders", [Vector3(0.05, 0, 0)])
	var defender := _unit(1, "Guards", [Vector3.ZERO])
	var out: Array = []
	(func() -> void: out.append(await _main._solo_confirm_strike_back(defender, charger, false))).call()
	await _await_prompt("Strike back?")
	var g := InputEventKey.new()
	g.keycode = KEY_G
	g.pressed = true
	_main.get_viewport().push_input(g)
	assert_bool(_main.get_viewport().is_input_handled()) \
		.override_failure_message("a hotkey reached the table behind the question").is_true()
	await _key(KEY_ENTER)
	var got: Variant = await _answer(out)
	assert_bool(got).is_true()

	out = []
	(func() -> void: out.append(await _main._solo_confirm_strike_back(defender, charger, false))).call()
	await _await_prompt("Strike back?")
	await _key(KEY_ESCAPE)
	got = await _answer(out)
	assert_bool(got).is_false()

	_main._solo_auto_saves = false
	_main._solo_batch = true
	out = []
	(func() -> void: out.append(await _main._solo_prompt_saves(charger, defender, "Rifle", 2, 4, 0))).call()
	await _await_prompt("Incoming fire!")
	await _key(KEY_ESCAPE)
	got = await _answer(out)
	assert_array(got).has_size(2)


## The shield: the pointer beside the card is on the shield (a STOP surface, so the table behind never
## sees the click), and a click there answers nothing.
func test_a_click_beside_the_card_answers_nothing(timeout := 120000) -> void:
	var charger := _unit(2, "Raiders", [Vector3(0.05, 0, 0)])
	var defender := _unit(1, "Guards", [Vector3.ZERO])
	var out: Array = []
	(func() -> void: out.append(await _main._solo_confirm_strike_back(defender, charger, false))).call()
	var p := await _await_prompt("Strike back?")
	var card := p as PromptCard
	var rect := (card.find_child("Card", true, false) as Control).get_global_rect()
	var vp := _main.get_viewport()
	var beside := Vector2(rect.position.x - 40, rect.get_center().y)
	E2EBoot.motion_canvas(vp, beside)
	assert_object(vp.gui_get_hovered_control()).is_same(card.get_node("Shield"))
	E2EBoot.click_canvas(vp, beside, true)
	E2EBoot.click_canvas(vp, beside, false)
	await _runner.simulate_frames(3)
	assert_array(out).override_failure_message("a click beside the card answered it").is_empty()
	assert_object(_prompt()).is_same(card)
	await _click(card.ok_button)
	await _answer(out)


# === the check itself =========================================================================

## The control check names a control that went missing (Hold hidden on a live prompt).
func test_the_inventory_check_names_a_removed_control(timeout := 120000) -> void:
	var charger := _unit(2, "Raiders", [Vector3(0.05, 0, 0)])
	var defender := _unit(1, "Guards", [Vector3.ZERO])
	var out: Array = []
	(func() -> void: out.append(await _main._solo_confirm_strike_back(defender, charger, false))).call()
	var p := await _await_prompt("Strike back?")
	assert_array(_missing(p, ["Strike back", "Hold"])).is_empty()
	_button(p, "Hold").hide()
	assert_array(_missing(p, ["Strike back", "Hold"])).contains_exactly(["button: Hold"])
	await _click(_button(p, "Strike back"))
	await _answer(out)
