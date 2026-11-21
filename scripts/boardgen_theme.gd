class_name BoardgenTheme
extends RefCounted
## The table-side look of a generated board's theme (the layout's `theme` key, absent = Deepworks): which shader draws it, the
## surface kinds that shader knows with their colours, and which dressing builders run. A theme is data - it adds no rule and no
## terrain class; what a cell does is the core's business.

const DEEPWORKS := "Deepworks"
const RUIN_TOWN := "RuinTown"
## Surface kinds in the order the board shaders know them (INSTANCE_CUSTOM.x). The town keeps the Deepworks seven and adds its own.
const DEEPWORKS_KINDS := ["ground", "street", "hazard", "tier1", "tier2", "ladder", "tier3", "kerb"]
## ... then a garden plot (rough), the city wall, an intact house (roofed: plaster between its timber), the rubble of a wall breach, a tiled gable
## roof and a brick chimney.
const TOWN_KINDS := ["ground", "street", "hazard", "tier1", "tier2", "ladder", "tier3", "kerb", "yard", "stone", "rim", "rough", "wall", "roofed", "rubble", "roof", "brick", "lantern", "wood"]
## Base colours of the town by kind (display values; the shader draws its stone, timber, plaster and tiles on them): earth, cobble grey, dangerous
## ground (cellar pit, pool), plaster tiers one value step apart per level, timber, a cool tower, the kerb (unused), a yard (the level-0 rest of a
## half-collapsed house), pale stone pieces, a rim line, a garden plot, the city wall stone, intact-house plaster, rubble, roof tiles, brick, a lit lantern, a wooden prop (crate, barrel, pile).
const TOWN_PALETTE := [Color(0.45, 0.36, 0.26), Color(0.50, 0.52, 0.56), Color(0.13, 0.20, 0.30), Color(0.66, 0.60, 0.48),
		Color(0.84, 0.78, 0.64), Color(0.38, 0.22, 0.10), Color(0.60, 0.61, 0.64), Color(0.40, 0.40, 0.40), Color(0.58, 0.44, 0.30),
		Color(0.88, 0.88, 0.86), Color(0.66, 0.64, 0.58), Color(0.30, 0.46, 0.22), Color(0.64, 0.64, 0.60), Color(0.88, 0.82, 0.70),
		Color(0.55, 0.50, 0.45), Color(0.72, 0.36, 0.26), Color(0.62, 0.34, 0.26), Color(1.0, 0.72, 0.36), Color(0.52, 0.36, 0.20)]
const DEEPWORKS_DRESSING := ["Props", "Landmarks", "Debris", "Sumps", "Rails"]
## The air of a board: the Tiefwerk ground mist and steam. The town has none yet (its dusk mist is a later look step).
const DEEPWORKS_ATMOSPHERE := ["Mist", "Steam"]


## The theme of `layout`: {id, shader, kinds, palette, dressing}. Unknown ids read as Deepworks (the core names only known ones).
static func of(layout: Dictionary) -> Dictionary:
	if str(layout.get("theme", DEEPWORKS)) == RUIN_TOWN:
		return {"id": RUIN_TOWN, "shader": preload("res://shaders/ruintown_board.gdshader"), "kinds": TOWN_KINDS,
			"palette": TOWN_PALETTE, "dressing": [], "atmosphere": []}
	return {"id": DEEPWORKS, "shader": preload("res://shaders/tiefwerk_board.gdshader"), "kinds": DEEPWORKS_KINDS,
		"palette": [], "dressing": DEEPWORKS_DRESSING, "atmosphere": DEEPWORKS_ATMOSPHERE}
