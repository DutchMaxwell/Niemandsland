extends Node
class_name WGSClient
## Wargaming Simulator (Udo's 3dWorld) Client
## Handles importing/exporting game states from WGS format
## WGS is designed for asynchronous web-based play, OpenTTS for direct desktop play

signal game_loaded(game: WGSGame)
signal import_failed(error: String)
signal export_ready(data: String)

## Conversion factor: 1 inch = 0.0254 meters
const INCH_TO_METER: float = 0.0254

## CSS Color name to Godot Color mapping
const CSS_COLORS = {
	"blanchedalmond": Color(1.0, 0.92, 0.80),
	"blue": Color(0.0, 0.0, 1.0),
	"red": Color(1.0, 0.0, 0.0),
	"green": Color(0.0, 0.5, 0.0),
	"yellow": Color(1.0, 1.0, 0.0),
	"orange": Color(1.0, 0.65, 0.0),
	"purple": Color(0.5, 0.0, 0.5),
	"pink": Color(1.0, 0.75, 0.8),
	"brown": Color(0.65, 0.16, 0.16),
	"gray": Color(0.5, 0.5, 0.5),
	"grey": Color(0.5, 0.5, 0.5),
	"white": Color(1.0, 1.0, 1.0),
	"black": Color(0.0, 0.0, 0.0),
	"cyan": Color(0.0, 1.0, 1.0),
	"magenta": Color(1.0, 0.0, 1.0),
	"lime": Color(0.0, 1.0, 0.0),
	"navy": Color(0.0, 0.0, 0.5),
	"teal": Color(0.0, 0.5, 0.5),
	"olive": Color(0.5, 0.5, 0.0),
	"maroon": Color(0.5, 0.0, 0.0),
	"silver": Color(0.75, 0.75, 0.75),
	"gold": Color(1.0, 0.84, 0.0),
	"coral": Color(1.0, 0.5, 0.31),
	"salmon": Color(0.98, 0.5, 0.45),
	"khaki": Color(0.94, 0.9, 0.55),
	"crimson": Color(0.86, 0.08, 0.24),
	"darkblue": Color(0.0, 0.0, 0.55),
	"darkgreen": Color(0.0, 0.39, 0.0),
	"darkred": Color(0.55, 0.0, 0.0),
}

## WGS Game state container
class WGSGame:
	var game_id: String = ""
	var table_width: float = 72.0  # Table width in inches (default 6ft)
	var table_depth: float = 48.0  # Table depth in inches (default 4ft)
	var units: Array[WGSUnit] = []
	var log_entries: Array[String] = []
	var notes: String = ""

	func get_unit_count() -> int:
		return units.size()

	func get_model_count() -> int:
		var count = 0
		for unit in units:
			count += unit.model_count
		return count

	func get_table_size_feet() -> Vector2:
		return Vector2(table_width / 12.0, table_depth / 12.0)

	func get_table_size_meters() -> Vector2:
		return Vector2(table_width * WGSClient.INCH_TO_METER, table_depth * WGSClient.INCH_TO_METER)


