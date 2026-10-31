extends GdUnitTestSuite
## Rules 3.6 lane shoot, row SHO-LOG-PRECISE: Precise's +1 to hit was folded silently, so a
## battle log never named the rule. It now writes one COMBAT line whenever the +1 applies, and
## the hit count stays exactly what it was (the log is visibility only, no dice change).
##
## _solo_hits serves shooting AND melee, so the single line covers both legs. Runs on the real
## scenes/main.tscn so the real BattleLog instance receives the event.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _log_text() -> String:
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


## Faces [6, 3, 2] at 3+: Precise scores them one better, so the 2 counts too — 3 hits, the
## same count the fold produced before the log line existed. The rule must name itself.
func test_a_precise_volley_names_itself_in_the_battle_log(timeout := 120000) -> void:
	var hits: int = await _main._solo_hits([6, 3, 2], 3, {"precise": true}, 14.0)
	assert_int(hits).is_equal(3)
	assert_str(_log_text()) \
		.override_failure_message("Precise added a hit with NO log line — the rules-fired gate can never count it") \
		.contains("Precise")


## The same tray without Precise: 2 hits and no phantom Precise line.
func test_a_non_precise_volley_stays_quiet(timeout := 120000) -> void:
	var hits: int = await _main._solo_hits([6, 3, 2], 3, {}, 14.0)
	assert_int(hits).is_equal(2)
	assert_str(_log_text()).not_contains("Precise")
