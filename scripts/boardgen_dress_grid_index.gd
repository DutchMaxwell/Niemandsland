class_name DressGridIndex
extends RefCounted
## The read-once grid of one board, packed for the honesty rules: the top height of every cell and
## the three things a rule asks of it (walkable, kept clear of clutter, a ladder's cell) in flat
## arrays, so a lookup is one array read instead of a scan of the layout. Built from the same rule
## helpers the dressing uses everywhere, so the index cannot drift from them; a test checks it
## against the layout cell by cell.

const WALKABLE := 1
const KEPT_CLEAR := 2
const LADDER := 4

var nx: int = 0
var nz: int = 0
var _tops := PackedFloat32Array()  # board inches per cell
var _flags := PackedByteArray()  # bits: WALKABLE | KEPT_CLEAR | LADDER per cell


func _init(layout: Dictionary) -> void:
	nx = int(layout.get("nx", 0))
	nz = int(layout.get("nz", 0))
	var count := nx * nz
	if count <= 0:
		return
	_tops.resize(count)
	_flags.resize(count)
	for i in count:
		var x := i % nx
		var z := floori(i / float(nx))
		_tops[i] = BoardgenDressRules.top_in(layout, x, z)
		if BoardgenDressRules.walkable(layout, i):
			_flags[i] |= WALKABLE
	for connector: Dictionary in layout.get("connectors", []):
		_mark_kept(int(connector["low"]), LADDER)
		_mark_kept(int(connector["high"]), LADDER)
	for landmark: Dictionary in layout.get("landmarks", []):
		for dz in int(landmark["h"]):
			for dx in int(landmark["w"]):
				_mark_kept((int(landmark["z"]) + dz) * nx + int(landmark["x"]) + dx, 0)


## The height of the surface cell (x, z) presents, in board inches (0 off the board).
func top_in(x: int, z: int) -> float:
	if nx <= 0 or nz <= 0 or x < 0 or z < 0 or x >= nx or z >= nz:
		return 0.0
	return _tops[z * nx + x]


## Whether a model can stand on cell `i` (false off the board).
func walkable(i: int) -> bool:
	return _has(i) and (_flags[i] & WALKABLE) != 0


## Whether clutter and props keep off cell `i`: a ladder's cell or a landmark's footprint.
func kept_clear(i: int) -> bool:
	return _has(i) and (_flags[i] & KEPT_CLEAR) != 0


## Whether cell `i` is one of a ladder's two cells (kept clear for the ladder itself).
func is_ladder(i: int) -> bool:
	return _has(i) and (_flags[i] & LADDER) != 0


## The number of cells the index describes.
func size() -> int:
	return _flags.size()


func _mark_kept(i: int, kind: int) -> void:
	if not _has(i):
		return
	_flags[i] |= KEPT_CLEAR | kind


func _has(i: int) -> bool:
	return i >= 0 and i < _flags.size()
