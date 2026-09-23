class_name DiceLook
extends Resource
## How the dice look — the ONE switch for the physics dice, the tray's dice icons in the tally and
## the dice log (uidice2, 23.09.2026). HouseStyle.DICE_LOOK names the shipped look; the three
## candidates below differ only in these numbers, never in code paths.
##
## Visual only: nothing here reaches the collision shape, mass, damping, the roll impulses or the
## face reader (DiceD6.top_face). Colour tags keep their own body colours on every look, and their
## pips switch to light / dark by body luminance, so the four tags read the same on all three looks.

@export var id: StringName = &"classic"
@export var title: String = ""
@export var body_color := Color(0.93, 0.93, 0.90)
@export var pip_color := Color(0.12, 0.12, 0.14)
@export_range(0.0, 1.0) var roughness := 0.45
@export_range(0.0, 1.0) var metallic := 0.0
@export_range(0.0, 1.0) var clearcoat := 0.0
@export_range(0.0, 1.0) var rim := 0.0             # soft light around the silhouette (smoked glass)
@export_range(0.0, 2.0) var pip_depth := 1.0       # engraving depth (normal-map strength)
@export_range(0.0, 1.0) var pip_metallic := 0.0
@export_range(0.0, 1.0) var pip_roughness := 0.7
@export_range(0.0, 0.3) var edge_radius := 0.14    # rounded edge, fraction of the edge length
@export var icon_border := Color(0.30, 0.30, 0.32)  # the tally / log icon's rim

const LOOK_IDS: Array[StringName] = [&"classic", &"house", &"brass"]

static var _override: StringName = &""
static var _cache: Dictionary = {}


## The look in force: a capture/test override, else HouseStyle.DICE_LOOK.
static func current() -> DiceLook:
	return named(_override if _override != &"" else HouseStyle.DICE_LOOK)


## Captures and tests switch the look for the whole process ("" = back to HouseStyle.DICE_LOOK).
static func set_override(look_id: StringName) -> void:
	_override = look_id if look_id in LOOK_IDS else &""


static func named(look_id: StringName) -> DiceLook:
	if not _cache.has(look_id):
		_cache[look_id] = _build(look_id if look_id in LOOK_IDS else &"classic")
	return _cache[look_id]


static func _build(look_id: StringName) -> DiceLook:
	var l := DiceLook.new()
	l.id = look_id
	match look_id:
		&"house":
			# (b) Dark smoked dice with gold pips — the panel's primary colour on the table.
			l.title = "House — smoked with gold pips"
			l.body_color = Color(0.13, 0.16, 0.185)
			l.pip_color = HouseStyle.GOLD
			l.roughness = 0.2
			l.clearcoat = 1.0
			l.rim = 0.5
			l.pip_depth = 0.8
			l.pip_metallic = 0.85
			l.pip_roughness = 0.3
			l.icon_border = HouseStyle.LINE
		&"brass":
			# (c) Machined brass with black enamel pips: brass is the grimdark staple (casings,
			# reliquaries) and the fantasy one (coins, armour) at once, and the metal catches the
			# light on every bevel, so a die's shape still reads when it is small in the tray.
			l.title = "Brass — machined, black enamel pips"
			l.body_color = Color(0.80, 0.62, 0.34)
			l.pip_color = Color(0.05, 0.045, 0.04)
			l.roughness = 0.32
			l.metallic = 1.0
			l.pip_depth = 1.2
			l.pip_roughness = 0.25
			l.edge_radius = 0.10
			l.icon_border = Color(0.45, 0.34, 0.16)
		_:
			# (a) Classic: ivory / bone with engraved dark pips.
			l.title = "Classic — ivory with engraved pips"
			l.body_color = DiceD6.BODY_COLOR
			l.pip_color = Color(0.10, 0.09, 0.08)
			l.roughness = 0.42
			l.clearcoat = 0.35
			l.pip_depth = 1.0
			l.pip_roughness = 0.8
	return l
