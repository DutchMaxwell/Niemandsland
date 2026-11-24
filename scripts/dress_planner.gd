class_name DressPlanner
extends RefCounted
## Base class of a dressing class planner: one instance per class of the board, asked once per
## build what it places. A planner reads the board through the DressContext (layout, kit, story,
## specs and the grid lookups) and returns typed placements; the base places nothing.


## The placements this planner draws for `context`; a planner that places nothing returns [].
func plan(_context: DressContext) -> Array[DressPlacement]:
	return []
