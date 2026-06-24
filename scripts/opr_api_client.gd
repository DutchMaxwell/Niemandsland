extends Node
class_name OPRApiClient
## OnePageRules Army Forge API Client
## Handles importing armies via Share-Link API and JSON files

signal army_loaded(army: OPRArmy)
signal import_failed(error: String)
signal loading_progress(message: String)

## OPR API base URL
const API_BASE_URL = "https://army-forge.onepagerules.com/api"

## HTTP request node for API calls
var _http_request: HTTPRequest

## Separate HTTP request node for army book fetches (to avoid conflicts)
var _book_http_request: HTTPRequest

## Cached army books (armyId -> book data)
var _army_books: Dictionary = {}

## Cached common/system rule responses (game-system id -> response data)
var _common_rules_cache: Dictionary = {}


## Army data structure
class OPRArmy:
	var id: String = ""
	var name: String = ""
	var game_system: String = ""  # e.g., "gf" (grimdark-future), "aof" (age-of-fantasy)
	var points: int = 0
	var player_id: int = 0  # Assigned player (1-4)
	var units: Array[OPRUnit] = []
	var model_count: int = 0
	var army_id: String = ""  # Army Book ID from API (e.g., "w7qor7b2kuifcyvk")
	var faction_name: String = ""  # Faction name from Army Book (e.g., "Alien Hives")
	var faction_folder: String = ""  # Normalized folder name (e.g., "alien_hives")
	var game_system_abbrev: String = ""  # Raw form: gf, gff, aof, aofs, aofr (for API calls)
	var rule_descriptions: Dictionary = {}  # special-rule name -> description text
	## The faction's spell list (from the army book). Each entry:
	## { "name": String, "threshold": int (spell-token cost to cast), "effect": String }.
	## Shown for caster units in the unit card + the casts dialog.
	var spells: Array = []

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
	## True if this unit is one half of an OPR "Combined" unit (two same-type
	## units merged into one larger unit). Both halves carry combined==true.
	var combined: bool = false
	## selectionId of the unit this one is joined to. For a Combined unit's
	## secondary half this points at the primary half; for a joined Hero it
	## points at the unit the Hero attached to.
	var join_to_unit: String = ""
	var name: String = ""
	var size: int = 1  # Number of models in unit
	var cost: int = 0  # Points cost
	var quality: int = 4  # Quality value (lower is better)
	var defense: int = 4  # Defense value (higher is better)
	var equipment: Array[String] = []
	## Per-model tool/equipment upgrades (non-weapon ArmyBookItems) carried by only a
	## SUBSET of the unit's models (count < size), e.g. "Synaptic Relay" on one model.
	## Each entry: {name: String, count: int}. Unit-wide items (count == size) are NOT
	## listed here; their granted rules still fold into special_rules. The
	## EquipmentDistributor pins these to specific models so the base ring labels them.
	var equipment_items: Array = []
	var special_rules: Array[String] = []
	## Display helper: item name -> [special-rule names it grants] (e.g. "Combat Shield" ->
	## ["Shielded"]). The granted rules ALSO stay in special_rules (functional / rules engine);
	## this map just lets the unit card show the item with a hover cascade instead of listing the
	## item and the rule it grants as flat siblings.
	var item_grants: Dictionary = {}
	var weapons: Array[OPRWeapon] = []
	var custom_name: String = ""  # User's nickname for the unit
	var upgrades: Array[String] = []  # Selected upgrade names
	var base_size_round: int = 32  # Recommended round base size in mm
	var base_size_square: int = 30  # Recommended square base size in mm
	var base_is_oval: bool = false  # True if base is oval (WIDTHxDEPTH format)
	## True for Age of Fantasy: Regiments — square/rectangular bases (rank-and-flank).
	var base_is_square: bool = false
	var base_width_mm: int = 32  # Width in mm (perpendicular to facing)
	var base_depth_mm: int = 32  # Depth in mm (in facing direction / "north")
	## True when the base was sized from Tough (no Army Forge recommendation) — a bracketless
	## vehicle/monster. Its base IS the intended footprint, so the model fits it exactly (no overhang),
	## unlike a small infantry round base where organic minis may spill over.
	var base_from_tough: bool = false
	## A mount/vehicle upgrade (e.g. a Combat Bike) brings its OWN base + model. When present:
	## mount_base = [is_oval, width_mm, depth_mm] (overrides the foot base on the carrier model) and
	## mount_name is the upgrade name (used to fuzzy-pick a faction mount/bike GLB).
	var mount_base: Array = []
	var mount_name: String = ""
	## Game system this unit was imported for (gf/gff/aof/aofs/aofr). Drives
	## regiment mode downstream; carried so it survives into GameUnit.unit_properties.
	var game_system: String = ""

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

	## Serialize the display-relevant profile so a peer's unit card can show the FULL loadout
	## (weapons, equipment, rules, base) for a remotely-synced unit — the card reads source_data via
	## _get_opr_unit(). Only the fields the card actually reads are included (issue #73), to keep the
	## wire/save payload lean. Round-trips through GameUnit.to_dict/from_dict.
	func to_dict() -> Dictionary:
		var weapon_dicts: Array = []
		for w in weapons:
			weapon_dicts.append(w.to_dict())
		return {
			"weapons": weapon_dicts,
			"equipment": equipment.duplicate(),
			"special_rules": special_rules.duplicate(),
			"base_is_oval": base_is_oval,
			"base_width_mm": base_width_mm,
			"base_depth_mm": base_depth_mm,
			"base_size_round": base_size_round,
		}

	static func from_dict(data: Dictionary) -> OPRUnit:
		var u := OPRUnit.new()
		for wd in data.get("weapons", []):
			if wd is Dictionary:
				u.weapons.append(OPRWeapon.from_dict(wd))
		for e in data.get("equipment", []):
			u.equipment.append(str(e))
		for r in data.get("special_rules", []):
			u.special_rules.append(str(r))
		u.base_is_oval = bool(data.get("base_is_oval", false))
		u.base_width_mm = int(data.get("base_width_mm", 32))
		u.base_depth_mm = int(data.get("base_depth_mm", 32))
		u.base_size_round = int(data.get("base_size_round", 32))
		return u


