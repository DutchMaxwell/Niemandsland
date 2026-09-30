extends GdUnitTestSuite
## E2E — uifix2 (30.09.): in solo the Combat Stage card sat on top of NACHTMAHR's turn banner (both
## are top-centre). The banner must stay readable while the card is up: their rects must not meet.

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
	GraphicsSettings.combat_stage_hold_s = 2.5
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func test_combat_stage_card_leaves_the_ai_banner_readable() -> void:
	_main._show_solo_ai_banner()
	var stage: CombatStage = _main.combat_stage
	stage.force_for_tests = true
	GraphicsSettings.combat_stage_hold_s = 30.0   # the card stays up while we measure
	stage.activation_begin("Tank shoots")
	stage.collect("Rifle: 4 shots, 2 hits")
	stage.phase("Declaration")   # not awaited: the hold runs on while the test measures
	await _runner.simulate_frames(6)
	var banner: Label = _main._solo_ai_banner
	var card: Control = stage._panel
	assert_bool(is_instance_valid(banner) and banner.is_visible_in_tree()).is_true()
	assert_bool(is_instance_valid(card) and card.is_visible_in_tree()).is_true()
	var b := banner.get_global_rect()
	var c := card.get_global_rect()
	assert_bool(b.intersects(c)) \
		.override_failure_message("the combat stage card %s covers the NACHTMAHR banner %s" % [c, b]) \
		.is_false()
	stage.skip()
	await E2EBoot.settle(get_tree())
