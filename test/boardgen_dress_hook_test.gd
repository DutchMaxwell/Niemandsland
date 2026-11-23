extends GdUnitTestSuite
## The dressing's hook into the board build (PLAN_RUINTOWN_DRESSING step 9): with no usable class the board is built exactly as before (same nodes, same colliders as a build with the dressing switched off); with the
## houses dressed (a fake planner on the stub kit) the old house look is absent (Houses, Roofs, RoofsHip, RoofsCatslide, Turrets, TurretRoofs), a Dress node exists, the colliders are IDENTICAL, and
## BoardgenGreybox.draws_itself(box, skip) - the zero scale of the instance loop - is false for exactly the house-class boxes (chimneys, lean-tos). A MultiMesh cannot be read back on the headless dummy renderer
## (its transforms come back as the identity), so the scale itself is judged on the BEFORE / AFTER stills. The static switches are put back after every test.

const SEED := 41
const CLASSES := ["houses", "tiers", "ladders", "walls", "towers", "ground", "props", "clutter"]


func after_test() -> void:
	BoardgenDress.test_mode = ""
	BoardgenDress.test_planners = {}


func _layout(seed: int, theme := "ruintown") -> Dictionary:
	return (ClassDB.instantiate("NmlCore") as Object).boardgen_layout_themed(seed, theme)


## A planner that dresses the houses with one stub box each (no GLB needed).
func _houses() -> GDScript:
	var s := GDScript.new()
	s.source_code = "extends RefCounted\nconst MODULES: Array[String] = [\"dr_litter_straw\"]\nstatic func plan(layout: Dictionary, _ctx: Dictionary) -> Array[Dictionary]:\n\tvar out: Array[Dictionary] = []\n\tfor lot: Dictionary in layout[\"lots\"]:\n\t\tif lot[\"kind\"] == \"Roofed\":\n\t\t\tout.append({\"module\": \"dr_litter_straw\", \"xf\": Transform3D(), \"cls\": \"houses\"})\n\treturn out\n"
	s.reload()
	return s


func _planners(houses: Variant) -> void:
	BoardgenDress.test_planners = {}
	for c in CLASSES:
		BoardgenDress.test_planners[c] = null
	BoardgenDress.test_planners["houses"] = houses


## A planner for a class that places nothing (it only says "this class is dressed").
func _silent() -> GDScript:
	var s := GDScript.new()
	s.source_code = "extends RefCounted\nconst MODULES: Array[String] = [\"dr_litter_straw\"]\nstatic func plan(_layout: Dictionary, _ctx: Dictionary) -> Array[Dictionary]:\n\treturn []\n"
	s.reload()
	return s


## {colliders: sorted [[size, centre]], paths: sorted node paths under the board with the engine's counters (@Type@123) taken out, instances: the Surfaces MultiMesh instance count}
func _build(layout: Dictionary) -> Dictionary:
	var table: Node3D = auto_free(Node3D.new())
	add_child(table)
	var board := BoardgenGreybox.attach(table, layout)
	var colliders := []
	for shape: CollisionShape3D in board.find_children("*", "CollisionShape3D", true, false):
		colliders.append([(shape.shape as BoxShape3D).size, shape.position])
	colliders.sort_custom(func(a: Array, b: Array) -> bool: return str(a) < str(b))
	var counter := RegEx.create_from_string("@(\\w+)@\\d+")
	var paths := []
	for n in board.find_children("*", "", true, false):
		paths.append(counter.sub(str(board.get_path_to(n)), "@$1", true))
	paths.sort()
	var silhouette := board.get_node_or_null("TownDressing/Silhouette") as MultiMeshInstance3D
	return {"colliders": colliders, "paths": paths, "instances": (board.get_node("Surfaces") as MultiMeshInstance3D).multimesh.instance_count, "silhouette": silhouette.multimesh.instance_count if silhouette != null else -1}


func test_without_a_usable_class_the_board_is_built_exactly_as_before() -> void:
	var layout := _layout(SEED)
	BoardgenDress.test_mode = "off"
	var off := _build(layout)
	BoardgenDress.test_mode = ""
	_planners(null)   # nothing to dress with: setup() is false
	var idle := _build(layout)
	assert_array(idle["paths"]).is_equal(off["paths"])
	assert_array(idle["colliders"]).is_equal(off["colliders"])
	assert_int(idle["instances"]).is_equal(off["instances"])
	assert_bool((off["paths"] as Array).has("TownDressing/Houses")).is_true()   # the old house look is there
	assert_bool((off["paths"] as Array).any(func(p: String) -> bool: return p.begins_with("Dress"))).is_false()
	assert_int((off["colliders"] as Array).size()).is_greater(50)


