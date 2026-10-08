class_name LessonFacts
extends RefCounted
## Current game state for LessonChecks. Snapshots own their counters so a later bump
## cannot change a step's entry baseline.

const METRES_PER_INCH := 0.0254

var _camera_pivot: Node3D
var _object_manager: Node
var _army_manager: Node
var _table: Node
var _map_layout: Node
var _left_panel: CanvasItem
var _main: Node
var _counters: Dictionary = {}


func setup(refs: Dictionary) -> void:
	_camera_pivot = refs.get("camera_pivot")
	_object_manager = refs.get("object_manager")
	_army_manager = refs.get("army_manager")
	_table = refs.get("table")
	_map_layout = refs.get("map_layout")
	_left_panel = refs.get("left_panel")
	_main = refs.get("main")
	if _object_manager != null and _object_manager.has_signal("measurement_finished"):
		if not _object_manager.measurement_finished.is_connected(_on_measurement_finished):
			_object_manager.measurement_finished.connect(_on_measurement_finished)
	if _main != null and _main.has_signal("human_attack_resolved"):
		if not _main.human_attack_resolved.is_connected(_on_human_attack_resolved):
			_main.human_attack_resolved.connect(_on_human_attack_resolved)
	if _main != null and _main.has_signal("human_cast_resolved"):
		if not _main.human_cast_resolved.is_connected(_on_human_cast_resolved):
			_main.human_cast_resolved.connect(_on_human_cast_resolved)

func snapshot() -> Dictionary:
	var facts := {"yaw": 0.0, "cam_dist": 0.0, "pivot": Vector3.ZERO,
		"counters": _counters.duplicate(), "tags": {},
		"table_size": Vector2.ZERO, "biome": "", "terrain_pieces": 0,
		"layout_pieces": 0, "deploy_type": 0, "menu_open": false,
		"units_p1": 0, "p1_all_in_zone": false, "phase": 0}
	if _table != null and "table_size" in _table:
		facts.table_size = _table.table_size
	if _table != null and "biome" in _table:
		facts.biome = String(_table.biome)
	facts.terrain_pieces = _count_terrain()
	if _map_layout != null and "placed_pieces" in _map_layout:
		facts.layout_pieces = (_map_layout.placed_pieces as Array).size()
	if _map_layout != null and "deployment_type" in _map_layout:
		facts.deploy_type = int(_map_layout.deployment_type)
	if is_instance_valid(_left_panel):
		facts.menu_open = _left_panel.visible
	var p1_units := _p1_units()
	facts.units_p1 = p1_units.size()
	facts.p1_all_in_zone = _p1_all_in_zone(p1_units)
	if _army_manager != null and "game_phase" in _army_manager:
		facts.phase = int(_army_manager.game_phase)
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


func _on_human_attack_resolved(attacker: GameUnit, melee: bool) -> void:
	_bump_tag("melee" if melee else "shoot", attacker)


func _on_human_cast_resolved(unit: GameUnit) -> void:
	_bump_tag("cast", unit)


## Count an event against a lesson unit's tag. Untagged (non-lesson) units are not the lesson's business.
func _bump_tag(prefix: String, unit: GameUnit) -> void:
	if unit == null:
		return
	var tag := String(unit.unit_properties.get("lesson_tag", ""))
	if tag.is_empty():
		return
	bump("%s:%s" % [prefix, tag])


## Free-placed and grid terrain pieces the object manager is responsible for, each counted once.
func _count_terrain() -> int:
	if _object_manager == null or not _object_manager.is_inside_tree():
		return 0
	var count := 0
	for obj in _object_manager.get_tree().get_nodes_in_group("terrain"):
		if obj is Node3D and UnitUtils.is_terrain(obj):
			count += 1
	return count


func _p1_units() -> Array:
	if _army_manager != null and _army_manager.has_method("get_game_units_for_player"):
		return _army_manager.get_game_units_for_player(1)
	return []


## True when there is at least one deployed player-1 model and every one of them stands inside the
## standard Front Line deployment zone (p.6). No units -> false, so the step cannot fake completion.
func _p1_all_in_zone(units: Array) -> bool:
	var probe := DeploymentCatalog.zone_test("front_line", 1)
	var models := 0
	for unit in units:
		if not unit is GameUnit:
			continue
		for model in unit.get_alive_models():
			if not is_instance_valid(model.node):
				continue
			models += 1
			var at := Vector2(model.node.global_position.x, model.node.global_position.z)
			if not probe.call(at):
				return false
	return models > 0
