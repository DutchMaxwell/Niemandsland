extends SceneTree
## NML-1140 step 10a — the identity smoke across the doctrine's two seams:
## `NmlCore.doctrine_place` (this repo's GDExtension) vs `nml_core.doctrine_place`
## (the twin's pyo3 seam) for the SAME pinned inputs must answer the SAME
## markers — identity across the seams is the design's whole point (design 0,
## gate 2(ii)): one implementation in the Rust core, two consumers, no GDScript
## copy of the choice logic.
##
## The pyo3 half runs through core/nml-core-py/tools/objective_doctrine_reference.py
## (the ONE fixture in two languages — change both or neither). Point
## NML_DOCTRINE_PYO3_PYTHON at a python that imports the nml_core built from
## THIS commit (maturin develop -m core/nml-core-py/Cargo.toml).
##
## RED: with NML_DOCTRINE_SMOKE_RED=1 the smoke perturbs ONE input on the
## extension side only (army A's Cannon range 24 -> 0) and requires the markers
## to DIFFER, proving the comparison has teeth; without the knob the markers
## must be equal. The doctrine has zero RNG and takes no seed (design 1/4), so
## the RED rides the deterministic identity input nearest to hand.
##
## Run: godot --headless --path . -s res://tools/objective_doctrine_smoke.gd
## Exit 0 green, 1 red.

const MODE := "search"
const COUNT := 3
const W_IN := 72.0
const D_IN := 48.0
const ZONES := {
	"zones": {
		"1": [[[-36, -24], [36, -24], [36, -12], [-36, -12]]],
		"2": [[[-36, 12], [36, 12], [36, 24], [-36, 24]]],
	}
}


static func _infantry(uid: String) -> Dictionary:
	return {
		"unit_id": uid, "name": "Line Infantry", "quality": 4, "defense": 4, "tough": 1,
		"wounds_max": [1, 1, 1, 1, 1], "model_count": 5,
		"weapons": [
			{"name": "Rifle", "range": 30, "attacks": 2, "count": 1, "ap": 1, "rules": []},
			{"name": "Carbine", "range": 18, "attacks": 1, "count": 2, "ap": 0, "rules": []}],
		"special_rules": [], "caster_value": 0,
		"move_bands": {"advance": 6.0, "rush": 12.0},
		"base_radius": 0.016, "game_system": "gf", "faction_folder": "gf_test",
		"item_grants": [], "attached_hero_rules": [],
		"shooting_range_bonus": 0, "max_activation_advance_bonus_in": 0.0,
	}


static func _walker(uid: String, cannon_range: int) -> Dictionary:
	return {
		"unit_id": uid, "name": "Heavy Walker", "quality": 4, "defense": 4, "tough": 6,
		"wounds_max": [6], "model_count": 1,
		"weapons": [{"name": "Cannon", "range": cannon_range, "attacks": 6, "count": 1, "ap": 2, "rules": []}],
		"special_rules": [], "caster_value": 0,
		"move_bands": {"advance": 6.0, "rush": 12.0},
		"base_radius": 0.025, "game_system": "gf", "faction_folder": "gf_test",
		"item_grants": [], "attached_hero_rules": [],
		"shooting_range_bonus": 0, "max_activation_advance_bonus_in": 0.0,
	}


static func _army(prefix: String, cannon_range: int = 24) -> Dictionary:
	return {
		"%s_0_inf" % prefix: _infantry("%s_0_inf" % prefix),
		"%s_1_walker" % prefix: _walker("%s_1_walker" % prefix, cannon_range),
	}


func _init() -> void:
	var python := OS.get_environment("NML_DOCTRINE_PYO3_PYTHON")
	if python.is_empty():
		print("IDENTITY SMOKE FAIL: NML_DOCTRINE_PYO3_PYTHON unset — point it at a python importing nml_core from this commit")
		quit(1)
		return
	var ref := _pyo3_reference(python)
	if ref.is_empty():
		quit(1)
		return
	if not ClassDB.class_exists("NmlCore"):
		print("IDENTITY SMOKE FAIL: NmlCore not loaded — build + install the extension (core/install_gdextension.sh)")
		quit(1)
		return
	var red := OS.get_environment("NML_DOCTRINE_SMOKE_RED") == "1"
	var army_a := _army("p1", 0) if red else _army("p1")
	var core := NmlCore.new()
	var ext: Dictionary = core.doctrine_place(null, MODE, [army_a, _army("p2")], COUNT, ZONES, W_IN, D_IN)
	if ext.is_empty():
		print("IDENTITY SMOKE FAIL: extension answered empty — last_error: %s" % core.last_error())
		quit(1)
		return
	# The mirrored refusal: a count no mission can draw fails on BOTH seams.
	var bad: Dictionary = core.doctrine_place(null, MODE, [_army("p1"), _army("p2")], 6, ZONES, W_IN, D_IN)
	if not bad.is_empty() or core.last_error().find("count must be <= 5") == -1:
		print("IDENTITY SMOKE FAIL: count 6 not refused — last_error: %s" % core.last_error())
		quit(1)
		return
	var ext_pos: Array = ext.get("positions")
	var ref_pos: Array = ref.get("positions")
	var identity: bool = _positions_equal(ext_pos, ref_pos) \
			and ext.get("swept") == int(ref.get("swept")) \
			and ext.get("mode") == ref.get("mode") \
			and ext_pos.size() > 0
	if red:
		if identity:
			print("RED FAIL: the perturbed extension side STILL matches the pyo3 markers — the compare has no teeth")
			quit(1)
		else:
			print("RED OK: perturbed extension side %s differs from the pyo3 markers %s" % [str(ext_pos), str(ref_pos)])
			quit(0)
		return
	if not identity:
		print("IDENTITY SMOKE FAIL: markers diverge — ext=%s ref=%s swept %s/%s mode %s/%s" % [str(ext_pos), str(ref_pos), str(ext.get("swept")), str(ref.get("swept")), str(ext.get("mode")), str(ref.get("mode"))])
		quit(1)
		return
	print("identity smoke: %d/%d positions equal, mode %s, swept %s — extension == pyo3" % [ext_pos.size(), ref_pos.size(), str(ext.get("mode")), str(ext.get("swept"))])
	quit(0)


func _pyo3_reference(python: String) -> Dictionary:
	var script := ProjectSettings.globalize_path("res://core/nml-core-py/tools/objective_doctrine_reference.py")
	var out_path := OS.get_user_data_dir().path_join("objective_doctrine_pyo3.json")
	DirAccess.remove_absolute(out_path)
	var rc := OS.execute(python, [script, out_path], [])
	if rc != 0 or not FileAccess.file_exists(out_path):
		print("IDENTITY SMOKE FAIL: pyo3 reference rc=%d — run it by hand for the traceback: %s" % [rc, script])
		return {}
	var text := FileAccess.open(out_path, FileAccess.READ).get_as_text()
	DirAccess.remove_absolute(out_path)
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary and parsed.has("positions"):
		return parsed
	print("IDENTITY SMOKE FAIL: pyo3 reference wrote no JSON object: %s" % text)
	return {}


static func _positions_equal(ext: Array, ref: Array) -> bool:
	if ext.size() != ref.size():
		return false
	for i in ext.size():
		var a: Array = ext[i]
		var b: Array = ref[i]
		if a.size() != 2 or b.size() != 2:
			return false
		if int(a[0]) != int(b[0]) or int(a[1]) != int(b[1]):
			return false
	return true