## Weapon data structure
class OPRWeapon:
	var name: String = ""
	var range_value: int = 0  # 0 = melee
	var attacks: int = 1
	var special_rules: Array[String] = []
	var count: int = 1
	## Name of the upgrade item that grants this weapon (e.g. a Weapon Team's HE Autocannon), or ""
	## for a normal loadout weapon. Granted weapons are shown in the unit card but NOT independently
	## distributed (build_loadout skips them) — they belong to the item's model, which already has
	## the special-equipment ring + enlarged base.
	var from_item: String = ""

	func get_display_text() -> String:
		var count_str = "" if count <= 1 else "%dx " % count
		var range_str = "Melee" if range_value == 0 else "%d\"" % range_value
		var text = "%s%s (%s, A%d)" % [count_str, name, range_str, attacks]
		if not special_rules.is_empty():
			text += " [%s]" % ", ".join(special_rules)
		return text

	func to_dict() -> Dictionary:
		return {
			"name": name,
			"range_value": range_value,
			"attacks": attacks,
			"special_rules": special_rules.duplicate(),
			"count": count,
			"from_item": from_item,
		}

	static func from_dict(data: Dictionary) -> OPRWeapon:
		var w := OPRWeapon.new()
		w.name = str(data.get("name", ""))
		w.range_value = int(data.get("range_value", 0))
		w.attacks = int(data.get("attacks", 1))
		w.count = int(data.get("count", 1))
		w.from_item = str(data.get("from_item", ""))
		for rule in data.get("special_rules", []):
			w.special_rules.append(str(rule))
		return w


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

	# Separate HTTP request for army book fetches
	_book_http_request = HTTPRequest.new()
	add_child(_book_http_request)


## Import army from a local JSON file (Army Forge export)
func import_from_file(file_path: String) -> OPRArmy:
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		push_error("OPRApiClient: Cannot open file: %s" % file_path)
		import_failed.emit("Cannot open file: %s" % file_path.get_file())
		return null

	var content = file.get_as_text()
	file.close()

	return await _parse_army_forge_json(content, file_path.get_file())


