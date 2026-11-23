class_name DressModuleSpec
extends RefCounted
## One module of the ruin-town kit manifest (assets/ruintown_dress.json), built ONCE by
## BoardgenDressKit and read-only by convention. Lengths are inches in module space, the unit the
## manifest states; the shadow hulls are already resolved. `errors` lists what was missing or
## malformed (collected here, never pushed; callers read them).

## A module without a hull list casts the shadow of its aabb shrunk by this much.
const SHRINK_IN := 0.05

var name: String = ""
var family: String = ""
var role: String = ""
var tags: PackedStringArray = PackedStringArray()
var materials: PackedStringArray = PackedStringArray()
var aabb_lo := Vector3.ZERO
var aabb_hi := Vector3.ZERO
var len_in: float = 0.0
var height_in: float = 0.0
var mount_in: float = 0.0
var proud_flat: float = 0.0
var proud_low: float = 0.0
var proud_high: float = 0.0
var shadow_hulls: Array = []  # [lo: Vector3, hi: Vector3] pairs, inches, module space, resolved
var openings: Array = []
var variant: String = ""  # the surface variant ("" or "card"): names <material>_<variant> surfaces
var stub: bool = false
var errors: PackedStringArray = PackedStringArray()


## The typed spec of one manifest entry; never fails, reports what it could not read in `errors`.
static func from_manifest(
	name: String, entry: Dictionary, materials: Dictionary
) -> DressModuleSpec:
	return DressModuleSpec.new(name, entry, materials)


func _init(spec_name: String, entry: Dictionary, materials_block: Dictionary) -> void:
	name = spec_name
	family = _value(entry, "family", "")
	role = _value(entry, "role", "")
	tags = _strings(entry, "tags")
	materials = _strings(entry, "materials")
	len_in = _value(entry, "len_in", 0.0)
	height_in = _value(entry, "height_in", 0.0)
	mount_in = _value(entry, "mount_in", 0.0, false)
	variant = _value(entry, "variant", "", false)
	stub = _value(entry, "stub", false)
	openings = _value(entry, "openings", [])
	var proud: Dictionary = _value(entry, "proud_in", {})
	proud_flat = _value(proud, "flat", 0.0)
	proud_low = _value(proud, "low", 0.0)
	proud_high = _value(proud, "high", 0.0)
	_read_aabb(entry)
	shadow_hulls = _hulls(entry)
	_check_materials(materials_block)


## A required (or optional) manifest value; `fallback` gives both the wanted type and the value on a
## missing or wrong entry (wrong or missing values are recorded in `errors`).
func _value(entry: Dictionary, key: String, fallback: Variant, required := true) -> Variant:
	if not entry.has(key):
		if required:
			errors.append("missing " + key)
		return fallback
	var value: Variant = entry[key]
	if typeof(value) == typeof(fallback):
		return value
	if typeof(fallback) == TYPE_FLOAT and typeof(value) == TYPE_INT:
		return float(value)
	errors.append(key + " is not " + type_string(typeof(fallback)))
	return fallback


func _strings(entry: Dictionary, key: String) -> PackedStringArray:
	var raw: Array = _value(entry, key, [])
	var out := PackedStringArray(
		raw.filter(func(item: Variant) -> bool: return typeof(item) == TYPE_STRING)
	)
	if out.size() != raw.size():
		errors.append(key + " has a non-string")
	return out


func _read_aabb(entry: Dictionary) -> void:
	var pair := _pair(_value(entry, "aabb_in", []))
	aabb_lo = pair[0] if pair.size() == 2 else Vector3.ZERO
	aabb_hi = pair[1] if pair.size() == 2 else Vector3.ZERO
	if pair.is_empty():
		errors.append("malformed aabb_in")
	elif aabb_lo.x > aabb_hi.x or aabb_lo.y > aabb_hi.y or aabb_lo.z > aabb_hi.z:
		errors.append("aabb_in lo above hi")


## [lo: Vector3, hi: Vector3] of an aabb or hull pair of three numbers each, or [] when malformed.
func _pair(value: Variant) -> Array:
	var pair: Array = value if typeof(value) == TYPE_ARRAY else []
	if pair.size() != 2 or _corner(pair[0]) == null or _corner(pair[1]) == null:
		return []
	return [_corner(pair[0]), _corner(pair[1])]


func _corner(value: Variant) -> Variant:
	var arr: Array = value if typeof(value) == TYPE_ARRAY else []
	if arr.size() != 3:
		return null
	if not arr.all(func(v: Variant) -> bool: return typeof(v) in [TYPE_INT, TYPE_FLOAT]):
		return null
	return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))


## The module's `shadow` list, or else its aabb shrunk by SHRINK_IN on every axis thicker than twice
## that (a flat piece keeps its thickness) - the same arithmetic BoardgenDressMesh uses.
func _hulls(entry: Dictionary) -> Array:
	if not entry.has("shadow"):
		var lo := aabb_lo
		var hi := aabb_hi
		for axis in 3:
			if hi[axis] - lo[axis] > 2.0 * SHRINK_IN:
				lo[axis] += SHRINK_IN
				hi[axis] -= SHRINK_IN
		return [[lo, hi]]
	var out: Array = []
	for hull: Variant in _value(entry, "shadow", []):
		var pair := _pair(hull)
		out.append(pair)
		if pair.is_empty():
			errors.append("malformed shadow hull")
	return out


func _check_materials(materials_block: Dictionary) -> void:
	if materials.is_empty():
		errors.append("no materials")
	var known := variant == ""
	for material in materials:
		var raw: Variant = materials_block.get(material)
		if typeof(raw) != TYPE_DICTIONARY:
			errors.append("unknown material " + material)
			continue
		var v: Variant = (raw as Dictionary).get("variants")
		known = known or (typeof(v) == TYPE_DICTIONARY and (v as Dictionary).has(variant))
	if not known:
		errors.append("unknown surface variant " + variant)
