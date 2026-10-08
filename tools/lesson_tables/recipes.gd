class_name LessonRecipes
extends RefCounted

## Recipe schema (documentation + tests). RECIPE_KEYS: the top-level keys a recipe may carry.
## UNIT_KEYS: the per-unit pick keys. The D1 combat-seam keys let a lesson table start in a
## prepared state (a Shaken unit, a Fatigued unit, parked casualties) instead of rolling for it.
const RECIPE_KEYS := ["size_feet", "biome", "deployment", "phase", "round", "sides", "ai_slots"]
const UNIT_KEYS := ["name", "nth", "tag", "at_in", "label", "shaken", "fatigued", "dead"]

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
	if id == "S-04":
		return {"size_feet": Vector2(4, 4), "biome": "temperate_grassland",
			"deployment": -1, "phase": 1, "round": 1, "ai_slots": [2], "sides": [
				{"player": 1, "fixture": "res://assets/tutorial/tutorial_army_p1.json", "units": [
					{"name": "Battle Brothers", "nth": 1, "tag": "alpha", "label": "Alpha Squad", "at_in": Vector2(-8, 16)},
					{"name": "Battle Brothers", "nth": 2, "tag": "bravo", "label": "Bravo Squad", "at_in": Vector2(8, 16)}]},
				{"player": 2, "fixture": "res://assets/tutorial/tutorial_army_p2.json", "units": [
					{"name": "Warriors", "nth": 1, "tag": "target", "at_in": Vector2(0, -18)}]}]}
	if id == "S-05":
		return {"size_feet": Vector2(4, 4), "biome": "temperate_grassland",
			"deployment": -1, "phase": 1, "round": 1, "ai_slots": [2], "sides": [
				{"player": 1, "fixture": "res://assets/tutorial/tutorial_army_p1.json", "units": [
					{"name": "Battle Brothers", "nth": 1, "tag": "alpha", "label": "Alpha Squad", "at_in": Vector2(0, 10)}]},
				{"player": 2, "fixture": "res://assets/tutorial/tutorial_army_p2.json", "units": [
					{"name": "Warriors", "nth": 1, "tag": "target", "at_in": Vector2(0, -8)},
					{"name": "Warriors", "nth": 2, "tag": "far", "at_in": Vector2(0, -22)}]}]}
	if id == "S-06":
		return {"size_feet": Vector2(4, 4), "biome": "temperate_grassland",
			"deployment": -1, "phase": 1, "round": 1, "ai_slots": [2], "sides": [
				{"player": 1, "fixture": "res://assets/tutorial/tutorial_army_p1.json", "units": [
					{"name": "Battle Brothers", "nth": 1, "tag": "alpha", "label": "Alpha Squad", "at_in": Vector2(0, 7)}]},
				{"player": 2, "fixture": "res://assets/tutorial/tutorial_army_p2.json", "units": [
					{"name": "Warriors", "nth": 1, "tag": "target", "at_in": Vector2(0, -1)}]}]}
	return {}
