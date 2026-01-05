class_name AICombat
extends RefCounted
## Handles combat resolution for AI units.
## Based on OPR Grimdark Future v3.5.1 rules.
## Shooting Sequence: Determine Attacks → Roll to Hit → Roll to Block → Remove Casualties
## Melee Sequence: Same + Return Strikes + Fatigue


## Combat result structure
class CombatResult:
	var attacker: GameUnit = null
	var defender: GameUnit = null
	var total_attacks: int = 0
	var hits: int = 0
	var blocked: int = 0
	var wounds: int = 0
	var casualties: Array[ModelInstance] = []
	var is_melee: bool = false
	var attacker_wounds: int = 0  # For melee comparison
	var defender_wounds: int = 0
	var winner: GameUnit = null   # For melee resolution


## Dice roll result for logging
class DiceRoll:
	var dice: Array[int] = []
	var target: int = 0
	var modifier: int = 0
	var successes: int = 0
	var fails: int = 0


signal combat_started(attacker: GameUnit, defender: GameUnit, is_melee: bool)
signal dice_rolled(roll_type: String, result: DiceRoll)
signal hits_scored(count: int)
signal wounds_dealt(count: int)
signal casualties_removed(models: Array[ModelInstance])
signal combat_ended(result: CombatResult)


# ===== Shooting =====

## Resolves a shooting attack from AI unit.
## @param attacker: The attacking AI unit
## @param defender: The target enemy unit
## @param context: AIContext for terrain/cover checks
## @returns: CombatResult with all details
static func resolve_shooting(
	attacker: GameUnit,
	defender: GameUnit,
	context: AIContext
) -> CombatResult:
	var result = CombatResult.new()

	if attacker == null or defender == null:
		push_error("AICombat: resolve_shooting called with null unit")
		return result

	if context == null:
		push_warning("AICombat: context is null in resolve_shooting")

	result.attacker = attacker
	result.defender = defender
	result.is_melee = false

	# Step 1: Determine Attacks
	var weapons_data = _get_shooting_weapons(attacker, defender)
	result.total_attacks = weapons_data.total_attacks

	if result.total_attacks == 0:
		return result

	# Step 2: Roll to Hit
	var hit_modifier = _get_shooting_modifiers(attacker, defender, context)
	var quality = attacker.get_quality()
	var hit_roll = _roll_quality_tests(result.total_attacks, quality, hit_modifier)
	result.hits = hit_roll.successes

	# Apply weapon special rules that modify hits
	result.hits = _apply_hit_multipliers(result.hits, weapons_data, defender)

	if result.hits == 0:
		return result

	# Step 3: Roll to Block
	var defense = defender.get_defense()
	var defense_modifier = _get_defense_modifiers(weapons_data, defender, context)
	var block_roll = _roll_defense_tests(result.hits, defense, defense_modifier)
	result.blocked = block_roll.successes
	result.wounds = result.hits - result.blocked

	# Apply Regeneration if defender has it
	result.wounds = _apply_regeneration(result.wounds, defender, weapons_data)

	# Step 4: Remove Casualties
	if result.wounds > 0:
		result.casualties = _remove_casualties(defender, result.wounds, weapons_data)

	result.defender_wounds = result.wounds
	return result


# ===== Melee =====

## Resolves a melee attack (charge).
## @param attacker: The charging AI unit
## @param defender: The target enemy unit
## @param context: AIContext
## @param is_fatigued: Whether attacker already fought this round
## @returns: CombatResult
static func resolve_melee(
	attacker: GameUnit,
	defender: GameUnit,
	context: AIContext,
	is_fatigued: bool = false
) -> CombatResult:
	var result = CombatResult.new()

	if attacker == null or defender == null:
		push_error("AICombat: resolve_melee called with null unit")
		return result

	result.attacker = attacker
	result.defender = defender
	result.is_melee = true

	# Check for Counter - defender strikes first
	if _has_counter(defender) and not is_fatigued:
		var counter_result = _resolve_melee_attacks(defender, attacker, context, false)
		result.attacker_wounds = counter_result.wounds

	# Impact hits (only if charging and not fatigued)
	if not is_fatigued:
		var impact_hits = _roll_impact_hits(attacker)
		if impact_hits > 0:
			var defense = defender.get_defense()
			var block_roll = _roll_defense_tests(impact_hits, defense, 0)
			var impact_wounds = impact_hits - block_roll.successes
			result.defender_wounds += impact_wounds
			if impact_wounds > 0:
				_remove_casualties(defender, impact_wounds, {})

	# Attacker strikes
	var attack_result = _resolve_melee_attacks(attacker, defender, context, is_fatigued)
	result.total_attacks = attack_result.total_attacks
	result.hits = attack_result.hits
	result.blocked = attack_result.blocked
	result.wounds = attack_result.wounds
	result.defender_wounds += result.wounds
	result.casualties = attack_result.casualties

	# Defender strikes back (per OPR Solo rules: "AI units must always strike back")
	if not defender.is_destroyed():
		var defender_fatigued = is_fatigued or defender.unit_properties.get("fought_this_round", false)
		var strike_back = _resolve_melee_attacks(defender, attacker, context, defender_fatigued)
		result.attacker_wounds += strike_back.wounds

	# Determine winner
	result.winner = _determine_melee_winner(result)

	# Mark both units as having fought this round (Fatigue)
	attacker.unit_properties["fought_this_round"] = true
	defender.unit_properties["fought_this_round"] = true

	return result


