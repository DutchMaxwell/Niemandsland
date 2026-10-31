extends GdUnitTestSuite
## Rules 3.6 wave, row DAT-16a-cast: two rules move spell tokens without naming themselves in the
## battle log. Every applied rule must write a line that names it (rules-must-log):
##   * Caster Group's per-round refill states the rule and the new token count (game_unit.gd).
##   * A Spell Accumulator battery that pays a friendly cast states who lent how many tokens, worded
##     close to the Rust core's own cast event (core/nml-core/src/sim.rs).
## The controls use a plain Caster(X): the very same refill/lend paths must stay silent about the
## two rules, so a blanket "casters always log" cannot pass.
## The fixture books are real 3.6 carriers from the mechanics maps: aof/ogres carries Caster Group,
## aof/dwarves carries Spell Accumulator (test/v36/dat_08c_test.gd pins those lookups).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254

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
	_main._solo_batch = true


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _log_since(start: int) -> String:
	var text := ""
	for e in _main.battle_log.entries().slice(start):
		text += str((e as Dictionary)["text"]) + "\n"
	return text


## The first logged line that contains `needle`, or "" when none does.
func _line_with(text: String, needle: String) -> String:
	for line in text.split("\n"):
		if str(line).contains(needle):
			return str(line)
	return ""


## A registered synthetic unit carrying `rules`; `system`/`book` make the registry see a real 3.6
## carrier, exactly like an imported army-book unit.
func _reg(pid: int, unit_name: String, x_in: float, tokens: int, rules: Array,
		system := "", book := "") -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, [Vector3(x_in * INCH, 0.0, 0.0)])
	u.unit_properties["special_rules"] = rules
	if not system.is_empty():
		u.unit_properties["game_system"] = system
		u.unit_properties["faction_folder"] = book
	u.casts_current = tokens
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## A multi-model caster group on one spot (each model a bearer the count follows).
func _group(pid: int, unit_name: String, models: int, rules: Array,
		system := "", book := "") -> GameUnit:
	var positions: Array = []
	for i in range(models):
		positions.append(Vector3(0.03 * i, 0.0, 0.0))
	var u := E2EBoot.make_unit(_main, pid, unit_name, positions)
	u.unit_properties["special_rules"] = rules
	if not system.is_empty():
		u.unit_properties["game_system"] = system
		u.unit_properties["faction_folder"] = book
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func _boost_card() -> PromptCard:
	for n in _main.get_children():
		if n is InterferenceDialog:
			for c in n.get_children():
				if c is PromptCard and (c as PromptCard).title == "Boost your cast?":
					return c
	return null


func _wait(cond: Callable) -> void:
	for _i in 300:
		if cond.call():
			return
		await get_tree().process_frame


## Cast a 1-token Bolt with one borrowed boost token and return the battle log written by the cast.
func _cast_with_one_boost(seer: GameUnit, target: GameUnit) -> String:
	var start: int = _main.battle_log.entries().size()
	var done := [false]
	(func() -> void:
		await _main._run_human_cast(seer, seer, {"name": "Bolt", "threshold": 1}, [target])
		done[0] = true).call()
	await _wait(func() -> bool: return done[0] or _boost_card() != null)
	var card := _boost_card()
	assert_object(card).override_failure_message("no boost tableau opened:\n%s" % _log_since(start)).is_not_null()
	if card != null:
		card.resolve(1)
	await _wait(func() -> bool: return done[0])
	assert_bool(done[0]).override_failure_message("the cast never resolved:\n%s" % _log_since(start)).is_true()
	return _log_since(start)


# ===== controls: the plain caster paths stay silent about the two rules =====

func test_a_plain_caster_refill_does_not_name_caster_group(timeout := 120000) -> void:
	var u := _reg(1, "PlainCaster", 0.0, 0, ["Caster(2)"], "aof", "goblins")
	u.initialize_caster_points()
	u.casts_current = 0   # a spent round: the plain refill accumulates back to 2
	var start: int = _main.battle_log.entries().size()
	_main.opr_army_manager.advance_round()
	var text := _log_since(start)
	assert_str(text).override_failure_message(
		"a plain Caster(X) refill must not claim Caster Group:\n%s" % text).not_contains("Caster Group")
	assert_int(u.casts_current).is_equal(2)
	await E2EBoot.settle(get_tree())


func test_a_plain_caster_lend_does_not_name_spell_accumulator(timeout := 120000) -> void:
	var seer := _reg(1, "Seer", 0.0, 1, ["Caster(1)"])
	var helper := _reg(1, "Helper", 6.0, 2, ["Caster(2)"])
	var brutes := _reg(2, "Brutes", 10.0, 0, [])
	var text := await _cast_with_one_boost(seer, brutes)
	assert_int(helper.casts_current).override_failure_message(
		"fixture: the plain caster must pay the boost:\n%s" % text).is_equal(1)
	assert_str(text).override_failure_message(
		"a plain Caster(X) lend must not claim Spell Accumulator:\n%s" % text).not_contains("Spell Accumulator")
	await E2EBoot.settle(get_tree())


# ===== the two silent rules must name themselves =====

## One method for both positive cases: gdUnit's static scanner drops the test declared AFTER a
## failing one, so two separate RED methods would hide the second case on the RED run. Assertions
## collect within a method, so both missing lines are reported here.
func test_the_two_rules_name_themselves_in_the_battle_log(timeout := 120000) -> void:
	# (1) Caster Group's per-round refill.
	var group := _group(1, "Ogre Caster Group", 3, ["Caster Group"], "aof", "ogres")
	group.initialize_caster_points()
	assert_int(group.casts_current).override_failure_message("fixture: 3 bearers grant 3 tokens").is_equal(3)
	group.casts_current = 1   # a spent round: the refill must report the new count
	var start: int = _main.battle_log.entries().size()
	_main.opr_army_manager.advance_round()
	var refill_text := _log_since(start)
	var refill_line := _line_with(refill_text, "Caster Group")
	assert_str(refill_line).override_failure_message(
		"a Caster Group refill must write a line naming the rule:\n%s" % refill_text).is_not_empty()
	assert_str(refill_line).override_failure_message(
		"the Caster Group line must state the new token count 3: %s" % refill_line).contains("3")
	assert_int(group.casts_current).is_equal(3)
	await E2EBoot.settle(get_tree())
	# (2) Spell Accumulator's lend into a friendly cast. Empty the group's purse first so the battery,
	# not the nearer Caster Group, is the one that pays the borrowed boost token.
	group.casts_current = 0
	var seer := _reg(1, "Seer", 0.0, 1, ["Caster(1)"], "aof", "dwarves")
	var battery := _reg(1, "Battery", 6.0, 2, ["Spell Accumulator(2)"], "aof", "dwarves")
	var brutes := _reg(2, "Brutes", 10.0, 0, [])
	var cast_text := await _cast_with_one_boost(seer, brutes)
	assert_int(battery.casts_current).override_failure_message(
		"fixture: the battery must pay the borrowed boost token:\n%s" % cast_text).is_equal(1)
	var lend_line := _line_with(cast_text, "Spell Accumulator")
	assert_str(lend_line).override_failure_message(
		"a Spell Accumulator lend must write a line naming the rule:\n%s" % cast_text).is_not_empty()
	assert_str(lend_line).override_failure_message(
		"the Spell Accumulator line must name the lender and the count: %s" % lend_line) \
		.contains("Battery")
	assert_str(lend_line).contains("1")
	await E2EBoot.settle(get_tree())
