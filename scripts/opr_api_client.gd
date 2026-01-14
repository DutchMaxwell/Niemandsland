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
	var base_size_round: int = 32  # Recommended round base size in mm
	var base_size_square: int = 30  # Recommended square base size in mm
	var base_is_oval: bool = false  # True if base is oval (WIDTHxDEPTH format)
	var base_width_mm: int = 32  # Width in mm (perpendicular to facing)
	var base_depth_mm: int = 32  # Depth in mm (in facing direction / "north")

	func get_display_name() -> String:
		if not custom_name.is_empty():
			return custom_name
		if size > 1:
			return "%s [%d]" % [name, size]
		return name

	## Get base radius in meters (for 3D spawning)
	func get_base_radius_meters() -> float:
		return (base_size_round / 2.0) * 0.001  # mm to meters

	## Get base diameter in meters
	func get_base_diameter_meters() -> float:
		return base_size_round * 0.001  # mm to meters

	func get_stats_text() -> String:
		var lines: Array[String] = []
		lines.append("[b]%s[/b]" % get_display_name())
		lines.append("Q%d+ | D%d+" % [quality, defense])
		var base_text = "%dx%dmm oval" % [base_width_mm, base_depth_mm] if base_is_oval else "%dmm round" % base_size_round
		lines.append("%d models | %d pts | %s base" % [size, cost, base_text])

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


## Safely convert a value to int (handles string, int, float, null)
## Also handles oval base format like "60x35" - returns the larger dimension
static func _safe_int(value, default: int = 0) -> int:
	if value == null:
		return default
	if value is int:
		return value
	if value is float:
		return int(value)
	if value is String:
		# Handle oval base format like "60x35" or "120x92"
		if "x" in value:
			var parts = value.split("x")
			if parts.size() >= 2:
				var width = parts[0].to_int() if parts[0].is_valid_int() else 0
				var depth = parts[1].to_int() if parts[1].is_valid_int() else 0
				# Return the larger dimension for sizing
				return max(width, depth)
		if value.is_valid_int():
			return value.to_int()
		elif value.is_valid_float():
			return int(value.to_float())
	return default


## Parse base size value and return [is_oval, width, depth]
## For round bases: returns [false, size, size]
## For oval bases like "60x35": returns [true, 35, 60] (width perpendicular to facing, depth in facing direction)
static func _parse_base_size(value, default: int = 32) -> Array:
	if value == null:
		return [false, default, default]

	if value is int:
		return [false, value, value]

	if value is float:
		return [false, int(value), int(value)]

	if value is String:
		# Handle oval base format like "60x35" or "120x92" (WIDTHxDEPTH)
		if "x" in value:
			var parts = value.split("x")
			if parts.size() >= 2:
				var first = parts[0].to_int() if parts[0].is_valid_int() else default
				var second = parts[1].to_int() if parts[1].is_valid_int() else default
				# Army Forge format: first number is WIDTH (larger), second is DEPTH (smaller)
				# But for miniatures, long side faces forward (north)
				# So: depth (facing direction) = larger value, width (perpendicular) = smaller value
				var depth = max(first, second)  # Long side in facing direction
				var width = min(first, second)  # Short side perpendicular
				return [true, width, depth]
		if value.is_valid_int():
			var size = value.to_int()
			return [false, size, size]
		elif value.is_valid_float():
			var size = int(value.to_float())
			return [false, size, size]

	return [false, default, default]


func _ready() -> void:
	_http_request = HTTPRequest.new()
	add_child(_http_request)
	_http_request.request_completed.connect(_on_request_completed)


## Import army from a local file (JSON or TXT Army Forge export)
func import_from_file(file_path: String) -> OPRArmy:
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		push_error("OPRApiClient: Cannot open file: %s" % file_path)
		import_failed.emit("Cannot open file: %s" % file_path.get_file())
		return null

	var content = file.get_as_text()
	file.close()

	# Detect format: Text export starts with "++"
	if content.strip_edges().begins_with("++"):
		return _parse_text_export(content, file_path.get_file())
	else:
		return await _parse_army_forge_json(content, file_path.get_file())


