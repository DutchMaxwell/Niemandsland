class_name AISpecialRules
extends RefCounted
## Handles special rule behaviors for AI units.
## Based on OPR Solo & Co-Op Rules v3.5.0.


## Checks if a unit should be kept in reserve (Ambush rule).
static func should_start_in_reserve(unit: GameUnit) -> bool:
	return unit.has_special_rule("Ambush")


## Checks if a unit should deploy after others (Scout rule).
static func should_deploy_last(unit: GameUnit) -> bool:
	return unit.has_special_rule("Scout")


## Checks if a unit should activate after others in its section (Counter rule).
static func should_activate_last_in_section(unit: GameUnit) -> bool:
	return unit.has_special_rule("Counter")


## Checks if a unit is a transport.
static func is_transport(unit: GameUnit) -> bool:
	return unit.has_special_rule("Transport")


## Gets the cargo capacity of a transport.
static func get_transport_capacity(unit: GameUnit) -> int:
	for model in unit.models:
		var rules = model.properties.get("special_rules", [])
		for rule in rules:
			var name = _get_rule_name(rule)
			var rating = _get_rule_rating(rule)
			if name == "Transport":
				return rating
	return 0


## Checks if unit ignores difficult terrain.
static func ignores_difficult_terrain(unit: GameUnit) -> bool:
	return unit.has_special_rule("Strider") or unit.has_special_rule("Flying")


## Checks if unit ignores dangerous terrain.
static func ignores_dangerous_terrain(unit: GameUnit) -> bool:
	return unit.has_special_rule("Flying")


## Checks if unit is an Aircraft.
static func is_aircraft(unit: GameUnit) -> bool:
	return unit.has_special_rule("Aircraft")


## Gets the fixed movement distance for Aircraft (always 30").
static func get_aircraft_move() -> float:
	return 30.0


## Checks if unit has Artillery (deploys on high ground, uses Hold+Shoot).
static func is_artillery(unit: GameUnit) -> bool:
	return unit.has_special_rule("Artillery")


## Checks if unit has Indirect weapons (Hold+Shoot when in range).
static func has_indirect(unit: GameUnit) -> bool:
	for model in unit.models:
		var weapons = model.get_weapons()
		for weapon in weapons:
			if _weapon_has_rule(weapon, "Indirect"):
				return true
	return false


## Checks if unit has Relentless (Hold+Shoot when in range).
static func has_relentless(unit: GameUnit) -> bool:
	return unit.has_special_rule("Relentless")


## Checks if unit is a Caster.
static func is_caster(unit: GameUnit) -> bool:
	# Check for Wizard, Caster, or Psychic rules
	return (unit.has_special_rule("Wizard") or
			unit.has_special_rule("Caster") or
			unit.has_special_rule("Psychic"))


## Gets the caster level for spell selection.
static func get_caster_level(unit: GameUnit) -> int:
	for model in unit.models:
		var rules = model.properties.get("special_rules", [])
		for rule in rules:
			var name = _get_rule_name(rule)
			var rating = _get_rule_rating(rule)
			if name in ["Wizard", "Caster", "Psychic"]:
				return rating
	return 0


## Selects a random spell for a caster unit.
## Returns spell index (D3 + caster level), or -1 if no valid spell.
static func select_spell(unit: GameUnit, available_spells: int) -> int:
	var caster_level = get_caster_level(unit)
	if caster_level == 0:
		return -1

	# Roll D3 + caster level
	var roll = (randi() % 3) + 1 + caster_level
	var spell_index = roll - 1  # Convert to 0-based

	# Wrap around if out of range
	if spell_index >= available_spells:
		spell_index = spell_index % available_spells

	return spell_index


## Modifies target priority based on weapon special rules.
## Returns a dictionary of priority modifiers.
static func get_target_priority_modifiers(unit: GameUnit, target: GameUnit) -> Dictionary:
	var modifiers = {
		"priority_bonus": 0.0,
		"should_target": true,
		"reason": ""
	}

	for model in unit.models:
		var weapons = model.get_weapons()
		for weapon in weapons:
			# AP - target high defense
			if _weapon_has_rule(weapon, "AP"):
				var ap = _get_weapon_rule_rating(weapon, "AP")
				if target.get_defense() >= 4:
					modifiers.priority_bonus += ap * 0.5
					modifiers.reason = "AP vs high defense"

			# Deadly - target Tough units (single model first, then lowest remaining)
			if _weapon_has_rule(weapon, "Deadly"):
				if target.get_size() == 1 and target.has_special_rule("Tough"):
					modifiers.priority_bonus += 10.0
					modifiers.reason = "Deadly vs single Tough model"
				elif target.has_special_rule("Tough"):
					modifiers.priority_bonus += 5.0
					modifiers.reason = "Deadly vs Tough unit"

			# Takedown - target heroes first
			if _weapon_has_rule(weapon, "Takedown"):
				if target.is_hero():
					modifiers.priority_bonus += 15.0
					modifiers.reason = "Takedown vs Hero"

			# Unstoppable - target Aircraft first
			if _weapon_has_rule(weapon, "Unstoppable"):
				if is_aircraft(target):
					modifiers.priority_bonus += 20.0
					modifiers.reason = "Unstoppable vs Aircraft"

	return modifiers