## Import army from a share link or list ID
## Share link format: https://army-forge.onepagerules.com/share?id=XXX&name=YYY
## Or just the list ID: XXX
func import_from_share_link(share_link_or_id: String) -> OPRArmy:
	var list_id = _extract_list_id(share_link_or_id)
	if list_id.is_empty():
		import_failed.emit("Invalid share URL or list ID")
		return null

	loading_progress.emit("Loading army from Army Forge...")

	# Call the TTS API endpoint
	var url = "%s/tts?id=%s" % [API_BASE_URL, list_id]

	var error = _http_request.request(url)
	if error != OK:
		push_error("OPRApiClient: HTTP request failed: %d" % error)
		import_failed.emit("Connection failed")
		return null

	# Wait for response
	var result = await _http_request.request_completed

	var response_code = result[1]
	var body = result[3]

	if response_code != 200:
		push_error("OPRApiClient: API returned %d" % response_code)
		import_failed.emit("API error: %d" % response_code)
		return null

	var json_text = body.get_string_from_utf8()
	return await _parse_tts_api_response(json_text)


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
		import_failed.emit("Invalid API response format")
		return null

	var data = json.data
	if not data is Dictionary:
		import_failed.emit("Invalid army data")
		return null

	var army = OPRArmy.new()

	# Parse army info
	army.id = data.get("id", str(Time.get_unix_time_from_system()))
	army.name = data.get("name", "Imported Army")
	army.game_system_abbrev = str(data.get("gameSystem", "gf"))
	army.game_system = _expand_game_system(army.game_system_abbrev)
	army.points = data.get("listPoints", 0)

	# Parse units - TTS API returns fully resolved units!
	var units_data = data.get("units", [])

	# Extract armyId from first unit (all units share the same armyId)
	if units_data.size() > 0:
		var first_unit = units_data[0]
		if first_unit is Dictionary:
			army.army_id = first_unit.get("armyId", "")

	for unit_data in units_data:
		var unit = _parse_tts_unit(unit_data, army.game_system_abbrev)
		if unit:
			army.units.append(unit)
			army.model_count += unit.size

	# Fold OPR "Combined" unit halves into single larger units (e.g. 2x[5] -> 1x[10]).
	# model_count is the sum of model sizes and is unchanged by merging.
	army.units = _merge_combined_units(army.units)

	# Fetch faction name from Army Book API using armyId
	if not army.army_id.is_empty():
		var book_data = await _fetch_army_book(army.army_id, army.game_system_abbrev)
		if not book_data.is_empty():
			army.faction_name = book_data.get("name", "")
			# Normalize faction name for folder: "Alien Hives" -> "alien_hives"
			army.faction_folder = army.faction_name.to_lower().replace(" ", "_").replace("-", "_")
			# Army-book special-rule descriptions (faction-specific take precedence).
			_extract_rule_descriptions(army, book_data)
			# Faction spell list (shown for caster units).
			_extract_spells(army, book_data)

	# Common/system rule descriptions (shared rules: Tough, AP, Fast, ...).
	if not army.game_system_abbrev.is_empty():
		await _fetch_common_rules(army)

	# Fallback: If Army Book API failed but we have a list name, try using that
	if army.faction_folder.is_empty() and not army.name.is_empty():
		var potential_folder = army.name.to_lower().replace(" ", "_").replace("-", "_")
		# Check if folder exists using DirAccess.open (works with res:// paths)
		var glb_path = "res://assets/miniatures/%s/glb/" % potential_folder
		var dir = DirAccess.open(glb_path)
		if dir:
			army.faction_name = army.name
			army.faction_folder = potential_folder

	print("OPRApiClient: Loaded from API '%s' - %d units, %d pts, %d models (faction: %s)" % [
		army.name, army.units.size(), army.points, army.model_count, army.faction_name
	])

	army_loaded.emit(army)
	return army


## Estimate a round base size (mm) from a unit's Tough value, used when Army Forge
## gives no base recommendation (common for vehicles / large monsters). Bands follow
## the Asgard rulebook height categories (Tough -> size class). 0 = leave unchanged.
static func _base_size_from_tough(tough: int) -> int:
	if tough >= 18:
		return 150  # Titans
	if tough >= 12:
		return 120  # Large monsters / giants / large vehicles
	if tough >= 9:
		return 80
	if tough >= 6:
		return 60   # Monsters / vehicles
	if tough >= 3:
		return 40   # Large infantry / cavalry
	return 0        # Normal infantry: keep the default base


## True if an Army Forge base value is a real recommendation. Army Forge sends
## bases:{round:"none"} for models without one (many vehicles / monsters), so the
## dict is non-empty but carries no usable size — those must fall back to Tough.
static func _is_usable_base_value(value) -> bool:
	if value is int or value is float:
		return value > 0
	if value is String:
		var s: String = value.strip_edges().to_lower()
		if s.is_empty() or s == "none" or s == "null" or s == "0":
			return false
		return "x" in s or s.is_valid_int() or s.is_valid_float()
	return false


