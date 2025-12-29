extends Node
class_name OPRApiClient
## OnePageRules Army Forge API Client
## Handles importing armies from JSON files and fetching unit data from OPR API

signal army_loaded(army: OPRArmy)
signal import_failed(error: String)
signal loading_progress(message: String)

## OPR API base URL
const API_BASE_URL = "https://army-forge.onepagerules.com/api"

## HTTP request node for API calls
var _http_request: HTTPRequest

## Cached army books (armyId -> book data)
var _army_books: Dictionary = {}


## Army data structure
class OPRArmy:
	var id: String = ""
	var name: String = ""
	var game_system: String = ""  # e.g., "gf" (grimdark-future), "aof" (age-of-fantasy)
	var points: int = 0
	var player_id: int = 0  # Assigned player (1-4)
	var units: Array[OPRUnit] = []
	var model_count: int = 0

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
	var selection_id: String = ""
	var name: String = ""
	var size: int = 1  # Number of models in unit
	var cost: int = 0  # Points cost
	var quality: int = 4  # Quality value (lower is better)
	var defense: int = 4  # Defense value (higher is better)
	var equipment: Array[String] = []
	var special_rules: Array[String] = []
	var weapons: Array[OPRWeapon] = []
	var custom_name: String = ""  # User's nickname for the unit
	var upgrades: Array[String] = []  # Selected upgrade names

	func get_display_name() -> String:
		if not custom_name.is_empty():
			return custom_name
		if size > 1:
			return "%s [%d]" % [name, size]
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
	var count: int = 1

	func get_display_text() -> String:
		var count_str = "" if count <= 1 else "%dx " % count
		var range_str = "Melee" if range_value == 0 else "%d\"" % range_value
		var text = "%s%s (%s, A%d)" % [count_str, name, range_str, attacks]
		if not special_rules.is_empty():
			text += " [%s]" % ", ".join(special_rules)
		return text


func _ready() -> void:
	_http_request = HTTPRequest.new()
	add_child(_http_request)
	_http_request.request_completed.connect(_on_request_completed)


## Import army from a local JSON file (Army Forge export)
func import_from_file(file_path: String) -> OPRArmy:
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		push_error("OPRApiClient: Cannot open file: %s" % file_path)
		import_failed.emit("Cannot open file: %s" % file_path.get_file())
		return null

	var json_text = file.get_as_text()
	file.close()

	return _parse_army_forge_json(json_text, file_path.get_file())


## Parse Army Forge JSON export (the real format)
func _parse_army_forge_json(json_text: String, source_name: String = "") -> OPRArmy:
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

	# Parse top-level fields
	army.id = data.get("id", str(Time.get_unix_time_from_system()))
	army.name = data.get("armyName", data.get("list", {}).get("name", source_name.get_basename()))
	army.game_system = _expand_game_system(data.get("gameSystem", "gf"))
	army.points = data.get("listPoints", 0)

	# Get list data
	var list_data = data.get("list", {})
	army.model_count = list_data.get("modelCount", 0)

	if army.points == 0:
		army.points = list_data.get("pointsLimit", 0)

	# Get army book ID for fetching unit definitions
	var army_id = data.get("armyId", "")
	var army_ids = data.get("armyIds", [])
	if army_id.is_empty() and army_ids.size() > 0:
		army_id = army_ids[0]

	# Parse units from list
	var units_data = list_data.get("units", [])

	# Try to load army book for full unit definitions
	var book_data = await _fetch_army_book(army_id, army.game_system)

	for unit_data in units_data:
		var unit = _parse_unit_from_list(unit_data, book_data)
		if unit:
			army.units.append(unit)

	print("OPRApiClient: Loaded army '%s' - %d units, %d pts, %d models" % [
		army.name, army.units.size(), army.points, army.model_count
	])

	army_loaded.emit(army)
	return army


## Expand game system abbreviation
func _expand_game_system(abbrev: String) -> String:
	match abbrev:
		"gf": return "Grimdark Future"
		"gff": return "Grimdark Future: Firefight"
		"aof": return "Age of Fantasy"
		"aofs": return "Age of Fantasy: Skirmish"
		"aofr": return "Age of Fantasy: Regiments"
		_: return abbrev


## Fetch army book data from OPR API
func _fetch_army_book(army_id: String, game_system: String) -> Dictionary:
	if army_id.is_empty():
		return {}

	# Check cache first
	if _army_books.has(army_id):
		return _army_books[army_id]

	loading_progress.emit("Loading army book data...")

	# Try to fetch from OPR API
	var url = "%s/army-books/%s" % [API_BASE_URL, army_id]
	print("OPRApiClient: Fetching army book from %s" % url)

	var error = _http_request.request(url)
	if error != OK:
		push_warning("OPRApiClient: Failed to request army book: %d" % error)
		return {}

	# Wait for response (simplified - in production use signals properly)
	await _http_request.request_completed

	return _army_books.get(army_id, {})


