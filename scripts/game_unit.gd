class_name GameUnit
extends RefCounted
## System-agnostic wrapper for a unit.
## Can wrap OPR units, WGS units, or generic miniatures.
## Provides a unified interface regardless of source.

# ===== Source Data =====

## Original data from import (OPRUnit, WGSUnit, or generic Dictionary)
var source_data: Variant = null

## Source type identifier: "opr", "wgs", "generic"
var source_type: String = "generic"

## Unique identifier for this unit (for multiplayer sync and save/load)
var unit_id: String = ""

# ===== Model-Level Data =====

## All models belonging to this unit
var models: Array[ModelInstance] = []

# ===== Unit-Level Properties =====
## Extracted from import, example:
## {
##   "name": "Saurian Warriors",
##   "size": 20,
##   "quality": 4,
##   "defense": 4,
##   "cost": 200,
##   "special_rules": ["Tough(3)", "Primal", "Fearless"],
##   "attached_heroes": [],       # Heroes that are "Joined to:" this unit
##   "attached_to": null,         # Unit this hero is "Joined to:"
## }
var unit_properties: Dictionary = {}

# ===== Activation State =====

## Whether this unit has activated this round
var is_activated: bool = false

## Which round this unit activated in
var activation_round: int = 0


# ===== Model Access Methods =====

## Gets a model by index (0-based).
func get_model(index: int) -> ModelInstance:
	if index >= 0 and index < models.size():
		return models[index]
	return null


## Finds the ModelInstance for a given Node3D.
func get_model_for_node(node: Node3D) -> ModelInstance:
	for model in models:
		if model.node == node:
			return model
	return null


## Gets all models that are still alive.
func get_alive_models() -> Array[ModelInstance]:
	var alive: Array[ModelInstance] = []
	for model in models:
		if model.is_alive:
			alive.append(model)
	return alive


## Gets the count of alive models.
func get_alive_count() -> int:
	var count = 0
	for model in models:
		if model.is_alive:
			count += 1
	return count


## Checks if all models are dead.
func is_destroyed() -> bool:
	return get_alive_count() == 0


## Gets models that have a specific property.
func get_models_with_property(key: String) -> Array[ModelInstance]:
	var result: Array[ModelInstance] = []
	for model in models:
		if model.has_property(key):
			result.append(model)
	return result


## Gets models that carry specific equipment.
func get_models_with_equipment(equipment_name: String) -> Array[ModelInstance]:
	var result: Array[ModelInstance] = []
	for model in models:
		if equipment_name in model.get_equipment():
			result.append(model)
	return result


## Gets models that have a specific special rule.
func get_models_with_rule(rule: String) -> Array[ModelInstance]:
	var result: Array[ModelInstance] = []
	for model in models:
		if model.has_special_rule(rule):
			result.append(model)
	return result


## Gets models with a specific marker.
func get_models_with_marker(marker_name: String) -> Array[ModelInstance]:
	var result: Array[ModelInstance] = []
	for model in models:
		if model.has_marker(marker_name):
			result.append(model)
	return result


# ===== Unit-Level Properties Access =====

## Gets the unit name.
func get_name() -> String:
	var custom_name = unit_properties.get("custom_name", "")
	if not custom_name.is_empty():
		return custom_name
	return unit_properties.get("name", "Unknown Unit")


## Gets the unit size (number of models).
func get_size() -> int:
	return unit_properties.get("size", models.size())


## Gets the quality value (for OPR).
func get_quality() -> int:
	return unit_properties.get("quality", 0)


## Gets the defense value (for OPR).
func get_defense() -> int:
	return unit_properties.get("defense", 0)


## Gets the point cost.
func get_cost() -> int:
	return unit_properties.get("cost", 0)


## Gets all special rules for this unit.
func get_special_rules() -> Array:
	return unit_properties.get("special_rules", [])


## Checks if this unit has a specific special rule.
func has_special_rule(rule: String) -> bool:
	var rules = get_special_rules()
	for r in rules:
		if r is String and r.begins_with(rule):
			return true
		elif r is Dictionary and r.get("name", "").begins_with(rule):
			return true
	return false


## Checks if this unit is a hero.
func is_hero() -> bool:
	return has_special_rule("Hero")


# ===== Hero Attachment =====

## Gets heroes attached to this unit.
func get_attached_heroes() -> Array:
	return unit_properties.get("attached_heroes", [])


## Gets the unit this hero is attached to.
func get_attached_to() -> Variant:
	return unit_properties.get("attached_to", null)


## Checks if this unit has attached heroes.
func has_attached_heroes() -> bool:
	return not get_attached_heroes().is_empty()


## Checks if this hero is attached to another unit.
func is_attached() -> bool:
	return get_attached_to() != null


# ===== Activation =====

## Activates this unit for the current round.
func activate(round_number: int) -> void:
	is_activated = true
	activation_round = round_number

	# Attached heroes activate together
	for hero in get_attached_heroes():
		if hero is GameUnit:
			hero.is_activated = true
			hero.activation_round = round_number


## Resets activation state for a new round.
func reset_activation() -> void:
	is_activated = false


# ===== Markers (Unit-Level) =====

## Adds a marker to all models.
func add_marker_to_all(marker_name: String) -> void:
	for model in models:
		model.add_marker(marker_name)


## Removes a marker from all models.
func remove_marker_from_all(marker_name: String) -> void:
	for model in models:
		model.remove_marker(marker_name)


## Clears all markers from all models.
func clear_all_markers() -> void:
	for model in models:
		model.clear_markers()


# ===== Serialization =====

## Returns a dictionary representation for saving.
func to_dict() -> Dictionary:
	var data = {
		"unit_id": unit_id,
		"source_type": source_type,
		"unit_properties": unit_properties.duplicate(true),
		"is_activated": is_activated,
		"activation_round": activation_round,
		"models": []
	}

	for model in models:
		data.models.append(model.to_dict())

	return data


## Creates a GameUnit from a dictionary (for loading).
## Note: source_data and node references must be restored separately.
static func from_dict(data: Dictionary) -> GameUnit:
	var unit = GameUnit.new()
	unit.unit_id = data.get("unit_id", "")
	unit.source_type = data.get("source_type", "generic")
	unit.unit_properties = data.get("unit_properties", {}).duplicate(true)
	unit.is_activated = data.get("is_activated", false)
	unit.activation_round = data.get("activation_round", 0)

	var saved_models = data.get("models", [])
	for model_data in saved_models:
		var model = ModelInstance.from_dict(model_data)
		model.unit = unit
		unit.models.append(model)

	return unit


## Generates a unique ID for this unit.
static func generate_unit_id() -> String:
	return str(Time.get_unix_time_from_system()) + "_" + str(randi())