## Resolves melee attacks for one side.
static func _resolve_melee_attacks(
	attacker: GameUnit,
	defender: GameUnit,
	context: AIContext,
	is_fatigued: bool
) -> CombatResult:
	var result = CombatResult.new()
	result.attacker = attacker
	result.defender = defender
	result.is_melee = true

	# Step 1: Determine Attacks (models within 2" horizontally, 4" vertically)
	var weapons_data = _get_melee_weapons(attacker, defender)
	result.total_attacks = weapons_data.total_attacks

	if result.total_attacks == 0:
		return result

	# Step 2: Roll to Hit
	var quality = attacker.get_quality()
	var hit_modifier = 0

	# Fatigue: only hit on unmodified 6
	if is_fatigued:
		quality = 6

	# Thrust: +1 to hit when charging
	if weapons_data.has_thrust and not is_fatigued:
		hit_modifier += 1

	# Furious: 6s deal extra hit (handled in multipliers)

	var hit_roll = _roll_quality_tests(result.total_attacks, quality, hit_modifier)
	result.hits = hit_roll.successes

	# Apply Furious (6s deal extra hit)
	if weapons_data.has_furious and not is_fatigued:
		result.hits += hit_roll.sixes

	if result.hits == 0:
		return result

	# Step 3: Roll to Block
	var defense = defender.get_defense()
	var defense_modifier = _get_melee_defense_modifiers(weapons_data)

	var block_roll = _roll_defense_tests(result.hits, defense, defense_modifier)
	result.blocked = block_roll.successes
	result.wounds = result.hits - result.blocked

	# Apply Regeneration
	result.wounds = _apply_regeneration(result.wounds, defender, weapons_data)

	# Step 4: Remove Casualties
	if result.wounds > 0:
		result.casualties = _remove_casualties(defender, result.wounds, weapons_data)

	return result


# ===== Dice Rolling =====

## Rolls quality tests (to hit).
## @returns: DiceRoll with results
static func _roll_quality_tests(count: int, quality: int, modifier: int) -> DiceRoll:
	var result = DiceRoll.new()
	result.target = quality
	result.modifier = modifier

	for i in range(count):
		var roll = randi() % 6 + 1
		result.dice.append(roll)

		var modified_roll = roll + modifier
		if roll == 1:
			# 1 always fails
			result.fails += 1
		elif roll == 6:
			# 6 always succeeds
			result.successes += 1
		elif modified_roll >= quality:
			result.successes += 1
		else:
			result.fails += 1

	return result


## Rolls defense tests (to block).
static func _roll_defense_tests(count: int, defense: int, modifier: int) -> DiceRoll:
	var result = DiceRoll.new()
	result.target = defense
	result.modifier = modifier

	for i in range(count):
		var roll = randi() % 6 + 1
		result.dice.append(roll)

		var modified_roll = roll + modifier
		if roll == 1:
			result.fails += 1
		elif roll == 6:
			result.successes += 1
		elif modified_roll >= defense:
			result.successes += 1
		else:
			result.fails += 1

	return result


# ===== Weapon Analysis =====

