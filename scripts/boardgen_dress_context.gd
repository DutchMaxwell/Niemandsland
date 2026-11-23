class_name DressContext
extends RefCounted
## Everything a planner may read of one board, built once by BoardgenDress: the layout, the kit, the
## story, the seed and the grid measurements. The grid lookups are methods so a later packed grid
## index can replace their bodies without touching a caller.

var layout: Dictionary = {}
var kit: BoardgenDressKit
var story: Dictionary = {}
var seed: int = 0
var nx: int = 0
var nz: int = 0
var cell_in: float = 0.0
var origin_in := Vector2.ZERO
var _kept_clear: Dictionary = {}
var _kept_ready := false


func _init(p_layout: Dictionary, p_kit: BoardgenDressKit, p_story: Dictionary, p_seed: int) -> void:
	layout = p_layout
	kit = p_kit
	story = p_story
	seed = p_seed
	nx = int(layout.get("nx", 0))
	nz = int(layout.get("nz", 0))
	cell_in = float(layout.get("cell_in", 0.0))
	origin_in = Vector2(nx, nz) * cell_in * -0.5


## The height of the surface cell (x, z) presents, in board inches (0 off the board).
func top_in(x: int, z: int) -> float:
	return BoardgenDressRules.top_in(layout, x, z)


## Whether a model can stand on cell `i`.
func walkable(i: int) -> bool:
	return BoardgenDressRules.walkable(layout, i)


## The cells no clutter or prop may take (both ladder cells, every landmark footprint), cached.
func kept_clear() -> Dictionary:
	if not _kept_ready:
		_kept_clear = BoardgenDressRules.kept_clear(layout)
		_kept_ready = true
	return _kept_clear


## The typed spec of a module, null when the kit does not know it.
func spec(name: String) -> DressModuleSpec:
	return kit.spec(name) if kit != null else null
