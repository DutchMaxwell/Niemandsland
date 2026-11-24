class_name BoardgenDress
extends Node3D
## The orchestrator of the ruin-town dressing (docs/adr/0003-generated-board-dressing.md): the grid
## stays the gameplay truth, authored modules become the look. It asks every planner (one script per
## class of the board, so each class can be added on its own) for placements, wraps them as
## DressPlacement, checks them against the honesty rules in a debug build, merges them into ONE mesh
## with one surface per shared material (DressMesh) plus the low-poly shadow proxy (DressShadow),
## and lets a planner add what is not a module (build_extra). A class switches from the old look to
## the dressing only when its planner exists AND its modules are usable (kit cached, Medium and up);
## `classes()` names those classes so the old builders skip them. Without a kit nothing here is
## active. A planner script has `const MODULES: Array[String]`, `static func plan(layout, ctx) ->
## Array[Dictionary]` and optionally `static func build_extra(layout, parent: Node3D, ctx)`.

const PLANNERS := ["houses", "tiers", "ladders", "walls", "towers", "ground", "props", "clutter"]
## Test switches: "off" = never dress, "stub" = force the stub kit (a box per module);
## `test_planners` = {class: Script} used instead of the files.
static var test_mode := ""
static var test_planners := {}

var kit: BoardgenDressKit
var story: Dictionary = {}
var _classes := {}  # class -> planner Script, the classes this board draws as modules


## The planner script of a class: a test double, else scripts/boardgen_dress_<name>.gd when it
## exists, else null.
static func planner(name: String) -> Script:
	if test_planners.has(name):
		return test_planners[name]
	var path := "res://scripts/boardgen_dress_%s.gd" % name
	return load(path) if ResourceLoader.exists(path) else null


## Which class draws a plan box today (BoardgenGreybox.plan): "" for a box that draws nothing (a
## roofed house, a hidden or collider-only box).
static func box_class(box: Dictionary) -> String:
	var kind: String = box["kind"]
	if box.has("lean_to") or kind == "brick":
		return "houses"
	if box.has("merlon") or (kind == "rubble" and box.has("prop")):
		return "walls"
	if box.has("party_stub") or ["tier1", "tier2", "tier3"].has(kind):
		return "tiers"
	if kind == "ladder" and not box.has("lantern"):
		return "ladders"
	if box.get("lm", "") == "Sump":
		return "ground"
	if box.has("lantern") or box.has("lm"):
		return "props"
	if box.has("prop"):
		return "clutter"
	return "ground" if ["ground", "street", "yard", "rough", "hazard", "rubble"].has(kind) else ""


## Prepares the dressing for a layout: true when this board is a town, the dressing is not switched
## off and at least one class has a planner with usable modules.
func setup(layout: Dictionary) -> bool:
	if test_mode == "off" or str(layout.get("theme", "")) != BoardgenTheme.RUIN_TOWN:
		return false
	var town_kit := BoardgenKit.new(BoardgenTheme.TOWN_LIBRARY)
	town_kit.name = "Kit"
	add_child(town_kit)
	kit = BoardgenDressKit.new(town_kit, test_mode == "stub")
	story = BoardgenDressStory.of(layout)
	for name: String in PLANNERS:
		var script := planner(name)
		if (
			script != null
			and kit.usable((script.get_script_constant_map() as Dictionary).get("MODULES", []))
		):
			_classes[name] = script
	return not _classes.is_empty()


## The classes drawn by modules on this board: {class: true} (the `skip` the old builders get).
func classes() -> Dictionary:
	var out := {}
	for name: String in _classes:
		out[name] = true
	return out


## The dressed board: every usable planner's placements, merged into DressMesh (no shadows of its
## own) and DressShadow (shadows only), then each planner's own extras.
func build(layout: Dictionary) -> void:
	var context := DressContext.new(layout, kit, story, int(layout.get("seed", 0)))
	var ctx := {"kit": kit, "story": story, "meta": kit.meta, "seed": int(layout.get("seed", 0))}
	var placements: Array[DressPlacement] = []
	for name: String in _classes:
		for p: Dictionary in (_classes[name] as Script).call("plan", layout, ctx):
			placements.append(DressPlacement.from_dict(p))
	if OS.is_debug_build():
		for line in BoardgenDressRules.violations(context, placements):
			push_warning("BoardgenDress: " + line)
	var mesh := MeshInstance3D.new()
	mesh.name = "DressMesh"
	mesh.mesh = BoardgenDressMesh.merge(placements, kit)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var lib: TiefwerkLibrary = null
	if test_mode != "stub":
		lib = TiefwerkLibrary.new(BoardgenTheme.TOWN_LIBRARY)
		lib.name = "TownLibrary"
		add_child(lib)
	var materials := BoardgenDressMaterials.make(kit.meta, lib)
	for surface in mesh.mesh.get_surface_count():
		var material_name: String = mesh.mesh.surface_get_name(surface)
		if materials.has(material_name):
			mesh.mesh.surface_set_material(surface, materials[material_name])
	add_child(mesh)
	var shadow := MeshInstance3D.new()
	shadow.name = "DressShadow"
	shadow.mesh = BoardgenDressMesh.shadow(placements, kit)
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	add_child(shadow)
	for name: String in _classes:
		if (_classes[name] as Script).has_method("build_extra"):
			(_classes[name] as Script).call("build_extra", layout, self, ctx)
