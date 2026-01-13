extends Control

# Glassmorphism Calculator with Advanced Features
class_name Calculator

# UI References
@export var display_label: Label
@export var history_label: RichTextLabel
@export var buttons_container: GridContainer
@export var history_scroll: ScrollContainer
@export var scientific_toggle: CheckButton


# Calculator state
var current_value: String = "0"
var stored_value: float = 0.0
var pending_operation: String = ""
var should_clear_display: bool = false
var calculation_history: Array[String] = []
var is_scientific_mode: bool = false
var memory_value: float = 0.0
var expression: String = "0"  # Full expression to display
var has_pending_operation: bool = false

# Module Paths
const SHRINK_PRESSED_BUTTON_MODULE = preload("uid://b8qi1eld0fd72")
const EXPAND_HOVERED_CONTROL_MODULE = preload("uid://32ps8lb55j17")

const MAX_DIGITS: int = 16
const MAX_HISTORY_ITEMS: int = 50

# Button layout for standard mode
const STANDARD_BUTTONS: Array[String] = [
	"C", "±", "%", "÷",
	"7", "8", "9", "×",
	"4", "5", "6", "-",
	"1", "2", "3", "+",
	"0", ".", "⌫", "="
]

# Button layout for scientific mode
const SCIENTIFIC_BUTTONS: Array[String] = [
	"C", "±", "%", "÷", "x²", "√",
	"7", "8", "9", "×", "sin", "cos",
	"4", "5", "6", "-", "tan", "log",
	"1", "2", "3", "+", "π", "e",
	"0", ".", "⌫", "=", "M+", "MR"
]

func _ready() -> void:
	
	# Connect signals
	scientific_toggle.toggled.connect(_on_scientific_mode_toggled)
	
	# Initialize calculator
	_create_buttons()
	_update_display()

func _create_buttons() -> void:
	# Clear existing buttons
	for child in buttons_container.get_children():
		child.queue_free()
	
	# Get button layout based on mode
	var button_layout: Array[String] = SCIENTIFIC_BUTTONS if is_scientific_mode else STANDARD_BUTTONS
	var columns: int = 6 if is_scientific_mode else 4
	buttons_container.columns = columns
	
	# Create buttons
	for button_text in button_layout:
		var button: Button = Button.new()
		button.custom_minimum_size = Vector2(80, 60)
		button.text = button_text
		button.pressed.connect(_on_button_pressed.bind(button_text))
		
		# Style specific buttons
		if button_text in ["÷", "×", "-", "+", "="]:
			button.modulate = Color(1.2, 1.0, 0.8)  # Orange tint for operators
		elif button_text == "C":
			button.modulate = Color(1.2, 0.8, 0.8)  # Red tint for clear
		elif button_text in ["sin", "cos", "tan", "log", "√", "x²", "π", "e"]:
			button.modulate = Color(0.8, 1.0, 1.2)  # Blue tint for scientific
		
		# Add hover and press effects
		_add_button_effects(button)
		
		buttons_container.add_child(button)

func _add_button_effects(button: Button) -> void:
	# Add shrink effect when pressed
	var shrink_module: Node = SHRINK_PRESSED_BUTTON_MODULE.instantiate()
	button.add_child(shrink_module)
	
	# Add expand effect when hovered
	var expand_module: Node = EXPAND_HOVERED_CONTROL_MODULE.instantiate()
	button.add_child(expand_module)

func _on_button_pressed(button_text: String) -> void:
	match button_text:
		"0", "1", "2", "3", "4", "5", "6", "7", "8", "9":
			_handle_digit(button_text)
		".":
			_handle_decimal()
		"C":
			_clear_all()
		"⌫":
			_handle_backspace()
		"±":
			_toggle_sign()
		"%":
			_handle_percentage()
		"+", "-", "×", "÷":
			_handle_operator(button_text)
		"=":
			_calculate_result()
		"π":
			_handle_constant(PI)
		"e":
			_handle_constant(exp(1))
		"x²":
			_handle_square()
		"√":
			_handle_square_root()
		"sin":
			_handle_trigonometric("sin")
		"cos":
			_handle_trigonometric("cos")
		"tan":
			_handle_trigonometric("tan")
		"log":
			_handle_logarithm()
		"M+":
			_memory_add()
		"MR":
			_memory_recall()

func _handle_digit(digit: String) -> void:
	if should_clear_display:
		current_value = digit
		should_clear_display = false
		# If we have a pending operation, append to expression
		if has_pending_operation:
			expression += " " + digit
		else:
			expression = digit
	elif current_value == "0" and not has_pending_operation:
		current_value = digit
		expression = digit
	elif current_value.length() < MAX_DIGITS:
		current_value += digit
		if has_pending_operation:
			expression += digit
		else:
			expression = current_value
	
	_update_display()