## Read the Tough(x) value from a special_rules array (0 if none).
static func _tough_from_rules(rules: Array) -> int:
	for rule in rules:
		var s := String(rule)
		if s.begins_with("Tough("):
			var v := s.trim_prefix("Tough(").trim_suffix(")")
			if v.is_valid_int():
				return v.to_int()
	return 0


## Enlarge a unit's (round) base to a Tough-derived size when the current base is
## smaller — gives bracketless vehicles / large monsters a sensible base + model
## scale instead of defaulting to a tiny 32mm base. Never shrinks an existing base.
static func _apply_tough_base_fallback(unit: OPRUnit) -> void:
	var estimate := _base_size_from_tough(_tough_from_rules(unit.special_rules))
	if estimate <= unit.base_size_round:
		return
	unit.base_is_oval = false
	unit.base_size_round = estimate
	unit.base_width_mm = estimate
	unit.base_depth_mm = estimate
	unit.base_from_tough = true  # fit the model to this base (no overhang) — it's a vehicle/monster


## Parse a unit from TTS API response
func _parse_tts_unit(data: Dictionary, game_system_abbrev: String = "") -> OPRUnit:
	var unit = OPRUnit.new()

	unit.game_system = game_system_abbrev
	unit.id = data.get("id", str(randi()))
	unit.selection_id = data.get("selectionId", "")
	unit.combined = data.get("combined", false)
	var join_target = data.get("joinToUnit", null)
	unit.join_to_unit = join_target if join_target is String else ""
	unit.name = data.get("name", "Unknown Unit")
	unit.custom_name = data.get("customName", "")
	unit.size = data.get("size", 1)
	unit.cost = data.get("cost", 0)
	unit.quality = data.get("quality", 4)
	unit.defense = data.get("defense", 4)

	# Parse base sizes from Army Forge recommendations. Army Forge returns
	# bases:{round:"none"} for models without one (many vehicles / monsters), so a
	# non-empty dict is not proof of a real recommendation — require a usable value.
	var bases = data.get("bases", {})
	var round_size = bases.get("round", "") if bases is Dictionary else ""
	var square_size = bases.get("square", "") if bases is Dictionary else ""
	var is_regiments: bool = game_system_abbrev == "aofr"
	var had_base_recommendation: bool = false
	if is_regiments and _is_usable_base_value(square_size):
		had_base_recommendation = true
		# Age of Fantasy: Regiments uses square/rectangular bases. Reuse the oval
		# WIDTHxDEPTH parser (long side faces +Z / "north"); render as a box later.
		var parsed = _parse_base_size(square_size, 25)
		unit.base_is_square = true
		unit.base_is_oval = false
		unit.base_width_mm = clampi(parsed[1], 20, 150)
		unit.base_depth_mm = clampi(parsed[2], 20, 150)
		unit.base_size_round = max(unit.base_width_mm, unit.base_depth_mm)
		unit.base_size_square = unit.base_size_round
	elif _is_usable_base_value(round_size):
		had_base_recommendation = true
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

	# Parse the loadout. Weapons (attacks > 0) become unit.weapons. Non-weapon items
	# (ArmyBookItem) are tools/upgrades: when only a SUBSET of the unit's models carry
	# one (count < size, e.g. "Synaptic Relay" on one model) keep it as structured
	# per-model equipment so EquipmentDistributor can pin it to a model and the base
	# ring can label it. Unit-wide items (count == size) stay folded into special_rules
	# as before. Granted abilities (Caster(2), Spell Conduit, ...) always fold into
	# special_rules, regardless of where the item itself is shown.
	var loadout = data.get("loadout", data.get("equipment", []))
	for item in loadout:
		var weapon = _parse_tts_weapon(item)
		if weapon and weapon.attacks > 0:
			unit.weapons.append(weapon)
			continue
		if item is String:
			if not item.is_empty() and item not in unit.special_rules:
				unit.special_rules.append(item)
			continue
		if not (item is Dictionary):
			continue

		var item_name: String = item.get("name", item.get("label", ""))
		var item_count: int = _safe_int(item.get("count", unit.size), unit.size)
		var per_model: bool = unit.size > 1 and item_count > 0 and item_count < unit.size
		var granted: Array[String] = _granted_rules_of_item(item)
		# Remember which rules this item grants so the unit card can show the item with a hover
		# cascade (Combat Shield -> Shielded) instead of flat siblings. Functional folding into
		# special_rules below is unchanged.
		if not item_name.is_empty() and not granted.is_empty():
			unit.item_grants[item_name] = granted

		# Weapons the item grants (a Weapon Team's HE Autocannon + Crew) → show in the unit card's
		# Weapons list. Marked from_item so build_loadout does NOT distribute them again — they ride
		# with the item's model (which already carries the special-equipment ring + enlarged base).
		# Drop their names from the rules line (they're weapons now, not profile-less rules).
		for gw in _granted_weapons_of_item(item):
			gw.from_item = item_name
			gw.count = maxi(1, item_count)
			unit.weapons.append(gw)
			unit.special_rules.erase(gw.name)

		# A mount/vehicle upgrade (Combat Bike, Steed, ...) carries its OWN base + model. For a single-
		# model unit — the ~universal mount case (a mounted hero) — REPLACE the unit base with the
		# mount's, so it drives the model fit AND persists everywhere (save/load + MP) via the unit's
		# base properties. mount_name drives a faction mount-GLB pick at spawn. (Multi-model mounts are
		# vanishingly rare in OPR and not modelled here.)
		var item_bases = item.get("bases", null)
		if item_bases is Dictionary and not item_bases.is_empty():
			# Only mount/vehicle upgrades carry a base entry -> record the name for the GLB pick.
			unit.mount_name = item_name
			if _is_usable_base_value(item_bases.get("round", "")):
				# A real base (Combat Bike 60x35): for a single-model unit replace the foot base.
				var pb := _parse_base_size(item_bases.get("round", ""), 32)
				unit.mount_base = [bool(pb[0]), int(pb[1]), int(pb[2])]
				if unit.size <= 1:
					unit.base_is_oval = bool(pb[0])
					unit.base_is_square = false
					unit.base_width_mm = int(pb[1])
					unit.base_depth_mm = int(pb[2])
					unit.base_size_round = maxi(int(pb[1]), int(pb[2]))
			# else: a base-less monster mount (round:"none") sizes from its (large) Tough below.

		if per_model:
			# Carried by a subset → pin to specific model(s) and show on the base ring.
			# Carry the item's granted rules ON the entry so the EquipmentDistributor can
			# apply a per-model stat (Tough) to only the carrier model (see below).
			unit.equipment_items.append({"name": item_name, "count": item_count, "rules": granted})
			if not item_name.is_empty() and item_name not in unit.equipment:
				unit.equipment.append(item_name)
		elif not item_name.is_empty() and item_name not in unit.special_rules:
			# Unit-wide tool → keep its name in the unit's rule line (legacy behaviour).
			unit.special_rules.append(item_name)

		# Abilities the item grants stay unit-wide (rules engine / unit card), EXCEPT a
		# per-model Tough(X): OPR Core Rules — Tough is a PER-MODEL stat, so an upgrade
		# carried by a subset (weapon-team / special weapon) must not buff the base squad's
		# wounds. Its Tough rides on the equipment_items entry and is applied to the carrier
		# model only by EquipmentDistributor; folding it unit-wide here caused the squad-wide
		# Tough bug.
		for granted_rule in granted:
			if per_model and granted_rule.begins_with("Tough("):
				continue
			if granted_rule not in unit.special_rules:
				unit.special_rules.append(granted_rule)

	# Rule-only upgrades (Banner, Musician, ...) grant an ArmyBookRule DIRECTLY on the selected
	# upgrade option and are NOT mirrored into the resolved `loadout` (unlike item/weapon upgrades,
	# which are). Fold those into the unit's rules so the Banner/Musician actually show on the card.
	_apply_selected_upgrade_rules(unit, data.get("selectedUpgrades", []))

	# No base recommendation from Army Forge → estimate from Tough (vehicles/monsters).
	if not had_base_recommendation:
		_apply_tough_base_fallback(unit)

	return unit


