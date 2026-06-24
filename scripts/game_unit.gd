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

# ===== Status Tokens =====

## Whether this unit is fatigued (unit-wide status)
var is_fatigued: bool = false

## Whether this unit is shaken (unit-wide status)
var is_shaken: bool = false

# ===== Caster Points =====

## Maximum caster points cap (OPR rule)
const CASTER_POINTS_CAP: int = 6

## Current available caster points
var casts_current: int = 0

## Points granted per round from Caster(X)
var casts_per_round: int = 0


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


## Gets all alive models of this unit PLUS those of any joined Heroes.
## Used where a joined Hero should be treated as part of the unit (boundary,
## unit card). Returns just get_alive_models() for units with no attached heroes.
func get_alive_models_with_attached() -> Array[ModelInstance]:
	var result: Array[ModelInstance] = get_alive_models()
	for hero in get_attached_heroes():
		if hero is GameUnit:
			result.append_array(hero.get_alive_models())
	return result


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


# ===== Special-Equipment Detection =====

## Extracts a weapon's display name from an OPRWeapon object or a Dictionary.
static func _weapon_name_of(weapon: Variant) -> String:
	if weapon is Dictionary:
		return str(weapon.get("name", ""))
	if weapon is Object and "name" in weapon:
		return str(weapon.name)
	return ""


## The distinct equipment/weapon names a model carries (weapons first, then
## equipment), de-duplicated and order-preserving.
func _model_loadout_names(model: ModelInstance) -> Array[String]:
	var names: Array[String] = []
	var seen: Dictionary = {}
	for weapon in model.get_weapons():
		var wname := _weapon_name_of(weapon)
		if not wname.is_empty() and not seen.has(wname):
			seen[wname] = true
			names.append(wname)
	for equip in model.get_equipment():
		var ename := str(equip)
		if not ename.is_empty() and not seen.has(ename):
			seen[ename] = true
			names.append(ename)
	return names


## Counts how many models carry each distinct weapon/equipment name.
func _loadout_carrier_counts() -> Dictionary:
	var carriers: Dictionary = {}
	for model in models:
		for item_name in _model_loadout_names(model):
			carriers[item_name] = carriers.get(item_name, 0) + 1
	return carriers


## Returns a model's SPECIAL loadout: weapons/equipment carried by only a strict
## MINORITY of the unit (carriers * 2 <= unit size). This flags genuine specials
## (a 1-of-10 Flamer, a Banner, a Sergeant's gear) while NOT flagging a base
## weapon whose count was merely reduced by a swap (e.g. 9-of-10). Order/dedup
## preserved (weapons first, then equipment). Single-model units return [].
func get_special_equipment_names(model: ModelInstance) -> Array[String]:
	var result: Array[String] = []
	var n := models.size()
	if n <= 1:
		return result

	var carriers := _loadout_carrier_counts()
	for item_name in _model_loadout_names(model):
		if carriers.get(item_name, 0) * 2 <= n:
			result.append(item_name)
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


## Resets unit status, wounds, markers and model visibility to import state.
## Used by Sort Table. Note: model positions/rotations are NOT changed here -
## the caller animates models back to their import positions (see
## ObjectManager.sort_table) so the movement can be watched on the table.
func reset_to_import_state() -> void:
	# Reset unit-level status
	is_activated = false
	is_fatigued = false
	is_shaken = false
	activation_round = 0

	# Reset caster points
	reset_caster_points()

	# Reset each model
	for model in models:
		# Reset wounds
		model.reset_wounds()

		# Clear markers
		model.clear_markers()

		# Revive hidden/removed models so they animate back into formation
		if model.node and is_instance_valid(model.node):
			model.node.visible = true
			model.node.set_meta("deleted", false)


# ===== Caster Points Methods =====

## Checks if this unit has the Caster special rule.
func is_caster() -> bool:
	return has_special_rule("Caster")


## Gets the Caster(X) value from special rules.
## Returns 0 if unit is not a caster.
func get_caster_value() -> int:
	var rules = get_special_rules()
	for r in rules:
		var rule_name = ""
		if r is String:
			rule_name = r
		elif r is Dictionary:
			rule_name = r.get("name", "")

		if rule_name.begins_with("Caster("):
			# Parse "Caster(3)" -> 3
			var start = rule_name.find("(") + 1
			var end = rule_name.find(")")
			if start > 0 and end > start:
				return int(rule_name.substr(start, end - start))
	return 0


