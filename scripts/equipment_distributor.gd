class_name EquipmentDistributor
extends RefCounted
## Distributes equipment from API data to ModelInstances.
## Uses only the API data structure - no hardcoded roles or equipment names.

# ===== Main Distribution Method =====

## Distributes loadout and special rules to all models in a GameUnit.
## @param game_unit: The GameUnit to populate
## @param loadout: Array of weapon/equipment items from API
## @param special_rules: Array of special rules from API (can be strings or dicts)
static func distribute(game_unit: GameUnit, loadout: Array, special_rules: Array) -> void:
	var unit_size = game_unit.models.size()
	if unit_size == 0:
		return

	# Step 1: Parse Tough(X) and set wounds for ALL models
	var wounds = _parse_tough_rating(special_rules)
	if wounds > 1:
		print("EquipmentDistributor: Found Tough(%d) for unit with %d models" % [wounds, unit_size])
	for model in game_unit.models:
		model.wounds_max = wounds
		model.wounds_current = wounds
		model.properties["tough"] = wounds

	# Step 2: Copy special rules to ALL models
	# API gives unit-wide rules, not model-specific
	var rule_strings = _normalize_rules(special_rules)
	for model in game_unit.models:
		model.properties["special_rules"] = rule_strings.duplicate()

	# Step 3: Distribute weapons.
	# - Universal weapons (carried by every model) go to ALL models.
	# - Limited weapons (a subset of models) fill DISTINCT models via a sequential
	#   cursor instead of all stacking on model 0. So a special weapon (e.g. a
	#   Flamer, count 1) lands on the model the base weapon's reduced count never
	#   reached - i.e. it REPLACES the base on that model. An additional weapon on
	#   a full-count base (count == unit_size) still stacks on top (an add-on).
	var universal_weapons: Array = []
	var limited_weapons: Array = []
	for item in loadout:
		if _get_attacks(item) > 0:
			if _get_count(item, unit_size) >= unit_size:
				universal_weapons.append(item)
			else:
				limited_weapons.append(item)
		else:
			# Equipment (attacks = 0)
			_assign_equipment_to_model(game_unit, item)

	for item in universal_weapons:
		for model in game_unit.models:
			_add_weapon_to_model(model, item)

	var cursor := 0
	for item in limited_weapons:
		var count = _get_count(item, unit_size)
		for _k in range(count):
			if cursor >= unit_size:
				cursor = 0  # safety wrap if limited counts exceed the unit size
			_add_weapon_to_model(game_unit.models[cursor], item)
			cursor += 1


# ===== Tough Parsing =====

## Parses Tough(X) from special rules array.
## Returns the wound count, or 1 if no Tough rule found.
static func _parse_tough_rating(rules: Array) -> int:
	for rule in rules:
		var name = ""
		var rating = 0

		if rule is String:
			name = rule
			# Parse "Tough(3)" format
			if name.begins_with("Tough(") and name.ends_with(")"):
				var rating_str = name.substr(6, name.length() - 7)
				rating = rating_str.to_int()
				if rating > 0:
					return rating
		elif rule is Dictionary:
			name = rule.get("name", "")
			rating = rule.get("rating", 0)
			if name == "Tough" and rating > 0:
				return rating

	return 1  # Default: 1 wound


## Converts special rules to a normalized string array.
static func _normalize_rules(rules: Array) -> Array:
	var result: Array = []
	for rule in rules:
		if rule is String:
			result.append(rule)
		elif rule is Dictionary:
			var name = rule.get("name", "")
			var rating = rule.get("rating", 0)
			if rating > 0:
				result.append("%s(%d)" % [name, rating])
			else:
				result.append(name)
	return result


# ===== Weapon/Equipment Access =====

## Gets the attacks value from a loadout item.
static func _get_attacks(item: Variant) -> int:
	if item is Dictionary:
		return item.get("attacks", 0)
	elif item.has_method("get") or "attacks" in item:
		return item.attacks if "attacks" in item else 0
	return 0


## Gets the count value from a loadout item.
## Returns unit_size if count is not specified (all models have it).
static func _get_count(item: Variant, unit_size: int) -> int:
	var count = 0
	if item is Dictionary:
		count = item.get("count", 0)
	elif "count" in item:
		count = item.count

	# If count is 0 or not specified, assume all models have it
	return count if count > 0 else unit_size


## Gets the name from a loadout item.
static func _get_name(item: Variant) -> String:
	if item is Dictionary:
		return item.get("name", "Unknown")
	elif "name" in item:
		return item.name
	return "Unknown"


# ===== Assignment Methods =====

## Adds a weapon to a model's weapons list.
static func _add_weapon_to_model(model: ModelInstance, weapon: Variant) -> void:
	var weapons = model.properties.get("weapons", [])
	weapons.append(weapon)
	model.properties["weapons"] = weapons


## Assigns equipment (non-weapon) to the first available model.
## Equipment without count is assigned to one model only.
static func _assign_equipment_to_model(game_unit: GameUnit, item: Variant) -> void:
	var equipment_name = _get_name(item)

	# Try to find a model without special equipment yet
	for model in game_unit.models:
		var equip = model.properties.get("equipment", [])
		if equip.is_empty():
			equip.append(equipment_name)
			model.properties["equipment"] = equip
			return

	# Fallback: assign to first model
	if game_unit.models.size() > 0:
		var equip = game_unit.models[0].properties.get("equipment", [])
		equip.append(equipment_name)
		game_unit.models[0].properties["equipment"] = equip


