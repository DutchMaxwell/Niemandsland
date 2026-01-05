class_name AIUnitClassifier
extends RefCounted
## Classifies units into AI behavior types based on their weapons.
## From OPR Solo & Co-Op Rules v3.5.0:
## - Hybrid: Melee weapons better than ranged
## - Shooting: Ranged weapons better than melee
## - Melee: No ranged weapons

enum UnitType {
	HYBRID,
	SHOOTING,
	MELEE
}


## Classifies a GameUnit based on its weapons.
## Returns UnitType.HYBRID, UnitType.SHOOTING, or UnitType.MELEE
static func classify(game_unit: GameUnit) -> UnitType:
	var best_melee_score = 0.0
	var best_ranged_score = 0.0

	# Check all models in the unit for weapons
	for model in game_unit.models:
		var weapons = model.get_weapons()
		for weapon in weapons:
			var score = _calculate_weapon_score(weapon)
			var range_val = _get_range(weapon)

			if range_val == 0:
				# Melee weapon
				best_melee_score = max(best_melee_score, score)
			else:
				# Ranged weapon
				best_ranged_score = max(best_ranged_score, score)

	# Classification logic per OPR rules
	if best_ranged_score == 0:
		# No ranged weapons = Melee unit
		return UnitType.MELEE
	elif best_melee_score > best_ranged_score:
		# Melee weapons better = Hybrid unit
		return UnitType.HYBRID
	else:
		# Ranged weapons better or equal = Shooting unit
		return UnitType.SHOOTING


## Calculates a score for a weapon to compare effectiveness.
## Higher score = more effective weapon.
static func _calculate_weapon_score(weapon: Variant) -> float:
	var attacks = _get_attacks(weapon)
	var ap = _get_ap(weapon)
	var special_bonus = _get_special_rules_bonus(weapon)

	# Simple scoring: attacks * (1 + AP/6) + special bonuses
	# AP is typically 1-6, so we normalize
	return attacks * (1.0 + ap / 6.0) + special_bonus


## Gets the range value from a weapon.
static func _get_range(weapon: Variant) -> int:
	if weapon is Dictionary:
		return weapon.get("range", 0)
	return 0


## Gets the attacks value from a weapon.
static func _get_attacks(weapon: Variant) -> int:
	if weapon is Dictionary:
		return weapon.get("attacks", 1)
	return 1


## Gets the AP value from a weapon's special rules.
static func _get_ap(weapon: Variant) -> int:
	var special_rules = []
	if weapon is Dictionary:
		special_rules = weapon.get("specialRules", [])

	for rule in special_rules:
		var name = ""
		var rating = 0

		if rule is String:
			# Parse "AP(2)" format
			if rule.begins_with("AP(") and rule.ends_with(")"):
				var rating_str = rule.substr(3, rule.length() - 4)
				return rating_str.to_int()
		elif rule is Dictionary:
			name = rule.get("name", "")
			rating = rule.get("rating", 0)
			if name == "AP":
				return rating

	return 0


## Gets a bonus score from special rules.
static func _get_special_rules_bonus(weapon: Variant) -> float:
	var bonus = 0.0
	var special_rules = []

	if weapon is Dictionary:
		special_rules = weapon.get("specialRules", [])

	for rule in special_rules:
		var name = _get_rule_name(rule)

		# Bonus for powerful special rules
		match name:
			"Deadly":
				bonus += 2.0
			"Blast":
				bonus += 1.5
			"Rending":
				bonus += 1.0
			"Poison":
				bonus += 0.5

	return bonus


## Extracts the rule name from a rule (string or dict).
static func _get_rule_name(rule: Variant) -> String:
	if rule is String:
		# Extract name before parentheses
		var paren = rule.find("(")
		if paren > 0:
			return rule.substr(0, paren)
		return rule
	elif rule is Dictionary:
		return rule.get("name", "")
	return ""


## Returns the unit type as a string for display.
static func type_to_string(unit_type: UnitType) -> String:
	match unit_type:
		UnitType.HYBRID:
			return "Hybrid"
		UnitType.SHOOTING:
			return "Shooting"
		UnitType.MELEE:
			return "Melee"
	return "Unknown"