## Import army from a share link or list ID
## Share link format: https://army-forge.onepagerules.com/share?id=XXX&name=YYY
## Or just the list ID: XXX
func import_from_share_link(share_link_or_id: String) -> OPRArmy:
	var list_id = _extract_list_id(share_link_or_id)
	if list_id.is_empty():
		import_failed.emit("Ungültige Share-URL oder List-ID")
		return null

	loading_progress.emit("Lade Armee von Army Forge...")

	# Call the TTS API endpoint
	var url = "%s/tts?id=%s" % [API_BASE_URL, list_id]
	print("OPRApiClient: Fetching from %s" % url)

	var error = _http_request.request(url)
	if error != OK:
		push_error("OPRApiClient: HTTP request failed: %d" % error)
		import_failed.emit("Verbindung fehlgeschlagen")
		return null

	# Wait for response
	var result = await _http_request.request_completed

	var response_code = result[1]
	var body = result[3]

	if response_code != 200:
		push_error("OPRApiClient: API returned %d" % response_code)
		import_failed.emit("API-Fehler: %d" % response_code)
		return null

	var json_text = body.get_string_from_utf8()
	return _parse_tts_api_response(json_text)


## Extract list ID from share link or raw ID
func _extract_list_id(input: String) -> String:
	input = input.strip_edges()

	# If it's a URL, extract the id parameter
	if input.begins_with("http"):
		# Parse URL: https://army-forge.onepagerules.com/share?id=XXX&name=YYY
		var id_start = input.find("id=")
		if id_start < 0:
			return ""
		id_start += 3  # Skip "id="
		var id_end = input.find("&", id_start)
		if id_end < 0:
			id_end = input.length()
		return input.substr(id_start, id_end - id_start)

	# Otherwise assume it's a raw ID
	return input


## Parse the TTS API response (contains full resolved unit data!)
func _parse_tts_api_response(json_text: String) -> OPRArmy:
	var json = JSON.new()
	var error = json.parse(json_text)

	if error != OK:
		push_error("OPRApiClient: JSON parse error: %s" % json.get_error_message())
		import_failed.emit("Ungültiges API-Response Format")
		return null

	var data = json.data
	if not data is Dictionary:
		import_failed.emit("Ungültige Armee-Daten")
		return null

	var army = OPRArmy.new()

	# Parse army info
	army.id = data.get("listId", str(Time.get_unix_time_from_system()))
	army.name = data.get("listName", "Imported Army")
	army.game_system = _expand_game_system(data.get("gameSystem", "gf"))
	army.points = data.get("listPoints", 0)

	# Parse units - TTS API returns fully resolved units!
	var units_data = data.get("units", [])
	for unit_data in units_data:
		var unit = _parse_tts_unit(unit_data)
		if unit:
			army.units.append(unit)
			army.model_count += unit.size

	print("OPRApiClient: Loaded from API '%s' - %d units, %d pts, %d models" % [
		army.name, army.units.size(), army.points, army.model_count
	])

	army_loaded.emit(army)
	return army


