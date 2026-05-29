class_name ModelInstance
extends RefCounted
## Represents a single model within a unit.
## Uses a generic properties dictionary - no hardcoded roles or equipment names.
## This allows flexibility for any game system (OPR, WGS, custom).

# ===== References =====

## Parent unit (GameUnit reference, Variant to avoid circular dependency)
var unit: Variant = null

## 3D model node on the table
var node: Node3D = null

## Position index within the unit (0-based)
var model_index: int = 0

# ===== Generic Properties =====
## All model-specific data from import.
## Example contents:
## {
##   "weapons": [OPRWeapon, OPRWeapon],      # Weapons THIS model carries
##   "equipment": ["Banner"],                 # Equipment THIS model carries (no count)
##   "special_rules": ["Primal", "Fearless"], # Rules THIS model has
##   "tough": 3,                              # Parsed from "Tough(3)"
##   "hero": false,                           # Optional: Hero flag
##   "attached_to": null,                     # Optional: "Joined to:" Unit reference
## }
var properties: Dictionary = {}

# ===== Runtime State (NOT from import) =====

## Current wounds remaining
var wounds_current: int = 1

## Maximum wounds (from Tough(X) or default 1)
var wounds_max: int = 1

## Whether this model is still alive
var is_alive: bool = true

## Runtime markers: ["Activated", "Pinned", "Shaken", etc.]
var markers: Array[String] = []

## Colors for custom (non-standard) markers, keyed by marker name. Standard
## marker colors come from UnitMarker.STANDARD_MARKERS and are not stored here.
var marker_colors: Dictionary = {}  # marker_name (String) -> Color

# ===== Import/Spawn Position (for Sort Table reset) =====

## Initial position when spawned
var import_position: Vector3 = Vector3.ZERO

## Initial rotation when spawned
var import_rotation: Vector3 = Vector3.ZERO


# ===== Helper Methods (Query, no hardcoding) =====

## Returns a display name for this model.
## Shows first equipment if available, otherwise "Model N".
func get_display_name() -> String:
	var equip = properties.get("equipment", [])
	if not equip.is_empty():
		return equip[0]  # First equipment as name
	return "Model %d" % (model_index + 1)


## Checks if this model has a specific property key.
func has_property(key: String) -> bool:
	return properties.has(key)


## Gets a property value with optional default.
func get_property(key: String, default: Variant = null) -> Variant:
	return properties.get(key, default)


## Checks if this model has a special rule (prefix match).
## e.g., has_special_rule("Tough") matches "Tough(3)"
func has_special_rule(rule: String) -> bool:
	var rules = properties.get("special_rules", [])
	for r in rules:
		if r is String and r.begins_with(rule):
			return true
		elif r is Dictionary and r.get("name", "").begins_with(rule):
			return true
	return false


## Gets all weapons assigned to this model.
func get_weapons() -> Array:
	return properties.get("weapons", [])


## Gets all equipment assigned to this model.
func get_equipment() -> Array:
	return properties.get("equipment", [])


## Checks if this model carries specific equipment.
func has_equipment(equipment_name: String) -> bool:
	return equipment_name in get_equipment()


## Applies damage to this model. Returns true if model died.
func apply_damage(damage: int) -> bool:
	var old_alive = is_alive
	wounds_current = max(0, wounds_current - damage)
	is_alive = wounds_current > 0
	return old_alive and not is_alive  # Returns true if just died


## Heals wounds on this model (up to max).
func heal(amount: int) -> void:
	wounds_current = min(wounds_max, wounds_current + amount)
	if wounds_current > 0:
		is_alive = true


## Resets this model to full health.
func reset_wounds() -> void:
	wounds_current = wounds_max
	is_alive = true


## Adds a marker to this model.
func add_marker(marker_name: String) -> void:
	if marker_name not in markers:
		markers.append(marker_name)


## Removes a marker from this model.
func remove_marker(marker_name: String) -> void:
	markers.erase(marker_name)


## Checks if this model has a specific marker.
func has_marker(marker_name: String) -> bool:
	return marker_name in markers


## Clears all markers from this model.
func clear_markers() -> void:
	markers.clear()


## Returns a dictionary representation for saving.
func to_dict() -> Dictionary:
	var colors_data := {}
	for key in marker_colors:
		var color: Color = marker_colors[key]
		colors_data[key] = [color.r, color.g, color.b, color.a]

	return {
		"model_index": model_index,
		"properties": properties.duplicate(true),
		"wounds_current": wounds_current,
		"wounds_max": wounds_max,
		"is_alive": is_alive,
		"markers": markers.duplicate(),
		"marker_colors": colors_data,
		"import_position": [import_position.x, import_position.y, import_position.z],
		"import_rotation": [import_rotation.x, import_rotation.y, import_rotation.z],
	}


## Creates a ModelInstance from a dictionary (for loading).
static func from_dict(data: Dictionary) -> ModelInstance:
	var instance = ModelInstance.new()
	instance.model_index = data.get("model_index", 0)
	instance.properties = data.get("properties", {}).duplicate(true)
	instance.wounds_current = data.get("wounds_current", 1)
	instance.wounds_max = data.get("wounds_max", 1)
	instance.is_alive = data.get("is_alive", true)

	var saved_markers = data.get("markers", [])
	instance.markers.clear()
	for marker in saved_markers:
		instance.markers.append(marker)

	var saved_colors = data.get("marker_colors", {})
	if saved_colors is Dictionary:
		for key in saved_colors:
			var arr = saved_colors[key]
			if arr is Array and arr.size() >= 4:
				instance.marker_colors[key] = Color(arr[0], arr[1], arr[2], arr[3])

	# Load import position/rotation (for Sort Table reset)
	var pos = data.get("import_position", [0, 0, 0])
	if pos is Array and pos.size() >= 3:
		instance.import_position = Vector3(pos[0], pos[1], pos[2])

	var rot = data.get("import_rotation", [0, 0, 0])
	if rot is Array and rot.size() >= 3:
		instance.import_rotation = Vector3(rot[0], rot[1], rot[2])

	return instance
