class_name LessonRecipes
extends RefCounted

static func recipe(id: String) -> Dictionary:
	if id == "S-01":
		return {"size_feet": Vector2(4, 4), "biome": "temperate_grassland",
			"deployment": -1, "phase": 0, "round": 1, "sides": [
				{"player": 1, "fixture": "res://assets/tutorial/tutorial_army_p1.json", "units": [
					{"name": "Battle Brothers", "nth": 1, "tag": "alpha", "at_in": Vector2(0, 12)}]}
			]}
	if id == "S-02":
		return {"size_feet": Vector2(4, 4), "biome": "temperate_grassland",
			"deployment": -1, "phase": 0, "round": 1, "sides": []}
	if id == "S-03":
		return {"size_feet": Vector2(6, 4), "biome": "temperate_grassland",
			"deployment": 1, "phase": 0, "round": 1, "sides": []}
	return {}