## Gets shooting weapons and calculates total attacks.
static func _get_shooting_weapons(attacker: GameUnit, defender: GameUnit) -> Dictionary:
	var data = {
		"total_attacks": 0,
		"weapons": [],
		"has_blast": false,
		"blast_value": 0,
		"has_ap": false,
		"ap_value": 0,
		"has_deadly": false,
		"deadly_value": 0,
		"has_rending": false,
		"has_indirect": false,
		"has_relentless": false,
		"ignores_regen": false
	}

	var defender_pos = _get_unit_center(defender)

	for model in attacker.models:
		if not model.is_alive:
			continue

		var model_pos = model.node.global_position if model.node else Vector3.ZERO
		var weapons = model.get_weapons()

		for weapon in weapons:
			if not weapon is Dictionary:
				continue

			var range_val = weapon.get("range", 0)
			if range_val == 0:
				continue  # Melee weapon

			var distance = model_pos.distance_to(defender_pos)
			if distance > range_val:
				continue  # Out of range

			var attacks = weapon.get("attacks", 1)
			data.total_attacks += attacks
			data.weapons.append(weapon)

			# Check special rules
			var special_rules = weapon.get("specialRules", [])
			for rule in special_rules:
				var name = _get_rule_name(rule)
				var rating = _get_rule_rating(rule)

				match name:
					"Blast":
						data.has_blast = true
						data.blast_value = max(data.blast_value, rating)
					"AP":
						data.has_ap = true
						data.ap_value = max(data.ap_value, rating)
					"Deadly":
						data.has_deadly = true
						data.deadly_value = max(data.deadly_value, rating)
					"Rending":
						data.has_rending = true
						data.ignores_regen = true
					"Bane":
						data.ignores_regen = true
					"Unstoppable":
						data.ignores_regen = true
					"Indirect":
						data.has_indirect = true
					"Relentless":
						data.has_relentless = true

	return data


## Gets melee weapons and calculates total attacks.
static func _get_melee_weapons(attacker: GameUnit, defender: GameUnit) -> Dictionary:
	var data = {
		"total_attacks": 0,
		"weapons": [],
		"has_ap": false,
		"ap_value": 0,
		"has_deadly": false,
		"deadly_value": 0,
		"has_rending": false,
		"has_furious": false,
		"has_thrust": false,
		"ignores_regen": false
	}

	var defender_pos = _get_unit_center(defender)

	for model in attacker.models:
		if not model.is_alive:
			continue

		var model_pos = model.node.global_position if model.node else Vector3.ZERO

		# Models within 2" horizontally can strike
		var horizontal_dist = Vector2(model_pos.x, model_pos.z).distance_to(
			Vector2(defender_pos.x, defender_pos.z)
		)
		if horizontal_dist > 2.0:
			continue

		var weapons = model.get_weapons()

		for weapon in weapons:
			if not weapon is Dictionary:
				continue

			var range_val = weapon.get("range", 0)
			if range_val > 0:
				continue  # Ranged weapon

			var attacks = weapon.get("attacks", 1)
			data.total_attacks += attacks
			data.weapons.append(weapon)

			# Check special rules
			var special_rules = weapon.get("specialRules", [])
			for rule in special_rules:
				var name = _get_rule_name(rule)
				var rating = _get_rule_rating(rule)

				match name:
					"AP":
						data.has_ap = true
						data.ap_value = max(data.ap_value, rating)
					"Deadly":
						data.has_deadly = true
						data.deadly_value = max(data.deadly_value, rating)
					"Rending":
						data.has_rending = true
						data.ignores_regen = true
					"Bane":
						data.ignores_regen = true
					"Furious":
						data.has_furious = true
					"Thrust":
						data.has_thrust = true

	# Check unit-level Furious
	if attacker.has_special_rule("Furious"):
		data.has_furious = true

	return data


# ===== Modifiers =====

## Gets shooting hit modifiers.
static func _get_shooting_modifiers(
	attacker: GameUnit,
	defender: GameUnit,
	context: AIContext
) -> int:
	var modifier = 0
	var distance = _get_unit_center(attacker).distance_to(_get_unit_center(defender))

	# Stealth: -1 to hit from over 9" away
	if defender.has_special_rule("Stealth") and distance > 9.0:
		modifier -= 1

	# Artillery: -2 to hit from over 9" (attacker is artillery)
	if attacker.has_special_rule("Artillery") and distance > 9.0:
		modifier += 1  # Artillery gets +1 when shooting over 9"

	# Aircraft: -12" to range (effectively harder to hit)
	if defender.has_special_rule("Aircraft"):
		# Already handled in range check, but could add -1 modifier
		pass

	# Indirect after moving: -1 to hit
	if attacker.unit_properties.get("moved_this_turn", false):
		for model in attacker.models:
			var weapons = model.get_weapons()
			for weapon in weapons:
				if _weapon_has_rule(weapon, "Indirect"):
					modifier -= 1
					break

	return modifier


## Gets defense modifiers from weapons.
static func _get_defense_modifiers(
	weapons_data: Dictionary,
	defender: GameUnit,
	context: AIContext
) -> int:
	var modifier = 0

	# AP reduces defense
	if weapons_data.has_ap:
		modifier -= weapons_data.ap_value

	# Cover: +1 to defense if in cover terrain
	if _is_in_cover(defender, context):
		# Check if weapon ignores cover (Blast, Indirect)
		if not weapons_data.has_blast and not weapons_data.get("has_indirect", false):
			modifier += 1

	return modifier


