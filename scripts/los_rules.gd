class_name LosRules
extends RefCounted
## Asgard tournament-standard line-of-sight helpers (Asgard Age of Fantasy, p.5):
## derive a model's Height category (1-6) from its profile. Pure/static so it is
## trivially testable and has no scene dependencies. The grid LOS query itself
## lives in terrain_overlay.gd (it owns the terrain grid).
##
## Height categories (Asgard p.5):
##   H1 Swarms
##   H2 Infantry / Artillery: no Tough; Heroes with Tough(3)
##   H3 Large Infantry / Cavalry / Chariots: Tough(3); Heroes with Tough(6)
##   H4 Large Cavalry / Monsters / Vehicles: Tough(6-9); Heroes with Tough(9)
##   H5 Large Monsters / Giants / Large Vehicles: Tough(12+)
##   H6 Titans: Tough(18+) and Fear

const HEIGHT_INFANTRY := 2  # default when no profile is available


## Asgard Height category (1-6) of a single model, derived from Tough + Hero/Fear.
## Category nuances we cannot read from the API (Swarm/Cavalry/Artillery) are
## approximated via Tough; this is faithful for the common cases and only matters
## for unit-as-blocker LOS (a later phase).
static func model_height_category(model: ModelInstance) -> int:
	if model == null:
		return HEIGHT_INFANTRY
	var tough: int = int(model.get_property("tough", 1))
	var is_hero: bool = model.has_special_rule("Hero")
	var has_fear: bool = model.has_special_rule("Fear")

	if tough >= 18 and has_fear:
		return 6
	if tough >= 12:
		return 5
	if tough >= 6:
		# Tough 6-11: monsters/vehicles are H4; a Hero of Tough(6) is one step smaller.
		return 3 if (is_hero and tough <= 6) else 4
	if tough >= 3:
		# Tough 3-5: large infantry/cavalry are H3; a Hero of Tough(3) is H2.
		return 2 if is_hero else 3
	return HEIGHT_INFANTRY  # no/low Tough -> infantry / artillery