## Parse a unit from TTS API response
func _parse_tts_unit(data: Dictionary) -> OPRUnit:
	var unit = OPRUnit.new()

	unit.id = data.get("id", str(randi()))
	unit.name = data.get("name", "Unknown Unit")
	unit.custom_name = data.get("customName", "")
	unit.size = data.get("size", 1)
	unit.cost = data.get("cost", 0)
	unit.quality = data.get("quality", 4)
	unit.defense = data.get("defense", 4)

	# Parse base sizes from Army Forge recommendations
	var bases = data.get("bases", {})
	if bases is Dictionary and not bases.is_empty():
		var round_size = bases.get("round", "32")
		var square_size = bases.get("square", "30")
		# Parse base size including oval format like "60x35"
		var parsed = _parse_base_size(round_size, 32)
		unit.base_is_oval = parsed[0]
		unit.base_width_mm = clampi(parsed[1], 20, 150)
		unit.base_depth_mm = clampi(parsed[2], 20, 150)
		# base_size_round stores the larger dimension for compatibility
		unit.base_size_round = max(unit.base_width_mm, unit.base_depth_mm)
		unit.base_size_square = _safe_int(square_size, 30)
		unit.base_size_square = clampi(unit.base_size_square, 20, 150)

	# Parse special rules (TTS API uses "rules" field, not "specialRules")
	var rules_field = data.get("rules", null)
	var special_rules_field = data.get("specialRules", null)
	print("DEBUG: Unit '%s' - rules_field: %s" % [unit.name, rules_field])
	print("DEBUG: Unit '%s' - specialRules_field: %s" % [unit.name, special_rules_field])

	var rules = []
	if rules_field is Array:
		rules = rules_field
	elif special_rules_field is Array:
		rules = special_rules_field
	for rule in rules:
		if rule is String:
			unit.special_rules.append(rule)
		elif rule is Dictionary:
			var rule_name = rule.get("name", "")
			var rule_rating = rule.get("rating", null)
			if rule_rating != null and str(rule_rating) != "":
				unit.special_rules.append("%s(%s)" % [rule_name, _format_rating(rule_rating)])
			elif not rule_name.is_empty():
				unit.special_rules.append(rule_name)

	# Parse equipment/loadout (weapons only - items with attacks > 0)
	var loadout = data.get("loadout", data.get("equipment", []))
	print("DEBUG: Parsing loadout with %d items" % loadout.size())
	for item in loadout:
		print("DEBUG: Loadout item: ", item)
		var weapon = _parse_tts_weapon(item)
		if weapon and weapon.attacks > 0:
			unit.weapons.append(weapon)
		else:
			# Items without attacks are upgrades/equipment, not weapons
			if item is String:
				if not item.is_empty() and item not in unit.special_rules:
					unit.special_rules.append(item)
			elif item is Dictionary:
				# Add the item name (e.g., "Psychic Synapses")
				var item_name = item.get("name", item.get("label", ""))
				if not item_name.is_empty() and item_name not in unit.special_rules:
					unit.special_rules.append(item_name)

				# IMPORTANT: Also add special rules GRANTED by the upgrade (e.g., "Caster(2)")
				# This is where upgrades like "Psychic Synapses" grant abilities like Caster
				var item_rules = item.get("specialRules", [])
				print("DEBUG: Item '%s' has specialRules: %s" % [item_name, item_rules])
				for item_rule in item_rules:
					var granted_rule = ""
					if item_rule is String:
						granted_rule = item_rule
					elif item_rule is Dictionary:
						var rule_name = item_rule.get("name", "")
						var rule_rating = item_rule.get("rating", null)
						if rule_rating != null and str(rule_rating) != "":
							granted_rule = "%s(%s)" % [rule_name, _format_rating(rule_rating)]
						elif not rule_name.is_empty():
							granted_rule = rule_name

					if not granted_rule.is_empty() and granted_rule not in unit.special_rules:
						print("DEBUG: Adding granted rule: %s" % granted_rule)
						unit.special_rules.append(granted_rule)

	print("DEBUG: Final special_rules for unit: %s" % [unit.special_rules])
	return unit


## Parse a weapon from TTS API response
## Returns null for non-weapon items (string items or items without attacks)
func _parse_tts_weapon(data) -> OPRWeapon:
	# String items are equipment/abilities, not weapons
	if data is String:
		return null

	if not data is Dictionary:
		return null

	var weapon = OPRWeapon.new()
	weapon.name = data.get("name", data.get("label", "Unknown"))
	weapon.range_value = data.get("range", 0)
	weapon.attacks = data.get("attacks", 0)  # Default 0 to detect non-weapons
	weapon.count = data.get("count", 1)

	var rules = data.get("specialRules", [])
	for rule in rules:
		if rule is String:
			weapon.special_rules.append(rule)
		elif rule is Dictionary:
			var rule_name = rule.get("name", "")
			var rule_rating = rule.get("rating", null)
			if rule_rating != null and str(rule_rating) != "":
				weapon.special_rules.append("%s(%s)" % [rule_name, _format_rating(rule_rating)])
			elif not rule_name.is_empty():
				weapon.special_rules.append(rule_name)

	return weapon