## Gets melee defense modifiers.
static func _get_melee_defense_modifiers(weapons_data: Dictionary) -> int:
	var modifier = 0

	if weapons_data.has_ap:
		modifier -= weapons_data.ap_value

	# Thrust: +AP(1) when charging
	if weapons_data.has_thrust:
		modifier -= 1

	return modifier


# ===== Hit Multipliers =====

## Applies hit multipliers (Blast, Relentless, etc.)
static func _apply_hit_multipliers(
	hits: int,
	weapons_data: Dictionary,
	defender: GameUnit
) -> int:
	var total_hits = hits

	# Blast: multiply hits by X (up to models in target unit)
	if weapons_data.has_blast:
		var defender_models = defender.get_alive_count()
		var multiplier = min(weapons_data.blast_value, defender_models)
		total_hits = hits * multiplier

	return total_hits


# ===== Regeneration =====

## Applies Regeneration saves.
static func _apply_regeneration(
	wounds: int,
	defender: GameUnit,
	weapons_data: Dictionary
) -> int:
	# Check if weapon ignores Regeneration
	if weapons_data.get("ignores_regen", false):
		return wounds

	if not defender.has_special_rule("Regeneration"):
		return wounds

	var remaining = wounds
	for i in range(wounds):
		var roll = randi() % 6 + 1
		if roll >= 5:  # 5+ ignores wound
			remaining -= 1

	return remaining


# ===== Casualty Removal =====

## Removes casualties from defender.
static func _remove_casualties(
	defender: GameUnit,
	wounds: int,
	weapons_data: Dictionary
) -> Array[ModelInstance]:
	var casualties: Array[ModelInstance] = []
	var remaining_wounds = wounds

	# Deadly: assign wounds to specific models, multiply by X
	if weapons_data.get("has_deadly", false):
		var deadly_value = weapons_data.get("deadly_value", 1)
		var deadly_wounds = wounds * deadly_value
		remaining_wounds = 0

		for model in defender.models:
			if not model.is_alive:
				continue
			if deadly_wounds <= 0:
				break

			var damage = min(deadly_wounds, model.wounds_current)
			model.wounds_current -= damage
			deadly_wounds -= damage

			if model.wounds_current <= 0:
				model.is_alive = false
				casualties.append(model)

		return casualties

	# Normal casualty removal
	for model in defender.models:
		if not model.is_alive:
			continue
		if remaining_wounds <= 0:
			break

		# Tough models take multiple wounds
		var model_wounds = min(remaining_wounds, model.wounds_current)
		model.wounds_current -= model_wounds
		remaining_wounds -= model_wounds

		if model.wounds_current <= 0:
			model.is_alive = false
			casualties.append(model)

	return casualties


# ===== Impact Hits =====

## Rolls impact hits for charging unit.
static func _roll_impact_hits(attacker: GameUnit) -> int:
	var total_impact = 0

	for model in attacker.models:
		if not model.is_alive:
			continue

		var rules = model.properties.get("special_rules", [])
		for rule in rules:
			var name = _get_rule_name(rule)
			var rating = _get_rule_rating(rule)
			if name == "Impact":
				# Check for Counter reduction
				# (handled elsewhere, but would reduce rating by 1 per Counter model)
				for i in range(rating):
					var roll = randi() % 6 + 1
					if roll >= 2:
						total_impact += 1

	return total_impact


# ===== Melee Resolution =====

## Determines winner of melee.
static func _determine_melee_winner(result: CombatResult) -> GameUnit:
	if result.defender_wounds > result.attacker_wounds:
		return result.attacker
	elif result.attacker_wounds > result.defender_wounds:
		return result.defender
	else:
		return null  # Tie


## Checks if defender has Counter.
static func _has_counter(unit: GameUnit) -> bool:
	for model in unit.models:
		var weapons = model.get_weapons()
		for weapon in weapons:
			if _weapon_has_rule(weapon, "Counter"):
				return true
	return false


# ===== Cover Check =====

## Checks if majority of unit is in cover.
static func _is_in_cover(unit: GameUnit, context: AIContext) -> bool:
	var in_cover = 0
	var total = 0

	for model in unit.models:
		if not model.is_alive:
			continue

		total += 1
		if model.node:
			var pos = model.node.global_position
			if context.is_in_cover(pos):
				in_cover += 1

	return in_cover > total / 2


# ===== Helper Methods =====

static func _get_unit_center(game_unit: GameUnit) -> Vector3:
	if game_unit == null:
		push_warning("AICombat: _get_unit_center called with null unit")
		return Vector3.ZERO

	var sum = Vector3.ZERO
	var count = 0
	for model in game_unit.models:
		if model.is_alive and model.node:
			sum += model.node.global_position
			count += 1
	if count > 0:
		return sum / count
	return Vector3.ZERO


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
