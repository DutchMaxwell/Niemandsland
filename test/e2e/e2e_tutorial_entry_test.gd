extends GdUnitTestSuite
## E2E — tutorial entry routing (fix/tutorial-entry).
##
## WHY A REAL BOOT. --import does not compile main.gd, and no unit-level suite loads it
## either (test/startup_menu_test.gd only exercises startup_menu.gd) — so a static check
## can never prove which tutorial the startup menu's single TUTORIAL entry actually routes
## to at runtime. This suite arms the exact ProjectSettings flags
## StartupMenu._arm_tutorial_flags() sets, boots the REAL res://scenes/main.tscn, and reads
## the live Main node to confirm which track/lesson/board _ready() actually chose — plus
## the identity battle-log line a human tester relies on to answer the same question
## in-game.

const Boot := preload("res://test/e2e/e2e_boot.gd")

var _runner: GdUnitSceneRunner
var _main: Node
var _before: Array
var _saved_tutorial_mode: Variant
var _saved_tutorial_lesson: Variant


func before_test() -> void:
	_before = Boot.root_children(get_tree())
	# Process-global ProjectSettings — save whatever this suite is about to overwrite so a
	# later suite never inherits tutorial_mode still armed.
	_saved_tutorial_mode = ProjectSettings.get_setting("niemandsland/tutorial_mode", false)
	_saved_tutorial_lesson = ProjectSettings.get_setting("niemandsland/tutorial_lesson", "")


func after_test() -> void:
	ProjectSettings.set_setting("niemandsland/tutorial_mode", _saved_tutorial_mode)
	ProjectSettings.set_setting("niemandsland/tutorial_lesson", _saved_tutorial_lesson)
	Boot.free_stray_root_nodes(get_tree(), _before)
	_main = null
	_runner = null


func test_tutorial_entry_routes_to_the_bundled_board_and_logs_it(timeout := 60000) -> void:
	# Arm the same flags StartupMenu._arm_tutorial_flags() sets. Must happen BEFORE the
	# scene is instantiated: main.gd reads-and-clears both settings synchronously inside
	# _ready() (the tutorial path takes the same chooser/intro-skip seam as harness_mode,
	# see main.gd's `if harness_mode or _tutorial_mode:`).
	ProjectSettings.set_setting("niemandsland/tutorial_mode", true)
	ProjectSettings.set_setting("niemandsland/tutorial_lesson", "")

	_runner = scene_runner(Boot.MAIN_SCENE)
	_main = _runner.scene()

	# ASSERT IMMEDIATELY — BEFORE any frame simulation. scene_runner() mounts the scene with
	# a plain add_child(), which runs Main._ready() synchronously (no `await` precedes the
	# tutorial block), so _tutorial_mode / _tutorial_start_lesson / _tutorial_board_pending
	# and the battle-log identity line are already set right here. The bundled board itself
	# (two real armies, ~54 minis, real model loading) is only QUEUED at this point via
	# call_deferred("_load_pending_battle", ...) — it has not started. Simulating frames
	# before reading these would let that load actually begin, which this suite must not
	# trigger (see the _tutorial_mode = false note below).
	assert_bool(_main._tutorial_mode).is_true()
	assert_str(_main._tutorial_start_lesson).is_equal("")
	# Load-bearing: only true when _ready() routed the pending load to
	# TutorialDirector.BOARD_PATH — i.e. the boot really landed on the OLD bundled tutorial
	# board, not on no board / some other board.
	assert_bool(_main._tutorial_board_pending) \
		.override_failure_message("the boot did not route the pending load to the bundled tutorial board") \
		.is_true()

	var log_text := ""
	for e in _main.battle_log.entries():
		log_text += str((e as Dictionary)["text"]) + "\n"
	assert_str(log_text) \
		.override_failure_message("no battle-log line names which tutorial was loaded (log: %s)" % log_text.strip_edges()) \
		.contains("Tutorial started")
	assert_str(log_text).contains("tool track")

	# Stop here, and do it BEFORE any further frame simulation. _on_intro_finished (itself
	# deferred) would call_deferred("_start_tutorial"), which awaits the board load in a
	# 120s poll loop — the routing facts are already asserted above, so the director must
	# never actually run in this suite.
	_main._tutorial_mode = false

	await Boot.settle(get_tree())
