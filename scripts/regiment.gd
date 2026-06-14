class_name Regiment
extends RefCounted
## Metadata companion for a RegimentTray — mirrors the role GameUnit plays for loose
## models. Holds the link between a unit and its movement-tray block plus the chosen
## frontage. Kept RefCounted (not a Node) so it round-trips through save data like
## GameUnit; the RegimentTray node owns the actual transforms.
##
## Serialization (to_dict/from_dict) lands with the save/load milestone.

# === Public state ===

var game_unit                       # GameUnit this regiment represents
var tray: Node3D = null             # the RegimentTray node
var frontage: int = 5               # models per rank


func _init(p_game_unit = null, p_tray: Node3D = null, p_frontage: int = 5) -> void:
	game_unit = p_game_unit
	tray = p_tray
	frontage = maxi(p_frontage, 1)


## Save data for this regiment block: frontage + the tray's world transform. Member
## models are implicit (the game unit's models), so they are not duplicated here.
func to_dict() -> Dictionary:
	var d := {"frontage": frontage}
	if is_instance_valid(tray):
		d["tray_pos"] = [tray.global_position.x, tray.global_position.y, tray.global_position.z]
		d["tray_rot_y"] = tray.rotation.y
	return d
