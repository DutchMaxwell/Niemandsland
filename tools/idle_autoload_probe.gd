extends SceneTree

const IdleRuntime := preload("res://scripts/visual/bone_texture_idle.gd")

func _initialize() -> void:
	var idle := IdleRuntime.new()
	root.add_child(idle)
	print("IDLE_AUTOLOAD_PROBE_OK")
	quit()
