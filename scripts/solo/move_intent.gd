class_name MoveIntent
extends RefCounted
## Solo/AI move-intent planning (Phase 0). Pure, side-effect-free geometry for "move this unit
## toward a point, but no further than its movement allowance". The unit moves as a RIGID block
## (every model shifts by the same table-plane delta), which preserves formation + coherency and
## matches how a regiment tray moves. Distances are clamped from the unit's ANCHOR (the centroid
## of its alive models) — the standard simplification of OPR unit movement for the indicator.
##
## This module decides WHERE; applying the move to real nodes (+ multiplayer broadcast + an undo
## MoveAction) is the executor's job, wired against ObjectManager when the SoloController lands.
## Kept pure so the planning is fully headless-testable. Straight-line only for now; obstacle-aware
## pathfinding is a later phase.

const INCHES_TO_METERS := 0.0254

## Table-plane centroid of a set of model world positions. Returns ZERO for an empty set.
## The anchor's Y is the average model Y (models rest at table height, so this is ~0).
static func anchor_of(model_positions: Array) -> Vector3:
	if model_positions.is_empty():
		return Vector3.ZERO
	var sum := Vector3.ZERO
	for pos: Vector3 in model_positions:
		sum += pos
	return sum / float(model_positions.size())


## The point an anchor reaches moving toward `target`, capped at `max_inches`. If the target is
## within range it is returned as-is; otherwise the point exactly `max_inches` along the direction.
## Movement is on the table plane (Y is taken from the anchor, so the unit doesn't rise/sink).
static func clamp_destination(anchor: Vector3, target: Vector3, max_inches: float) -> Vector3:
	var to_target := target - anchor
	to_target.y = 0.0
	var dist := to_target.length()
	var max_m := max_inches * INCHES_TO_METERS
	if dist <= max_m or dist < 0.0001:
		return Vector3(target.x, anchor.y, target.z)
	var step := to_target.normalized() * max_m
	return anchor + step


## The rigid table-plane translation that moves a unit whose anchor is at `anchor` so the anchor
## lands on `destination`. Y is zeroed — a unit move never changes model heights.
static func move_delta(anchor: Vector3, destination: Vector3) -> Vector3:
	return Vector3(destination.x - anchor.x, 0.0, destination.z - anchor.z)


## Convenience: the rigid delta to move a unit (given its model positions) toward `target`, capped
## at `max_inches`. Apply this delta to every model. Returns ZERO if the unit has no models.
static func plan_unit_move(model_positions: Array, target: Vector3, max_inches: float) -> Vector3:
	if model_positions.is_empty():
		return Vector3.ZERO
	var anchor := anchor_of(model_positions)
	var destination := clamp_destination(anchor, target, max_inches)
	return move_delta(anchor, destination)


## Straight-line table-plane distance between two points, in inches (for range/decision checks).
static func distance_inches(a: Vector3, b: Vector3) -> float:
	var d := Vector3(b.x - a.x, 0.0, b.z - a.z)
	return d.length() / INCHES_TO_METERS
