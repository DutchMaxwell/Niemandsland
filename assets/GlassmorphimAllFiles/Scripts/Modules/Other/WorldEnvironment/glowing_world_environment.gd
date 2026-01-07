class_name GlowingWorldEnvironment
extends WorldEnvironment


## Enables glow
func enable_glow() -> void:
	if not environment:
		push_error("GlowingWorldEnvironment: Cannot enable glow - no Environment resource!")
		return
	
	if environment.background_mode != Environment.BG_CANVAS:
		push_warning("GlowingWorldEnvironment: Background mode is not Canvas. Setting it to Canvas for glow to work.")
		environment.background_mode = Environment.BG_CANVAS
	
	environment.glow_enabled = true


## Disables glow
func disable_glow() -> void:
	if not environment:
		push_error("GlowingWorldEnvironment: Cannot disable glow - no Environment resource!")
		return
	
	if environment.background_mode != Environment.BG_CANVAS:
		push_warning("GlowingWorldEnvironment: Background mode is not Canvas. Setting it to Canvas for glow to work.")
		environment.background_mode = Environment.BG_CANVAS
	
	environment.glow_enabled = false
