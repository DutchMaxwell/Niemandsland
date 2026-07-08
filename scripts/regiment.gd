class_name Regiment
extends RefCounted
## Metadata companion for a RegimentTray — mirrors the role GameUnit plays for loose
## models. Holds the link between a unit and its movement-tray block, the chosen
## frontage, and the pooled-tough wound counter (AoF:R v3.5.1 p.9 "Remove Casualties":
## models are removed from the back rank). Kept RefCounted (not a Node) so it
## round-trips through save data like GameUnit; the RegimentTray node owns the
## actual transforms.

# === Public state ===

var game_unit                       # GameUnit this regiment represents
var tray: Node3D = null             # the RegimentTray node
var frontage: int = 5               # models per rank

## Pooled-tough wounds taken on the whole regiment (0..pool_max). The regiment is
## treated as a single Tough(pool_max) entity for the wound counter: a 10-model
## Tough(1) unit has pool_max 10, and each wound removes the rearmost model. For
## mixed Tough (e.g. a Tough(2) hero in a Tough(1) squad), the back models die first
## and each absorbs up to its Tough value before the next takes wounds. Persisted
## in unit_properties["regiment_wounds_taken"] and synced via NetworkManager.
var wounds_taken: int = 0


func _init(p_game_unit = null, p_tray: Node3D = null, p_frontage: int = 5) -> void:
	game_unit = p_game_unit
	tray = p_tray
	frontage = maxi(p_frontage, 1)


## The maximum wound pool = sum of every model's Tough (wounds_max). For a 10-model
## Tough(1) unit this is 10; a Tough(2) hero + 9 Tough(1) squadmates = 11.
static func pool_max(toughs: Array) -> int:
	var total: int = 0
	for t in toughs:
		total += maxi(int(t), 1)
	return total


## Whether a regiment uses the pooled-wound counter (all models Tough(1)). For such
## units the counter removes whole models from the back rank (AoF:R v3.5.1 p.9). A
## regiment with any Tough(X>1) model keeps the classic per-model wound tracking
## (each model absorbs its Tough value before dying) — the pooled counter does not
## apply, and the radial menu offers the per-model wounds dialog instead.
static func is_pooled_tough1(toughs: Array) -> bool:
	if toughs.is_empty():
		return false
	for t in toughs:
		if int(t) != 1:
			return false
	return true


## Given the per-model Tough values (index 0 = front rank, last = back rank) and the
## total `wounds_taken` on the regiment, return whether each model is alive. The back
## rank dies first: walking back-to-front, each model absorbs up to its Tough value
## before the next model takes wounds. AoF:R v3.5.1 p.9 "Remove Casualties".
static func alive_mask_for_wounds(toughs: Array, wounds_taken: int) -> Array[bool]:
	var n := toughs.size()
	var mask: Array[bool] = []
	mask.resize(n)
	var taken := maxi(wounds_taken, 0)
	# Walk back-to-front (the rearmost model is removed first); assign the mask in place.
	var wounds_behind: int = 0
	for i in range(n - 1, -1, -1):
		var tough := maxi(int(toughs[i]), 1)
		var wounds_on_this: int = maxi(0, taken - wounds_behind)
		mask[i] = wounds_on_this < tough
		wounds_behind += tough
	return mask


## Wounds currently on a specific model (0 if alive, up to Tough if dead). Used to
## keep ModelInstance.wounds_current in sync with the pooled counter.
static func wounds_on_model(toughs: Array, wounds_taken: int, index: int) -> int:
	var n := toughs.size()
	if index < 0 or index >= n:
		return 0
	var taken := maxi(wounds_taken, 0)
	# Sum the Tough of all models behind this one (higher index = further back).
	var wounds_behind: int = 0
	for i in range(index + 1, n):
		wounds_behind += maxi(int(toughs[i]), 1)
	var tough := maxi(int(toughs[index]), 1)
	var on_this: int = maxi(0, taken - wounds_behind)
	return mini(on_this, tough)


## Save data for this regiment block: frontage, tray transform, and the pooled wound
## counter. Member models are implicit (the game unit's models), so they are not
## duplicated here.
func to_dict() -> Dictionary:
	var d := {"frontage": frontage, "wounds_taken": wounds_taken}
	if is_instance_valid(tray):
		d["tray_pos"] = [tray.global_position.x, tray.global_position.y, tray.global_position.z]
		d["tray_rot_y"] = tray.rotation.y
		d["network_id"] = tray.get_meta("network_id", 0)   # keep MP identity across save/load (bus 036)
	return d
