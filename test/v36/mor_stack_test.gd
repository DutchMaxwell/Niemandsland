extends GdUnitTestSuite
## Morale test rolls, rules 3.6: Banner and Bravery Aura each give +1 and they ADD UP, so a unit that has
## both is +2 in total. Two entries of the SAME Bravery rule (the carrier's "Bravery Aura" and the bare
## "Bravery" the aura expansion stamps beside it) are one rule and stay +1. The other Banner-family
## spellings keep their best-of read. Below epoch 73 nothing changes.

const Boot := preload("res://test/e2e/e2e_boot.gd")

var _runner: GdUnitSceneRunner
var _main: Node
var _roots: Array
var _epoch_before: int
var _seq := 0


func before_test() -> void:
	_epoch_before = AiActRecorder.rules_epoch
	Boot.arm_harness_mode()
	_roots = Boot.root_children(get_tree())
	_runner = scene_runner(Boot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main._solo_batch = true
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch_before
	Boot.free_stray_root_nodes(get_tree(), _roots)
	_main = null
	_runner = null


## A scene-free Quality 4 unit (real registry, no hand-written params).
func _pure(rules: Array) -> GameUnit:
	_seq += 1
	var u := GameUnit.new()
	u.unit_id = "pure%d" % _seq
	u.unit_properties = {"player_id": 1, "name": "Pure", "quality": 4, "defense": 4,
		"game_system": "gf", "special_rules": rules}
	var m := ModelInstance.new()
	m.is_alive = true
	u.models.append(m)
	return u


func _board_unit(rules: Array) -> GameUnit:
	_seq += 1
	var u := Boot.make_unit(_main, 1, "Stack%d" % _seq, [Vector3(0.05, 0, 0)])
	u.unit_properties["game_system"] = "gf"
	u.unit_properties["special_rules"] = rules
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## Seeds the tray so its first die is `face`.
func _seed_first_die(face: int) -> void:
	var rng := RandomNumberGenerator.new()
	for candidate in range(500):
		rng.seed = candidate
		if rng.randi_range(1, 6) == face:
			_main.seed_tray_rng(candidate)
			return
	fail("no seed rolls a %d first" % face)


func _log_text() -> String:
	var out := ""
	for entry in _main.battle_log.entries():
		out += str(entry["text"]) + "\n"
	return out


func test_banner_and_bravery_aura_add_up_to_plus_two() -> void:
	assert_int(SoloController.morale_bonus_of(_pure(["Banner", "Bravery Aura"]))).override_failure_message(
		"Banner + Bravery Aura must be +2").is_equal(2)
	# The aura carrier is an attached Hero; the expansion stamps the bare "Bravery" on host and Hero.
	var host := _pure(["Banner", "Bravery"])
	host.unit_properties["attached_heroes"] = [_pure(["Hero", "Bravery Aura", "Bravery"])]
	assert_int(SoloController.morale_bonus_of(host)).override_failure_message(
		"a Banner host with a Bravery Aura Hero must be +2").is_equal(2)


## CONTROLS: these pass with and without the change.
func test_one_bravery_rule_and_one_banner_stay_plus_one() -> void:
	assert_int(SoloController.morale_bonus_of(_pure(["Banner"]))).is_equal(1)
	assert_int(SoloController.morale_bonus_of(_pure(["Bravery Aura"]))).is_equal(1)
	# The carrier's own name and the base the expansion stamps beside it are ONE rule.
	assert_int(SoloController.morale_bonus_of(_pure(["Bravery Aura", "Bravery"]))).is_equal(1)
	# Another Banner-family spelling still reads best-of with Banner.
	assert_int(SoloController.morale_bonus_of(_pure(["Banner", "Valiant"]))).is_equal(1)


func test_epoch_72_keeps_the_best_of_read() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	assert_int(SoloController.morale_bonus_of(_pure(["Banner", "Bravery Aura"]))).is_equal(1)


func test_the_dice_path_rolls_a_test_with_both_at_plus_two() -> void:
	var u := _board_unit(["Banner", "Bravery Aura"])
	_seed_first_die(2)   # passes on 2+ with +2; fails on 3+ with +1
	var passed: bool = await _main._solo_morale_test(u, "t")
	assert_bool(passed).override_failure_message("a die of 2 must pass at +2\n" + _log_text()).is_true()
	assert_str(_log_text()).contains("gets +2 to morale test rolls (passes on 2+)")


## CONTROL: a spell-caused test keeps only the Bravery Aura +1 (Banner is shooting and melee only), so
## summing must not let the Banner half leak in: a die of 2 still fails on 3+.
func test_a_spell_caused_test_still_takes_the_banner_half_out() -> void:
	var u := _board_unit(["Banner", "Bravery Aura"])
	_seed_first_die(2)
	var passed: bool = await _main._solo_morale_test(u, "t", false, "Spell Drain")
	assert_bool(passed).override_failure_message("a die of 2 must fail at +1\n" + _log_text()).is_false()
	assert_str(_log_text()).contains("passes on 3+")