## Format rating value - removes decimal places for whole numbers (1.0 -> 1)
func _format_rating(value) -> String:
	if value is float:
		# Check if it's a whole number
		if value == int(value):
			return str(int(value))
		return str(value)
	return str(value)


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


## Parse Army Forge TEXT export (contains all resolved data)
## Format: ++ Army Name - Faction (version) [Game Points] [Unit Count] ++
func _parse_text_export(text: String, source_name: String = "") -> OPRArmy:
	var army = OPRArmy.new()
	army.id = str(Time.get_unix_time_from_system())

	var lines = text.split("\n")
	var current_unit: OPRUnit = null

	for line in lines:
		line = line.strip_edges()
		if line.is_empty():
			continue

		# Parse header: ++ Army Name - Faction (version) [GF 3000pts] [8 Units] ++
		if line.begins_with("++") and line.ends_with("++"):
			var header = line.trim_prefix("++").trim_suffix("++").strip_edges()
			_parse_header(header, army)
			continue

		# Parse joined unit indicator
		if line.begins_with("| Joined to:"):
			continue

		# Check if this is a unit line (has Q#+ D#+ pattern)
		var unit_regex = RegEx.new()
		# Pattern: [Nx] Unit Name [size] Q#+ D#+ | pts | Special Rules
		unit_regex.compile("^(\\d+x\\s+)?(.+?)\\s*\\[(\\d+)\\]\\s+Q(\\d+)\\+\\s+D(\\d+)\\+\\s*\\|\\s*(\\d+)pts\\s*\\|\\s*(.*)$")
		var unit_match = unit_regex.search(line)

		if unit_match:
			# Save previous unit
			if current_unit:
				army.units.append(current_unit)

			current_unit = OPRUnit.new()
			current_unit.id = str(randi())

			# Parse multiplier (e.g., "2x")
			var multiplier_str = unit_match.get_string(1).strip_edges()
			var multiplier = 1
			if not multiplier_str.is_empty():
				multiplier = multiplier_str.trim_suffix("x").to_int()

			current_unit.name = unit_match.get_string(2).strip_edges()
			current_unit.size = unit_match.get_string(3).to_int()
			current_unit.quality = unit_match.get_string(4).to_int()
			current_unit.defense = unit_match.get_string(5).to_int()
			current_unit.cost = unit_match.get_string(6).to_int()

			# Parse special rules
			var rules_str = unit_match.get_string(7).strip_edges()
			if not rules_str.is_empty():
				current_unit.special_rules = _parse_special_rules_text(rules_str)

			# If there's a multiplier, we need to duplicate units
			if multiplier > 1:
				# Add the first unit
				army.units.append(current_unit)
				# Add duplicates
				for i in range(multiplier - 1):
					var dup_unit = OPRUnit.new()
					dup_unit.id = str(randi())
					dup_unit.name = current_unit.name
					dup_unit.size = current_unit.size
					dup_unit.quality = current_unit.quality
					dup_unit.defense = current_unit.defense
					dup_unit.cost = current_unit.cost
					dup_unit.special_rules = current_unit.special_rules.duplicate()
					army.units.append(dup_unit)
				current_unit = army.units[-1]  # Point to last for weapon parsing

		elif current_unit and not line.begins_with("++"):
			# This should be a weapons line
			var weapons = _parse_weapons_text(line)
			for w in weapons:
				current_unit.weapons.append(w)
			# Apply weapons to all duplicated units if applicable
			# (weapons are added to the last unit reference)

	# Add the last unit
	if current_unit and not army.units.has(current_unit):
		army.units.append(current_unit)

	# Calculate model count
	for unit in army.units:
		army.model_count += unit.size

	if army.name.is_empty():
		army.name = source_name.get_basename()

	print("OPRApiClient: Parsed TEXT export '%s' - %d units, %d pts, %d models" % [
		army.name, army.units.size(), army.points, army.model_count
	])

	army_loaded.emit(army)
	return army