func _handle_decimal() -> void:
	if should_clear_display:
		current_value = "0."
		should_clear_display = false
		if has_pending_operation:
			expression += " 0."
		else:
			expression = "0."
	elif not "." in current_value:
		current_value += "."
		if has_pending_operation:
			expression += "."
		else:
			expression = current_value
	
	_update_display()

func _handle_backspace() -> void:
	if current_value.length() > 1:
		current_value = current_value.substr(0, current_value.length() - 1)
		# Update expression too
		if expression.length() > 1 and not has_pending_operation:
			expression = current_value
		elif has_pending_operation and expression.length() > 1:
			expression = expression.substr(0, expression.length() - 1)
	else:
		current_value = "0"
		if not has_pending_operation:
			expression = "0"
	
	_update_display()

func _toggle_sign() -> void:
	if current_value != "0":
		if current_value.begins_with("-"):
			current_value = current_value.substr(1)
		else:
			current_value = "-" + current_value
		
		# Update expression if we're not in the middle of an operation
		if not has_pending_operation:
			expression = current_value
	
	_update_display()

func _handle_percentage() -> void:
	var value: float = current_value.to_float()
	current_value = str(value / 100.0)
	if not has_pending_operation:
		expression = current_value
	_update_display()

func _handle_operator(operator: String) -> void:
	if pending_operation != "" and not should_clear_display:
		_calculate_result()
	
	stored_value = current_value.to_float()
	pending_operation = operator
	should_clear_display = true
	has_pending_operation = true
	
	# Update expression to show the operator
	# Build expression properly
	if expression == "Error":
		expression = current_value
	
	# Only show the formatted number in expression if we just calculated
	if not has_pending_operation or should_clear_display:
		expression = current_value + " " + operator
	else:
		# We're chaining operations
		expression = current_value + " " + operator
	
	_update_display()

func _calculate_result() -> void:
	if pending_operation == "":
		return
	
	var current: float = current_value.to_float()
	var result: float = 0.0
	
	match pending_operation:
		"+":
			result = stored_value + current
		"-":
			result = stored_value - current
		"×":
			result = stored_value * current
		"÷":
			if current != 0:
				result = stored_value / current
			else:
				current_value = "Error"
				_update_display()
				return
	
	# Check for overflow before formatting
	var formatted_result: String = _format_number(result)
	
	# Add to history
	var history_entry: String = "%s %s %s = %s" % [
		_format_number(stored_value),
		pending_operation,
		_format_number(current),
		formatted_result
	]
	_add_to_history(history_entry)
	
	current_value = formatted_result
	pending_operation = ""
	should_clear_display = true
	has_pending_operation = false
	expression = current_value
	_update_display()

func _handle_constant(value: float) -> void:
	current_value = _format_number(value)
	should_clear_display = true
	if has_pending_operation:
		expression += " " + current_value
	else:
		expression = current_value
	_update_display()

func _handle_square() -> void:
	var value: float = current_value.to_float()
	var result: float = value * value
	
	# Check for overflow
	var formatted_result: String = _format_number(result)
	_add_to_history("%s² = %s" % [_format_number(value), formatted_result])
	current_value = formatted_result
	should_clear_display = true
	has_pending_operation = false
	expression = current_value
	_update_display()

func _handle_square_root() -> void:
	var value: float = current_value.to_float()
	if value >= 0:
		var result: float = sqrt(value)
		_add_to_history("√%s = %s" % [_format_number(value), _format_number(result)])
		current_value = _format_number(result)
	else:
		current_value = "Error"
	should_clear_display = true
	has_pending_operation = false
	expression = current_value
	_update_display()

func _handle_trigonometric(func_name: String) -> void:
	var value: float = current_value.to_float()
	var result: float = 0.0
	
	# Convert to radians for calculation
	var radians: float = deg_to_rad(value)
	
	match func_name:
		"sin":
			result = sin(radians)
		"cos":
			result = cos(radians)
		"tan":
			result = tan(radians)
	
	_add_to_history("%s(%s°) = %s" % [func_name, _format_number(value), _format_number(result)])
	current_value = _format_number(result)
	should_clear_display = true
	has_pending_operation = false
	expression = current_value
	_update_display()

func _handle_logarithm() -> void:
	var value: float = current_value.to_float()
	if value > 0:
		var result: float = log(value) / log(10)  # Base 10 logarithm
		_add_to_history("log(%s) = %s" % [_format_number(value), _format_number(result)])
		current_value = _format_number(result)
	else:
		current_value = "Error"
	should_clear_display = true
	has_pending_operation = false
	expression = current_value
	_update_display()