## Initializes caster points based on Caster(X) rule.
## Should be called when unit is created or game starts.
func initialize_caster_points() -> void:
	casts_per_round = get_caster_value()
	if casts_per_round > 0:
		casts_current = casts_per_round


## Adds caster points for a new round (accumulates, capped at 6).
func add_round_caster_points() -> void:
	if casts_per_round > 0:
		casts_current = mini(casts_current + casts_per_round, CASTER_POINTS_CAP)


## Spends caster points. Returns true if successful, false if not enough points.
func spend_caster_points(amount: int) -> bool:
	if casts_current >= amount:
		casts_current -= amount
		return true
	return false


## Resets caster points to the per-round value (for game reset).
func reset_caster_points() -> void:
	casts_current = casts_per_round


## Sets caster points to a specific value (for manual adjustment).
func set_caster_points(value: int) -> void:
	casts_current = clampi(value, 0, CASTER_POINTS_CAP)


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


## Sets a counter marker's value on all models (keeps the unit-wide token in sync).
func set_marker_value_on_all(marker_name: String, value: int) -> void:
	for model in models:
		model.set_marker_value(marker_name, value)


## Gets a counter marker's value (read from the first model as representative).
func get_marker_value(marker_name: String) -> int:
	if models.is_empty():
		return 0
	return models[0].get_marker_value(marker_name)


# ===== Serialization =====

## Returns a dictionary representation for saving.
func to_dict() -> Dictionary:
	# attached_to / attached_heroes hold GameUnit refs, which are not JSON-
	# serializable. Store their unit_ids instead so attachment can be rebuilt
	# after load (see SaveManager._restore_hero_attachments_after_load).
	var props := unit_properties.duplicate(true)
	var attached_to = props.get("attached_to")
	props["attached_to"] = attached_to.unit_id if attached_to is GameUnit else ""
	var hero_ids: Array = []
	for hero in props.get("attached_heroes", []):
		if hero is GameUnit:
			hero_ids.append(hero.unit_id)
	props["attached_heroes"] = hero_ids

	var data = {
		"unit_id": unit_id,
		"source_type": source_type,
		"unit_properties": props,
		"is_activated": is_activated,
		"activation_round": activation_round,
		"is_fatigued": is_fatigued,
		"is_shaken": is_shaken,
		"casts_current": casts_current,
		"casts_per_round": casts_per_round,
		"models": []
	}

	# OPR units carry a derived OPRUnit profile in source_data (the full weapon / equipment / base
	# info the unit card shows). It is an object, not JSON-serializable, so serialize its display
	# fields — otherwise a peer's card falls back to model 0's basic weapons and loses the special
	# loadout (issue #73). Both the per-army broadcast and the join snapshot funnel through here.
	if source_type == "opr" and source_data is OPRApiClient.OPRUnit:
		data["source_data"] = (source_data as OPRApiClient.OPRUnit).to_dict()

	for model in models:
		data.models.append(model.to_dict())

	return data


## Creates a GameUnit from a dictionary (for loading).
## Note: source_data and node references must be restored separately.
static func from_dict(data: Dictionary) -> GameUnit:
	var unit = GameUnit.new()
	unit.unit_id = data.get("unit_id", "")
	unit.source_type = data.get("source_type", "generic")
	# Restore the OPR display profile so a synced/loaded unit's card shows the full loadout (#73);
	# absent for old saves / non-OPR units, in which case source_data stays null (card uses the
	# leaner per-model fallback, exactly as before).
	if unit.source_type == "opr" and data.get("source_data") is Dictionary:
		unit.source_data = OPRApiClient.OPRUnit.from_dict(data["source_data"])
	unit.unit_properties = data.get("unit_properties", {}).duplicate(true)
	unit.is_activated = data.get("is_activated", false)
	unit.activation_round = data.get("activation_round", 0)
	unit.is_fatigued = data.get("is_fatigued", false)
	unit.is_shaken = data.get("is_shaken", false)
	unit.casts_current = data.get("casts_current", 0)
	unit.casts_per_round = data.get("casts_per_round", 0)

	var saved_models = data.get("models", [])
	for model_data in saved_models:
		var model = ModelInstance.from_dict(model_data)
		model.unit = unit
		unit.models.append(model)

	# Initialize caster points for old saves that don't have them
	if unit.casts_per_round == 0 and unit.casts_current == 0:
		unit.initialize_caster_points()

	return unit


## Generates a unique ID for this unit.
static func generate_unit_id() -> String:
	return str(Time.get_unix_time_from_system()) + "_" + str(randi())
