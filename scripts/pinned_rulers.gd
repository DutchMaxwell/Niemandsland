class_name PinnedRulers
extends Node3D
## Owns the persistent, shared rulers (PinnedRuler instances) on the table. Mirrors the
## system-owner overlay pattern (CoherencyVisualizer / UnitBoundaryVisualizer): a direct
## child of /root/Main holding the visuals so they never interfere with selection or
## physics. Rulers are SESSION-ONLY — they sync to late-joiners (network_manager) but are
## NOT written to the .nml save, exactly like remote cursors and avatars.

const PinnedRulerScript := preload("res://scripts/pinned_ruler.gd")

## Per-owner colour palette (peer id → colour), kept in sync with main._get_player_color
## and OPRArmyManager.PLAYER_COLORS so a ruler reads in its owner's colour on every client.
const OWNER_COLORS: Dictionary = {
	1: Color(0.2, 0.4, 0.9),  # Blue
	2: Color(0.9, 0.2, 0.2),  # Red
	3: Color(0.2, 0.8, 0.3),  # Green
	4: Color(0.9, 0.7, 0.1),  # Yellow
}
## Solo / unknown owner: a neutral cyan that is not any player colour.
const SOLO_COLOR: Color = Color(0.25, 0.85, 0.95)

# === Private variables ===

var _rulers: Dictionary = {}  # id (int) -> PinnedRuler

# === Public ===

## Add (or replace, if the id already exists) a ruler. The colour is DERIVED from the
## owner so every client renders the same ruler in the same owner colour.
func add_ruler(id: int, owner_peer: int, from_pos: Vector3, to_pos: Vector3,
		distance_inches: float, blocked: bool) -> void:
	remove_ruler(id)
	var ruler: PinnedRuler = PinnedRulerScript.new()
	ruler.name = "PinnedRuler_%d" % id
	add_child(ruler)
	ruler.setup(id, owner_peer, from_pos, to_pos, distance_inches, blocked,
			color_for_owner(owner_peer))
	_rulers[id] = ruler


func remove_ruler(id: int) -> void:
	var ruler: Node = _rulers.get(id)
	if ruler != null and is_instance_valid(ruler):
		ruler.queue_free()
	_rulers.erase(id)


## Remove every ruler owned by one player (their "clear my rulers").
func clear_owner(owner_peer: int) -> void:
	for id in _rulers.keys():
		var ruler: PinnedRuler = _rulers[id]
		if is_instance_valid(ruler) and ruler.owner_peer == owner_peer:
			remove_ruler(id)


## Remove all rulers (the host's "clear all").
func clear_all() -> void:
	for id in _rulers.keys():
		remove_ruler(id)


func color_for_owner(owner_peer: int) -> Color:
	return OWNER_COLORS.get(owner_peer, SOLO_COLOR)


## Id of the nearest ruler within max_dist (metres) of a table point, or -1 if none.
## owner_filter >= 0 restricts the search to that owner's rulers (a player removing only
## their own); -1 searches any owner (the host removing anyone's).
func nearest_ruler_at(xz: Vector3, max_dist: float, owner_filter: int = -1) -> int:
	var best_id: int = -1
	var best_dist: float = max_dist
	for id in _rulers:
		var ruler: PinnedRuler = _rulers[id]
		if not is_instance_valid(ruler):
			continue
		if owner_filter >= 0 and ruler.owner_peer != owner_filter:
			continue
		var d: float = ruler.distance_to_point(xz)
		if d <= best_dist:
			best_dist = d
			best_id = id
	return best_id


func ruler_count() -> int:
	return _rulers.size()


## Owner peer of a ruler by id (-1 if unknown). Named `ruler_owner`, not `get_owner`,
## to avoid shadowing Node.get_owner().
func ruler_owner(id: int) -> int:
	var ruler: Node = _rulers.get(id)
	return (ruler as PinnedRuler).owner_peer if is_instance_valid(ruler) else -1


## Serialise the active rulers for the late-joiner state sync. NOT used for .nml saves —
## rulers are session-only.
func serialize() -> Array:
	var out: Array = []
	for id in _rulers:
		var r: PinnedRuler = _rulers[id]
		if not is_instance_valid(r):
			continue
		out.append({
			"id": r.id, "owner": r.owner_peer,
			"fx": r.from_pos.x, "fy": r.from_pos.y, "fz": r.from_pos.z,
			"tx": r.to_pos.x, "ty": r.to_pos.y, "tz": r.to_pos.z,
			"dist": r.distance_inches, "blocked": r.blocked,
		})
	return out


func restore(list: Array) -> void:
	for d in list:
		add_ruler(int(d["id"]), int(d["owner"]),
				Vector3(d["fx"], d["fy"], d["fz"]),
				Vector3(d["tx"], d["ty"], d["tz"]),
				float(d["dist"]), bool(d["blocked"]))