## HTTP request completed handler
func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		push_warning("OPRApiClient: API request failed (result=%d, code=%d)" % [result, response_code])
		return

	var json = JSON.new()
	var parse_result = json.parse(body.get_string_from_utf8())
	if parse_result != OK:
		push_warning("OPRApiClient: Failed to parse API response")
		return

	var data = json.data
	if data is Dictionary and data.has("_id"):
		var army_id = data.get("_id", "")
		if not army_id.is_empty():
			_army_books[army_id] = data
			print("OPRApiClient: Cached army book '%s'" % data.get("name", army_id))


## Parse a unit from list data, enriching with book data if available
func _parse_unit_from_list(list_unit: Dictionary, book_data: Dictionary) -> OPRUnit:
	var unit = OPRUnit.new()

	var unit_def_id = list_unit.get("id", "")
	var selection_id = list_unit.get("selectionId", "")

	unit.id = unit_def_id
	unit.selection_id = selection_id

	# Try to find unit definition in book data
	var unit_def = _find_unit_in_book(unit_def_id, book_data)

	if unit_def.is_empty():
		# No book data - create placeholder with ID
		unit.name = "Unit %s" % unit_def_id.left(6)
		unit.quality = 4
		unit.defense = 4
		unit.size = 1
		unit.cost = 0
	else:
		# Parse from book definition
		unit.name = unit_def.get("name", "Unknown Unit")
		unit.quality = unit_def.get("quality", 4)
		unit.defense = unit_def.get("defense", 4)
		unit.size = unit_def.get("size", 1)
		unit.cost = unit_def.get("cost", 0)

		# Parse special rules
		var rules = unit_def.get("specialRules", [])
		for rule in rules:
			if rule is String:
				unit.special_rules.append(rule)
			elif rule is Dictionary:
				var rule_name = rule.get("name", "")
				var rule_rating = rule.get("rating", "")
				if not rule_rating.is_empty():
					unit.special_rules.append("%s(%s)" % [rule_name, str(rule_rating)])
				else:
					unit.special_rules.append(rule_name)

		# Parse equipment/loadout
		var equipment = unit_def.get("equipment", [])
		for equip in equipment:
			var weapon = _parse_weapon(equip)
			if weapon:
				unit.weapons.append(weapon)

		var loadout = unit_def.get("loadout", [])
		for item in loadout:
			var weapon = _parse_weapon(item)
			if weapon:
				unit.weapons.append(weapon)

	# Parse selected upgrades
	var selected_upgrades = list_unit.get("selectedUpgrades", [])
	for upgrade in selected_upgrades:
		var upgrade_id = upgrade.get("upgradeId", "")
		if not upgrade_id.is_empty():
			var upgrade_def = _find_upgrade_in_book(upgrade_id, book_data)
			if not upgrade_def.is_empty():
				var upgrade_name = upgrade_def.get("name", upgrade_id)
				unit.upgrades.append(upgrade_name)
				# Add upgrade cost
				unit.cost += upgrade_def.get("cost", 0)

	return unit


## Find unit definition in book data
func _find_unit_in_book(unit_id: String, book_data: Dictionary) -> Dictionary:
	if book_data.is_empty():
		return {}

	var units = book_data.get("units", [])
	for unit in units:
		if unit.get("id", "") == unit_id:
			return unit

	return {}


## Find upgrade definition in book data
func _find_upgrade_in_book(upgrade_id: String, book_data: Dictionary) -> Dictionary:
	if book_data.is_empty():
		return {}

	var upgrade_packages = book_data.get("upgradePackages", [])
	for package in upgrade_packages:
		var sections = package.get("sections", [])
		for section in sections:
			var options = section.get("options", [])
			for option in options:
				if option.get("id", "") == upgrade_id:
					return option

	return {}


## Parse a weapon from equipment/loadout data
func _parse_weapon(data) -> OPRWeapon:
	if data is String:
		var weapon = OPRWeapon.new()
		weapon.name = data
		return weapon

	if not data is Dictionary:
		return null

	var weapon = OPRWeapon.new()
	weapon.name = data.get("name", data.get("label", "Unknown Weapon"))
	weapon.range_value = data.get("range", 0)
	weapon.attacks = data.get("attacks", 1)
	weapon.count = data.get("count", 1)

	var rules = data.get("specialRules", [])
	for rule in rules:
		if rule is String:
			weapon.special_rules.append(rule)
		elif rule is Dictionary:
			var rule_name = rule.get("name", "")
			var rule_rating = rule.get("rating", "")
			if not rule_rating.is_empty():
				weapon.special_rules.append("%s(%s)" % [rule_name, str(rule_rating)])
			else:
				weapon.special_rules.append(rule_name)

	return weapon


## Create a sample/test army for development
static func create_test_army(player_id: int = 1) -> OPRArmy:
	var army = OPRArmy.new()
	army.id = "test_army_%d" % player_id
	army.name = "Test Army %d" % player_id
	army.game_system = "Grimdark Future"
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