## Folds rule-only upgrade gains (ArmyBookRule entries on a selectedUpgrade option) into the unit.
## Banner / Musician / Sergeant & co. are PER-MODEL roles ("upgrade up to N models with one") —
## physically ONE model carries the banner / plays music / leads — so they become equipment_items,
## which the EquipmentDistributor pins to a specific model and the base ring labels (exactly like a
## carried item such as "Banner of War"). A gain that affects ALL models (or the whole unit) folds
## into the unit-wide special_rules instead. Item/weapon gains are skipped: they already ride in the
## resolved `loadout`. One selectedUpgrade entry == one upgraded model.
func _apply_selected_upgrade_rules(unit, selected_upgrades: Array) -> void:
	var role_counts: Dictionary = {}      # rule name -> number of models that carry it
	var role_unit_wide: Dictionary = {}   # rule name -> true if any entry upgrades ALL models
	for su in selected_upgrades:
		if not (su is Dictionary):
			continue
		var option = su.get("option", {})
		if not (option is Dictionary):
			continue
		var affects_all := false
		var upgrade = su.get("upgrade", {})
		if upgrade is Dictionary:
			var affects = upgrade.get("affects", {})
			if affects is Dictionary and str(affects.get("type", "")) == "all":
				affects_all = true
		for gain in option.get("gains", []):
			if not (gain is Dictionary) or gain.get("type", "") != "ArmyBookRule":
				continue
			var rname := str(gain.get("name", gain.get("label", ""))).strip_edges()
			if rname.is_empty():
				continue
			var rating = gain.get("rating", null)
			var full := "%s(%s)" % [rname, _format_rating(rating)] if rating != null and str(rating) != "" else rname
			role_counts[full] = int(role_counts.get(full, 0)) + 1
			if affects_all:
				role_unit_wide[full] = true
	for full in role_counts:
		var count: int = int(role_counts[full])
		# A subset of the models carry it -> per-model role (base ring on the bearer). The whole unit
		# (count >= size, or an explicit "all models" upgrade) -> a unit-wide rule.
		if unit.size > 1 and not bool(role_unit_wide.get(full, false)) and count < unit.size:
			unit.equipment_items.append({"name": full, "count": count, "rules": []})
			if full not in unit.equipment:
				unit.equipment.append(full)
		elif full not in unit.special_rules:
			unit.special_rules.append(full)


