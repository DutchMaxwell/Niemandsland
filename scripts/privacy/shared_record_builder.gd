class_name SharedRecordBuilder
extends RefCounted
## Pure privacy boundary for locally previewed game records. Every copied field is
## named below; unknown keys disappear before canonical serialization.

const ID_CHARS := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.:"


static func build(record: Dictionary) -> PackedByteArray:
	var payload := _root(record)
	var body := JSON.stringify(payload, "", true, true)
	payload["payload_sha256"] = body.sha256_text()
	return JSON.stringify(payload, "", true, true).to_utf8_buffer()


static func _root(source: Dictionary) -> Dictionary:
	var out := {}
	_int(out, source, "payload_schema_version")
	_int(out, source, "consent_schema_version")
	_hex(out, source, "deletion_code", 32)
	_id(out, source, "record_id")
	_id(out, source, "game_version")
	_id(out, source, "build_hash")
	_int(out, source, "core_abi")
	_int(out, source, "rules_epoch")
	_bool(out, source, "training_use")
	out["brain"] = _brain(_dict(source, "brain"))
	out["game"] = _game(_dict(source, "game"))
	out["table"] = _table(_dict(source, "table"))
	out["armies"] = _dict_array(source.get("armies", []), _army)
	out["actions"] = _dict_array(source.get("actions", []), _action)
	_int(out, source, "rounds")
	out["final"] = _final(_dict(source, "final"))
	return out


static func _brain(source: Dictionary) -> Dictionary:
	var out := {}
	_id(out, source, "engine")
	_id(out, source, "id")
	_id(out, source, "hash")
	return out


static func _game(source: Dictionary) -> Dictionary:
	var out := {}
	_id(out, source, "system_id")
	_id(out, source, "mission_id")
	_id(out, source, "scoring_id")
	_int(out, source, "random_seed")
	_int(out, source, "layout_seed")
	_int(out, source, "dice_seed")
	return out


static func _table(source: Dictionary) -> Dictionary:
	var out := {}
	_number(out, source, "width_inches")
	_number(out, source, "height_inches")
	out["terrain"] = _dict_array(source.get("terrain", []), _table_item)
	out["objectives"] = _dict_array(source.get("objectives", []), _table_item)
	return out


static func _table_item(source: Dictionary) -> Dictionary:
	var out := {}
	_id(out, source, "type_id")
	_number(out, source, "x")
	_number(out, source, "y")
	_number(out, source, "rotation")
	_int(out, source, "owner")
	return out


static func _army(source: Dictionary) -> Dictionary:
	var out := {}
	_int(out, source, "side")
	_id(out, source, "book_id")
	_id(out, source, "faction_id")
	out["units"] = _dict_array(source.get("units", []), _unit)
	return out


static func _unit(source: Dictionary) -> Dictionary:
	var out := {}
	_id(out, source, "unit_id")
	_id(out, source, "profile_id")
	_int(out, source, "quality")
	_int(out, source, "defense")
	_int(out, source, "model_count")
	out["loadout_ids"] = _id_array(source.get("loadout_ids", []))
	out["rule_ids"] = _id_array(source.get("rule_ids", []))
	return out


static func _action(source: Dictionary) -> Dictionary:
	var out := {}
	_int(out, source, "index")
	_int(out, source, "round")
	_int(out, source, "side")
	_id(out, source, "unit_id")
	_id(out, source, "kind")
	out["from"] = _number_array(source.get("from", []))
	out["to"] = _number_array(source.get("to", []))
	_id(out, source, "target_id")
	out["dice_faces"] = _int_array(source.get("dice_faces", []))
	_number(out, source, "score")
	return out


static func _final(source: Dictionary) -> Dictionary:
	var out := {}
	out["vp"] = _int_array(source.get("vp", []))
	out["objective_owners"] = _int_array(source.get("objective_owners", []))
	_id(out, source, "outcome")
	return out


static func _dict(source: Dictionary, key: String) -> Dictionary:
	var value = source.get(key, {})
	return value as Dictionary if value is Dictionary else {}


static func _dict_array(value, mapper: Callable) -> Array:
	var out: Array = []
	if value is not Array:
		return out
	for item in value:
		if item is Dictionary:
			out.append(mapper.call(item as Dictionary))
	return out


static func _id(out: Dictionary, source: Dictionary, key: String, exact_length: int = 0) -> void:
	if not source.has(key) or typeof(source[key]) != TYPE_STRING:
		return
	var value: String = source[key]
	if value.length() > 128 or (exact_length > 0 and value.length() != exact_length):
		return
	for character in value:
		if not ID_CHARS.contains(character):
			return
	out[key] = value


static func _int(out: Dictionary, source: Dictionary, key: String) -> void:
	if not source.has(key):
		return
	var value = source[key]
	if typeof(value) == TYPE_INT:
		out[key] = value
	elif typeof(value) == TYPE_FLOAT and is_finite(value) and value == floor(value):
		out[key] = int(value)


static func _number(out: Dictionary, source: Dictionary, key: String) -> void:
	if source.has(key) and typeof(source[key]) in [TYPE_INT, TYPE_FLOAT]:
		out[key] = source[key]


static func _bool(out: Dictionary, source: Dictionary, key: String) -> void:
	if source.has(key) and typeof(source[key]) == TYPE_BOOL:
		out[key] = source[key]


static func _id_array(value) -> Array:
	var out: Array = []
	if value is not Array:
		return out
	for item in value:
		var holder := {"v": item}
		var clean := {}
		_id(clean, holder, "v")
		if clean.has("v"):
			out.append(clean["v"])
	return out


static func _int_array(value) -> Array:
	var out: Array = []
	if value is Array:
		for item in value:
			if typeof(item) == TYPE_INT:
				out.append(item)
			elif typeof(item) == TYPE_FLOAT and is_finite(item) and item == floor(item):
				out.append(int(item))
	return out


static func _number_array(value) -> Array:
	var out: Array = []
	if value is Array:
		for item in value:
			if typeof(item) in [TYPE_INT, TYPE_FLOAT]:
				out.append(item)
	return out


static func _hex(out: Dictionary, source: Dictionary, key: String, exact_length: int) -> void:
	if not source.has(key) or typeof(source[key]) != TYPE_STRING:
		return
	var value: String = source[key]
	if value.length() != exact_length:
		return
	for character in value:
		if not "0123456789abcdef".contains(character):
			return
	out[key] = value
