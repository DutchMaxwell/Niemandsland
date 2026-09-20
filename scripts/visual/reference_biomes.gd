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
	"sun_energy": 3.20,
	"sun_color_day": Color(1.0,0.94,0.82),
	"sun_color_sunset": Color(1.0,0.82,0.60),
	"sun_angles_day": Vector2(-52.0,52.0),
	"sun_angles_sunset": Vector2(-40.0,24.0),
	"ambient_energy": 0.45,
	"ambient_color": Color(0.93,0.87,0.72),
	"fill_energy": 0.26,
	"fill_color": Color(0.99,0.95,0.86),
	"saturation": 0.90,
}


static func get_profile(biome_name: String) -> Dictionary:
	return ARID_DESERT if biome_name == "arid_desert" else GRASSLAND
