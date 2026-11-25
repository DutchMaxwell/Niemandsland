class_name BoardgenDressLadders
extends DressPlanner
## The ladder planner of the ruin-town dressing (SPEC_RUINTOWN_DRESSING step 21): the kit ladder
## plan of BoardgenGreybox renamed to the dr_ modules - one 3 in segment per 3 in of rise, the
## topmost one dr_ladder_top, at the very transforms the greybox uses (metres, board space, origin
## on the wall face, +z away from it). Pure data: the box ladders it replaces are not solid, so no
## collider is added or removed. Without the two modules the class stays on the greybox ladders.

const MODULES: Array[String] = ["dr_ladder_3in", "dr_ladder_top"]
const KIT_TO_DRESS := {"ladder_3in": "dr_ladder_3in", "ladder_top": "dr_ladder_top"}


## One placement per ladder segment of the board, class "ladders".
func plan(context: DressContext) -> Array[DressPlacement]:
	var out: Array[DressPlacement] = []
	var kit := BoardgenGreybox.ladder_kit_plan(context.layout)
	for key: String in kit:
		for item: Dictionary in kit[key]:
			out.append(DressPlacement.new(KIT_TO_DRESS[key], item["xf"], "ladders"))
	return out
