class_name BoardgenSumps
extends Node3D
## The toxic sumps of a seeded boardgen board (the layout's Hazard cells, e.g. the Sump landmark): a low concrete kerb round each pool
## and one green glow per pool. The liquid itself (ripples, depth, scum, bubbles, the stain on the floor and walls) is the board shader.
## VISUAL ONLY: the cells stay the Dangerous ground the rules read, nothing here is a collider or a blocker. plan-style functions are pure
## functions of the layout, so one seed always builds the same sumps.

const INCHES_TO_METERS := 0.0254
const SKIN_IN := 0.04   # the level-0 ground skin
## The kerb stands inside the pool's own outer rim, never on the open floor, and is as low as a flat prop: a base may stand on it.
const KERB_W_IN := 0.28
const KERB_H_IN := 0.12
const GLOW := Color(0.3, 1.0, 0.18)
const GLOW_ENERGY := 0.1
const GLOW_RANGE_IN := 9.0
const GLOW_HEIGHT_IN := 0.7


static func is_sump(layout: Dictionary, x: int, z: int) -> bool:
	if x < 0 or z < 0 or x >= layout["nx"] or z >= layout["nz"]:
		return false
	var c: Dictionary = layout["cells"][z * layout["nx"] + x]
	return c["level"] == 0 and c["lot_kind"] == "Hazard"


## The kerb boxes (inches off the board centre, kind "kerb"): along every edge of a sump cell that meets open level-0 floor. An edge
## against a tier wall or the board rim gets none (the wall is the basin's side).
static func kerbs(layout: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var cell := float(layout["cell_in"])
	var origin := Vector2(layout["nx"], layout["nz"]) * cell * -0.5
	for z in layout["nz"]:
		for x in layout["nx"]:
			if not is_sump(layout, x, z):
				continue
			var lo := origin + Vector2(x, z) * cell
			for d in BoardgenProps.DIRS:
				var o := Vector2i(x, z) + d
				if is_sump(layout, o.x, o.y) or o.x < 0 or o.y < 0 or o.x >= layout["nx"] or o.y >= layout["nz"] \
						or layout["cells"][o.y * layout["nx"] + o.x]["level"] > 0:
					continue
				var a := lo + Vector2(maxf(d.x, 0.0) * (cell - KERB_W_IN), maxf(d.y, 0.0) * (cell - KERB_W_IN))   # inset on the side of d
				var size := Vector2(KERB_W_IN if d.x != 0 else cell, KERB_W_IN if d.y != 0 else cell)
				out.append({"lo": Vector3(a.x, SKIN_IN, a.y), "hi": Vector3(a.x + size.x, SKIN_IN + KERB_H_IN, a.y + size.y), "kind": "kerb", "solid": false})
	return out


## The pools: connected sump cells, {cells: Array[Vector2i], centre: Vector2 (inches off the board centre)}, in scan order.
static func pools(layout: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seen := {}
	var cell := float(layout["cell_in"])
	var origin := Vector2(layout["nx"], layout["nz"]) * cell * -0.5
	for z in layout["nz"]:
		for x in layout["nx"]:
			if seen.has(Vector2i(x, z)) or not is_sump(layout, x, z):
				continue
			var members: Array[Vector2i] = []
			var todo: Array[Vector2i] = [Vector2i(x, z)]
			seen[Vector2i(x, z)] = true
			while not todo.is_empty():
				var at: Vector2i = todo.pop_back()
				members.append(at)
				for d in BoardgenProps.DIRS:
					if is_sump(layout, at.x + d.x, at.y + d.y) and not seen.has(at + d):
						seen[at + d] = true
						todo.append(at + d)
			var sum := Vector2.ZERO
			for m in members:
				sum += origin + (Vector2(m) + Vector2(0.5, 0.5)) * cell
			out.append({"cells": members, "centre": sum / members.size()})
	return out


## One shadowless green omni light just over each pool: it tints the kerb, the walls and the feet of the models beside it.
func build(layout: Dictionary) -> void:
	for pool in pools(layout):
		var light := OmniLight3D.new()
		light.position = Vector3(pool["centre"].x, GLOW_HEIGHT_IN, pool["centre"].y) * INCHES_TO_METERS
		light.light_color = GLOW
		light.light_energy = GLOW_ENERGY
		light.omni_range = GLOW_RANGE_IN * INCHES_TO_METERS
		add_child(light)
