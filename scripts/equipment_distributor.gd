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

	# Limited items: slot-grouped per-model assignment (see _assign_limited_to_models). Shared with
	# per_model_toughs() so a weapon-team model's enlarged base + its special-weapon ring agree.
	for a in _assign_limited_to_models(limited, unit_size):
		var model: ModelInstance = game_unit.models[a["model"]]
		_add_loadout_item_to_model(model, a["item"])
		_apply_item_tough_to_model(model, a["item"])


## The slot a loadout item occupies for per-model distribution: ranged / melee / equipment get
## SEPARATE cursors so a leader model keeps its distinct ranged + melee weapons together.
static func _loadout_slot_key(item: Dictionary) -> String:
	if int(item.get("attacks", 0)) <= 0:
		return "equip"
	return "ranged" if int(item.get("range", 0)) > 0 else "melee"


## The (item, model-index) assignment for LIMITED (count < size) loadout items: grouped by SLOT
## (ranged / melee / equipment), each slot filled from its OWN cursor at 0 with base (high-count)
## weapons first, so a leader model's distinct ranged + melee weapons land on the SAME model.
## SINGLE SOURCE OF TRUTH for both distribute() (weapons) AND per_model_toughs() (base sizing) —
## they MUST agree, else a weapon-team model's enlarged base and its special-weapon ring split
## onto different models. Universal across units/factions. Returns Array of { "item", "model" }.
static func _assign_limited_to_models(limited: Array, unit_size: int) -> Array:
	var out: Array = []
	var by_slot: Dictionary = {}
	for item in limited:
		var key := _loadout_slot_key(item)
		if not by_slot.has(key):
			by_slot[key] = []
		by_slot[key].append(item)
	for key in by_slot:
		var slot_items: Array = by_slot[key]
		slot_items.sort_custom(func(a, b): return _get_count(a, unit_size) > _get_count(b, unit_size))
		var cursor := 0
		for item in slot_items:
			var count = _get_count(item, unit_size)
			for _k in range(count):
				if cursor >= unit_size:
					cursor = 0  # safety wrap if a slot's counts exceed the unit size
				out.append({"item": item, "model": cursor})
				cursor += 1
	return out


## Builds the loadout dictionaries (weapons + equipment items) that distribute() walks.
## Shared by create_from_opr_unit AND the spawner, so per-model base sizing can derive the
## SAME per-model Tough distribute() will later apply (one source of truth, no drift).
static func build_loadout(opr_unit: Variant) -> Array:
	var loadout: Array = []
	for weapon in opr_unit.weapons:
		if not weapon.from_item.is_empty():
			continue  # item-granted (e.g. Weapon Team) weapons are display-only, not distributed
		loadout.append({
			"name": weapon.name,
			"range": weapon.range_value,
			"attacks": weapon.attacks,
			"count": weapon.count,
			"specialRules": weapon.special_rules.duplicate()
		})
	for equip_item in opr_unit.equipment_items:
		loadout.append({
			"name": equip_item.get("name", ""),
			"attacks": 0,
			"count": equip_item.get("count", 1),
			"specialRules": equip_item.get("rules", [])
		})
	return loadout


## Returns the final per-model Tough(X) for EVERY model index (index i = model i), replicating
## distribute()'s universal/limited cursor walk exactly. Lets the spawner pick a per-model base
## BEFORE the GameUnit (and thus model.properties["tough"]) exists. Keep in sync with distribute().
static func per_model_toughs(unit_size: int, loadout: Array, special_rules: Array) -> Array:
	var base_tough := _parse_tough_rating(special_rules)
	var toughs: Array = []
	for _i in range(maxi(0, unit_size)):
		toughs.append(base_tough)
	if unit_size <= 0:
		return toughs
	var universal: Array = []
	var limited: Array = []
	for item in loadout:
		if _get_count(item, unit_size) >= unit_size:
			universal.append(item)
		else:
			limited.append(item)
	for item in universal:
		var it := _parse_tough_rating(_item_special_rules(item))
		for i in range(unit_size):
			toughs[i] = maxi(toughs[i], it)
	# SAME slot-grouped assignment distribute() uses, so the model that gets a weapon-team item's
	# elevated Tough (→ enlarged base) is the SAME model that gets the special weapon (→ its ring).
	for a in _assign_limited_to_models(limited, unit_size):
		var it := _parse_tough_rating(_item_special_rules(a["item"]))
		toughs[a["model"]] = maxi(toughs[a["model"]], it)
	return toughs


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
	# Take the LARGEST Tough granted, not the first listed: a Tough(3) hero on a Tough(12) mount
	# (dinosaur, large vehicle, ...) must size its base + wounds from Tough 12, not Tough 3.
	var best: int = 0
	for rule in rules:
		var rating: int = 0
		if rule is String:
			var name: String = rule
			# Parse "Tough(3)" format
			if name.begins_with("Tough(") and name.ends_with(")"):
				rating = name.substr(6, name.length() - 7).to_int()
		elif rule is Dictionary:
			if rule.get("name", "") == "Tough":
				rating = int(rule.get("rating", 0))
		if rating > best:
			best = rating
	return best if best > 0 else BASE_WOUNDS  # Default: at least 1 wound to be killed


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
		"item_grants": opr_unit.item_grants.duplicate(true),  # item -> granted rules (unit-card cascade)
		"base_size_round": opr_unit.base_size_round,
		"base_size_square": opr_unit.base_size_square,
		"base_is_oval": opr_unit.base_is_oval,
		"base_is_square": opr_unit.base_is_square,
		"base_width_mm": opr_unit.base_width_mm,
		"base_depth_mm": opr_unit.base_depth_mm,
		"mount_name": opr_unit.mount_name,  # mount/vehicle upgrade -> re-fuzzy-match its GLB on load
		"base_from_tough": opr_unit.base_from_tough,  # Tough-derived base -> fit model exactly (no overhang)
		"game_system": opr_unit.game_system,
		"regiment_mode": opr_unit.game_system == "aofr",
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

	# Build the loadout (weapons + equipment) and distribute. build_loadout() is shared with the
	# spawner's per-model base sizing, so the carrier model's elevated Tough matches its bigger base.
	var loadout: Array = build_loadout(opr_unit)
	distribute(game_unit, loadout, opr_unit.special_rules)

	# Initialize caster points if unit has Caster rule
	game_unit.initialize_caster_points()

	return game_unit


