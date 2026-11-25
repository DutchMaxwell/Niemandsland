class_name BoardgenDressMaterials
extends RefCounted
## The shared materials of the ruin-town dressing, made from the kit manifest's `materials` block
## (docs/adr/0004-dressing-materials-and-kit-manifest.md). A textured entry (`set`) becomes one
## ShaderMaterial of ruintown_dress.gdshader with the set's maps from the TiefwerkLibrary; while
## that set is not cached it is a flat StandardMaterial3D in the entry's tone (never null). A plain
## entry (`colour`) is a StandardMaterial3D with colour / roughness / metallic / emission and, with
## `vertex_colour`, the modules' own vertex colours as albedo (times the colour). The
## merged mesh binds them by surface name.

const SHADER: Shader = preload("res://shaders/ruintown_dress.gdshader")
# shader key "veg_solid": modelled plants
const VEG_SOLID_SHADER: Shader = preload("res://shaders/ruintown_dress_veg_solid.gdshader")
# shader key "veg_card": card tufts
const VEG_CARD_SHADER: Shader = preload("res://shaders/ruintown_dress_veg_card.gdshader")
## Shader uniform -> map name of a TiefwerkLibrary set.
const MAPS := {"albedo_tex": "albedo", "normal_tex": "normal", "orm_tex": "orm"}
## The vegetation entry's float keys that both vegetation shaders take as uniforms of the same name,
## with their defaults.
const VEG_LIGHT_DEFAULTS := {"wrap": 0.4, "backlight": 0.7, "roughness": 0.9}
const VEG_ALBEDO_SCALE := 0.14


## name -> Material for every entry of meta["materials"], plus one `<name>_<variant>` material for
## every entry of its `variants` block (the entry with the variant's keys laid over it). `lib` may
## be null (then every textured entry is flat).
static func make(meta: Dictionary, lib: TiefwerkLibrary) -> Dictionary:
	var out := {}
	var entries: Dictionary = meta.get("materials", {})
	for name: String in entries:
		var entry: Dictionary = entries[name]
		out[name] = _material(entry, lib)
		out[name].resource_name = name
		var variants: Dictionary = entry.get("variants", {})
		for variant: String in variants:
			var merged := entry.duplicate()
			merged.erase("variants")
			merged.merge(variants[variant], true)
			var key := BoardgenDressKit.surface_name(name, variant, entries)
			out[key] = _material(merged, lib)
			out[key].resource_name = key
	return out


## One material of an entry: by its `shader` key, else the set shader for a textured entry that is
## cached, else plain.
static func _material(entry: Dictionary, lib: TiefwerkLibrary) -> Material:
	match str(entry.get("shader", "")):
		"veg_solid":
			return _veg_solid(entry)
		"veg_card":
			return _veg_card(entry, lib)
	var material: Material = _textured(entry, lib) if entry.has("set") else null
	return material if material != null else _plain(entry)


## The modelled vegetation: never null and never flat (it needs no texture).
static func _veg_solid(entry: Dictionary) -> ShaderMaterial:
	var sm := _veg_base(entry, VEG_SOLID_SHADER)
	sm.set_shader_parameter("albedo_scale", float(entry.get("albedo_scale", VEG_ALBEDO_SCALE)))
	return sm


## The card tufts: they need the `card.set` atlas - while that set is not cached the atlas is fully
## transparent and the cards draw nothing.
static func _veg_card(entry: Dictionary, lib: TiefwerkLibrary) -> ShaderMaterial:
	var sm := _veg_base(entry, VEG_CARD_SHADER)
	var card: Dictionary = entry.get("card", {})
	var tone := _colour(card.get("tone", [0.15, 0.15, 0.15]))
	sm.set_shader_parameter("alpha_scissor", float(card.get("alpha_scissor", 0.4)))
	sm.set_shader_parameter("card_tone", Vector3(tone.r, tone.g, tone.b))
	var set_name := str(card.get("set", ""))
	var atlas: Texture2D = lib.set_texture(set_name, "albedo") if lib != null else null
	var dry: Texture2D = lib.set_texture(set_name, "dry") if atlas != null else null
	sm.set_shader_parameter(
		"atlas",
		(
			atlas
			if atlas != null
			else ImageTexture.create_from_image(Image.create_empty(1, 1, false, Image.FORMAT_RGBA8))
		)
	)
	sm.set_shader_parameter("atlas_dry", dry if dry != null else sm.get_shader_parameter("atlas"))
	return sm


static func _veg_base(entry: Dictionary, shader: Shader) -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	sm.shader = shader
	for key: String in VEG_LIGHT_DEFAULTS:
		sm.set_shader_parameter(key, float(entry.get(key, VEG_LIGHT_DEFAULTS[key])))
	return sm


static func _textured(e: Dictionary, lib: TiefwerkLibrary) -> ShaderMaterial:
	var set_name := str(e["set"])
	if lib == null or lib.set_texture(set_name, "albedo") == null:
		return null  # not cached: the caller makes the flat tone
	var sm := ShaderMaterial.new()
	sm.shader = SHADER
	for uniform: String in MAPS:
		sm.set_shader_parameter(uniform, lib.set_texture(set_name, MAPS[uniform]))
	sm.set_shader_parameter("tile_in", float(e.get("tile_in", 3.0)))
	sm.set_shader_parameter("world_uv", str(e.get("uv", "mesh")) == "world")
	sm.set_shader_parameter("tone", _colour(e.get("tone", [1.0, 1.0, 1.0])))
	sm.set_shader_parameter("normal_depth", float(e.get("normal_depth", 1.0)))
	return sm


## A plain material, or the flat stand-in of a textured one (its tone, a matte surface).
static func _plain(e: Dictionary) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = _colour(e.get("colour", e.get("tone", [1.0, 1.0, 1.0])))
	m.roughness = float(e.get("roughness", 0.9))
	m.metallic = float(e.get("metallic", 0.0))
	# the modules paint their own tones as vertex colours (straw, rags, sacks):
	# the material only shades them
	m.vertex_color_use_as_albedo = bool(e.get("vertex_colour", false))
	if e.has("emission"):
		m.emission_enabled = true
		m.emission = _colour(e["emission"])
		m.emission_energy_multiplier = float(e.get("emission_energy", 1.0))
	return m


static func _colour(rgb: Array) -> Color:
	return Color(float(rgb[0]), float(rgb[1]), float(rgb[2]))
