class_name UnitUtils
extends RefCounted
## Static utility class for unit detection and queries.
## Provides a unified interface to check object types and retrieve unit data.

# ===== Unit Type Enum =====

enum UnitType {
	NONE,           # Not a unit (terrain, dice, etc.)
	GAME_UNIT,      # OPR/WGS unit with full stats
	PROXY_UNIT,     # Miniature assigned as proxy for a unit
	GENERIC_UNIT    # Generic miniature without stats
}


# ===== Unit Detection =====

## Checks if an object is any kind of unit.
static func is_unit(obj: Node3D) -> bool:
	if not obj:
		return false
	return obj.is_in_group("unit") or \
		   obj.is_in_group("opr_unit") or \
		   obj.is_in_group("wgs_unit")


## Returns the UnitType for an object.
static func get_unit_type(obj: Node3D) -> UnitType:
	if not obj:
		return UnitType.NONE
	if obj.is_in_group("opr_unit") or obj.is_in_group("wgs_unit"):
		return UnitType.GAME_UNIT
	if obj.has_meta("proxy_unit"):
		return UnitType.PROXY_UNIT
	if obj.is_in_group("miniature"):
		return UnitType.GENERIC_UNIT
	return UnitType.NONE


## Checks if an object is terrain.
static func is_terrain(obj: Node3D) -> bool:
	if not obj:
		return false
	return obj.is_in_group("terrain") or \
		   obj.is_in_group("terrain_piece")


## Checks if an object is a dice.
static func is_dice(obj: Node3D) -> bool:
	if not obj:
		return false
	return obj.is_in_group("dice")


# ===== GameUnit Access =====

## Gets the GameUnit for a model node.
static func get_game_unit(obj: Node3D) -> GameUnit:
	if not obj:
		return null
	return obj.get_meta("game_unit", null)


## Gets the ModelInstance for a model node.
static func get_model_instance(obj: Node3D) -> ModelInstance:
	if not obj:
		return null
	return obj.get_meta("model_instance", null)


## Gets the model index within a unit.
static func get_model_index(obj: Node3D) -> int:
	if not obj:
		return -1
	return obj.get_meta("model_index", -1)


# ===== Legacy OPR Access =====

## Gets the OPRUnit for a model (legacy compatibility).
static func get_opr_unit(obj: Node3D) -> Variant:
	if not obj:
		return null
	return obj.get_meta("opr_unit", null)


## Gets the player ID for a unit model.
static func get_player_id(obj: Node3D) -> int:
	if not obj:
		return 0
	# Try GameUnit first
	var game_unit = get_game_unit(obj)
	if game_unit:
		return game_unit.unit_properties.get("player_id", 0)
	# Fallback to legacy meta
	return obj.get_meta("opr_player_id", obj.get_meta("player_id", 0))


# ===== Unit Model Queries =====

## Gets all model nodes for a unit (from any model in the unit).
static func get_all_unit_models(obj: Node3D) -> Array[Node3D]:
	var result: Array[Node3D] = []
	var game_unit = get_game_unit(obj)
	if not game_unit:
		if is_unit(obj):
			result.append(obj)
		return result

	for model in game_unit.models:
		if model.node and is_instance_valid(model.node):
			result.append(model.node)
	return result


## Gets all alive model nodes for a unit.
static func get_alive_unit_models(obj: Node3D) -> Array[Node3D]:
	var result: Array[Node3D] = []
	var game_unit = get_game_unit(obj)
	if not game_unit:
		return result

	for model in game_unit.get_alive_models():
		if model.node and is_instance_valid(model.node):
			result.append(model.node)
	return result


## Checks if a selection contains models from the same unit.
static func is_same_unit(objects: Array) -> bool:
	if objects.is_empty():
		return false

	var first_unit = get_game_unit(objects[0])
	if not first_unit:
		return false

	for obj in objects:
		var unit = get_game_unit(obj)
		if unit != first_unit:
			return false
	return true


## Checks if all models of a unit are selected.
static func is_entire_unit_selected(selected: Array, any_model: Node3D) -> bool:
	var game_unit = get_game_unit(any_model)
	if not game_unit:
		return false

	var all_models = get_all_unit_models(any_model)
	if all_models.size() != selected.size():
		return false

	for model in all_models:
		if model not in selected:
			return false
	return true


# ===== Unit Display Info =====

## Gets a display name for a unit.
static func get_unit_display_name(obj: Node3D) -> String:
	var game_unit = get_game_unit(obj)
	if game_unit:
		var name = game_unit.get_name()
		var suffix = game_unit.unit_properties.get("display_suffix", "")
		var size = game_unit.get_size()
		if size > 1:
			return "%s%s [%d]" % [name, suffix, size]
		return name + suffix

	# Fallback to OPR unit
	var opr_unit = get_opr_unit(obj)
	if opr_unit:
		return opr_unit.get_display_name()

	return obj.name


## Gets a display name for a model.
static func get_model_display_name(obj: Node3D) -> String:
	var model_instance = get_model_instance(obj)
	if model_instance:
		return model_instance.get_display_name()

	var index = get_model_index(obj)
	if index >= 0:
		return "Model %d" % (index + 1)

	return obj.name


## Gets unit stats as formatted text.
static func get_unit_stats_text(obj: Node3D) -> String:
	var game_unit = get_game_unit(obj)
	if game_unit:
		var lines: Array[String] = []
		lines.append("[b]%s[/b]" % get_unit_display_name(obj))

		var q = game_unit.get_quality()
		var d = game_unit.get_defense()
		if q > 0 and d > 0:
			lines.append("Q%d+ | D%d+" % [q, d])

		var alive = game_unit.get_alive_count()
		var total = game_unit.models.size()
		var cost = game_unit.get_cost()
		lines.append("%d/%d models | %d pts" % [alive, total, cost])

		var rules = game_unit.get_special_rules()
		if not rules.is_empty():
			lines.append("")
			lines.append("[u]Special:[/u]")
			var rule_strings: Array[String] = []
			for rule in rules:
				if rule is String:
					rule_strings.append(rule)
				elif rule is Dictionary:
					var name = rule.get("name", "")
					var rating = rule.get("rating", 0)
					if rating > 0:
						rule_strings.append("%s(%d)" % [name, rating])
					else:
						rule_strings.append(name)
			lines.append(", ".join(rule_strings))

		if game_unit.is_activated:
			lines.append("")
			lines.append("[color=gray]Activated (Round %d)[/color]" % game_unit.activation_round)

		return "\n".join(lines)

	# Fallback to OPR unit
	var opr_unit = get_opr_unit(obj)
	if opr_unit and opr_unit.has_method("get_stats_text"):
		return opr_unit.get_stats_text()

	return "No stats available"


# ===== Selection Helpers =====

## Expands selection to include all models of selected units.
static func expand_to_full_units(selected: Array) -> Array[Node3D]:
	var result: Array[Node3D] = []
	var processed_units: Array = []

	for obj in selected:
		if not obj is Node3D:
			continue

		var game_unit = get_game_unit(obj)
		if game_unit and game_unit not in processed_units:
			processed_units.append(game_unit)
			for model in game_unit.models:
				if model.node and is_instance_valid(model.node):
					if model.node not in result:
						result.append(model.node)
		elif not game_unit and obj not in result:
			result.append(obj)

	return result


## Gets unique GameUnits from a selection.
static func get_unique_units(selected: Array) -> Array[GameUnit]:
	var result: Array[GameUnit] = []

	for obj in selected:
		if not obj is Node3D:
			continue

		var game_unit = get_game_unit(obj)
		if game_unit and game_unit not in result:
			result.append(game_unit)

	return result
