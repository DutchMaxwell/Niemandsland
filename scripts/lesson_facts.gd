class_name LessonFacts
extends RefCounted
## Current game state for LessonChecks. Snapshots own their counters so a later bump
## cannot change a step's entry baseline.

const METRES_PER_INCH := 0.0254

var _camera_pivot: Node3D
var _object_manager: Node
var _army_manager: Node
var _counters: Dictionary = {}


func setup(refs: Dictionary) -> void:
	_camera_pivot = refs.get("camera_pivot")
	_object_manager = refs.get("object_manager")
	_army_manager = refs.get("army_manager")
	if _object_manager != null and _object_manager.has_signal("measurement_finished"):
		if not _object_manager.measurement_finished.is_connected(_on_measurement_finished):
			_object_manager.measurement_finished.connect(_on_measurement_finished)

func snapshot() -> Dictionary:
	var facts := {"yaw": 0.0, "cam_dist": 0.0, "pivot": Vector3.ZERO,
		"counters": _counters.duplicate(), "tags": {}}
	if is_instance_valid(_camera_pivot):
		facts.yaw = _camera_pivot.rotation.y
		facts.pivot = _camera_pivot.global_position
		var camera := _camera_pivot.get_node_or_null("Camera3D") as Camera3D
		if camera != null:
			facts.cam_dist = camera.position.length()
	if _army_manager != null and _army_manager.has_method("get_all_game_units"):
		var selected: Array = []
		if _object_manager != null and _object_manager.has_method("get_selected_objects"):
			selected = _object_manager.get_selected_objects()
		for unit in _army_manager.get_all_game_units():
			if not unit is GameUnit:
				continue
			var tag := String(unit.unit_properties.get("lesson_tag", ""))
			if tag.is_empty():
				continue
			var alive: Array[ModelInstance] = unit.get_alive_models()
			var whole := not alive.is_empty()
			var sum := Vector2.ZERO
			var positioned := 0
			for model in alive:
				if not is_instance_valid(model.node):
					whole = false
					continue
				whole = whole and selected.has(model.node)
				sum += Vector2(model.node.global_position.x, model.node.global_position.z)
				positioned += 1
			facts.tags[tag] = {"selected_whole": whole,
				"centroid_in": sum / float(positioned) / METRES_PER_INCH if positioned > 0 else Vector2.ZERO,
				"alive": alive.size()}
	return facts


func bump(key: String) -> void:
	_counters[key] = int(_counters.get(key, 0)) + 1


func _on_measurement_finished(_distance_inches: float) -> void:
	bump("measure")