## WGS Unit data structure
class WGSUnit:
	var index: int = 0  # Line index in the file
	var base_size: float = 1.0  # Base size in inches
	var base_width: float = 1.0  # For multi-base units
	var base_depth: float = 1.0  # For multi-base units
	var columns: int = 1  # Models per row
	var rows: int = 1  # Number of rows
	var model_count: int = 1  # Total models
	var is_multibase: bool = false
	var position_x: float = 0.0  # X position in inches
	var position_y: float = 0.0  # Y position in inches (maps to Z in 3D)
	var color: Color = Color.GRAY
	var color_name: String = "gray"
	var angle: float = 0.0  # Rotation in radians
	var image_id: int = -1  # Custom image ID
	var name: String = ""
	var description: String = ""
	var full_text: String = ""  # Raw text with escapes

	# Parsed stats (from OPR-style notation)
	var quality: int = 0  # Q value (0 = not specified)
	var defense: int = 0  # D value (0 = not specified)
	var points: int = 0
	var weapons: Array[String] = []
	var special_rules: Array[String] = []
	var tags: Array[String] = []  # e.g., #scaf2#, #norotation#

	func get_display_name() -> String:
		if name.is_empty():
			return "Unit %d" % index
		return name

	func get_position_3d() -> Vector3:
		# WGS uses inches, OpenTTS uses meters
		# Y in WGS maps to Z in 3D (top-down view)
		return Vector3(
			position_x * WGSClient.INCH_TO_METER,
			0.0,
			position_y * WGSClient.INCH_TO_METER
		)

	func get_base_radius_meters() -> float:
		return (base_size / 2.0) * WGSClient.INCH_TO_METER

	func get_stats_text() -> String:
		var lines: Array[String] = []
		lines.append("[b]%s[/b]" % get_display_name())

		if quality > 0 and defense > 0:
			lines.append("Q%d+ | D%d+" % [quality, defense])

		if points > 0:
			lines.append("%d pts" % points)

		if model_count > 1:
			lines.append("%d models" % model_count)

		if not weapons.is_empty():
			lines.append("")
			lines.append("[u]Weapons:[/u]")
			for weapon in weapons:
				lines.append("• %s" % weapon)

		if not special_rules.is_empty():
			lines.append("")
			lines.append("[u]Special:[/u]")
			lines.append(", ".join(special_rules))

		return "\n".join(lines)


## Import game state from WGS text file
func import_from_file(file_path: String) -> WGSGame:
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		push_error("WGSClient: Cannot open file: %s" % file_path)
		import_failed.emit("Cannot open file: %s" % file_path.get_file())
		return null

	var content = file.get_as_text()
	file.close()

	var game_id = file_path.get_file().get_basename()
	return _parse_game_state(content, game_id)


## Import game state from text content
func import_from_text(content: String, game_id: String = "") -> WGSGame:
	if game_id.is_empty():
		game_id = "wgs_%d" % Time.get_unix_time_from_system()
	return _parse_game_state(content, game_id)


## Parse WGS game state text format
func _parse_game_state(content: String, game_id: String) -> WGSGame:
	var game = WGSGame.new()
	game.game_id = game_id

	# Split into lines
	var lines = content.split("\n")
	var unit_index = 0
	var line_number = 0

	for line in lines:
		line = line.strip_edges()
		if line.is_empty():
			line_number += 1
			continue

		# First line: table width in inches
		if line_number == 0:
			game.table_width = float(line)
			line_number += 1
			continue

		# Second line: table depth in inches
		if line_number == 1:
			game.table_depth = float(line)
			line_number += 1
			print("WGSClient: Table size %dx%d inches (%.1fx%.1f ft)" % [
				int(game.table_width), int(game.table_depth),
				game.table_width / 12.0, game.table_depth / 12.0
			])
			continue

		# Remaining lines: units
		var unit = _parse_unit_line(line, unit_index)
		if unit:
			game.units.append(unit)
			unit_index += 1

		line_number += 1

	print("WGSClient: Loaded game '%s' - %d units, %d models" % [
		game.game_id, game.get_unit_count(), game.get_model_count()
	])

	game_loaded.emit(game)
	return game


