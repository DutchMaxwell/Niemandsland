extends Node
class_name OPRApiClient
## OnePageRules Army Forge API Client
## Handles importing armies from JSON files and API endpoints

signal army_loaded(army: OPRArmy)
signal import_failed(error: String)
signal download_progress(current: int, total: int)

## Army data structure
class OPRArmy:
	var id: String = ""
	var name: String = ""
	var game_system: String = ""  # e.g., "grimdark-future", "age-of-fantasy"
	var points: int = 0
	var player_id: int = 0  # Assigned player (1 or 2)
	var units: Array[OPRUnit] = []

	func get_total_points() -> int:
		var total = 0
		for unit in units:
			total += unit.cost
		return total

	func get_unit_count() -> int:
		var count = 0
		for unit in units:
			count += unit.size
		return count


## Unit data structure
class OPRUnit:
	var id: String = ""
	var name: String = ""
	var size: int = 1  # Number of models in unit
	var cost: int = 0  # Points cost
	var quality: int = 4  # Quality value (lower is better)
	var defense: int = 4  # Defense value (higher is better)
	var equipment: Array[String] = []
	var special_rules: Array[String] = []
	var weapons: Array[OPRWeapon] = []
	var custom_name: String = ""  # User's nickname for the unit

	func get_display_name() -> String:
		if not custom_name.is_empty():
			return custom_name
		return name

	func get_stats_text() -> String:
		var lines: Array[String] = []
		lines.append("[b]%s[/b]" % get_display_name())
		lines.append("Q%d+ | D%d+" % [quality, defense])
		lines.append("%d models | %d pts" % [size, cost])

		if not weapons.is_empty():
			lines.append("")
			lines.append("[u]Weapons:[/u]")
			for weapon in weapons:
				lines.append("• %s" % weapon.get_display_text())

		if not special_rules.is_empty():
			lines.append("")
			lines.append("[u]Special:[/u]")
			lines.append(", ".join(special_rules))

		return "\n".join(lines)


## Weapon data structure
class OPRWeapon:
	var name: String = ""
	var range_value: int = 0  # 0 = melee
	var attacks: int = 1
	var special_rules: Array[String] = []

	func get_display_text() -> String:
		var range_str = "Melee" if range_value == 0 else "%d\"" % range_value
		var text = "%s (%s, A%d)" % [name, range_str, attacks]
		if not special_rules.is_empty():
			text += " [%s]" % ", ".join(special_rules)
		return text


## Import army from a local JSON file (Army Forge export)
func import_from_file(file_path: String) -> OPRArmy:
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		push_error("OPRApiClient: Cannot open file: %s" % file_path)
		import_failed.emit("Cannot open file: %s" % file_path.get_file())
		return null

	var json_text = file.get_as_text()
	file.close()

	return _parse_army_json(json_text, file_path.get_file())


## Import army from a share URL (needs the list ID)
func import_from_share_id(list_id: String) -> void:
	# Army Forge share URLs use this format:
	# https://army-forge.onepagerules.com/share?id={LIST_ID}
	# The actual data endpoint is not publicly documented
	# For now, we'll use the exported JSON approach
	push_warning("OPRApiClient: Direct API import not yet supported. Please export JSON from Army Forge.")
	import_failed.emit("Direct API import not supported. Please use 'Share as File' in Army Forge.")


## Parse Army Forge JSON export
func _parse_army_json(json_text: String, source_name: String = "") -> OPRArmy:
	var json = JSON.new()
	var error = json.parse(json_text)

	if error != OK:
		push_error("OPRApiClient: JSON parse error: %s" % json.get_error_message())
		import_failed.emit("Invalid JSON format")
		return null

	var data = json.data
	if not data is Dictionary:
		import_failed.emit("Invalid army data format")
		return null

	var army = OPRArmy.new()
	army.id = data.get("id", str(Time.get_unix_time_from_system()))
	army.name = data.get("name", source_name.get_basename())
	army.game_system = data.get("gameSystem", "unknown")
	army.points = data.get("points", 0)

	# Parse units
	var units_data = data.get("units", [])
	for unit_data in units_data:
		var unit = _parse_unit(unit_data)
		if unit:
			army.units.append(unit)

	# Calculate actual points if not provided
	if army.points == 0:
		army.points = army.get_total_points()

	print("OPRApiClient: Loaded army '%s' - %d units, %d pts" % [army.name, army.units.size(), army.points])
	army_loaded.emit(army)
	return army