# ===== Hero Attachment =====

## Attaches a hero to a target unit.
static func attach_hero_to_unit(hero: GameUnit, target: GameUnit) -> void:
	# Hero remembers target
	hero.unit_properties["attached_to"] = target

	# Target remembers hero
	var heroes = target.unit_properties.get("attached_heroes", [])
	if hero not in heroes:
		heroes.append(hero)
	target.unit_properties["attached_heroes"] = heroes


## Detaches a hero from its current unit.
static func detach_hero(hero: GameUnit) -> void:
	var target = hero.unit_properties.get("attached_to", null)
	if target and target is GameUnit:
		var heroes = target.unit_properties.get("attached_heroes", [])
		heroes.erase(hero)
		target.unit_properties["attached_heroes"] = heroes
	hero.unit_properties["attached_to"] = null


# ===== Factory Method =====

## Creates a GameUnit with ModelInstances from an OPRUnit object.
## @param opr_unit: OPRApiClient.OPRUnit object
## @param nodes: Array of Node3D for the spawned models
## @param player_id: Player ID for this unit
## @returns: Configured GameUnit
static func create_from_opr_unit(opr_unit: Variant, nodes: Array[Node3D], player_id: int = 1) -> GameUnit:
	var game_unit = GameUnit.new()
	game_unit.source_data = opr_unit
	game_unit.source_type = "opr"
	game_unit.unit_id = GameUnit.generate_unit_id()

	# Extract unit-level properties from OPRUnit
	game_unit.unit_properties = {
		"name": opr_unit.name,
		"custom_name": opr_unit.custom_name,
		"size": opr_unit.size,
		"quality": opr_unit.quality,
		"defense": opr_unit.defense,
		"cost": opr_unit.cost,
		"special_rules": opr_unit.special_rules.duplicate(),
		"base_size_round": opr_unit.base_size_round,
		"base_is_oval": opr_unit.base_is_oval,
		"base_width_mm": opr_unit.base_width_mm,
		"base_depth_mm": opr_unit.base_depth_mm,
		"player_id": player_id,
		"attached_heroes": [],
		"attached_to": null,
	}

	# Create ModelInstances for each node
	for i in range(nodes.size()):
		var model = ModelInstance.new()
		model.unit = game_unit
		model.node = nodes[i]
		model.model_index = i
		game_unit.models.append(model)

		# Set metadata on the node
		nodes[i].set_meta("model_instance", model)
		nodes[i].set_meta("game_unit", game_unit)
		nodes[i].set_meta("model_index", i)

	# Convert OPRWeapons to loadout dictionaries for distribution
	var loadout: Array = []
	for weapon in opr_unit.weapons:
		loadout.append({
			"name": weapon.name,
			"range": weapon.range_value,
			"attacks": weapon.attacks,
			"count": weapon.count,
			"specialRules": weapon.special_rules.duplicate()
		})

	# Add equipment items (attacks = 0)
	for equipment_name in opr_unit.equipment:
		loadout.append({
			"name": equipment_name,
			"attacks": 0,
			"count": 1
		})

	# Distribute equipment using the loadout
	distribute(game_unit, loadout, opr_unit.special_rules)

	# Initialize caster points if unit has Caster rule
	game_unit.initialize_caster_points()

	return game_unit


## Creates a GameUnit with ModelInstances from OPR API data.
## @param api_unit: Dictionary with unit data from API
## @param nodes: Array of Node3D for the spawned models
## @returns: Configured GameUnit
static func create_from_opr_api(api_unit: Dictionary, nodes: Array[Node3D]) -> GameUnit:
	var game_unit = GameUnit.new()
	game_unit.source_type = "opr"
	game_unit.unit_id = GameUnit.generate_unit_id()

	# Extract unit-level properties
	game_unit.unit_properties = {
		"name": api_unit.get("name", "Unknown"),
		"custom_name": api_unit.get("customName", ""),
		"size": api_unit.get("size", nodes.size()),
		"quality": api_unit.get("quality", 4),
		"defense": api_unit.get("defense", 4),
		"cost": api_unit.get("cost", 0),
		"special_rules": api_unit.get("specialRules", []),
		"bases": api_unit.get("bases", {}),
		"attached_heroes": [],
		"attached_to": null,
	}

	# Create ModelInstances for each node
	for i in range(nodes.size()):
		var model = ModelInstance.new()
		model.unit = game_unit
		model.node = nodes[i]
		model.model_index = i
		game_unit.models.append(model)

		# Set metadata on the node
		nodes[i].set_meta("model_instance", model)
		nodes[i].set_meta("game_unit", game_unit)
		nodes[i].set_meta("model_index", i)

	# Distribute equipment from loadout
	var loadout = api_unit.get("loadout", [])
	var special_rules = api_unit.get("specialRules", [])
	distribute(game_unit, loadout, special_rules)

	# Initialize caster points if unit has Caster rule
	game_unit.initialize_caster_points()

	return game_unit
