class_name BoardgenDressMaterials
extends RefCounted
## The eleven shared materials of the ruin-town dressing, made from the kit manifest's `materials` block
## (docs/adr/0004-dressing-materials-and-kit-manifest.md). A textured entry (`set`) becomes one ShaderMaterial of ruintown_dress.gdshader with the set's maps from the
## TiefwerkLibrary; while that set is not cached it is a flat StandardMaterial3D in the entry's tone (never null). A plain entry
## (`colour`) is a StandardMaterial3D with colour / roughness / metallic / emission. The merged mesh binds them by surface name.

const SHADER: Shader = preload("res://shaders/ruintown_dress.gdshader")
const VEG_SHADER: Shader = preload("res://shaders/ruintown_dress_veg.gdshader")   # ct_veg: ONE shader, two variants (modelled plants, cards)
## Shader uniform -> map name of a TiefwerkLibrary set.
const MAPS := {"albedo_tex": "albedo", "normal_tex": "normal", "orm_tex": "orm"}
## The vegetation entry's float keys that are shader uniforms of the same name, with their defaults.
const VEG_DEFAULTS := {"albedo_scale": 0.14, "wrap": 0.4, "backlight": 0.7, "roughness": 0.9}


## name -> Material for every entry of meta["materials"]. `lib` may be null (then every textured entry is flat).
static func make(meta: Dictionary, lib: TiefwerkLibrary) -> Dictionary:
	var out := {}
	var entries: Dictionary = meta.get("materials", {})
	for name: String in entries:
		var e: Dictionary = entries[name]
		if e.get("shader", "") == "veg":   # vegetation: ct_veg (modelled blades, moss) and ct_veg_card (the card tufts) of one entry
			out[name] = _veg(e, lib, false)
			out[name + "_card"] = _veg(e, lib, true)
			out[name].resource_name = name
			out[name + "_card"].resource_name = name + "_card"
			continue
		var m: Material = _textured(e, lib) if e.has("set") else null
		if m == null:
			m = _plain(e)
		m.resource_name = name
		out[name] = m
	return out


## The vegetation material: never null and never flat (it needs no texture); cards need the `grass_cards` atlas - while that set is not cached the atlas is fully transparent and the cards draw nothing.
static func _veg(e: Dictionary, lib: TiefwerkLibrary, cards: bool) -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	sm.shader = VEG_SHADER
	for key: String in VEG_DEFAULTS:
		sm.set_shader_parameter(key, float(e.get(key, VEG_DEFAULTS[key])))
	var card: Dictionary = e.get("card", {})
	var tone := _colour(card.get("tone", [0.15, 0.15, 0.15]))
	sm.set_shader_parameter("use_cards", 1.0 if cards else 0.0)
	sm.set_shader_parameter("alpha_scissor", float(card.get("alpha_scissor", 0.4)))
	sm.set_shader_parameter("card_tone", Vector3(tone.r, tone.g, tone.b))
	var set_name := str(card.get("set", ""))
	var atlas: Texture2D = lib.set_texture(set_name, "albedo") if lib != null else null
	var dry: Texture2D = lib.set_texture(set_name, "dry") if atlas != null else null
	sm.set_shader_parameter("atlas", atlas if atlas != null else ImageTexture.create_from_image(Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)))
	sm.set_shader_parameter("atlas_dry", dry if dry != null else sm.get_shader_parameter("atlas"))
	return sm


static func _textured(e: Dictionary, lib: TiefwerkLibrary) -> ShaderMaterial:
	var set_name := str(e["set"])
	if lib == null or lib.set_texture(set_name, "albedo") == null:
		return null   # not cached: the caller makes the flat tone
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
	if e.has("emission"):
		m.emission_enabled = true
		m.emission = _colour(e["emission"])
		m.emission_energy_multiplier = float(e.get("emission_energy", 1.0))
	return m


static func _colour(rgb: Array) -> Color:
	return Color(float(rgb[0]), float(rgb[1]), float(rgb[2]))
