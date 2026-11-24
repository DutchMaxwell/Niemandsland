class_name DressContext
extends RefCounted
## Everything a planner may read of one board, built once by BoardgenDress: the layout, the kit, the
## story, the seed and the grid measurements. The grid lookups are methods over a DressGridIndex, so
## a rule asks for a cell's top, walkability or kept-clear flag with one array read. `p_scan` reads
## the layout on every lookup instead: the pre-index path, which a test times against the index.

var layout: Dictionary = {}
var kit: BoardgenDressKit
var story: Dictionary = {}
var seed: int = 0
var nx: int = 0
var nz: int = 0
var cell_in: float = 0.0
var origin_in := Vector2.ZERO
var _index: DressGridIndex
var _scan := false
var _kept_clear: Dictionary = {}
var _kept_ready := false


func _init(
	p_layout: Dictionary, p_kit: BoardgenDressKit, p_story: Dictionary, p_seed: int, p_scan := false
) -> void:
	layout = p_layout
	kit = p_kit
	story = p_story
	seed = p_seed
	_scan = p_scan
	nx = int(layout.get("nx", 0))
	nz = int(layout.get("nz", 0))
	cell_in = float(layout.get("cell_in", 0.0))
	origin_in = Vector2(nx, nz) * cell_in * -0.5
	if not _scan:
		_index = DressGridIndex.new(layout)


## The height of the surface cell (x, z) presents, in board inches (0 off the board).
func top_in(x: int, z: int) -> float:
	if _scan:
		return BoardgenDressRules.top_in(layout, x, z)
	return _index.top_in(x, z)


## Whether a model can stand on cell `i`.
func walkable(i: int) -> bool:
	if _scan:
		return BoardgenDressRules.walkable(layout, i)
	return _index.walkable(i)


## Whether clutter and props keep off cell `i`.
func kept_clear_cell(i: int) -> bool:
	if _scan:
		return kept_clear().has(i)
	return _index.kept_clear(i)


## The cells no clutter or prop may take (both ladder cells, every landmark footprint), cached.
func kept_clear() -> Dictionary:
	if not _kept_ready:
		if _scan:
			_kept_clear = BoardgenDressRules.kept_clear(layout)
		else:
			for i in _index.size():
				if _index.kept_clear(i):
					_kept_clear[i] = "ladder" if _index.is_ladder(i) else "landmark"
		_kept_ready = true
	return _kept_clear


## The typed spec of a module, null when the kit does not know it.
func spec(name: String) -> DressModuleSpec:
	return kit.spec(name) if kit != null else null
