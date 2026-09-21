extends RefCounted
## Per-biome profiles for the art-direction reference. One code path drives every biome;
## a profile only supplies textures, understory recipe, lighting and the table biome key.
## The grassland values are the template and must stay byte-for-byte identical.

const GRASSLAND := {
	"name": "grassland",
	"biome": "",
	"desert_mode": false,
	"textures": {
		"meadow": "res://assets/terrain/reference/meadow.webp",
		"earth": "res://assets/terrain/reference/hero/rough-earth.webp",
		"woodland": "res://assets/terrain/reference/hero/forest-duff.webp",
	},
	"understory": "grassland",
	"forests": true,
	"dust": false,
	"fog_color": Color(0.74,0.75,0.72),
	"fog_density": 3.0,
	"sun_energy": 2.55,
	"sun_color_day": Color(1,0.90,0.76),
	"sun_color_sunset": Color(1,0.85,0.69),
	"sun_angles_day": Vector2(-58.0,38.0),
	"sun_angles_sunset": Vector2(-40.0,28.0),
	"ambient_energy": 0.32,
	"ambient_color": Color(0.77,0.84,0.94),
	"fill_energy": 0.40,
	"fill_color": Color(0.95,0.94,0.90),
	"saturation": 0.82,
}

const ARID_DESERT := {
	"name": "arid_desert",
	"biome": "arid_desert",
	"desert_mode": true,
	"textures": {
		"meadow": "res://assets/terrain/reference/desert/sand.webp",
		"earth": "res://assets/terrain/reference/desert/cracked-earth.webp",
		"woodland": "res://assets/terrain/reference/desert/scree.webp",
	},
	"understory": "desert",
	"forests": false,
	"dust": true,
	"fog_color": Color(0.84,0.71,0.50),
	"fog_density": 5.0,
	"sun_energy": 2.90,
	"sun_color_day": Color(1.0,0.94,0.82),
	"sun_color_sunset": Color(1.0,0.82,0.60),
	"sun_angles_day": Vector2(-52.0,52.0),
	"sun_angles_sunset": Vector2(-40.0,24.0),
	"ambient_energy": 0.38,
	"ambient_color": Color(0.90,0.84,0.70),
	"fill_energy": 0.24,
	"fill_color": Color(0.99,0.95,0.86),
	"saturation": 0.90,
}


const FROZEN_TUNDRA := {
	"name": "frozen_tundra",
	"biome": "frozen_tundra",
	"desert_mode": false,
	"tundra_mode": true,
	"textures": {
		"meadow": "res://assets/terrain/reference/tundra/wind-snow.webp",
		"earth": "res://assets/terrain/reference/tundra/frost-soil.webp",
		"woodland": "res://assets/terrain/reference/tundra/cloudy-ice.webp",
	},
	"understory": "tundra",
	"forests": false,
	"dust": false,
	"fog_color": Color(0.72,0.80,0.88),
	"fog_density": 2.0,
	"sun_energy": 1.85,
	"sun_color_day": Color(0.96,0.97,1.0),
	"sun_color_sunset": Color(1.0,0.84,0.70),
	"sun_angles_day": Vector2(-58.0,30.0),
	"sun_angles_sunset": Vector2(-40.0,20.0),
	"ambient_energy": 0.34,
	"ambient_color": Color(0.66,0.77,0.94),
	"fill_energy": 0.30,
	"fill_color": Color(0.79,0.86,0.97),
	"saturation": 0.78,
}


const VOLCANIC_ASH := {
	"name": "volcanic_ash",
	"biome": "volcanic_ash",
	"desert_mode": false,
	"volcanic_mode": true,
	"textures": {
		"meadow": "res://assets/terrain/reference/volcanic/fine-ash.webp",
		"earth": "res://assets/terrain/reference/volcanic/cooled-lava.webp",
		"woodland": "res://assets/terrain/reference/volcanic/porous-basalt.webp",
	},
	"understory": "volcanic",
	"forests": false,
	"dust": false,
	"fog_color": Color(0.44,0.43,0.41),
	"fog_density": 1.4,
	"sun_energy": 2.25,
	"sun_color_day": Color(1.0,0.94,0.86),
	"sun_color_sunset": Color(1.0,0.75,0.52),
	"sun_angles_day": Vector2(-58.0,36.0),
	"sun_angles_sunset": Vector2(-40.0,22.0),
	"ambient_energy": 0.40,
	"ambient_color": Color(0.76,0.81,0.89),
	"fill_energy": 0.34,
	"fill_color": Color(0.87,0.91,0.97),
	"saturation": 0.84,
}


const ALIEN_JUNGLE := {
	"name": "alien_jungle", "biome": "alien_jungle",
	"desert_mode": false, "jungle_mode": true,
	"textures": {
		"meadow": "res://assets/terrain/reference/jungle/velvet-moss.webp",
		"earth": "res://assets/terrain/reference/jungle/damp-humus.webp",
		"woodland": "res://assets/terrain/reference/jungle/jungle-litter.webp",
	},
	"understory": "jungle", "forests": false, "dust": false,
	"fog_color": Color(0.62,0.72,0.65), "fog_density": 3.2,
	"sun_energy": 2.25,
	"sun_color_day": Color(1.0,0.93,0.80), "sun_color_sunset": Color(1.0,0.80,0.60),
	"sun_angles_day": Vector2(-58.0,42.0), "sun_angles_sunset": Vector2(-40.0,25.0),
	"ambient_energy": 0.40, "ambient_color": Color(0.66,0.79,0.81),
	"fill_energy": 0.34, "fill_color": Color(0.81,0.91,0.83),
	"saturation": 0.82,
}


const URBAN_RUINS := {
	"name": "urban_ruins", "biome": "urban_ruins",
	"desert_mode": false, "urban_mode": true,
	"textures": {
		"meadow": "res://assets/terrain/reference/volcanic/porous-basalt.webp",
		"earth": "res://assets/terrain/reference/volcanic/fine-ash.webp",
		"woodland": "res://assets/terrain/reference/desert/scree.webp",
	},
	"understory": "urban", "forests": false, "dust": false,
	"fog_color": Color(0.68,0.71,0.74), "fog_density": 1.2,
	"sun_energy": 2.15,
	"sun_color_day": Color(1.0,0.94,0.85), "sun_color_sunset": Color(1.0,0.80,0.61),
	"sun_angles_day": Vector2(-58.0,36.0), "sun_angles_sunset": Vector2(-40.0,24.0),
	"ambient_energy": 0.38, "ambient_color": Color(0.72,0.80,0.92),
	"fill_energy": 0.32, "fill_color": Color(0.85,0.90,0.96),
	"saturation": 0.82,
}


static func get_profile(biome_name: String) -> Dictionary:
	match biome_name:
		"arid_desert": return ARID_DESERT
		"frozen_tundra": return FROZEN_TUNDRA
		"volcanic_ash": return VOLCANIC_ASH
		"alien_jungle": return ALIEN_JUNGLE
		"urban_ruins": return URBAN_RUINS
		_: return GRASSLAND
