extends GdUnitTestSuite
## E2E — NML-955: the AI's explanation window faded out from under the maintainer. "Das
## ERKLÄRUNGSfenster der KI sollte dauerhaft angezeigt werden und nicht einfach ausgeblendet. So
## kann ich es gar nicht wirklich studieren."
##
## The 2026-07-24 UI audit gave EVERY toast a 6 s auto-hide because plain notices used to stay
## nailed to the screen forever. Right for notices, wrong for explanations: an explanation arrives
## while the AI holds the turn (the player cannot pause it), it is the evidence he is supposed to
## read, and six seconds later it is gone. The two kinds are separated here — explanations stay
## until the next event replaces them or a click takes them down, notices keep their fade.
##
## Driven on the real main.tscn toast (UI/SoloActionToast), including a real click through the
## viewport's input pipeline.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _persist_before: bool = true


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_persist_before = GraphicsSettings.ai_explain_persistent   # autoload: shared across suites
	GraphicsSettings.ai_explain_persistent = true
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)


func after_test() -> void:
	GraphicsSettings.ai_explain_persistent = _persist_before
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _toast() -> Label:
	return _main.get_node_or_null("UI/SoloActionToast") as Label


func test_an_operational_notice_keeps_its_fade() -> void:
	# CONTROL, declared before the red ones: the export/autosave class of message must NOT become
	# sticky, and must not start eating clicks over the battlefield. Without this the fix could
	# "pass" by simply making every toast permanent — the exact bug the 2026-07-24 audit removed.
	_main._solo_show_toast("Battle Log exported → user://battle_log.txt")
	var t := _toast()
	assert_object(t).is_not_null()
	assert_bool(t.visible).is_true()
	assert_bool(_main._solo_toast_sticky) \
		.override_failure_message("an operational notice went sticky — it would sit on screen forever") \
		.is_false()
	assert_int(t.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)


func test_an_ai_explanation_stays_up() -> void:
	_main._solo_show_explain("NACHTMAHR: Grunts shoot Riders")
	await _runner.simulate_frames(4)
	var t := _toast()
	assert_bool(t.visible) \
		.override_failure_message("NML-955 — the AI explanation was hidden again; the maintainer cannot study what is not on screen") \
		.is_true()
	assert_bool(_main._solo_toast_sticky).is_true()
	assert_int(t.mouse_filter) \
		.override_failure_message("a sticky explanation must be able to take the click that dismisses it") \
		.is_equal(Control.MOUSE_FILTER_STOP)
	assert_str(t.tooltip_text).contains("dismiss")


func test_the_next_event_replaces_the_explanation() -> void:
	# "until the next event replaces it" — not "until the end of time".
	_main._solo_show_explain("NACHTMAHR: Grunts shoot Riders")
	_main._solo_show_explain("NACHTMAHR: Riders charge Grunts")
	await _runner.simulate_frames(2)
	assert_str(_toast().text).is_equal("NACHTMAHR: Riders charge Grunts")
	assert_bool(_toast().visible).is_true()


func test_a_click_dismisses_the_explanation() -> void:
	_main._solo_show_explain("NACHTMAHR: Grunts shoot Riders")
	await _runner.simulate_frames(4)
	var t := _toast()
	var centre: Vector2 = t.get_global_rect().get_center()
	E2EBoot.click_canvas(_main.get_viewport(), centre, true)
	E2EBoot.click_canvas(_main.get_viewport(), centre, false)
	await _runner.simulate_frames(2)
	assert_bool(t.visible) \
		.override_failure_message("NML-955 — the explanation could not be clicked away (rect %s)" % str(t.get_global_rect())) \
		.is_false()
	assert_bool(_main._solo_toast_sticky).is_false()
	assert_int(t.mouse_filter) \
		.override_failure_message("a dismissed toast must stop taking clicks over the table") \
		.is_equal(Control.MOUSE_FILTER_IGNORE)


func test_a_phase_boundary_clear_leaves_the_explanation_standing() -> void:
	# The unforced hides in the flow (end of the ambush round) must not blank an explanation the
	# player is mid-read; only a dismiss click and the next event may.
	_main._solo_show_explain("NACHTMAHR: Grunts ambush in from reserve")
	_main._solo_hide_toast()
	assert_bool(_toast().visible).is_true()
	_main._solo_hide_toast(true)
	assert_bool(_toast().visible).is_false()


func test_the_setting_hands_the_fade_back() -> void:
	# The switch exists so a player who does NOT want a standing explanation gets the old fade.
	GraphicsSettings.ai_explain_persistent = false
	_main._solo_show_explain("NACHTMAHR: Grunts shoot Riders")
	assert_bool(_main._solo_toast_sticky).is_false()
	assert_int(_toast().mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
