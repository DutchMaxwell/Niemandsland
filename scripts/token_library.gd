class_name TokenLibrary
extends RefCounted
## A reusable registry of user-defined custom tokens, keyed by name. Holds the
## display color, whether the token is a counter, and an optional effect text
## shown on hover. The library is the source of truth for a custom token's color
## and effect (so editing it updates every instance), is persisted in the .nml
## save, and synced across multiplayer peers.

## name (String) -> {color: Color, is_counter: bool, effect: String}
var definitions: Dictionary = {}


## Adds or updates a token definition.
func define(token_name: String, color: Color, is_counter: bool, effect: String) -> void:
	if token_name.is_empty():
		return
	definitions[token_name] = {"color": color, "is_counter": is_counter, "effect": effect}


## Whether a definition exists for this name.
func has(token_name: String) -> bool:
	return definitions.has(token_name)


## Returns the full definition dict (empty dict if unknown).
func get_definition(token_name: String) -> Dictionary:
	return definitions.get(token_name, {})


## Returns the stored color, or the fallback if the token is unknown.
func get_color(token_name: String, fallback: Color = Color(0.6, 0.6, 0.6)) -> Color:
	if definitions.has(token_name):
		return definitions[token_name].get("color", fallback)
	return fallback


## Returns the effect text (empty if unknown / none).
func get_effect(token_name: String) -> String:
	if definitions.has(token_name):
		return definitions[token_name].get("effect", "")
	return ""


## Whether the token is a counter (false if unknown).
func is_counter(token_name: String) -> bool:
	if definitions.has(token_name):
		return definitions[token_name].get("is_counter", false)
	return false


## All defined token names.
func names() -> Array:
	return definitions.keys()


## Removes a definition.
func erase(token_name: String) -> void:
	definitions.erase(token_name)


## Renames a definition (keeps its color/effect/is_counter). Returns true if the
## rename happened. Caller is responsible for migrating existing token instances.
func rename(old_name: String, new_name: String) -> bool:
	if old_name == new_name or new_name.is_empty():
		return false
	if not definitions.has(old_name) or definitions.has(new_name):
		return false
	definitions[new_name] = definitions[old_name]
	definitions.erase(old_name)
	return true


## Serializes the library for saving.
func to_dict() -> Dictionary:
	var out: Dictionary = {}
	for token_name in definitions:
		var def: Dictionary = definitions[token_name]
		var c: Color = def.get("color", Color.WHITE)
		out[token_name] = {
			"color": [c.r, c.g, c.b, c.a],
			"is_counter": def.get("is_counter", false),
			"effect": def.get("effect", ""),
		}
	return out


## Loads the library from saved data (replaces current contents).
func from_dict(data: Dictionary) -> void:
	definitions.clear()
	for token_name in data:
		var def = data[token_name]
		if not def is Dictionary:
			continue
		var arr = def.get("color", [1, 1, 1, 1])
		var color := Color.WHITE
		if arr is Array and arr.size() >= 4:
			color = Color(arr[0], arr[1], arr[2], arr[3])
		definitions[token_name] = {
			"color": color,
			"is_counter": bool(def.get("is_counter", false)),
			"effect": str(def.get("effect", "")),
		}
