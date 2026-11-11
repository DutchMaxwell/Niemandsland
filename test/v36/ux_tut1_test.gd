extends GdUnitTestSuite
## UX-TUT1: the tutorial practice armies and the arena lists carry rules 3.6 names only.
## Every name below is a 3.5 unit, weapon, rule or item name that 3.6 dropped, renamed, or kept with a
## new meaning, and that the 3.6 Battle Brothers and Robot Legions books do not carry (checked name by
## name against both books and the common rules). Names only.

const FILES := [
	"res://assets/tutorial/tutorial_army_p1.json",
	"res://assets/tutorial/tutorial_army_p2.json",
	"res://assets/tutorial/tutorial_army_caster.json",
	"res://assets/arena_lists/p1_2000.json",
	"res://assets/arena_lists/p1_3000.json",
	"res://assets/arena_lists/p2_2000.json",
	"res://assets/arena_lists/p2_3000.json",
]

const DENIED := [
	"Atom-Caster", "CCW", "Courage Aura", "D-Mark", "Destructive", "Exterminator Cannon", "Gauss Rifle",
	"Heavy CCW", "Heavy Gauss Cannon", "Jetpacks", "Lacerate", "Master Heavy Rifle", "Mobile Artillery",
	"Piercing Assault", "Piercing Assault Aura", "Re-Position Artillery", "Reaper Rifle", "Self-Repair Boost",
	"Self-Repair Boost Buff", "Shielded", "Storm Rifle", "Unique", "Versatile Attack", "Void Blade",
]


## Every String under a "name" key anywhere in the list: units, weapons, rules, items, upgrade gains.
static func _names(node: Variant, out: Dictionary) -> void:
	if node is Dictionary:
		if node.get("name") is String:
			out[node["name"]] = true
		for value in node.values():
			_names(value, out)
	elif node is Array:
		for value in node:
			_names(value, out)


func test_lists_load_and_carry_names() -> void:
	for path in FILES:
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		assert_bool(data is Dictionary).override_failure_message("%s does not parse" % path).is_true()
		var found := {}
		_names(data, found)
		assert_bool(found.has("Battle Brothers") or found.has("Warriors")) \
			.override_failure_message("%s: no core unit name found, the walker sees nothing" % path).is_true()


func test_no_list_carries_a_name_rules_3_6_removed_or_reused() -> void:
	var hits: Array[String] = []
	for path in FILES:
		var found := {}
		_names(JSON.parse_string(FileAccess.get_file_as_string(path)), found)
		for denied in DENIED:
			if found.has(denied):
				hits.append("%s: %s" % [path.get_file(), denied])
	assert_array(hits).override_failure_message("3.5-only names in the lists:\n" + "\n".join(hits)).is_empty()
