class_name BoardgenTownWater
## The town's standing water as surfaces of shaders/ruintown_water.gdshader (look plan R18): the fountain basin holds water that catches
## the moon and the lamps. Drawn only: no collider, no shadow, nothing a model stands on. Every surface sits inside its basin.

const SHADER := preload("res://shaders/ruintown_water.gdshader")
## The dress kit's fountain (dr_fountain, forge kit_k4 fountain()): the basin wall's inner face is an octagon of corner radius 1.95 in, the
## kit's own water plane is 0.78 in up. The water sits a hair above it and a hair inside the wall.
const KIT_WALL_CORNER_IN := 1.95
const KIT_WATER_IN := 0.78
const LIFT_IN := 0.02
## The shader's flat sheen per quality preset (lead decision 26.11.): Ultra's own reflections already light the water about 10 luma
## over Medium, so there the sheen goes and the ripple glints stay; the basin stays under the setts round it.
const SHEEN := 0.3
const SHEEN_ULTRA := 0.0


## One Dictionary per water surface, in inches off the board centre: {centre_in: Vector2, half_in: Vector2 (x = the apothem of an octagon),
## y_in, octagon, bank_in, ring}. `kit_props` = the dress kit draws the fountain (dr_fountain) instead of the kit-off boxes.
static func surfaces(layout: Dictionary, kit_props: bool) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var cell_in := float(layout["cell_in"])
	var origin := Vector2(layout["nx"], layout["nz"]) * cell_in * -0.5
	for lm: Dictionary in layout["landmarks"]:
		if lm["kind"] != "TankCluster":
			continue
		var c := origin + (Vector2(lm["x"], lm["z"]) + Vector2(lm["w"], lm["h"]) * 0.5) * cell_in
		var apothem := KIT_WALL_CORNER_IN * cos(PI / 8.0) - 0.01 if kit_props else BoardgenGreybox.FOUNTAIN_APOTHEM_IN - BoardgenGreybox.FOUNTAIN_WALL_IN * 0.5 - 0.01
		var y := KIT_WATER_IN + LIFT_IN if kit_props else BoardgenGreybox.FOUNTAIN_WATER_IN + 0.01
		out.append({"centre_in": c, "half_in": Vector2(apothem, apothem), "y_in": y, "octagon": true, "bank_in": 0.0, "ring": 0.6})
	return out


static func sheen_for(preset: int) -> float:
	return SHEEN_ULTRA if preset >= GraphicsSettings.QualityPreset.ULTRA else SHEEN


## The preset's sheen on every surface of `water` (BoardgenGreybox calls this where the board's materials learn the preset).
static func apply_preset(water: Node, preset: int) -> void:
	if water == null:
		return
	for mi: MeshInstance3D in water.find_children("*", "MeshInstance3D", false, false):
		(mi.material_override as ShaderMaterial).set_shader_parameter("sheen", sheen_for(preset))


## The water of the board: one plane per surface under one node (null when the board holds none).
static func build(layout: Dictionary, kit_props: bool) -> Node3D:
	var list := surfaces(layout, kit_props)
	if list.is_empty():
		return null
	var root := Node3D.new()
	root.name = "TownWater"
	for s: Dictionary in list:
		var mesh := PlaneMesh.new()
		mesh.size = Vector2(s["half_in"]) * 2.0 * BoardgenGreybox.INCHES_TO_METERS
		mesh.subdivide_width = 8
		mesh.subdivide_depth = 8
		var mat := ShaderMaterial.new()
		mat.shader = SHADER
		mat.set_shader_parameter("half_in", s["half_in"])
		mat.set_shader_parameter("octagon", s["octagon"])
		mat.set_shader_parameter("bank_in", s["bank_in"])
		mat.set_shader_parameter("ring_strength", s["ring"])
		mat.set_shader_parameter("clock", 0.0 if BoardgenTownLife.pinned else 1.0)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var c: Vector2 = s["centre_in"]
		mi.position = Vector3(c.x, float(s["y_in"]), c.y) * BoardgenGreybox.INCHES_TO_METERS
		root.add_child(mi)
	return root
