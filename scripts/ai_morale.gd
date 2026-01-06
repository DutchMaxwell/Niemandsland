class_name AIMorale
extends RefCounted
## Handles morale tests for AI units.
## Based on OPR Grimdark Future v3.5.1 morale rules.
## Morale tests: Pass = nothing, Fail = Shaken (or Rout if at half strength).


## Morale test result
enum MoraleResult {
	PASSED,
	SHAKEN,
	ROUTED
}


## Morale test outcome
class MoraleOutcome:
	var result: MoraleResult = MoraleResult.PASSED
	var roll: int = 0
	var quality: int = 0
	var was_at_half: bool = false
	var had_fearless: bool = false
	var fearless_reroll: int = 0


signal morale_test_taken(unit: GameUnit, outcome: MoraleOutcome)
signal unit_shaken(unit: GameUnit)
signal unit_routed(unit: GameUnit)


# ===== Morale Test Triggers =====

## Checks if unit needs morale test from casualties.
## "At end of activation in which unit takes wounds leaving it at half or less"
static func needs_morale_test(
	unit: GameUnit,
	wounds_taken_this_activation: int
) -> bool:
	if unit == null:
		return false

	if wounds_taken_this_activation == 0:
		return false

	var starting_size = unit.unit_properties.get("starting_size", unit.get_size())
	var current_size = unit.get_alive_count()

	# Single model with Tough
	if starting_size == 1:
		var starting_tough = unit.unit_properties.get("starting_tough", 1)
		var current_tough = 0
		for model in unit.models:
			current_tough += model.wounds_current

		return current_tough <= starting_tough / 2

	# Multi-model unit
	return current_size <= starting_size / 2


## Checks if unit was at half strength for melee morale.
static func was_at_half_strength(unit: GameUnit) -> bool:
	var starting_size = unit.unit_properties.get("starting_size", unit.get_size())
	var current_size = unit.get_alive_count()

	if starting_size == 1:
		var starting_tough = unit.unit_properties.get("starting_tough", 1)
		var current_tough = 0
		for model in unit.models:
			current_tough += model.wounds_current
		return current_tough <= starting_tough / 2

	return current_size <= starting_size / 2


# ===== Taking Morale Tests =====

## Takes a morale test for a unit.
## @param unit: The unit taking the test
## @param is_melee: Whether this is from melee combat
## @param lost_melee: Whether the unit lost the melee
## @returns: MoraleOutcome
static func take_morale_test(
	unit: GameUnit,
	is_melee: bool = false,
	lost_melee: bool = false
) -> MoraleOutcome:
	var outcome = MoraleOutcome.new()

	if unit == null:
		push_error("AIMorale: take_morale_test called with null unit")
		return outcome

	outcome.quality = unit.get_quality()
	outcome.was_at_half = was_at_half_strength(unit)

	# Roll quality test
	outcome.roll = randi() % 6 + 1

	# Check if test passed
	var passed = outcome.roll >= outcome.quality

	# Fearless: 4+ to count as passed instead
	if not passed and _has_fearless(unit):
		outcome.had_fearless = true
		outcome.fearless_reroll = randi() % 6 + 1
		if outcome.fearless_reroll >= 4:
			passed = true

	if passed:
		outcome.result = MoraleResult.PASSED
		return outcome

	# Test failed - determine consequence
	if is_melee:
		# Melee morale: Shaken if over half, Rout if at half or less
		if outcome.was_at_half:
			outcome.result = MoraleResult.ROUTED
		else:
			outcome.result = MoraleResult.SHAKEN
	else:
		# Non-melee morale: Always Shaken
		outcome.result = MoraleResult.SHAKEN

	return outcome


## Applies morale outcome to unit.
static func apply_morale_outcome(unit: GameUnit, outcome: MoraleOutcome) -> void:
	match outcome.result:
		MoraleResult.SHAKEN:
			_apply_shaken(unit)
		MoraleResult.ROUTED:
			_apply_routed(unit)


# ===== Shaken Status =====

## Applies Shaken status to unit.
## "Shaken units must stay idle, always fail morale, can't seize objectives"
static func _apply_shaken(unit: GameUnit) -> void:
	for model in unit.models:
		model.add_marker("Shaken")

	unit.unit_properties["is_shaken"] = true


