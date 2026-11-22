class_name BoardgenDressRules
extends RefCounted
## The honesty rules of the ruin-town dressing (PLAN_RUINTOWN_DRESSING, R1-R5 as plain arithmetic): the dressing never hides a walkable cell, never suggests a surface that is not there. The grid is the truth;
## a placement {module, xf (Transform3D, metres, board space), cls} is checked against it with the numbers its manifest module declares (aabb_in, proud_in per height band, tags, family, role). Pure data, headless.
## Everything is in board inches, origin at the board centre. A model standing on a walkable cell needs the column above its top free: FLAT (0.08) of anything, then nothing up to CLEAR (2.0), except the
## edge strip of an edge that drops (R4); above CLEAR only an overhang (R2). R3 = the drawn face sits 0..0.2 inside the collider face. R5 = the ladder zones carry only ladders and plain faces.
## This file grows in three steps: 5a the grid helpers and the constants (here), 5b violations() for R1 / R2 / R4, 5c R3 and R5.

const IN_M := 0.0254
const FLAT := 0.08
const CLEAR := 2.0
const OVERHANG := 0.35
const REACH := 0.2
const EDGE := 0.4
const PARAPET := 0.7
const LADDER_GAP := 0.9
const LEAN_MAX := 1.5
const TOL := 0.02   # how far a piece may poke over a limit before it counts
const DIRS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]   # N, E, S, W


## The height of the surface a cell presents (a tall tower 12, a roofed house 2.5, else its level); off the board 0.
static func top_in(layout: Dictionary, x: int, z: int) -> float:
	if x < 0 or z < 0 or x >= int(layout["nx"]) or z >= int(layout["nz"]):
		return 0.0
	var c: Dictionary = layout["cells"][z * int(layout["nx"]) + x]
	return float(layout.get("tower_in", 12.0)) if c["lot_kind"] == "Tower" else BoardgenGreybox.SOLID_IN if c["lot_kind"] == "Roofed" else float(layout["level_in"][int(c["level"])])


## Whether a model can stand on cell `i`: not a roofed house, not a tall tower, not a solid landmark's footprint.
static func walkable(layout: Dictionary, i: int) -> bool:
	var nx := int(layout["nx"])
	var x := i % nx
	var z := floori(i / float(nx))
	for lm: Dictionary in layout["landmarks"]:
		if lm["solid"] and x >= int(lm["x"]) and x < int(lm["x"]) + int(lm["w"]) and z >= int(lm["z"]) and z < int(lm["z"]) + int(lm["h"]):
			return false
	return not ["Roofed", "Tower"].has(layout["cells"][i]["lot_kind"])


## The cells no clutter or prop may take: both cells of every ladder and every landmark footprint. {cell index: "ladder" | "landmark"}
static func kept_clear(layout: Dictionary) -> Dictionary:
	var out := {}
	for c: Dictionary in layout["connectors"]:
		out[int(c["low"])] = "ladder"
		out[int(c["high"])] = "ladder"
	for lm: Dictionary in layout["landmarks"]:
		for dz in int(lm["h"]):
			for dx in int(lm["w"]):
				out[(int(lm["z"]) + dz) * int(layout["nx"]) + int(lm["x"]) + dx] = "landmark"
	return out


## The transform of a face module: its origin on the face's start point moved `inset_in` INTO the mass (against `out`), x along the face, y up, z out; `lean_deg` tips the top outward (negative: inward).
static func face_xf(start_in: Vector3, along: Vector3, out: Vector3, inset_in: float, lean_deg: float) -> Transform3D:
	return Transform3D(Basis(along, Vector3.UP, out) * Basis(Vector3.RIGHT, deg_to_rad(lean_deg)), (start_in - out * inset_in) * IN_M)