## The special-rule names an upgrade item GRANTS, read from both the "specialRules"
## (weapon-style) and "content" (upgrade-style) fields, formatted like "Caster(2)".
func _granted_rules_of_item(item: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var raw: Array = []
	var raw_special = item.get("specialRules", [])
	if raw_special is Array:
		raw.append_array(raw_special)
	var raw_content = item.get("content", [])
	if raw_content is Array:
		raw.append_array(raw_content)
	for entry in raw:
		var granted := ""
		if entry is String:
			granted = entry
		elif entry is Dictionary:
			if entry.get("type", "") == "ArmyBookWeapon":
				continue  # a weapon profile (e.g. a Weapon Team's HE Autocannon) — surfaced as a
				# weapon in the unit card, not as a (profile-less) entry in the rules line
			var rule_name = entry.get("name", "")
			var rule_rating = entry.get("rating", null)
			if rule_rating != null and str(rule_rating) != "":
				granted = "%s(%s)" % [rule_name, _format_rating(rule_rating)]
			elif not rule_name.is_empty():
				granted = rule_name
		if not granted.is_empty() and granted not in result:
			result.append(granted)
	return result


## The weapons an upgrade item grants (e.g. a Weapon Team's "HE Autocannon" + "Crew"), parsed from
## the ArmyBookWeapon entries in its "content". Real weapon profiles → surfaced in the unit card's
## Weapons list instead of as profile-less names in the rules line.
func _granted_weapons_of_item(item: Dictionary) -> Array:
	var weapons: Array = []
	var raw_content = item.get("content", [])
	if not (raw_content is Array):
		return weapons
	for entry in raw_content:
		if entry is Dictionary and entry.get("type", "") == "ArmyBookWeapon":
			var w = _parse_tts_weapon(entry)
			if w and w.attacks > 0:
				weapons.append(w)
	return weapons


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
	# Handle null values explicitly (get() returns null if key exists but value is null)
	var range_val = data.get("range", 0)
	weapon.range_value = range_val if range_val != null else 0
	var attacks_val = data.get("attacks", 0)
	weapon.attacks = attacks_val if attacks_val != null else 0
	var count_val = data.get("count", 1)
	weapon.count = count_val if count_val != null else 1

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
	army.game_system_abbrev = str(data.get("gameSystem", "gf"))
	army.game_system = _expand_game_system(army.game_system_abbrev)
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
	var book_data = await _fetch_army_book(army_id, army.game_system_abbrev)

	for unit_data in units_data:
		var unit = _parse_unit_from_list(unit_data, book_data)
		if unit:
			army.units.append(unit)

	# Fold OPR "Combined" unit halves into single larger units (e.g. 2x[5] -> 1x[10]).
	army.units = _merge_combined_units(army.units)

	# Special-rule descriptions: army-book first, then shared system rules.
	army.army_id = army_id
	if not book_data.is_empty():
		_extract_rule_descriptions(army, book_data)
	if not army.game_system_abbrev.is_empty():
		await _fetch_common_rules(army)

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
func _fetch_army_book(army_id: String, game_system_abbrev: String) -> Dictionary:
	if army_id.is_empty():
		return {}

	# Check cache first
	if _army_books.has(army_id):
		return _army_books[army_id]

	loading_progress.emit("Loading army book data...")

	# The army-book endpoint REQUIRES the ?gameSystem= query param — without it the API
	# returns an empty body, so the faction's special rules + name would be missing.
	var gs_id := _game_system_id(game_system_abbrev)
	var url = "%s/army-books/%s?gameSystem=%d" % [API_BASE_URL, army_id, gs_id]

	var error = _book_http_request.request(url)
	if error != OK:
		push_warning("OPRApiClient: Failed to request army book: %d" % error)
		return {}

	# Wait for response
	var result = await _book_http_request.request_completed
	var response_code = result[1]
	var body = result[3]

	if response_code != 200:
		push_warning("OPRApiClient: Army book API returned %d" % response_code)
		return {}

	# Parse the response directly here
	var json = JSON.new()
	var parse_result = json.parse(body.get_string_from_utf8())
	if parse_result != OK:
		push_warning("OPRApiClient: Failed to parse army book response")
		return {}

	var data = json.data
	if data is Dictionary and data.has("name"):
		_army_books[army_id] = data
		return data

	return {}


# =============================================================================
# Special-rule descriptions (army-forge API)
# =============================================================================

## Maps a game-system abbreviation to the army-forge API game-system id.
static func _game_system_id(abbrev: String) -> int:
	match abbrev:
		"gf": return 2
		"gff": return 3
		"aof": return 4
		"aofs": return 5
		"aofr": return 6
		_: return 2


## Pulls special-rule name -> description pairs from an army-book response.
## Army-book rules take precedence over the shared common rules.
func _extract_rule_descriptions(army: OPRArmy, book_data: Dictionary) -> void:
	for key in ["specialRules", "customRules"]:
		var rules = book_data.get(key, [])
		if not (rules is Array):
			continue
		for rule in rules:
			if rule is Dictionary:
				var rname := str(rule.get("name", ""))
				var desc := str(rule.get("description", ""))
				if not rname.is_empty() and not desc.is_empty():
					army.rule_descriptions[rname] = desc


## Parse the faction's spell list from the army book. Each spell carries its casting cost
## (threshold = spell tokens to spend) + effect text; shown for caster units.
func _extract_spells(army: OPRArmy, book_data: Dictionary) -> void:
	var spells = book_data.get("spells", [])
	if not (spells is Array):
		return
	for sp in spells:
		if not (sp is Dictionary):
			continue
		var sname := str(sp.get("name", ""))
		if sname.is_empty():
			continue
		army.spells.append({
			"name": sname,
			"threshold": int(sp.get("threshold", 0)),
			"effect": str(sp.get("effect", "")),
		})


## The radius (inches) a spell projects from the caster, parsed from its effect text — the first
## `<n>"` token (e.g. "...within 12\", which..." → 12). 0 if the spell has no range (self /
## army-wide), in which case no preview ring is shown on hover.
static func spell_radius_inches(effect: String) -> int:
	var re := RegEx.new()
	if re.compile("(\\d+)\\s*[\"”]") != OK:
		return 0
	var m := re.search(effect)
	return int(m.get_string(1)) if m else 0


## Fetches the shared/common rule descriptions for the army's game system and merges
## them in WITHOUT overwriting army-book-specific descriptions. Cached per system.
func _fetch_common_rules(army: OPRArmy) -> void:
	var gs_id := _game_system_id(army.game_system_abbrev)
	if _common_rules_cache.has(gs_id):
		_merge_common_descriptions(army, _common_rules_cache[gs_id])
		return
	var url = "%s/rules/common/%d" % [API_BASE_URL, gs_id]
	var error = _book_http_request.request(url)
	if error != OK:
		push_warning("OPRApiClient: Failed to request common rules: %d" % error)
		return
	var result = await _book_http_request.request_completed
	var response_code = result[1]
	var body = result[3]
	if response_code != 200:
		push_warning("OPRApiClient: Common rules API returned %d" % response_code)
		return
	var json = JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK or not (json.data is Dictionary):
		push_warning("OPRApiClient: Failed to parse common rules response")
		return
	_common_rules_cache[gs_id] = json.data
	_merge_common_descriptions(army, json.data)


## Merges common "rules" + "traits" ({name, description}) into the army's map,
## keeping any army-book-specific description already present (precedence).
func _merge_common_descriptions(army: OPRArmy, data: Dictionary) -> void:
	for key in ["rules", "traits"]:
		var arr = data.get(key, [])
		if not (arr is Array):
			continue
		for rule in arr:
			if rule is Dictionary:
				var rname := str(rule.get("name", ""))
				var desc := str(rule.get("description", ""))
				if rname.is_empty() or desc.is_empty():
					continue
				if not army.rule_descriptions.has(rname):
					army.rule_descriptions[rname] = desc


## Returns the description for a special rule, or "" if unknown. Handles
## parameterised rules: "Tough(3)" / "AP(1)" fall back to the base "Tough" / "AP".
static func get_rule_description(rule_name: String, army: OPRArmy) -> String:
	if not army:
		return ""
	if army.rule_descriptions.has(rule_name):
		return army.rule_descriptions[rule_name]
	var paren := rule_name.find("(")
	if paren > 0:
		var base := rule_name.substr(0, paren).strip_edges()
		if army.rule_descriptions.has(base):
			return army.rule_descriptions[base]
	return ""


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


## Parse a unit from list data, enriching with book data if available
func _parse_unit_from_list(list_unit: Dictionary, book_data: Dictionary) -> OPRUnit:
	var unit = OPRUnit.new()

	var unit_def_id = list_unit.get("id", "")
	var selection_id = list_unit.get("selectionId", "")

	unit.id = unit_def_id
	unit.selection_id = selection_id
	unit.combined = list_unit.get("combined", false)
	var join_target = list_unit.get("joinToUnit", null)
	unit.join_to_unit = join_target if join_target is String else ""

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

	# This path carries no base recommendation, so size the base from Tough
	# (only enlarges high-Tough vehicles/monsters; normal infantry keep the default).
	_apply_tough_base_fallback(unit)

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


## Folds OPR "Combined" unit halves into single larger units.
## OPR rule (core): two units of the SAME type may be Combined into one unit at
## list-building (e.g. 2x[5 models] -> 1x[10 models]). Army Forge exports both
## halves as separate entries, each with combined==true; the secondary half's
## joinToUnit points at the primary (anchor) half's selectionId. We fold the
## secondary into the anchor - summing model count, cost and weapon counts - and
## drop it from the unit list.
## A joined Hero (combined==false, joinToUnit set) is a distinct model and is
## intentionally left as its own unit.
func _merge_combined_units(units: Array[OPRUnit]) -> Array[OPRUnit]:
	# Index the anchor halves (combined, no joinToUnit) by their selectionId.
	var anchors_by_selection: Dictionary = {}
	for unit in units:
		if unit.combined and unit.join_to_unit.is_empty() and not unit.selection_id.is_empty():
			anchors_by_selection[unit.selection_id] = unit

	var merged: Array[OPRUnit] = []
	for unit in units:
		# Secondary half of a Combined unit: fold it into its anchor and drop it.
		if unit.combined and not unit.join_to_unit.is_empty() and anchors_by_selection.has(unit.join_to_unit):
			var anchor: OPRUnit = anchors_by_selection[unit.join_to_unit]
			anchor.size += unit.size
			anchor.cost += unit.cost
			_merge_weapon_counts(anchor.weapons, unit.weapons)
			continue
		merged.append(unit)

	return merged


## Folds `extra` weapons into `target`, summing counts for identical weapons
## (same name/range/attacks/rules) so a merged unit shows e.g. "Rifle x10".
func _merge_weapon_counts(target: Array[OPRWeapon], extra: Array[OPRWeapon]) -> void:
	for weapon in extra:
		var existing_match: OPRWeapon = null
		for existing in target:
			if existing.name == weapon.name \
					and existing.range_value == weapon.range_value \
					and existing.attacks == weapon.attacks \
					and existing.special_rules == weapon.special_rules:
				existing_match = existing
				break
		if existing_match:
			existing_match.count += weapon.count
		else:
			target.append(weapon)


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
