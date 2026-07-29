extends GdUnitTestSuite
## E2E — #193: Surge's on-6 bonus hits landed SILENTLY. The tray said "2 hits", the wound
## line said "3 hits", and the player read it as a broken counter — the exact report from the
## community flamer game. Every other on-6 branch in _solo_hits (Relentless, Furious, Sergeant,
## extra-attack Surge) already logs; plain Surge was the last silent one.
##
## test/ai_combat_math_test.gd pins the ARITHMETIC (surge_bonus_hits). What no test covered is
## the VISIBILITY: the battle-log line main.gd writes next to the bonus. Runs on the real
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


func test_surge_bonus_hit_writes_a_log_line(timeout := 120000) -> void:
	# One unmodified 6 on a 3+ roll: 2 base hits (6, 3) + 1 Surge bonus = 3.
	var hits: int = await _main._solo_hits([6, 3, 2], 3, {"surge": true}, 14.0)
	assert_int(hits).is_equal(3)
	assert_str(_log_text()) \
		.override_failure_message("#193 — Surge added a hit with NO log line: the tray shows 2 hits, the wound line 3, and the player reads a broken counter instead of a rule") \
		.contains("Surge: +1 hit")


func test_point_blank_surge_outside_range_stays_quiet(timeout := 120000) -> void:
	# Point-Blank Surge (within 12") at 14": no bonus — and no phantom log line either.
	var hits: int = await _main._solo_hits([6, 3, 2], 3, {"surge": true, "surge_within_in": 12.0}, 14.0)
	assert_int(hits).is_equal(2)
	assert_str(_log_text()).not_contains("Surge:")
