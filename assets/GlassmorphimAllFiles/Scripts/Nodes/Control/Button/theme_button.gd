extends Button

@export var light_theme: Texture2D
@export var dark_theme: Texture2D
@export var control_to_multiply: Control
@export var transition_color_rect: ColorRect
@export var transition_start_duration: float = 0.1
@export var transition_end_duration: float = 0.6


var canvas_item_material: CanvasItemMaterial
var current_tween: Tween


func _ready() -> void:
	if not control_to_multiply:
		push_error("No control to multiply in Theme Button!")
		return
	
	if control_to_multiply.material:
		canvas_item_material = control_to_multiply.material
	else:
		canvas_item_material = CanvasItemMaterial.new()
		control_to_multiply.material = canvas_item_material


func _on_toggled(toggled_on: bool) -> void:
	# Kill any existing tween if running
	if current_tween and current_tween.is_running():
		current_tween.kill()
	
	if not transition_color_rect:
		if toggled_on:
			icon = dark_theme
			canvas_item_material.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
		else:
			icon = light_theme
			canvas_item_material.blend_mode = CanvasItemMaterial.BLEND_MODE_MIX
		return

	# Create new tween and store it
	current_tween = create_tween()
	current_tween.tween_property(transition_color_rect, "modulate:a", 1.0, transition_start_duration)
	current_tween.finished.connect(func() -> void:
		if toggled_on:
			icon = dark_theme
			canvas_item_material.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
		else:
			icon = light_theme
			canvas_item_material.blend_mode = CanvasItemMaterial.BLEND_MODE_MIX
		# Create the fade-in tween and store it
		current_tween = create_tween()
		current_tween.tween_property(transition_color_rect, "modulate:a", 0.0, transition_end_duration)
	)