## Parse a single unit line from WGS format
## Format: {size},{x},{y},{color},{angle},{imageId},{name}
func _parse_unit_line(line: String, index: int) -> WGSUnit:
	# WGS uses COMMA as escape for actual commas in text
	# We need to be careful when splitting
	var parts = _smart_split(line)

	if parts.size() < 7:
		push_warning("WGSClient: Invalid line format at index %d: %s" % [index, line])
		return null

	var unit = WGSUnit.new()
	unit.index = index

	# Parse size (can be single value or multi-base format)
	var size_str = parts[0]
	if "x" in size_str:
		# Multi-base format: WxDxCxRxN or WxDxCxR
		var size_parts = size_str.split("x")
		if size_parts.size() >= 4:
			unit.is_multibase = true
			unit.base_width = float(size_parts[0])
			unit.base_depth = float(size_parts[1])
			unit.columns = int(size_parts[2])
			unit.rows = int(size_parts[3])
			if size_parts.size() >= 5:
				unit.model_count = int(size_parts[4])
			else:
				unit.model_count = unit.columns * unit.rows
			unit.base_size = max(unit.base_width, unit.base_depth)
	else:
		unit.base_size = float(size_str)
		unit.model_count = 1

	# Parse position
	unit.position_x = float(parts[1])
	unit.position_y = float(parts[2])

	# Parse color
	unit.color_name = parts[3].to_lower()
	unit.color = _parse_color(unit.color_name)

	# Parse angle (radians)
	unit.angle = float(parts[4])

	# Parse image ID
	unit.image_id = int(parts[5])

	# Parse name/description (everything after field 6)
	unit.full_text = parts[6] if parts.size() > 6 else ""
	_parse_unit_text(unit)

	return unit


## Smart split that handles COMMA escapes in the name field
func _smart_split(line: String) -> Array[String]:
	var result: Array[String] = []
	var parts = line.split(",")

	# First 6 fields are always simple
	for i in range(min(6, parts.size())):
		result.append(parts[i])

	# Field 7 onwards is the name/description - rejoin with commas
	if parts.size() > 6:
		var name_parts: Array[String] = []
		for i in range(6, parts.size()):
			name_parts.append(parts[i])
		result.append(",".join(name_parts))

	return result


## Parse color from CSS color name
func _parse_color(color_name: String) -> Color:
	var lower_name = color_name.to_lower().strip_edges()
	if CSS_COLORS.has(lower_name):
		return CSS_COLORS[lower_name]

	# Try to parse as hex
	if lower_name.begins_with("#"):
		return Color.html(lower_name)

	return Color.GRAY


## Parse unit text field (name, stats, weapons)
func _parse_unit_text(unit: WGSUnit) -> void:
	# Decode escape sequences
	var text = unit.full_text
	text = text.replace("BIGNEWLINE", "\n\n")
	text = text.replace("NEWLINE", "\n")
	text = text.replace("COMMA", ",")

	var lines = text.split("\n")

	# First line is the name
	if not lines.is_empty():
		unit.name = lines[0].strip_edges()

	# Parse remaining lines for stats
	for i in range(1, lines.size()):
		var line = lines[i].strip_edges()
		if line.is_empty():
			continue

		# Check for tags like #scaf2#, #norotation#
		var tag_regex = RegEx.new()
		tag_regex.compile("#(\\w+)#")
		var tag_matches = tag_regex.search_all(line)
		for tag_match in tag_matches:
			unit.tags.append(tag_match.get_string(1))

		# Parse Q/D stats: "Q5+ D5+ | 40pts"
		if "Q" in line and "D" in line:
			var stats_regex = RegEx.new()
			stats_regex.compile("Q(\\d+)\\+.*D(\\d+)\\+")
			var stats_match = stats_regex.search(line)
			if stats_match:
				unit.quality = int(stats_match.get_string(1))
				unit.defense = int(stats_match.get_string(2))

			# Parse points
			var pts_regex = RegEx.new()
			pts_regex.compile("(\\d+)\\s*pts?")
			var pts_match = pts_regex.search(line)
			if pts_match:
				unit.points = int(pts_match.get_string(1))
			continue

		# Parse weapon lines
		if "(" in line and ("A" in line or "\"" in line):
			unit.weapons.append(line)
			continue

		# Accumulate description
		if not line.begins_with("#"):
			if unit.description.is_empty():
				unit.description = line
			else:
				unit.description += "\n" + line


## Export game state to WGS text format
func export_to_text(game: WGSGame) -> String:
	var lines: Array[String] = []

	# First two lines: table size
	lines.append(str(int(game.table_width)))
	lines.append(str(int(game.table_depth)))

	# Unit lines
	for unit in game.units:
		lines.append(_format_unit_line(unit))

	var content = "\r\n".join(lines) + "\r\n"
	export_ready.emit(content)
	return content