func test_with_the_houses_dressed_the_old_house_look_is_gone_and_the_colliders_are_identical() -> void:
	var layout := _layout(SEED)
	BoardgenDress.test_mode = "off"
	var before := _build(layout)
	BoardgenDress.test_mode = "stub"
	_planners(_houses())
	var after := _build(layout)
	var paths: Array = after["paths"]
	for gone in ["TownDressing/Houses", "TownDressing/Roofs", "TownDressing/RoofsHip", "TownDressing/RoofsCatslide", "TownDressing/Turrets", "TownDressing/TurretRoofs"]:
		assert_bool(paths.has(gone)).override_failure_message(gone).is_false()
		assert_bool((before["paths"] as Array).has(gone)).override_failure_message("control: " + gone).is_true()   # they all existed before
	assert_bool(paths.has("Dress") and paths.has("Dress/DressMesh") and paths.has("Dress/DressShadow")).is_true()
	assert_bool(paths.has("TownDressing/Silhouette")).is_true()   # walls, towers and tiers keep their old look
	assert_array(after["colliders"]).is_equal(before["colliders"])   # THE TRUTH: no collider moves, appears or vanishes
	assert_int(after["instances"]).is_equal(before["instances"])   # the same boxes, only their scale changes


func test_draws_itself_with_the_dressed_classes_is_false_for_exactly_the_house_boxes() -> void:
	var houses := 0
	var others := 0
	for s in [41, 25, 3]:
		for b: Dictionary in BoardgenGreybox.plan(_layout(s)):
			assert_bool(BoardgenGreybox.draws_itself(b)).is_equal(BoardgenGreybox.draws_itself(b, {}))   # no skip: as before
			assert_bool(BoardgenGreybox.draws_itself(b, {"tiers": true})).is_equal(BoardgenGreybox.draws_itself(b) and BoardgenDress.box_class(b) != "tiers")
			var drawn := BoardgenGreybox.draws_itself(b, {"houses": true})
			if BoardgenDress.box_class(b) == "houses":
				assert_bool(drawn).is_false()   # the chimney and lean-to boxes: zero scale, collider (none: they are not solid) untouched
				houses += 1
			else:
				assert_bool(drawn).is_equal(BoardgenGreybox.draws_itself(b))
				others += 1
	assert_bool(houses > 0 and others > houses).is_true()


func test_the_silhouette_skips_the_wall_tower_and_tier_pieces_of_the_classes_the_dressing_draws() -> void:
	var layout := _layout(SEED)
	BoardgenDress.test_mode = "off"
	var all: int = _build(layout)["silhouette"]
	var parts := BoardgenTownSilhouette.wall_parts(layout)
	var tiers := parts.filter(func(p: Dictionary) -> bool: return BoardgenTownSilhouette._part_class(layout, p) == "tiers").size()
	var walls := parts.filter(func(p: Dictionary) -> bool: return BoardgenTownSilhouette._part_class(layout, p) == "walls").size()
	var towers := parts.size() - tiers - walls
	var extras := all - parts.size()   # the ruin gables and the rafters of the tiers
	assert_bool(tiers > 0 and walls > 0 and towers > 0 and extras > 0).is_true()   # every piece kind exists on this board
	BoardgenDress.test_mode = "stub"
	_planners(null)
	BoardgenDress.test_planners["tiers"] = _silent()
	assert_int(_build(layout)["silhouette"]).is_equal(walls + towers)   # no tier part, no ruin gable, no rafter
	_planners(null)
	BoardgenDress.test_planners["walls"] = _silent()
	assert_int(_build(layout)["silhouette"]).is_equal(all - walls)
	_planners(null)
	BoardgenDress.test_planners["towers"] = _silent()
	assert_int(_build(layout)["silhouette"]).is_equal(all - towers)
	_planners(null)
	for c in ["tiers", "walls", "towers"]:
		BoardgenDress.test_planners[c] = _silent()
	assert_int(_build(layout)["silhouette"]).is_equal(0)


func test_a_deepworks_board_never_creates_a_dressing() -> void:
	BoardgenDress.test_mode = "stub"
	_planners(_houses())
	var built := _build(_layout(SEED, "deepworks"))
	assert_bool((built["paths"] as Array).any(func(p: String) -> bool: return p.begins_with("Dress"))).is_false()
