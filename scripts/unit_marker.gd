class_name UnitMarker
extends RefCounted
## Represents a marker that can be applied to units or models.
## Supports standard OPR markers and custom freetext markers.

# ===== Marker Types =====

enum MarkerType {
	STANDARD,    # Predefined OPR marker
	CUSTOM       # User-defined freetext marker
}


# ===== Standard Marker Definitions =====

## Standard OPR markers with their properties
const STANDARD_MARKERS = {
	"Activated": {
		"icon": "✓",
		"color": Color(0.5, 0.5, 0.5),  # Gray
		"description": "Unit has activated this round"
	},
	"Shaken": {
		"icon": "S",
		"color": Color(0.9, 0.8, 0.2),  # Yellow
		"description": "-1 Q/D, half movement, no objectives"
	},
	"Fatigued": {
		"icon": "⚡",
		"color": Color(0.9, 0.5, 0.2),  # Orange
		"description": "No Impact attacks this round"
	},
	"Pinned": {
		"icon": "📍",
		"color": Color(0.2, 0.5, 0.9),  # Blue
		"description": "Cannot move"
	},
	"Stunned": {
		"icon": "★",
		"color": Color(0.7, 0.2, 0.7),  # Purple
		"description": "Cannot take actions"
	},
	"Spell": {
		"icon": "✨",
		"color": Color(0.8, 0.4, 0.9),  # Light Purple
		"description": "Active spell effect"
	},
}

## Wound markers (special handling)
const WOUND_MARKERS = {
	"Wound1": {"icon": "❤️", "color": Color(0.9, 0.2, 0.2), "value": 1},
	"Wound3": {"icon": "❤️3", "color": Color(0.9, 0.2, 0.2), "value": 3},
	"Wound5": {"icon": "❤️5", "color": Color(0.9, 0.2, 0.2), "value": 5},
}


# ===== Marker Properties =====

## Type of marker
var type: MarkerType = MarkerType.STANDARD

## Marker name/identifier
var name: String = ""

## Display icon (emoji or text)
var icon: String = ""

## Background/accent color
var color: Color = Color.WHITE

## Optional tooltip/description
var tooltip: String = ""

## Round when this marker expires (0 = permanent)
var expires_on_round: int = 0

## For wound markers: the wound value
var wound_value: int = 0

## Whether this is a counter marker (renders an adjustable number instead of a
## letter). Used to track army special rules with a resource/stacking value.
var is_counter: bool = false

## Starting value for a counter marker.
var counter_value: int = 0

## Optional longer effect/description text (shown on hover, stored in the library).
var effect: String = ""


# ===== Factory Methods =====

## Creates a standard OPR marker.
static func create_standard(marker_name: String) -> UnitMarker:
	var marker = UnitMarker.new()
	marker.type = MarkerType.STANDARD
	marker.name = marker_name

	if STANDARD_MARKERS.has(marker_name):
		var def = STANDARD_MARKERS[marker_name]
		marker.icon = def.icon
		marker.color = def.color
		marker.tooltip = def.description
	elif WOUND_MARKERS.has(marker_name):
		var def = WOUND_MARKERS[marker_name]
		marker.icon = def.icon
		marker.color = def.color
		marker.wound_value = def.value
		marker.tooltip = "%d wound(s)" % def.value

	return marker


## Creates a custom freetext marker (status token: on/off letter).
static func create_custom(text: String, marker_color: Color = Color.WHITE, effect_text: String = "") -> UnitMarker:
	var marker = UnitMarker.new()
	marker.type = MarkerType.CUSTOM
	marker.name = text
	marker.icon = "📝"
	marker.color = marker_color
	marker.tooltip = text
	marker.effect = effect_text
	return marker


## Creates a custom counter marker (renders an adjustable number). For special
## rules whose mechanic is a resource/stacking value the player tracks by hand.
static func create_counter(text: String, marker_color: Color = Color.WHITE, start_value: int = 0, effect_text: String = "") -> UnitMarker:
	var marker = create_custom(text, marker_color, effect_text)
	marker.is_counter = true
	marker.counter_value = maxi(0, start_value)
	return marker


## Creates a wound marker with specific value.
static func create_wound(value: int) -> UnitMarker:
	var marker = UnitMarker.new()
	marker.type = MarkerType.STANDARD
	marker.wound_value = value
	marker.color = Color(0.9, 0.2, 0.2)

	if value == 1:
		marker.name = "Wound1"
		marker.icon = "❤️"
	elif value == 3:
		marker.name = "Wound3"
		marker.icon = "❤️3"
	elif value == 5:
		marker.name = "Wound5"
		marker.icon = "❤️5"
	else:
		marker.name = "Wound%d" % value
		marker.icon = "❤️%d" % value

	marker.tooltip = "%d wound(s)" % value
	return marker


## Creates a temporary marker that expires after a specific round.
static func create_temporary(text: String, expires_round: int, marker_color: Color = Color.YELLOW) -> UnitMarker:
	var marker = create_custom(text, marker_color)
	marker.expires_on_round = expires_round
	marker.tooltip = "%s (expires round %d)" % [text, expires_round]
	return marker


# ===== Serialization =====

## Converts marker to dictionary for saving.
func to_dict() -> Dictionary:
	return {
		"type": type,
		"name": name,
		"icon": icon,
		"color": [color.r, color.g, color.b, color.a],
		"tooltip": tooltip,
		"expires_on_round": expires_on_round,
		"wound_value": wound_value,
		"is_counter": is_counter,
		"counter_value": counter_value
	}


## Creates a marker from a dictionary.
static func from_dict(data: Dictionary) -> UnitMarker:
	var marker = UnitMarker.new()
	marker.type = data.get("type", MarkerType.STANDARD)
	marker.name = data.get("name", "")
	marker.icon = data.get("icon", "")

	var color_arr = data.get("color", [1, 1, 1, 1])
	marker.color = Color(color_arr[0], color_arr[1], color_arr[2], color_arr[3])

	marker.tooltip = data.get("tooltip", "")
	marker.expires_on_round = data.get("expires_on_round", 0)
	marker.wound_value = data.get("wound_value", 0)
	marker.is_counter = data.get("is_counter", false)
	marker.counter_value = data.get("counter_value", 0)

	return marker


# ===== Display =====

## Gets a short display string for the marker.
func get_display_text() -> String:
	if wound_value > 0:
		return "❤️%d" % wound_value
	return icon if not icon.is_empty() else name


## Checks if this marker should be removed at the given round.
func should_expire(current_round: int) -> bool:
	return expires_on_round > 0 and current_round >= expires_on_round


# ===== Utility =====

## Gets all standard marker names.
static func get_standard_marker_names() -> Array[String]:
	var names: Array[String] = []
	for key in STANDARD_MARKERS.keys():
		names.append(key)
	return names


## Checks if a marker name is a standard marker.
static func is_standard_marker(marker_name: String) -> bool:
	return STANDARD_MARKERS.has(marker_name) or WOUND_MARKERS.has(marker_name)


## Common marker colors for custom markers.
const CUSTOM_COLORS = [
	Color(0.9, 0.2, 0.2),   # Red
	Color(0.9, 0.8, 0.2),   # Yellow
	Color(0.2, 0.8, 0.2),   # Green
	Color(0.2, 0.5, 0.9),   # Blue
	Color(0.8, 0.4, 0.9),   # Purple
	Color(0.9, 0.9, 0.9),   # White
]
