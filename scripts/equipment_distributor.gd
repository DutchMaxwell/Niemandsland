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

	# Step 1: Set the BASE Tough(X) wounds shared by the whole squad.
	# OPR Core Rules — Tough(X): "models with this rule are only killed once they have
	# taken X or more wounds." Tough is a PER-MODEL stat, not a unit-wide one. The unit's
	# special_rules carry the squad's base value; an upgraded model (weapon-team / special
	# weapon / joined model) overrides this with its own elevated Tough in Step 3b. Without
	# that split, a single upgraded model's Tough would wrongly buff every base model.
	var base_wounds = _parse_tough_rating(special_rules)
	for model in game_unit.models:
		model.wounds_max = base_wounds
		model.wounds_current = base_wounds
		model.properties["tough"] = base_wounds

	# Step 2: Copy special rules to ALL models
	# API gives unit-wide rules, not model-specific
	var rule_strings = _normalize_rules(special_rules)
	for model in game_unit.models:
		model.properties["special_rules"] = rule_strings.duplicate()

	# Step 3: Distribute weapons AND tools/equipment by count.
	# - Universal entries (count >= unit_size) go on ALL models.
	# - Limited entries (count < unit_size) fill DISTINCT models via a sequential
	#   cursor instead of all stacking on model 0. So a special weapon (e.g. a Flamer,
	#   count 1) lands on the model the base weapon's reduced count never reached -
	#   i.e. it REPLACES the base there; an add-on on a full-count base still stacks.
	#   A subset tool (e.g. a 1-of-10 "Synaptic Relay") lands on one model the same way.
	# Weapons go to the model's weapon list, non-weapon items (attacks == 0) to its
	# equipment list, so the base ring can label per-model specials.
	var universal: Array = []
	var limited: Array = []
	for item in loadout:
		if _get_count(item, unit_size) >= unit_size:
			universal.append(item)
		else:
			limited.append(item)

	for item in universal:
		for model in game_unit.models:
			_add_loadout_item_to_model(model, item)
			_apply_item_tough_to_model(model, item)

	var cursor := 0
	for item in limited:
		var count = _get_count(item, unit_size)
		for _k in range(count):
			if cursor >= unit_size:
				cursor = 0  # safety wrap if limited counts exceed the unit size
			_add_loadout_item_to_model(game_unit.models[cursor], item)
			_apply_item_tough_to_model(game_unit.models[cursor], item)
			cursor += 1


# ===== Tough Parsing =====

## Minimum wound count: every model takes at least 1 wound to be killed (OPR core).
const BASE_WOUNDS: int = 1

## Applies a per-model elevated Tough(X) to ONE model when its OWN loadout item
## (a weapon-team / special weapon / joined-model upgrade) grants a higher Tough than
## the squad's base. OPR Core Rules — Tough(X) is a per-model stat, so an upgraded
## model's extra wounds must NOT spill onto the base squad models. Never lowers a model
## below its current (base) value; only the carrier of the item is elevated.
static func _apply_item_tough_to_model(model: ModelInstance, item: Variant) -> void:
	var item_tough: int = _parse_tough_rating(_item_special_rules(item))
	if item_tough <= model.wounds_max:
		return
	model.wounds_max = item_tough
	model.wounds_current = item_tough
	model.properties["tough"] = item_tough


## Reads a loadout item's own special-rule list (e.g. a weapon's "specialRules" array).
## Returns an empty array when the item carries none.
static func _item_special_rules(item: Variant) -> Array:
	if item is Dictionary:
		var rules: Variant = item.get("specialRules", [])
		return rules if rules is Array else []
	if "specialRules" in item:
		var rules: Variant = item.specialRules
		return rules if rules is Array else []
	return []


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

	return BASE_WOUNDS  # Default: every model takes at least 1 wound to be killed


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


## Routes a loadout entry to the right per-model list: weapons (attacks > 0) to the
## model's weapon list, everything else (tools/equipment) to its equipment list.
static func _add_loadout_item_to_model(model: ModelInstance, item: Variant) -> void:
	if _get_attacks(item) > 0:
		_add_weapon_to_model(model, item)
	else:
		_add_equipment_to_model(model, _get_name(item))


## Adds an equipment/tool name to a model's equipment list (deduped per model).
static func _add_equipment_to_model(model: ModelInstance, equipment_name: String) -> void:
	if equipment_name.is_empty():
		return
	var equip = model.properties.get("equipment", [])
	if equipment_name not in equip:
		equip.append(equipment_name)
	model.properties["equipment"] = equip


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

	# Add per-model tool/equipment upgrades (non-weapon items on a subset of models).
	# They flow through the same count-based distribution as weapons, so each lands on
	# specific model(s) and the base ring can label it. The item's granted "rules" ride
	# along as specialRules so a per-model Tough(X) is applied to its carrier model only.
	for equip_item in opr_unit.equipment_items:
		loadout.append({
			"name": equip_item.get("name", ""),
			"attacks": 0,
			"count": equip_item.get("count", 1),
			"specialRules": equip_item.get("rules", [])
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
