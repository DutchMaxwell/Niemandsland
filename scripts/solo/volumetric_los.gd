class_name VolumetricLos
extends RefCounted
## The ONE volumetric line-of-sight truth (elevation program, Phase A; GF Advanced Rules v3.5.1 p.56
## "alternative method"): every model occupies a CYLINDER standing on its base, every terrain piece is a
## 3D VOLUME in real dimensions, and a sight query is ONE 3D segment from eye to eye. Pure + static, no
## scene / mesh / physics dependency — the game (terrain_overlay, main.gd, sight fan, ruler) and the
## headless simulator both call THIS module, so sight math and sight visuals can never disagree again.
##
## UNITS: METRES everywhere inside this module (INCHES_TO_METERS). Callers that hold inch coordinates
## (solo_sim) convert at the boundary. Never mix the two inside a call.
##
## Model heights come from the BASE SIZE via the official table, NEVER from mesh bounds: meshes are
## optional per-client CDN content, so a mesh-derived height would desync multiplayer. Line of sight must
## stay a pure function of synced state (position + base size).

const INCHES_TO_METERS := 0.0254

## Official volumetric model heights as Vector2(base size in mm, model height in inches). Sizes between
## two rows interpolate LINEARLY; anything below the first / above the last row clamps to it.
const BASE_HEIGHT_TABLE := [
	Vector2(25.0, 1.0), Vector2(32.0, 1.25), Vector2(40.0, 1.5),
	Vector2(50.0, 2.0), Vector2(60.0, 3.0), Vector2(100.0, 4.0),
]


# === Model heights from the base (P1) ===

## Model height in INCHES for a round base of `base_mm`, off BASE_HEIGHT_TABLE (linear between rows,
## clamped outside). Oval bases feed their mean size in through oval_effective_mm().
static func height_in_for_base_mm(_base_mm: float) -> float:
	return 0.0


## Effective (round-equivalent) base size in mm of an OVAL base: the mean of its two axes.
static func oval_effective_mm(_width_mm: float, _depth_mm: float) -> float:
	return 0.0


# === Segment vs. volume (slab-clip first, then the flat 2D test) ===
# A volume is an upright prism: a 2D footprint extruded between y0 and y1 (metres). The exact test is
# therefore "clip the segment's t-range by the y-slab [y0,y1], then run the existing 2D footprint test on
# the CLIPPED XZ subsegment" — seeing OVER a piece is simply an empty clip, which is the whole elevation
# win. Volume dicts (registry entries) are:
#   box: {"kind":"box","c":Vector2,"he":Vector2,"yaw":float,"y0":float,"y1":float,"solid":bool}
#   cyl: {"kind":"cyl","c":Vector2,"r":float,"y0":float,"y1":float,"solid":bool}

## True if the 3D segment a->b touches the upright box volume `vol` (rotated footprint, yaw follows the
## node rotation.y convention of TerrainRules.point_in_obb).
static func segment_hits_box(_a: Vector3, _b: Vector3, _vol: Dictionary) -> bool:
	return false


## True if the 3D segment a->b touches the upright cylinder volume `vol`.
static func segment_hits_cyl(_a: Vector3, _b: Vector3, _vol: Dictionary) -> bool:
	return false
