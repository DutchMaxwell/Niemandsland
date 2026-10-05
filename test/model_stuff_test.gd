extends GdUnitTestSuite
## What a model is made of (flesh, machine, undead) decides whether it bleeds, leaks oil or crumbles. The army data has
## no model kind, so keywords in the name and rules decide; the old rule called every Tough(6+) unit a vehicle, so a
## Tough(12) monster burned with oil (VFX brief finding, maintainer 04.10.: "fix the Tough(6+) = vehicle heuristic").

const StuffScript = preload("res://scripts/vfx/model_stuff.gd")


func test_a_big_creature_is_no_longer_a_vehicle() -> void:
	var M = StuffScript.Stuff
	var table := [["Carnivo-Rex", ["Tough(12)", "Fear"], M.FLESH], ["Heavy Annihilator", ["Strider", "Tough(6)", "Self-Repair"], M.MACHINE],
		["APC", ["Tough(6)", "Transport(11)"], M.MACHINE], ["Predator", ["Tough(6)"], M.MACHINE],
		["Battle Brothers", ["Fearless"], M.FLESH], ["Bone Giant", ["Tough(6)", "Undead"], M.UNDEAD],
		["Ogre Brute", [{"name": "Tough", "rating": 6}, "Tough(6)"], M.FLESH]]
	for row in table:
		assert_int(StuffScript.stuff_of_props({"name": row[0], "special_rules": row[1]})).override_failure_message(row[0]) \
			.is_equal(row[2])


func test_a_battlefield_stain_follows_what_the_model_is_made_of() -> void:
	var main: Node = auto_free(load("res://scripts/main.gd").new())
	assert_bool(main.call("_stain_is_vehicle", {"name": "APC", "special_rules": ["Tough(6)", "Transport(11)"]})).is_true()
	assert_bool(main.call("_stain_is_vehicle", {"name": "Carnivo-Rex", "special_rules": ["Tough(12)", "Fear"]})).is_false()
	assert_bool(main.call("_stain_is_vehicle", {"name": "Warriors", "special_rules": ["Self-Repair"]})).is_true()
