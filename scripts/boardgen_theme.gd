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
const TOWN_PALETTE := [Color(0.43, 0.42, 0.40), Color(0.50, 0.52, 0.56), Color(0.13, 0.20, 0.30), Color(0.66, 0.60, 0.48),
		Color(0.84, 0.78, 0.64), Color(0.40, 0.37, 0.34), Color(0.60, 0.61, 0.64), Color(0.40, 0.40, 0.40), Color(0.58, 0.44, 0.30),
		Color(0.88, 0.88, 0.86), Color(0.66, 0.64, 0.58), Color(0.30, 0.46, 0.22), Color(0.64, 0.64, 0.60), Color(0.88, 0.82, 0.70),
		Color(0.55, 0.50, 0.45), Color(0.72, 0.36, 0.26), Color(0.44, 0.31, 0.26), Color(1.0, 0.72, 0.36), Color(0.44, 0.37, 0.30)]   # (look review 2) weathered dark wood: the saturated (0.52, 0.36, 0.20) read orange at dusk, black at Night
## The authored T-R1 surface sets the town shader can read (library set -> shader suffix), in the order of the shader's `t_on`: coursed stone, plaster, timber, earth. The theme key of
## TiefwerkLibrary / BoardgenKit for the town.
const TOWN_LIBRARY := "ruintown"
## The street, flag-top and roof sets follow (texture plan step 16); the shader reads only the first four until it takes them as arrays (step 18).
const TOWN_SETS := [["coursed_stone", "stone"], ["plaster", "plaster"], ["timber", "timber"], ["earth", "earth"], ["cobbles", "cobbles"],
		["flags", "flags"], ["roof_tiles", "roof"]]
## The scale contract of the town's sets (texture plan, decision D-TEX2): board inches one tile covers, its pixels, and the size of the feature
## that must read from the start camera (stone, flag, plank, slate row; 0 = no pattern). 110-180 texels per inch keeps two neighbouring
## surfaces within x2 of each other; a feature >= 0.30 in is >= 4.4 px at the start camera (14.5 px/in).
const TOWN_SET_CONTRACT := {"coursed_stone": {"tile_in": 3.0, "px": 512, "feature_in": 0.35}, "plaster": {"tile_in": 6.0, "px": 1024, "feature_in": 0.0},
		"timber": {"tile_in": 3.25, "px": 512, "feature_in": 0.36}, "earth": {"tile_in": 8.0, "px": 1024, "feature_in": 0.0},
		"cobbles": {"tile_in": 3.0, "px": 512, "feature_in": 0.33}, "flags": {"tile_in": 4.0, "px": 512, "feature_in": 0.5},
		"roof_tiles": {"tile_in": 3.3, "px": 512, "feature_in": 0.30}}
const TOWN_TEXELS_PER_IN := Vector2(110.0, 180.0)
const TOWN_FEATURE_MIN_IN := 0.30
const TOWN_SETS_MAX_BYTES := 32000000   # (lead 26.11.) was 16 MB; the four soil sets (12.6 MB, LOOK5 S2) took the staged library to 27.7 MB. The real limit is the download time (ticket KIT-DL-SPEED), not this number
## The mean linear albedo of each set (measured on the staged masters): the shader multiplies its palette tone by texture / mean, so a tint survives and only the detail changes.
## The four SOIL sets of the yards (LOOK5 R20, S2; lead pick 26.11.: green direction (b) realistic dark), in the order of the shader's soil layers: bare, mud, grass, verge / wet.
## Albedo and normal 1024 px, ORH (R ao, G roughness, B height) 512 px; read only as texture arrays by ruintown_soil.gdshaderinc (S4 calls it).
const TOWN_SOIL := ["soil_bare", "soil_mud", "soil_grass", "soil_verge"]
const TOWN_SOIL_CONTRACT := {"soil_bare": {"tile_in": 6.0, "px": 1024, "feature_in": 0.0}, "soil_mud": {"tile_in": 6.0, "px": 1024, "feature_in": 0.0},
		"soil_grass": {"tile_in": 6.0, "px": 1024, "feature_in": 0.0}, "soil_verge": {"tile_in": 6.0, "px": 1024, "feature_in": 0.0}}
## Their mean linear albedo (the 1k sources: polyhaven stony_dirt_path, muddy_tracks, sparse_grass, brown_mud_03): the shader's ratio denominator.
const TOWN_SOIL_MEANS := [Vector3(0.0806, 0.048, 0.0257), Vector3(0.0807, 0.0292, 0.0114), Vector3(0.0819, 0.0489, 0.0083), Vector3(0.0936, 0.0733, 0.048)]
const TOWN_SET_MEANS := {"stone": Vector3(0.377, 0.244, 0.137), "plaster": Vector3(0.4065, 0.3669, 0.3513), "timber": Vector3(0.1207, 0.0743, 0.0443), "earth": Vector3(0.1747, 0.1326, 0.0824)}
const DEEPWORKS_DRESSING := ["Props", "Landmarks", "Debris", "Sumps", "Rails"]
## The air of a board: the town's ground fog with its lamp pools (BoardgenGroundFog) on both themes (maintainer 26.11.: the town's fog goes to Tiefwerk);
## Tiefwerk keeps its vent steam and, over its acid sumps only, the green mist shimmer (maintainer 26.11., D-FOG3).
const DEEPWORKS_ATMOSPHERE := ["GroundFog", "Steam", "Mist"]
const TOWN_ATMOSPHERE := ["GroundFog"]


## The theme of `layout`: {id, shader, kinds, palette, dressing}. Unknown ids read as Deepworks (the core names only known ones).
static func of(layout: Dictionary) -> Dictionary:
	if str(layout.get("theme", DEEPWORKS)) == RUIN_TOWN:
		return {"id": RUIN_TOWN, "shader": preload("res://shaders/ruintown_board.gdshader"), "kinds": TOWN_KINDS,
			"palette": TOWN_PALETTE, "dressing": [], "atmosphere": TOWN_ATMOSPHERE}
	return {"id": DEEPWORKS, "shader": preload("res://shaders/tiefwerk_board.gdshader"), "kinds": DEEPWORKS_KINDS,
		"palette": [], "dressing": DEEPWORKS_DRESSING, "atmosphere": DEEPWORKS_ATMOSPHERE}
