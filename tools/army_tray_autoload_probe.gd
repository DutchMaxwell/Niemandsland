extends SceneTree

const TrayStyle := preload("res://scripts/visual/army_tray_style.gd")

func _initialize() -> void:
	var tray := Node3D.new()
	var plate := MeshInstance3D.new()
	plate.mesh = BoxMesh.new()
	tray.add_child(plate)
	var style := TrayStyle.new()
	tray.add_child(style)
	root.add_child(tray)
	style.setup(Vector2(0.2, 0.2), Color.RED)
	print("TRAY_AUTOLOAD_PROBE_OK")
	quit()