## Removes Shaken status from unit.
## "When activated, spend activation being idle to stop being Shaken"
static func remove_shaken(unit: GameUnit) -> void:
	for model in unit.models:
		model.remove_marker("Shaken")

	unit.unit_properties["is_shaken"] = false


## Checks if unit is Shaken.
static func is_shaken(unit: GameUnit) -> bool:
	return unit.unit_properties.get("is_shaken", false)


# ===== Routed Status =====

## Applies Routed status (removes unit from game).
static func _apply_routed(unit: GameUnit) -> void:
	for model in unit.models:
		model.is_alive = false
		model.add_marker("Routed")

	unit.unit_properties["is_routed"] = true


## Checks if unit has routed.
static func has_routed(unit: GameUnit) -> bool:
	return unit.unit_properties.get("is_routed", false)


# ===== Melee Morale =====

## Handles morale for melee combat.
## "Only the loser takes a morale test, regardless of casualties"
static func handle_melee_morale(
	winner: GameUnit,
	loser: GameUnit
) -> MoraleOutcome:
	if loser == null or loser.is_destroyed():
		return MoraleOutcome.new()  # Destroyed units don't take tests

	var outcome = take_morale_test(loser, true, true)
	apply_morale_outcome(loser, outcome)

	return outcome


# ===== Fear =====

## Gets Fear bonus for melee morale.
## "Fear(X): counts as having dealt +X wounds when checking who won melee"
static func get_fear_bonus(unit: GameUnit) -> int:
	var total_fear = 0

	for model in unit.models:
		if not model.is_alive:
			continue

		var rules = model.properties.get("special_rules", [])
		for rule in rules:
			var name = _get_rule_name(rule)
			var rating = _get_rule_rating(rule)
			if name == "Fear":
				total_fear += rating

	return total_fear


# ===== Shaken Effects =====

## Gets modified combat stats for Shaken units.
## "Shaken units may strike back counting as fatigued"
static func get_shaken_combat_modifiers(unit: GameUnit) -> Dictionary:
	if not is_shaken(unit):
		return {}

	return {
		"is_fatigued": true,
		"quality": 6  # Only hit on 6s
	}


## Checks if Shaken unit can take action.
## "Shaken units must stay idle"
static func can_take_action(unit: GameUnit, action: String) -> bool:
	if not is_shaken(unit):
		return true

	# Shaken units can only go idle (which removes Shaken)
	return action == "idle"


# ===== AI Morale Decisions =====

## AI decision: should we strike back in melee?
## "AI units must always strike back" (from Solo rules)
static func ai_should_strike_back(unit: GameUnit) -> bool:
	# Per OPR Solo rules, AI always strikes back
	return true


## AI decision: evaluate risk of charging based on morale.
static func evaluate_charge_risk(
	attacker: GameUnit,
	defender: GameUnit
) -> float:
	var risk = 0.0

	# Risk increases if we're close to half strength
	var attacker_size = attacker.get_alive_count()
	var starting_size = attacker.unit_properties.get("starting_size", attacker.get_size())

	if attacker_size <= starting_size / 2:
		risk += 0.5  # Already at half, could rout

	# Risk decreases with Fearless
	if _has_fearless(attacker):
		risk -= 0.2

	# Risk increases against high-damage targets
	var defender_attacks = _estimate_attacks(defender)
	if defender_attacks > attacker_size:
		risk += 0.3

	return clamp(risk, 0.0, 1.0)


# ===== Helper Methods =====

static func _has_fearless(unit: GameUnit) -> bool:
	# All models must have Fearless for the unit to have it
	for model in unit.models:
		if not model.is_alive:
			continue
		if not model.has_special_rule("Fearless"):
			return false
	return true


static func _estimate_attacks(unit: GameUnit) -> int:
	var total = 0
	for model in unit.models:
		if not model.is_alive:
			continue
		var weapons = model.get_weapons()
		for weapon in weapons:
			if weapon is Dictionary:
				total += weapon.get("attacks", 1)
	return total


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
