extends SceneTree
## D8a (NML-1073 M5): the ground truth that proves core/nml-core/src/objectives.rs
## draws the SAME layout ObjectiveLayout.generate draws, for the same seed, board and
## mission. Without this fixture the Rust mirror is an assertion, not a fact.
##
## The board is held FIXED across the seeds on purpose: the layout seed drives the
## objective stream, and pinning one board isolates the generator from the terrain
## layouter. `cells` travels with the fixture so the Rust test needs no bank.
##
## Run once: godot --headless --path . -s res://tools/objective_fixture.gd
## Writes core/nml-core/tests/fixtures/objective_layout.json.

const OUT_PATH := "res://core/nml-core/tests/fixtures/objective_layout.json"
const BOARD_SEED := 20260710      # arena_match.LAYOUT_SEED — the board the corpora played
const SEEDS := 50


func _init() -> void:
	var world := SchoolTerrain.generate(BOARD_SEED)
	var cells: Dictionary = world["cells"]
	var n: int = world["n"]
	var cell_list: Array = []
	for k in cells:
		cell_list.append([(k as Vector2i).x, (k as Vector2i).y, int(cells[k])])
	cell_list.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	var style := DeploymentCatalog.get_style("front_line")
	# The three missions the generator actually serves: the two catalog 'alternate'
	# missions, plus a synthetic fixed-count one that exercises the branch where the
	# count spec is a NUMBER and therefore draws nothing.
	var missions := {
		"duel": MissionCatalog.get_mission("duel"),
		"pitched_battle": MissionCatalog.get_mission("pitched_battle"),
		"alternate_fixed4": {"markers": {"count": 4, "placement": "alternate"}},
	}
	var cases: Array = []
	for mid in missions:
		for s in range(SEEDS):
			var seed_v := BOARD_SEED + s
			cases.append({"mission": mid, "count_spec": (missions[mid]["markers"] as Dictionary)["count"],
				"layout_seed": seed_v,
				"layout": ObjectiveLayout.generate(seed_v, missions[mid], style, cells, n)})
	var f := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({"board_seed": BOARD_SEED, "n": n, "cells": cell_list,
		"zones": style["zones"], "table_w_in": 72.0, "table_d_in": 48.0, "cases": cases}, "  "))
	f.close()
	print("[OBJFIX] %d cases over %d seeds x %d missions -> %s" % [
		cases.size(), SEEDS, missions.size(), OUT_PATH])
	quit(0)