## Parse a single unit from JSON
func _parse_unit(data: Dictionary) -> OPRUnit:
	var unit = OPRUnit.new()

	unit.id = data.get("id", str(randi()))
	unit.name = data.get("name", "Unknown Unit")
	unit.custom_name = data.get("customName", "")
	unit.size = data.get("size", 1)
	unit.cost = data.get("cost", 0)
	unit.quality = data.get("quality", 4)
	unit.defense = data.get("defense", 4)

	# Parse equipment list
	var equipment = data.get("equipment", [])
	for equip in equipment:
		if equip is String:
			unit.equipment.append(equip)
		elif equip is Dictionary:
			unit.equipment.append(equip.get("name", "Unknown"))

	# Parse special rules
	var rules = data.get("specialRules", [])
	for rule in rules:
		if rule is String:
			unit.special_rules.append(rule)
		elif rule is Dictionary:
			var rule_name = rule.get("name", "")
			var rule_rating = rule.get("rating", "")
			if not rule_rating.is_empty():
				unit.special_rules.append("%s(%s)" % [rule_name, rule_rating])
			else:
				unit.special_rules.append(rule_name)

	# Parse weapons
	var weapons = data.get("weapons", data.get("loadout", []))
	for weapon_data in weapons:
		var weapon = _parse_weapon(weapon_data)
		if weapon:
			unit.weapons.append(weapon)

	return unit


## Parse a weapon from JSON
func _parse_weapon(data) -> OPRWeapon:
	if data is String:
		var weapon = OPRWeapon.new()
		weapon.name = data
		return weapon

	if not data is Dictionary:
		return null

	var weapon = OPRWeapon.new()
	weapon.name = data.get("name", "Unknown Weapon")
	weapon.range_value = data.get("range", 0)
	weapon.attacks = data.get("attacks", 1)

	var rules = data.get("specialRules", [])
	for rule in rules:
		if rule is String:
			weapon.special_rules.append(rule)
		elif rule is Dictionary:
			weapon.special_rules.append(rule.get("name", ""))

	return weapon


## Create a sample/test army for development
static func create_test_army(player_id: int = 1) -> OPRArmy:
	var army = OPRArmy.new()
	army.id = "test_army_%d" % player_id
	army.name = "Test Army %d" % player_id
	army.game_system = "grimdark-future"
	army.player_id = player_id

	# Add some test units
	var unit1 = OPRUnit.new()
	unit1.name = "Battle Brothers"
	unit1.size = 5
	unit1.cost = 100
	unit1.quality = 3
	unit1.defense = 4
	unit1.special_rules = ["Tough(3)"]

	var rifle = OPRWeapon.new()
	rifle.name = "Assault Rifle"
	rifle.range_value = 24
	rifle.attacks = 1
	unit1.weapons.append(rifle)

	var ccw = OPRWeapon.new()
	ccw.name = "CCW"
	ccw.range_value = 0
	ccw.attacks = 1
	unit1.weapons.append(ccw)

	army.units.append(unit1)

	var unit2 = OPRUnit.new()
	unit2.name = "Heavy Support"
	unit2.size = 3
	unit2.cost = 150
	unit2.quality = 3
	unit2.defense = 5
	unit2.special_rules = ["Slow", "Tough(6)"]

	var heavy = OPRWeapon.new()
	heavy.name = "Heavy Machinegun"
	heavy.range_value = 36
	heavy.attacks = 3
	heavy.special_rules = ["AP(1)"]
	unit2.weapons.append(heavy)

	army.units.append(unit2)

	army.points = army.get_total_points()
	return army
