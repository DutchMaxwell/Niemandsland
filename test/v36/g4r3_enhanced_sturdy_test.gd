extends GdUnitTestSuite
## G4 round 3, row C-STURDY-BOOST (lead ruling D1): Enhanced Sturdy REPLACES Sturdy's over-9" condition, it does not
## stack on it: +1 Defense in total, at any range. The core already switches Sturdy's gate off while the upgrade
## is carried (`sturdy_boost_gates_guarded`); the table added the upgrade's +1 AND Sturdy's +1 on a shot from over
## 9" (aof_011/25: saves on 2+ where the core saves on 3+). From EPOCH_73_V36 the table's over-9" rule skips a base
## rule its carried upgrade replaces, in the AI and in the human volley; EPOCH_72_PLAYTEST_RULES keeps the stack.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254
const SEED := 5
const OVER9 := "shot from over 9"

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


func _rifle() -> OPRApiClient.OPRWeapon:
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Test Rifle"
	w.range_value = 24
	w.attacks = 8
	w.count = 1
	return w


func _unit(pid: int, unit_name: String, positions: Array) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, positions)
	for i in u.models.size():
		(u.models[i] as ModelInstance).model_index = i
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## Four Mountain-Warriors-style models (Sturdy, Defense 4+) `gap_in` away from a Quality 2+ rifle; the boost, when
## asked for, arrives the way the game delivers it: a spell token granting "Enhanced Sturdy" (Rune of Protection).
func _fixture(gap_in: float, boosted: bool) -> Dictionary:
	var tank := _unit(1, "Test Tank", [Vector3.ZERO])
	tank.unit_properties["quality"] = 2
	var src := OPRApiClient.OPRUnit.new()
	src.weapons.assign([_rifle()])
	tank.source_type = "opr"
	tank.source_data = src
	var positions: Array = []
	for i in 4:
		positions.append(Vector3(gap_in * INCH, 0, 0.02 * i))
	var squad := _unit(2, "Mountain Warriors", positions)
	squad.unit_properties["game_system"] = "gf"
	squad.unit_properties["faction_folder"] = "dwarf_guilds"
	squad.unit_properties["special_rules"] = ["Sturdy"]
	for m in squad.models:
		(m as ModelInstance).properties["special_rules"] = ["Sturdy"]
	if boosted:
		_main._solo_place_spell_tokens("Rune of Protection", [squad],
			{"kind": "buff", "grants_rule": "Enhanced Sturdy", "duration": "once"})
	return {"tank": tank, "squad": squad}


func _ai_volley(epoch: int, gap_in: float, boosted: bool) -> String:
	AiActRecorder.rules_epoch = epoch
	var f := _fixture(gap_in, boosted)
	var shots: Array = []
	for p in AiShooting.profiles_in_range([_rifle()], 0.0):
		shots.append({"member": f["tank"], "quality": 2, "alive": 1, "max": 1, "reach": 24, "profile": p})
	_main.seed_tray_rng(SEED)
	await _main._solo_resolve_ai_volley(f["tank"], f["squad"], shots)
	var text := _log_text()
	await E2EBoot.settle(get_tree())
	return text


func _human_volley(epoch: int, gap_in: float, boosted: bool) -> String:
	AiActRecorder.rules_epoch = epoch
	var f := _fixture(gap_in, boosted)
	_main.seed_tray_rng(SEED)
	await _main._run_human_shooting(f["tank"], f["squad"])
	var text := _log_text()
	await E2EBoot.settle(get_tree())
	return text


## EPOCH_72 leg (declared first: gdUnit drops tests declared after a failing one): the old stack stays — the upgrade's
## +1 and Sturdy's +1 on a shot from over 9".
func test_the_upgrade_and_sturdy_stack_at_epoch_72(timeout := 120000) -> void:
	var text: String = await _ai_volley(AiActRecorder.EPOCH_72_PLAYTEST_RULES, 16.0, true)
	assert_str(text).override_failure_message("fixture: the token's Enhanced Sturdy must count (log: %s)" % text) \
		.contains("is Enhanced Sturdy: +1 Defense")
	assert_str(text).override_failure_message("EPOCH_72 keeps Sturdy's over-9in +1 (log: %s)" % text).contains(OVER9)


## CONTROL: plain Sturdy keeps its +1 on a shot from over 9" at 73.
func test_plain_sturdy_keeps_its_over_nine_inch_bonus_at_epoch_73(timeout := 120000) -> void:
	var text: String = await _ai_volley(AiActRecorder.EPOCH_73_V36, 16.0, false)
	assert_str(text).override_failure_message("plain Sturdy: +1 from over 9in (log: %s)" % text).contains(OVER9)
	assert_str(text).not_contains("Enhanced Sturdy")


## The parity act's shape: Sturdy plus the token's Enhanced Sturdy, shot from over 9" — the upgrade counts once and
## Sturdy's distance +1 is replaced; the log names the replaced rule.
func test_ai_enhanced_sturdy_replaces_sturdys_over_nine_inch_bonus_at_epoch_73(timeout := 120000) -> void:
	var text: String = await _ai_volley(AiActRecorder.EPOCH_73_V36, 16.0, true)
	assert_str(text).override_failure_message("fixture: the token's Enhanced Sturdy must count (log: %s)" % text) \
		.contains("is Enhanced Sturdy: +1 Defense (saves on 3+)")
	assert_str(text) \
		.override_failure_message("C-STURDY-BOOST — Sturdy's over-9in +1 must not stack on the upgrade (log: %s)" % text) \
		.not_contains(OVER9)
	assert_str(text).override_failure_message("rules-must-log — name the replaced rule (log: %s)" % text) \
		.contains("Enhanced Sturdy: replaces Sturdy")


## The human volley reads the same rule.
func test_human_enhanced_sturdy_replaces_sturdys_over_nine_inch_bonus_at_epoch_73(timeout := 120000) -> void:
	var text: String = await _human_volley(AiActRecorder.EPOCH_73_V36, 16.0, true)
	assert_str(text).override_failure_message("fixture: the token's Enhanced Sturdy must count (log: %s)" % text) \
		.contains("is Enhanced Sturdy: +1 Defense (saves on 3+)")
	assert_str(text) \
		.override_failure_message("C-STURDY-BOOST — the human volley must not stack Sturdy on the upgrade (log: %s)" % text) \
		.not_contains(OVER9)
