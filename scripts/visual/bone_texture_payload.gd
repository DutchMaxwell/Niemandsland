class_name BoneTexturePayload
extends RefCounted
## Validated optional manifest contract; no rendering or scene changes.

static func valid_entry(entry: Dictionary) -> bool:
	for key in ["version", "frames", "fps", "bones"]:
		var value: Variant = entry.get(key)
		if not (value is float or value is int) or not is_finite(float(value)):
			return false
	if int(entry.get("version", 0)) != 1 or not CtexLoader.ctex_compatible(str(entry.get("godot_version", ""))):
		return false
	if int(entry.get("frames", 0)) < 2 or int(entry.get("frames", 0)) > 4096:
		return false
	if float(entry.get("fps", 0)) <= 0 or float(entry.get("fps", 0)) > 120:
		return false
	if int(entry.get("bones", 0)) < 1 or int(entry.get("bones", 0)) > 256:
		return false
	for key in ["mesh", "poses"]:
		var blob: Variant = entry.get(key)
		if not _valid_blob(blob):
			return false
	var materials: Variant = entry.get("materials", [])
	if not materials is Array:
		return false
	for material in materials:
		if not material is Dictionary:
			return false
		var surface: Variant = material.get("surface")
		# JSON.parse_string represents numbers as floats, even integer surface indices.
		if not (surface is float or surface is int) or not is_finite(float(surface)):
			return false
		if float(surface) < 0 or float(surface) != floorf(float(surface)):
			return false
		if not _valid_blob(material.get("albedo")):
			return false
		if material.has("normal") and not _valid_blob(material.normal):
			return false
	var bounds: Variant = entry.get("bounds")
	if not bounds is Array or bounds.size() != 6:
		return false
	for value in bounds:
		if not (value is float or value is int) or not is_finite(float(value)):
			return false
	return float(bounds[3]) > 0 and float(bounds[4]) > 0 and float(bounds[5]) > 0

static func _valid_blob(blob: Variant) -> bool:
	if not blob is Dictionary or str(blob.get("url", "")).is_empty():
		return false
	var sha := str(blob.get("sha256", ""))
	if sha.length() != 64:
		return false
	for character in sha:
		if not character in "0123456789abcdef":
			return false
	return true
