extends ProgressBar

# Animation Settings
@export_group("Animation")
## Animation duration in seconds
@export_range(0.1, 10.0, 0.1) var animation_duration: float = 2.0
## Animation transition type
@export_enum("LINEAR", "SINE", "QUINT", "QUART", "QUAD", "EXPO", "ELASTIC", "CUBIC", "CIRC", "BOUNCE", "BACK", "SPRING") var transition_type: int = Tween.TRANS_CUBIC
## Animation easing type  
@export_enum("IN", "OUT", "IN_OUT", "OUT_IN") var easing_type: int = Tween.EASE_IN_OUT
## Auto start animation on ready
@export var auto_start: bool = true
## Loop the animation
@export var loop_animation: bool = false
## Ping-pong animation (goes back and forth)
@export var ping_pong: bool = true
## Delay before animation starts (in seconds)
@export_range(0.0, 5.0, 0.1) var start_delay: float = 0.0
## Delay between loops (in seconds)
@export_range(0.0, 5.0, 0.1) var loop_delay: float = 0.0

var tween: Tween = null
var animation_direction: int = 1 # 1 for forward, -1 for backward

func _ready() -> void:
	if auto_start:
		start_animation()

func start_animation() -> void:
	# Kill any existing tween
	if tween:
		tween.kill()
	
	# Reset to 0 and direction
	value = 0
	animation_direction = 1
	
	# Start the animation sequence
	_animate_sequence()

func _animate_sequence() -> void:
	# Create new tween
	tween = create_tween()
	
	# Apply initial delay only on first run
	if value == 0 and animation_direction == 1 and start_delay > 0:
		tween.tween_interval(start_delay)
	
	if ping_pong and loop_animation:
		# Ping-pong animation
		if animation_direction == 1:
			# Forward: 0 to 100
			tween.tween_property(self, "value", 100.0, animation_duration).set_trans(transition_type).set_ease(easing_type)
		else:
			# Backward: 100 to 0
			tween.tween_property(self, "value", 0.0, animation_duration).set_trans(transition_type).set_ease(easing_type)
		
		# Add loop delay if set
		if loop_delay > 0:
			tween.tween_interval(loop_delay)
		
		# Toggle direction for next animation
		animation_direction *= -1
		tween.finished.connect(_on_tween_finished)
	else:
		# Regular animation (always forward)
		tween.tween_property(self, "value", 100.0, animation_duration).set_trans(transition_type).set_ease(easing_type)
		
		if loop_animation:
			# Add loop delay if set
			if loop_delay > 0:
				tween.tween_interval(loop_delay)
			tween.finished.connect(_on_tween_finished)

func _on_tween_finished() -> void:
	if loop_animation:
		if ping_pong:
			# Continue ping-pong animation
			_animate_sequence()
		else:
			# Reset and start again
			value = 0
			_animate_sequence()

func stop_animation() -> void:
	if tween:
		tween.kill()
		tween = null

func pause_animation() -> void:
	if tween:
		tween.pause()

func resume_animation() -> void:
	if tween:
		tween.play()

func reset() -> void:
	stop_animation()
	value = 0