func _memory_add() -> void:
	memory_value += current_value.to_float()
	_show_memory_indicator()

func _memory_recall() -> void:
	current_value = _format_number(memory_value)
	should_clear_display = true
	if has_pending_operation:
		expression += " " + current_value
	else:
		expression = current_value
	_update_display()

func _clear_all() -> void:
	current_value = "0"
	stored_value = 0.0
	pending_operation = ""
	should_clear_display = false
	has_pending_operation = false
	expression = "0"
	_update_display()

func _format_number(value: float) -> String:
	# Check for infinity or numbers exceeding 64-bit integer bounds
	if is_inf(value) or is_nan(value):
		return "E"  # Show capital E for overflow
	
	# Check if number exceeds safe integer bounds (2^53 for precise representation)
	# or approaches 64-bit limits
	if abs(value) > 9007199254740992.0:  # 2^53, beyond which precision is lost
		return "E"  # Show capital E for overflow
	
	# Format number for display
	if abs(value) < 0.0000001 and value != 0:
		return "%.6e" % value  # Scientific notation for very small numbers
	else:
		var formatted: String = "%.8f" % value
		# Remove trailing zeros
		while formatted.ends_with("0") and formatted.contains("."):
			formatted = formatted.substr(0, formatted.length() - 1)
		if formatted.ends_with("."):
			formatted = formatted.substr(0, formatted.length() - 1)
		return formatted

func _update_display() -> void:
	# Show expression if we have a pending operation, otherwise show current value
	var display_text: String = expression if has_pending_operation else current_value
	display_label.text = display_text
	
	# Adjust font size based on text length
	var base_font_size: int = 48
	if display_text.length() > 10:
		display_label.add_theme_font_size_override("font_size", base_font_size - (display_text.length() - 10) * 2)
	else:
		display_label.add_theme_font_size_override("font_size", base_font_size)

func _add_to_history(entry: String) -> void:
	calculation_history.append(entry)
	
	# Limit history size
	if calculation_history.size() > MAX_HISTORY_ITEMS:
		calculation_history.pop_front()
	
	# Update history display
	var history_text: String = ""
	for i in range(calculation_history.size() - 1, -1, -1):
		history_text += calculation_history[i] + "\n"
	
	history_label.text = history_text
	
	# Scroll to bottom
	await get_tree().process_frame
	history_scroll.scroll_vertical = int(history_scroll.get_v_scroll_bar().max_value)

func _show_memory_indicator() -> void:
	# Flash memory indicator
	var memory_label: Label = display_label.get_parent().get_node_or_null("MemoryIndicator")
	if memory_label:
		memory_label.modulate.a = 1.0
		var tween: Tween = create_tween()
		tween.tween_property(memory_label, "modulate:a", 0.3, 1.0)

func _on_scientific_mode_toggled(enabled: bool) -> void:
	is_scientific_mode = enabled
	_create_buttons()

func _input(event: InputEvent) -> void:
	# Keyboard input handling
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_0, KEY_KP_0:
				_on_button_pressed("0")
			KEY_1, KEY_KP_1:
				_on_button_pressed("1")
			KEY_2, KEY_KP_2:
				_on_button_pressed("2")
			KEY_3, KEY_KP_3:
				_on_button_pressed("3")
			KEY_4, KEY_KP_4:
				_on_button_pressed("4")
			KEY_5, KEY_KP_5:
				_on_button_pressed("5")
			KEY_6, KEY_KP_6:
				_on_button_pressed("6")
			KEY_7, KEY_KP_7:
				_on_button_pressed("7")
			KEY_8, KEY_KP_8:
				_on_button_pressed("8")
			KEY_9, KEY_KP_9:
				_on_button_pressed("9")
			KEY_PERIOD, KEY_KP_PERIOD:
				_on_button_pressed(".")
			KEY_PLUS, KEY_KP_ADD:
				_on_button_pressed("+")
			KEY_MINUS, KEY_KP_SUBTRACT:
				_on_button_pressed("-")
			KEY_ASTERISK, KEY_KP_MULTIPLY:
				_on_button_pressed("×")
			KEY_SLASH, KEY_KP_DIVIDE:
				_on_button_pressed("÷")
			KEY_ENTER, KEY_KP_ENTER:
				_on_button_pressed("=")
			KEY_BACKSPACE:
				_on_button_pressed("⌫")
			KEY_ESCAPE:
				_on_button_pressed("C")
