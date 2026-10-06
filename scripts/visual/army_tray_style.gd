extends Node3D
## Extends gfx/tray-felt (087adcc3): felt, walnut and lit staging bands; geometry is cosmetic.
const FELT := Color(0.11,0.095,0.075)
const WALNUT := Color(0.20,0.12,0.06)
var _originals := {}
var _surface: MeshInstance3D
var _felt: ShaderMaterial
var _wood: ShaderMaterial
var _support: Node3D

func setup(size: Vector2, player_color: Color) -> void:
	_felt = _material(FELT.lerp(player_color,0.08), false)
	_wood = _material(WALNUT.lerp(player_color,0.12), true)
	for child in get_parent().get_children():
		if child is MeshInstance3D:
			_originals[child] = child.material_override
			if _surface == null:
				_surface = child
	_support = Node3D.new()
	_support.name = "TraySupport"
	add_child(_support)
	for i in 5:
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(size.x,0.08,size.y) if i == 0 else Vector3(0.055,0.25,0.055)
		mesh.mesh = box
		mesh.material_override = _wood
		mesh.position = Vector3(0,-0.05,0) if i == 0 else Vector3(size.x*0.43*(-1 if i % 2 == 0 else 1),-0.21,size.y*0.43*(-1 if i < 3 else 1))
		_support.add_child(mesh)
	var graphics := _graphics()
	if graphics != null:
		graphics.connect("settings_applied", Callable(self, "_refresh"))
	_refresh()

## The autoload is absent in standalone --script probes; look it up instead of naming the global.
func _graphics() -> Node:
	return get_node_or_null("/root/GraphicsSettings")

static func _material(color: Color, wood: bool) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/visual/army_tray.gdshader")
	material.set_shader_parameter("base_color",color)
	material.set_shader_parameter("wood",wood)
	return material

func _refresh(_preset_name := "") -> void:
	var graphics := _graphics()
	if graphics == null:
		return
	var enabled: bool = graphics.army_tray_dressing_enabled()
	_support.visible = enabled
	for i in range(1,5):
		_support.get_child(i).visible = graphics.world_enabled(graphics.current_preset)
	for mesh: MeshInstance3D in _originals:
		var original: Material = _originals[mesh]
		if not enabled:
			mesh.material_override = original
		elif mesh == _surface:
			mesh.material_override = _felt
		elif mesh.mesh is PlaneMesh:
			var band := original.duplicate() as StandardMaterial3D
			band.albedo_color.a = 0.055
			band.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
			mesh.material_override = band
		else:
			mesh.material_override = _wood
