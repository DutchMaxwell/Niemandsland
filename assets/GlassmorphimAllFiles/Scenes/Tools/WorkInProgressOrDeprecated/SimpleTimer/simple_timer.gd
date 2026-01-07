extends Control

# Timer Tool for Start, Stop, and Reset functionality
class_name SimpleTimer

# UI References
@export var start_button: Button
@export var stop_button: Button
@export var reset_button: Button
@export var timer_label: Label

# Timer variables
var timer: Timer = Timer.new()
var time_elapsed: int = 0

func _ready() -> void:
	# Initialize UI
	start_button = $VBoxContainer/HBoxContainer/StartButton
	stop_button = $VBoxContainer/HBoxContainer/StopButton
	reset_button = $VBoxContainer/HBoxContainer/ResetButton
	timer_label = $VBoxContainer/TimerLabel

	# Connect button signals
	start_button.pressed.connect(start_timer)
	stop_button.pressed.connect(stop_timer)
	reset_button.pressed.connect(reset_timer)

	# Timer setup
	timer.wait_time = 1
	timer.one_shot = false
	timer.timeout.connect(_update_time)
	add_child(timer)

func start_timer() -> void:
	timer.start()

func stop_timer() -> void:
	timer.stop()

func reset_timer() -> void:
	timer.stop()
	time_elapsed = 0
	_update_timer_label()

func _update_time() -> void:
	time_elapsed += 1
	_update_timer_label()

func _update_timer_label() -> void:
	var seconds_passed: int = time_elapsed % 60
	var minutes_passed: int = (time_elapsed / 60) % 60
	var hours_passed: int = time_elapsed / 3600
	timer_label.text = str(hours_passed).pad_zeros(2) + ":" + str(minutes_passed).pad_zeros(2) + ":" + str(seconds_passed).pad_zeros(2)
