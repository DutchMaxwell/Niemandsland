class_name LessonCard
extends PanelContainer
## One instruction at a time, centered below the top bar.

signal continue_pressed
signal skip_pressed
signal leave_pressed
signal stay_pressed
signal action_pressed(fixture: String)

var chapter_title := ""
var _header: Label
var _step_text: Label
var _rule: Label
var _progress: Label
var _action: Button
var _action_fixture := ""
var _continue: Button
var _skip: Button
var _leave: Button
var _chapter_list: Button
var _stay: Button


func _ready() -> void:
	HouseStyle.apply(self)
	anchor_left = 0.5
	anchor_right = 0.5
	offset_left = -210
	offset_right = 210
	offset_top = 72
	offset_bottom = 72
	grow_vertical = Control.GROW_DIRECTION_END
	mouse_filter = Control.MOUSE_FILTER_STOP
	var content := VBoxContainer.new()
	content.name = "Content"
	content.add_theme_constant_override(&"separation", HouseStyle.GAP_ROW)
	add_child(content)
	var header_row := HouseStyle.panel_header("TRIAL BY FIRE · " + chapter_title, true)
	_header = header_row.get_child(0) as Label
	(header_row.get_node("CloseButton") as Button).pressed.connect(func() -> void: leave_pressed.emit())
	content.add_child(header_row)
	_step_text = HouseStyle.label("", HouseStyle.BODY)
	_step_text.name = "StepText"
	_step_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_step_text.custom_minimum_size.x = 380
	content.add_child(_step_text)
	_rule = HouseStyle.label("", HouseStyle.CAPTION)
	_rule.name = "Rule"
	content.add_child(_rule)
	_progress = HouseStyle.label("", HouseStyle.SMALL)
	_progress.name = "Progress"
	content.add_child(_progress)
	_action = _add_button(content, "ActionButton", "", HouseStyle.BUTTON)
	_continue = _add_button(content, "ContinueButton", "Continue", HouseStyle.PRIMARY)
	_skip = _add_button(content, "SkipButton", "Skip step", HouseStyle.BUTTON)
	_leave = _add_button(content, "LeaveButton", "Leave lesson", HouseStyle.BUTTON)
	_chapter_list = _add_button(content, "ChapterListButton", "Chapter list", HouseStyle.PRIMARY)
	_stay = _add_button(content, "StayButton", "Stay on the table", HouseStyle.BUTTON)
	_continue.pressed.connect(func() -> void: continue_pressed.emit())
	_skip.pressed.connect(func() -> void: skip_pressed.emit())
	_leave.pressed.connect(func() -> void: leave_pressed.emit())
	_chapter_list.pressed.connect(func() -> void: leave_pressed.emit())
	_stay.pressed.connect(func() -> void: stay_pressed.emit())
	_action.pressed.connect(func() -> void: action_pressed.emit(_action_fixture))
	_continue.hide()
	_action.hide()
	_chapter_list.hide()
	_stay.hide()


func _add_button(parent: Control, node_name: String, text: String, variant: StringName) -> Button:
	var button := HouseStyle.button(text, variant)
	button.name = node_name
	parent.add_child(button)
	return button


func show_step(index: int, total: int, step: Dictionary) -> void:
	_header.text = ("TRIAL BY FIRE · " + chapter_title).to_upper()
	_step_text.text = String(step.get("text", ""))
	var rule := String(step.get("rule", ""))
	_rule.text = "Rulebook " + rule
	_rule.visible = not rule.is_empty()
	_progress.text = "Step %d of %d" % [index + 1, total]
	_progress.show()
	var checks: Array = step.get("all", [])
	var first: Dictionary = checks[0] if not checks.is_empty() else {}
	_continue.visible = first.get("check") == "counter_grew" \
		and first.get("args", {}).get("key") == "continue"
	var action: Dictionary = step.get("action", {})
	_action_fixture = String(action.get("fixture", ""))
	_action.text = String(action.get("label", ""))
	_action.visible = not action.is_empty()
	_skip.show()
	_leave.show()
	_chapter_list.hide()
	_stay.hide()


func show_complete(title: String) -> void:
	_header.text = ("TRIAL BY FIRE · " + title).to_upper()
	_step_text.text = "Chapter complete ✓"
	_rule.hide()
	_progress.hide()
	_continue.hide()
	_action.hide()
	_skip.hide()
	_leave.hide()
	_chapter_list.show()
	_stay.show()
