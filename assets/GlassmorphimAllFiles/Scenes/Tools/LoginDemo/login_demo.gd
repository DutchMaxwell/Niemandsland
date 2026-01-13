extends Control


@export var fireflies: CPUParticles2D
@export var firefly_fade_duration: float = 2.0
@export var glowing_world_environment: GlowingWorldEnvironment

var firefly_tween: Tween


func _on_theme_button_toggled(toggled_on: bool) -> void:
	if not fireflies:
		push_error("No fireflies particle system assigned!")
		return
	
	# Kill any existing tween
	if firefly_tween and firefly_tween.is_running():
		firefly_tween.kill()
	
	# Create new tween for smooth transition
	firefly_tween = create_tween()
	
	if toggled_on:  # Dark theme - make fireflies visible
		glowing_world_environment.enable_glow()
		# Fade in fireflies
		firefly_tween.tween_property(fireflies, "modulate:a", 1.0, firefly_fade_duration)
	else:  # Light theme - hide fireflies
		glowing_world_environment.disable_glow()
		# Fade out fireflies
		firefly_tween.tween_property(fireflies, "modulate:a", 0.0, firefly_fade_duration)
