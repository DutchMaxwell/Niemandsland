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
var _unit_dock: Node
var _battle_log: Node
var _terrain_overlay: Node
var _counters: Dictionary = {}


func setup(refs: Dictionary) -> void:
	_camera_pivot = refs.get("camera_pivot")
	_object_manager = refs.get("object_manager")
	_army_manager = refs.get("army_manager")
	_table = refs.get("table")
	_map_layout = refs.get("map_layout")
	_left_panel = refs.get("left_panel")
	_main = refs.get("main")
	_unit_dock = refs.get("unit_dock")
	_battle_log = refs.get("battle_log")
	_terrain_overlay = refs.get("terrain_overlay")
	if _object_manager != null and _object_manager.has_signal("measurement_finished"):
		if not _object_manager.measurement_finished.is_connected(_on_measurement_finished):
			_object_manager.measurement_finished.connect(_on_measurement_finished)
	if _battle_log != null and _battle_log.has_signal("entry_added"):
		if not _battle_log.entry_added.is_connected(_on_battle_log_entry):
			_battle_log.entry_added.connect(_on_battle_log_entry)
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
		"units_p1": 0, "p1_all_in_zone": false, "phase": 0,
		"bands": false, "round": 0, "card_presented": false}
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
	if _army_manager != null and "current_round" in _army_manager:
		facts.round = int(_army_manager.current_round)
	if _object_manager != null and "movement_range_controller" in _object_manager:
		var mr: Node = _object_manager.movement_range_controller
		if mr != null and mr.has_method("active_count"):
			facts.bands = mr.active_count() > 0
	if _unit_dock != null and _unit_dock.has_method("get_presented_unit"):
		facts.card_presented = _unit_dock.get_presented_unit() != null
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
		var all_units: Array = _army_manager.get_all_game_units()
		for unit in all_units:
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
				"alive": alive.size(), "activated": unit.is_activated,
				"shaken": unit.is_shaken, "fatigued": unit.is_fatigued,
				"card_presented": _is_card_presented(unit),
				"terrain": _terrain_mode(alive),
				"enemy_gap_in": _enemy_gap_in(unit, all_units)}
	return facts


func bump(key: String) -> void:
	_counters[key] = int(_counters.get(key, 0)) + 1


func _on_measurement_finished(_distance_inches: float) -> void:
	bump("measure")


func _on_human_attack_resolved(attacker: GameUnit, melee: bool) -> void:
	_bump_tag("melee" if melee else "shoot", attacker)


func _on_human_cast_resolved(unit: GameUnit) -> void:
	_bump_tag("cast", unit)


## Pile-in and consolidation have no lasting state to read — they are one-shot resolver events. Mark
## them by their battle-log lines so a lesson step can gate on "the event happened" (counter_grew).
func _on_battle_log_entry(entry: Dictionary) -> void:
	var text := String(entry.get("text", ""))
	var low := text.to_lower()
	if low.contains("pile in"):
		bump("log:pile_in")
	if low.contains("consolidat"):
		bump("log:consolidate")
	# Morale outcome lines read "<name> passes morale" / "<name> fails morale …". Bump a counter for
	# the TESTED unit's lesson tag so a lesson can gate "the volley forced a morale test"
	# (log:morale:target).
	for suffix in [" passes morale", " fails morale"]:
		var mi := text.find(suffix)
		if mi > 0:
			var mtag := _tag_for_name(text.substr(0, mi))
			if not mtag.is_empty():
				bump("log:morale:%s" % mtag)
			break
	# Melee strike lines read "<unit name> strikes with <weapon> at <target> …". Bump a counter for
	# the STRIKER's lesson tag, so a lesson can gate "the defender struck back" (strike:target).
	var marker := " strikes with "
	var at := text.find(marker)
	if at > 0:
		var tag := _tag_for_name(text.substr(0, at))
		if not tag.is_empty():
			bump("strike:%s" % tag)


## Whether this unit's card is the one currently presented in the unit dock (S-07 Tough read).
func _is_card_presented(unit: GameUnit) -> bool:
	if _unit_dock == null or not _unit_dock.has_method("get_presented_unit"):
		return false
	return _unit_dock.get_presented_unit() == unit


## The terrain type MOST of a unit's alive models stand on (S-08), or 0 (NONE) when there is no
## overlay. Ties resolve to the last type that took the lead.
func _terrain_mode(alive: Array[ModelInstance]) -> int:
	if _terrain_overlay == null or not _terrain_overlay.has_method("get_terrain_at_world_position"):
		return 0
	var counts: Dictionary = {}
	var best := 0
	var best_n := 0
	for model in alive:
		if not is_instance_valid(model.node):
			continue
		var t := int(_terrain_overlay.get_terrain_at_world_position(model.node.global_position))
		var n := int(counts.get(t, 0)) + 1
		counts[t] = n
		if n > best_n:
			best_n = n
			best = t
	return best


## The lesson tag of the tagged unit whose on-screen name is `unit_name`, or "" (untagged units are
## not the lesson's business). Names are unique in a lesson table.
func _tag_for_name(unit_name: String) -> String:
	if _army_manager == null or not _army_manager.has_method("get_all_game_units"):
		return ""
	for unit in _army_manager.get_all_game_units():
		if unit is GameUnit and unit.get_name() == unit_name:
			return String(unit.unit_properties.get("lesson_tag", ""))
	return ""


## Base-to-base gap (inches) from `unit` to its nearest enemy, via the solo controller's own melee
## geometry. INF when there is no controller or no enemy, so a gap gate can never fake completion.
func _enemy_gap_in(unit: GameUnit, all_units: Array) -> float:
	if _main == null or not ("solo_controller" in _main):
		return INF
	var sc: Node = _main.solo_controller
	if sc == null or not sc.has_method("nearest_melee_gap_in"):
		return INF
	var pid := int(unit.unit_properties.get("player_id", 0))
	var best := INF
	for other in all_units:
		if other == unit or not other is GameUnit:
			continue
		if int(other.unit_properties.get("player_id", 0)) == pid:
			continue
		best = minf(best, float(sc.nearest_melee_gap_in(unit, other)))
	return best


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
