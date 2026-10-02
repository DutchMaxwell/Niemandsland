class_name SandboxPlacementGhost
extends Node3D
## Click-to-place for the terrain shelf: once armed with a catalog entry, a flat translucent footprint follows
## the cursor on the table; a click on the table drops the piece there, Esc cancels. It lives under the
## ObjectManager (so it is in the 3D world) and asks it for the cursor point and for the spawn.

## Emitted after a piece was dropped (the shelf turns it into its piece_placed seam).
signal dropped(prop_id: String)
## Emitted when the player cancelled with Esc.
signal cancelled

const GHOST_TINT := Color(HouseStyle.ACCENT, 0.35)

# Untyped on purpose (same reason as SandboxTerrainShelf._object_manager).
var _object_manager: Node = null
var _entry: Dictionary = {}
var _mesh: MeshInstance3D = null


func setup(object_manager: Node) -> void:
	_object_manager = object_manager
	visible = false
	set_process(false)
	var inch := 0.0254
	var side: float = float(object_manager.get("SANDBOX_DEFAULT_FOOTPRINT_INCHES") if object_manager.get("SANDBOX_DEFAULT_FOOTPRINT_INCHES") != null else 3.0)
	var box := BoxMesh.new()
	box.size = Vector3(side * inch * 2.0, 0.004, side * inch * 2.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = GHOST_TINT
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	box.material = mat
	_mesh = MeshInstance3D.new()
	_mesh.mesh = box
	add_child(_mesh)


func is_armed() -> bool:
	return not _entry.is_empty()


## Start following the cursor with `entry` ({prop_id, kind, ...} from sandbox_catalog).
func arm(entry: Dictionary) -> void:
	_entry = entry
	visible = true
	set_process(true)
	set_process_input(true)
	_follow_cursor()


func cancel() -> void:
	var was_armed := is_armed()
	_entry = {}
	visible = false
	set_process(false)
	if was_armed:
		cancelled.emit()


## Drop the armed piece at the cursor's table point. False when nothing is armed.
func commit() -> bool:
	if not is_armed() or _object_manager == null:
		return false
	var pos: Vector3 = _object_manager.get_cursor_table_position()
	_object_manager.spawn_sandbox_terrain(_entry.get("prop_id", ""), int(_entry.get("kind", 0)), pos)
	dropped.emit(str(_entry.get("prop_id", "")))
	return true


func _process(_delta: float) -> void:
	_follow_cursor()


func _follow_cursor() -> void:
	if _object_manager != null and is_armed():
		global_position = _object_manager.get_cursor_table_position()


func _input(event: InputEvent) -> void:
	if not is_armed():
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		cancel()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# Only a click on the bare table counts - a click on any UI (the shelf itself, the HUD) does not.
		if get_viewport().gui_get_hovered_control() == null and commit():
			get_viewport().set_input_as_handled()