## Format a single unit to WGS line format
func _format_unit_line(unit: WGSUnit) -> String:
	var size_str: String
	if unit.is_multibase:
		size_str = "%sx%sx%sx%sx%s" % [
			unit.base_width, unit.base_depth,
			unit.columns, unit.rows, unit.model_count
		]
	else:
		size_str = str(unit.base_size)

	# Encode special characters in text
	var text = unit.full_text
	if text.is_empty():
		text = unit.name
		if not unit.description.is_empty():
			text += "NEWLINE" + unit.description.replace("\n\n", "BIGNEWLINE").replace("\n", "NEWLINE")
	text = text.replace(",", "COMMA")

	return "%s,%s,%s,%s,%s,%s,%s" % [
		size_str,
		unit.position_x,
		unit.position_y,
		unit.color_name,
		unit.angle,
		unit.image_id,
		text
	]


## Convert a 3D position back to WGS coordinates (inches)
func position_to_wgs(pos: Vector3) -> Vector2:
	return Vector2(
		pos.x / INCH_TO_METER,
		pos.z / INCH_TO_METER
	)


## Convert rotation to WGS angle
func rotation_to_wgs_angle(rotation_y: float) -> float:
	# WGS uses radians, same as Godot
	return rotation_y


## Create a WGS action string for move action
func create_move_action(game_id: String, moves: Array) -> String:
	# moves is array of {index, x, y, angle}
	var parts: Array[String] = [game_id, "3"]  # 3 = move action

	for move in moves:
		parts.append(str(move.index))
		parts.append(str(move.x))
		parts.append(str(move.y))
		parts.append(str(move.angle))

	return ",".join(parts)


## Create a WGS action string for add unit action
func create_add_action(game_id: String, unit: WGSUnit) -> String:
	var parts: Array[String] = [
		game_id,
		"11",  # 11 = add without image
		str(unit.base_size),
		str(unit.position_x),
		str(unit.position_y),
		unit.color_name,
		str(unit.angle),
		str(unit.image_id),
		unit.full_text.replace(",", "COMMA").replace("\n", "NEWLINE")
	]
	return ",".join(parts)


## Create a WGS action string for remove action
func create_remove_action(game_id: String, unit_indices: Array[int]) -> String:
	var parts: Array[String] = [game_id, "4"]  # 4 = remove action
	for idx in unit_indices:
		parts.append(str(idx))
	return ",".join(parts)


## Create a WGS action string for dice roll
func create_dice_action(game_id: String, dice_count: int, dice_type: String = "d6") -> String:
	return "%s,7,%d,%s" % [game_id, dice_count, dice_type]


## Convert WGSGame to OPR-compatible army for spawning
func convert_to_opr_army(game: WGSGame, player_id: int = 1) -> OPRApiClient.OPRArmy:
	var army = OPRApiClient.OPRArmy.new()
	army.id = game.game_id
	army.name = "WGS: %s" % game.game_id
	army.game_system = "wgs-import"
	army.player_id = player_id

	for wgs_unit in game.units:
		var unit = OPRApiClient.OPRUnit.new()
		unit.id = "%s_%d" % [game.game_id, wgs_unit.index]
		unit.name = wgs_unit.get_display_name()
		unit.size = wgs_unit.model_count
		unit.cost = wgs_unit.points
		unit.quality = wgs_unit.quality if wgs_unit.quality > 0 else 4
		unit.defense = wgs_unit.defense if wgs_unit.defense > 0 else 4

		# Convert weapons
		for weapon_str in wgs_unit.weapons:
			var weapon = OPRApiClient.OPRWeapon.new()
			weapon.name = weapon_str
			unit.weapons.append(weapon)

		army.units.append(unit)

	army.points = army.get_total_points()
	return army
