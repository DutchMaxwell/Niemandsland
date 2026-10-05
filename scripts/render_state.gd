class_name RenderState
extends RefCounted
## ONE owner of the game table's contested Environment values. The quality preset, the mood / lighting-panel light,
## the biome reference and the cinematic intro each hand their values in as a LAYER; this class computes the effective
## value per property and is the only one that writes it. Before, each of them wrote the shared Environment directly
## and the call order decided the look (graphics council 03.10.: Overcast -> Ultra switched SDFGI on, Ultra -> Overcast
## did not; Low after a dressed Medium kept the reference's glow).
##
## Layers, lowest first. A property no layer sets falls back to the value the Environment had when a layer first
## touched it (the scene's own value).
const LAYERS: Array[String] = ["preset", "light", "reference", "grading", "intro"]

var _env: Environment
var _base := {}
var _layers := {}


func _init(env: Environment) -> void:
	_env = env
	for layer in LAYERS:
		_layers[layer] = {}


## Replace a whole layer; {} clears it.
func set_layer(layer: String, values: Dictionary) -> void:
	_remember(values)
	_layers[layer] = values.duplicate()
	_resolve()


## Change single values of a layer (a mood blend calls the light setters every frame).
func merge_layer(layer: String, values: Dictionary) -> void:
	_remember(values)
	(_layers[layer] as Dictionary).merge(values, true)
	_resolve()


## The value `key` gets from the layers (the highest layer that sets it wins).
func effective(key: String) -> Variant:
	var value: Variant = _base.get(key)
	for layer in LAYERS:
		if (_layers[layer] as Dictionary).has(key):
			value = _layers[layer][key]
	return value


func _remember(values: Dictionary) -> void:
	for key in values:
		if not _base.has(key):
			_base[key] = _env.get(key)


func _resolve() -> void:
	for key in _base:
		var value: Variant = effective(key)
		if _env.get(key) != value:
			_env.set(key, value)