## Checks if AI should use army special rules.
## "AI units must always use army special rules as soon as activated"
static func should_use_army_ability(_unit: GameUnit) -> bool:
	# AI always uses abilities when activated
	return true


## Gets deployment priority for Artillery units.
## "Artillery must deploy in highest position with most LOS"
static func get_artillery_deployment_priority() -> Dictionary:
	return {
		"prefer_high_ground": true,
		"prefer_max_los": true,
		"ignore_objective_distance": true
	}


# ===== Movement Behavior Modifiers =====

## Gets movement behavior for cover terrain.
## "AI units must always move into or behind cover terrain"
static func should_seek_cover(unit: GameUnit, is_moving_to_objective: bool) -> bool:
	var unit_type = AIUnitClassifier.classify(unit)

	# All unit types seek cover
	# But not if the cover is also difficult terrain AND moving to objective
	if is_moving_to_objective:
		return false  # Objectives take priority

	return true


## Checks if unit should stay in cover instead of moving.
## "Shooting and Hybrid must stay in cover and shoot instead of moving away"
static func should_stay_in_cover(
	unit: GameUnit,
	is_in_cover: bool,
	is_moving_to_objective: bool
) -> bool:
	if not is_in_cover:
		return false

	if is_moving_to_objective:
		return false

	var unit_type = AIUnitClassifier.classify(unit)
	return unit_type != AIUnitClassifier.UnitType.MELEE


# ===== Strike Back Behavior =====

## "AI units must always strike back whenever they are charged"
static func should_strike_back(_unit: GameUnit) -> bool:
	return true


# ===== Helper Methods =====

static func _get_rule_name(rule: Variant) -> String:
	if rule is String:
		var paren = rule.find("(")
		if paren > 0:
			return rule.substr(0, paren)
		return rule
	elif rule is Dictionary:
		return rule.get("name", "")
	return ""


static func _get_rule_rating(rule: Variant) -> int:
	if rule is String:
		var paren_start = rule.find("(")
		var paren_end = rule.find(")")
		if paren_start > 0 and paren_end > paren_start:
			var rating_str = rule.substr(paren_start + 1, paren_end - paren_start - 1)
			return rating_str.to_int()
	elif rule is Dictionary:
		return rule.get("rating", 0)
	return 0


static func _weapon_has_rule(weapon: Variant, rule_name: String) -> bool:
	if not weapon is Dictionary:
		return false

	var special_rules = weapon.get("specialRules", [])
	for rule in special_rules:
		if _get_rule_name(rule) == rule_name:
			return true
	return false


static func _get_weapon_rule_rating(weapon: Variant, rule_name: String) -> int:
	if not weapon is Dictionary:
		return 0

	var special_rules = weapon.get("specialRules", [])
	for rule in special_rules:
		if _get_rule_name(rule) == rule_name:
			return _get_rule_rating(rule)
	return 0


# ===== AI Deployment Special Cases =====

## Handles Ambush deployment at start of round 2.
class AmbushHandler:
	static func get_units_to_deploy(ai_units: Array[GameUnit]) -> Array[GameUnit]:
		var result: Array[GameUnit] = []
		for unit in ai_units:
			if unit.has_special_rule("Ambush"):
				if unit.unit_properties.get("in_reserve", false):
					result.append(unit)
		return result


## Handles Scout deployment after all other units.
class ScoutHandler:
	static func get_units_to_deploy_last(ai_units: Array[GameUnit]) -> Array[GameUnit]:
		var result: Array[GameUnit] = []
		for unit in ai_units:
			if unit.has_special_rule("Scout"):
				result.append(unit)
		return result


## Handles Transport setup (random cargo assignment).
class TransportHandler:
	## Assigns random units to transports, filling capacity.
	static func assign_cargo(
		transports: Array[GameUnit],
		infantry: Array[GameUnit]
	) -> Dictionary:
		var assignments = {}  # transport_id -> [unit_ids]

		var available_infantry = infantry.duplicate()
		available_infantry.shuffle()

		for transport in transports:
			var capacity = AISpecialRules.get_transport_capacity(transport)
			var cargo: Array[GameUnit] = []
			var current_size = 0

			while not available_infantry.is_empty() and current_size < capacity:
				var unit = available_infantry.pop_front()
				var unit_size = unit.get_size()

				if current_size + unit_size <= capacity:
					cargo.append(unit)
					current_size += unit_size

			assignments[transport.unit_id] = cargo

		return assignments


	## Marks units as embarked in transport.
	static func embark_units(transport: GameUnit, cargo: Array[GameUnit]) -> void:
		for unit in cargo:
			unit.unit_properties["embarked_in"] = transport.unit_id
			unit.unit_properties["in_reserve"] = true

		transport.unit_properties["cargo"] = cargo.map(func(u): return u.unit_id)


	## Disembarks units from transport (round 1 activation).
	static func disembark_units(transport: GameUnit, all_units: Array[GameUnit]) -> Array[GameUnit]:
		var cargo_ids = transport.unit_properties.get("cargo", [])
		var disembarked: Array[GameUnit] = []

		for unit in all_units:
			if unit.unit_id in cargo_ids:
				unit.unit_properties["embarked_in"] = null
				unit.unit_properties["in_reserve"] = false
				disembarked.append(unit)

		transport.unit_properties["cargo"] = []

		return disembarked