## Parse header line from text export
func _parse_header(header: String, army: OPRArmy) -> void:
	# Format: Army Name - Faction (version) [GF 3000pts] [8 Units]

	# Extract points
	var pts_regex = RegEx.new()
	pts_regex.compile("\\[(\\w+)\\s+(\\d+)pts\\]")
	var pts_match = pts_regex.search(header)
	if pts_match:
		army.game_system = _expand_game_system(pts_match.get_string(1).to_lower())
		army.points = pts_match.get_string(2).to_int()

	# Extract army name (before the first bracket or dash-separated parts)
	var name_part = header
	var bracket_pos = header.find("[")
	if bracket_pos > 0:
		name_part = header.left(bracket_pos).strip_edges()

	# Try to get just the army name (usually first part before " - ")
	var parts = name_part.split(" - ")
	if parts.size() > 0:
		army.name = parts[0].strip_edges()


## Parse special rules from text format
func _parse_special_rules_text(rules_str: String) -> Array[String]:
	var rules: Array[String] = []

	# Regex to remove count prefix like "3x"
	var count_regex = RegEx.new()
	count_regex.compile("^\\d+x\\s+")

	# Split by comma, but be careful with rules like "Tough(3)"
	var current_rule = ""
	var paren_depth = 0

	for c in rules_str:
		if c == '(':
			paren_depth += 1
			current_rule += c
		elif c == ')':
			paren_depth -= 1
			current_rule += c
		elif c == ',' and paren_depth == 0:
			var rule = current_rule.strip_edges()
			rule = count_regex.sub(rule, "")
			if not rule.is_empty():
				rules.append(rule)
			current_rule = ""
		else:
			current_rule += c

	# Don't forget the last rule
	var last_rule = current_rule.strip_edges()
	last_rule = count_regex.sub(last_rule, "")
	if not last_rule.is_empty():
		rules.append(last_rule)

	return rules


## Parse weapons from text format
## Format: Weapon Name (Range", A#, Rules), ...
func _parse_weapons_text(line: String) -> Array[OPRWeapon]:
	var weapons: Array[OPRWeapon] = []

	# Split by "), " to separate weapons
	var weapon_strs = line.split("), ")

	for ws in weapon_strs:
		ws = ws.strip_edges()
		if ws.is_empty():
			continue

		# Add back the closing paren if it was stripped
		if not ws.ends_with(")"):
			ws += ")"

		var weapon = _parse_single_weapon_text(ws)
		if weapon:
			weapons.append(weapon)

	return weapons


## Parse a single weapon from text format
## Format: [Nx] Weapon Name (Range", A#, Rules)
func _parse_single_weapon_text(weapon_str: String) -> OPRWeapon:
	var weapon = OPRWeapon.new()

	# Check for count prefix (e.g., "3x")
	var count_regex = RegEx.new()
	count_regex.compile("^(\\d+)x\\s+")
	var count_match = count_regex.search(weapon_str)
	if count_match:
		weapon.count = count_match.get_string(1).to_int()
		weapon_str = weapon_str.substr(count_match.get_end())

	# Find the opening parenthesis to separate name from stats
	var paren_pos = weapon_str.find("(")
	if paren_pos < 0:
		weapon.name = weapon_str.strip_edges()
		return weapon

	weapon.name = weapon_str.left(paren_pos).strip_edges()
	var stats_str = weapon_str.substr(paren_pos + 1).trim_suffix(")").strip_edges()

	# Parse stats inside parentheses
	var stats_parts = stats_str.split(",")
	for part in stats_parts:
		part = part.strip_edges()

		# Check for range (e.g., "24"")
		if part.ends_with("\""):
			weapon.range_value = part.trim_suffix("\"").to_int()
		# Check for attacks (e.g., "A3")
		elif part.begins_with("A") and part.substr(1).is_valid_int():
			weapon.attacks = part.substr(1).to_int()
		# Everything else is a special rule
		elif not part.is_empty():
			weapon.special_rules.append(part)

	return weapon


## Fetch army book data from OPR API
func _fetch_army_book(army_id: String, _game_system: String) -> Dictionary:
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
		var str_weapon = OPRWeapon.new()
		str_weapon.name = data
		return str_weapon

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
