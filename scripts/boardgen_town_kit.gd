class_name BoardgenTownKit
extends Node3D
## The authored K-R1 modules of a ruin-town board (PLAN_RUINTOWN phase B): tiled gable roofs (two pitches; a quarter broken over a
## rafter frame), chimneys, merlons (wall, towers, hall) and rubble heaps against both ends of every wall breach. VISUAL ONLY, in the
## same places as the procedural pieces they replace (nobody stands on a roof; a heap stays inside the 0.75 in wall strip).
## Each module is drawn with the world-triplanar material of ONE texture set (TiefwerkLibrary keyed "ruintown") when the set is cached,
## else with the kit's vertex-colour material and a tint. active() is false on Low / web or while a module is missing: then the
## procedural look stays (prism roofs, chimney and merlon boxes). Dev: NML_RUINTOWN_KIT_DIR (GLBs), NML_RUINTOWN_LIB_DIR (manifest + .ctex).

const THEME := "ruintown"
const INCHES_TO_METERS := 0.0254
const ROOF_L_IN := 6.6   # the reference roof the modules were built at; each lot stretches it
const ROOF_W_IN := 3.6
const ROOF_H_IN := {"roof_gable_low": 1.6, "roof_gable_steep": 2.6, "roof_sag_low": 1.6, "roof_sag_steep": 2.6, "roof_broken_a": 2.0, "roof_broken_b": 2.0, "roof_rafters": 2.0}
const BROKEN_ROOF_SHARE := 0.34   # (train 3, H2: one roof in three is broken, at least one per board half)
## (train 3, H2) the instance colour per roof on top of the set's tint: 60 % slate blue-grey, 40 % a dull clay (the toy red is gone).
const ROOF_SLATE := Color(0.62, 0.78, 0.92)
const ROOF_CLAY := Color(0.62, 0.72, 0.8)
## (train 3) the battlements were the palest thing in the wall view: every merlon and capstone a step darker and weathered, two in five mossy.
const MERLON_WEATHERED := Color(0.62, 0.63, 0.6)
const MERLON_MOSSY := Color(0.5, 0.6, 0.44)
const ROOF_PLAIN_VALUE := 0.5   # (ROOF-WARM) a textureless kit roof's value against TINT x instance colour
const ROOF_UV_TILE_IN := 3.0   # the roof modules' UVs count tiles of this size (kr1_town.py roof_uv)
const CHIMNEY_TOP_IN := 3.6   # a chimney module's cap height above its foot (the foot sinks into the house)
const MODULES := ["roof_gable_low", "roof_gable_steep", "roof_broken_a", "roof_broken_b", "roof_rafters", "chimney_pots", "chimney_broken",
	"merlon", "merlon_broken", "rubble_a", "rubble_b", "rubble_c"]
const TINT := {"roof_tiles": Color(0.44, 0.38, 0.35), "timber": Color(0.42, 0.30, 0.20), "coursed_stone": Color(0.62, 0.58, 0.52), "none": Color.WHITE}
## The instance colour on a textured module: warms the dark clay tiles towards the town's red roofs, cools the stone towards the wall's grey.
const TEXTURED_TINT := {"roof_tiles": Color(0.6, 0.76, 0.92), "timber": Color(0.84, 0.9, 1.0), "coursed_stone": Color(0.62, 0.68, 0.76), "none": Color.WHITE}
## The authored clutter of BoardgenTownClutter (batches A2 / A2b / A6): the texture set each module is drawn with (the rest is "none": the kit's vertex colours, real colours for plants and cloth).
const CLUTTER_SET := {"tower_cap_burnt": "timber", "barrel": "timber", "crate": "timber", "bucket": "timber", "woodpile": "timber", "barrel_broken": "timber", "crate_broken": "timber", "cart_wreck": "timber", "loose_wheel": "timber",
	"splinters_flat": "timber", "trough": "coursed_stone", "debris_flat_a": "coursed_stone", "debris_flat_b": "coursed_stone",
	"fountain_basin": "coursed_stone", "fountain_column": "coursed_stone", "statue_plinth": "coursed_stone", "statue_stump": "coursed_stone", "pool_kerb": "coursed_stone", "well_ring": "coursed_stone", "well_frame": "timber",
	"hall_column_a": "coursed_stone", "hall_column_b": "coursed_stone", "hall_pediment": "coursed_stone", "hall_step": "coursed_stone", "tower_turret": "coursed_stone", "pool_spout": "coursed_stone",
	"rubble_heap_a": "coursed_stone", "rubble_heap_b": "coursed_stone", "stall_frame": "timber", "stall_frame_ruined": "timber", "sign_board_loaf": "timber", "sign_board_boot": "timber", "timber_ladder_3in": "timber", "timber_ladder_top": "timber",
	"cart_toppled": "timber", "handcart": "timber", "table_overturned": "timber", "stall_collapsed": "timber", "barricade": "timber", "woodpile_block": "timber", "trough_used": "coursed_stone",
	"fence_wattle": "timber", "fence_wattle_gap": "timber", "fence_wattle_corner": "timber", "fence_plank": "timber", "fence_plank_gap": "timber", "fence_plank_corner": "timber",
	"sign_large_key": "timber", "sign_large_fish": "timber", "sign_large_mug": "timber", "sign_large_shears": "timber"}
## The A7 / A8 modules drawn in their own vertex colours (loads, cloth, hay: a texture set would draw wood grain on sacks and canvas).
const OWN_COLOUR := ["cart_toppled_load", "handcart_load", "table_overturned_load", "stall_collapsed_cloth", "hay_heap", "sign_large_iron"]
## A module's own instance tint on top of its set's (the vertex colour of the module is baked by the assets lane; this is the table's side of the same knob): the pool kerb's pale top read as a dashed
## white line round the pond from above, so its run is tinted down to a weathered stone.
## The kit's ladder segments (a 3 in segment and the top segment with stiles past the edge): the SAME transforms as the Deepworks kit ladders - BoardgenGreybox.ladder_kit_plan(layout), one segment per
## 3 in of every connector's rise, the origin on the wall face at the connector's edge point, +z away from the wall - so the walkable / ladder data is identical (boxes of kind ladder are not solid).
const LADDER_MODULES := ["timber_ladder_3in", "timber_ladder_top"]
const MODULE_TINT := {"pool_kerb": Color(0.52, 0.55, 0.6), "tower_cap_burnt": Color(0.32, 0.30, 0.28), "rubble_heap_a": Color(0.5, 0.44, 0.38), "rubble_heap_b": Color(0.36, 0.32, 0.28),
	"fountain_basin": Color(0.6, 0.63, 0.58), "fountain_basin_b": Color(0.6, 0.63, 0.58), "fountain_column": Color(0.64, 0.66, 0.6),   # (train 3, lead: the basin was the palest thing in the street view - grey weathered stone like the merlons)
	"hay_heap": Color(0.7, 0.64, 0.52), "stall_collapsed_cloth": Color(0.76, 0.72, 0.68), "lantern_post": Color(0.17, 0.165, 0.16), "lantern_post_iron": Color(0.4, 0.4, 0.4),
	"weeds_a": Color(0.62, 0.46, 0.42), "weeds_b": Color(0.62, 0.46, 0.42), "ivy_cluster_small": Color(0.62, 0.46, 0.42), "ivy_cluster_large": Color(0.62, 0.46, 0.42),
	"ivy_strand_a": Color(0.62, 0.46, 0.42), "ivy_strand_b": Color(0.62, 0.46, 0.42)}   # (lead review of #3312: the plants were houseplant green, the most saturated thing in the frame - a dull grey-green, darker than the wall)   # (21.11.: the hay and the striped cloth were the palest shapes of a scene; the lamp's base and cage read as white bars - dark iron now, only the glass glows)   # (heaps: grey-brown rubble and ash, never a white blob - lead 21.11.)   # a charred frame: the timber grain, dark
## Glass of a lamp and the coals of a brazier: drawn with an emissive material, the OmniLight sits at their origin.
const GLOW := {"lantern_glow": Color(1.0, 0.72, 0.38), "brazier_coals": Color(1.0, 0.45, 0.18)}

var kit: BoardgenKit
var lib: TiefwerkLibrary


func _init() -> void:
	kit = BoardgenKit.new(THEME)
	kit.name = "Kit"
	add_child(kit)
	lib = TiefwerkLibrary.new(THEME)
	lib.name = "Library"
	add_child(lib)


func active() -> bool:
	return kit.usable(MODULES)


## The texture set a module is drawn with.
static func set_of(module: String) -> String:
	if BoardgenTownKit.CLUTTER_SET.has(module):
		return CLUTTER_SET[module]
	if module.begins_with(("weeds")) or module.begins_with("bramble") or module.begins_with("dead_tree") or module.begins_with("ivy") or module.begins_with("lantern") or module in OWN_COLOUR or module in ["cloth_flat", "laundry_line", "sack_pile", "fountain_leaves", "stall_awning", "stall_awning_ruined", "brazier", "sign_bracket"]:
		return "none"
	if module in ["roof_rafters", "beam_end", "shutter", "shutter_open", "door"] or module.begins_with("hf_"):
		return "timber"
	return "roof_tiles" if module.begins_with("roof_") else "coursed_stone"


## True for a greybox box the kit draws instead (a chimney or a merlon).
static func replaces(box: Dictionary) -> bool:
	return box.get("merlon", false) or box["kind"] == "brick"


## True for the SOLID box of a fountain or a statue plinth when the kit draws that landmark instead (its collider stays).
func draws_landmark(box: Dictionary) -> bool:
	match box.get("lm", ""):
		"TankCluster":
			return kit.usable(BoardgenTownClutter.FOUNTAIN_MODULES)
		"Crane":
			return kit.usable(BoardgenTownClutter.STATUE_MODULES)
	return false


## True for a greybox box an authored clutter module draws instead: a lamp post / its glass cube when the lamp modules are cached, a strip prop whose piece is cached.
func replaces_clutter(box: Dictionary) -> bool:
	if box["kind"] == "ladder" and not box.get("lantern", false):   # a timber box ladder (not a lamp post, which borrows the colour): its rails and rungs are the kit's ladder segments
		return kit.usable(LADDER_MODULES)
	if box.get("lantern", false):
		return kit.usable(BoardgenTownClutter.LAMP_MODULES)
	var m := BoardgenTownClutter.prop_module(box)
	return m != "" and kit.usable([m])


static func _item(basis: Basis, at_in: Vector3) -> Dictionary:
	return {"xf": Transform3D(basis, at_in * INCHES_TO_METERS), "colour": Color.WHITE}


## {module: [{xf, colour}]}, metres off the board centre. Pure data.
static func plan(layout: Dictionary) -> Dictionary:
	var out := {}
	var add := func(m: String, item: Dictionary) -> void:
		if not out.has(m):
			out[m] = []
		out[m].append(item)
	var add_all := func(m: String, items: Array) -> void:
		for item: Dictionary in items:
			add.call(m, item)
	var gables := BoardgenTownDressing.roofs(layout).filter(func(r: Dictionary) -> bool: return r["type"] == "gable")   # hips and catslides have no module: the procedural meshes stay
	var lowest := {}   # per half: the gable with the lowest hash breaks if none does by its own hash
	for r: Dictionary in gables:
		var h := BoardgenTownDressing._hash(r["lot"], r["half"], 7)
		if not lowest.has(r["half"]) or h < BoardgenTownDressing._hash(lowest[r["half"]]["lot"], r["half"], 7):
			lowest[r["half"]] = r
	for r: Dictionary in gables:
		var h := BoardgenTownDressing._hash(r["lot"], r["half"], 7)
		var broken := h < BROKEN_ROOF_SHARE or int(lowest[r["half"]]["lot"]) == int(r["lot"])
		var m := ("roof_broken_a" if h < BROKEN_ROOF_SHARE * 0.5 else "roof_broken_b") if broken else ("roof_sag_low" if float(r["height"]) < 2.1 else "roof_sag_steep")
		var tint := ROOF_SLATE if BoardgenTownDressing._hash(r["lot"], r["half"], 16) < 0.8 else ROOF_CLAY   # (roofs lane 22.11.: slate four in five, a dull clay one in five)
		var yaw := float(r["yaw"]) + (0.0 if r["along_x"] else PI * 0.5) + (PI if BoardgenTownDressing._hash(r["lot"], r["half"], 8) < 0.5 else 0.0)   # the body's yaw and skew, as the procedural roofs have it
		var at := Vector3(r["centre"].x, r["eaves"], r["centre"].y)   # on the house's own eaves line
		for part in ([m, "roof_rafters"] if m.begins_with("roof_broken") else [m]):
			var s := Vector3(float(r["length"]) / ROOF_L_IN, float(r["height"]) / ROOF_H_IN[part], float(r["width"]) / ROOF_W_IN)
			var item := _item(Basis(Vector3.UP, yaw) * Basis.from_scale(s), at)
			if part != "roof_rafters":
				item["colour"] = tint
			add.call(part, item)
	var chimneys := BoardgenTownDressing.chimneys(layout)
	for i in chimneys.size():
		var c: Dictionary = chimneys[i]
		var centre: Vector3 = (c["lo"] + c["hi"]) * 0.5
		var m := "chimney_pots" if BoardgenTownDressing._hash(i, 0, 9) < 0.7 else "chimney_broken"
		add.call(m, _item(Basis(Vector3.UP, PI * 0.5 * (i % 4)), Vector3(centre.x, c["hi"].y - CHIMNEY_TOP_IN, centre.z)))
	var ladders := BoardgenGreybox.ladder_kit_plan(layout)
	for key: String in ladders:
		add_all.call("timber_" + key, ladders[key])
	var frames := BoardgenTownFrames.plan(layout)   # (train 3) the half-timber shells
	for m: String in frames:
		add_all.call(m, frames[m])
	var clutter := BoardgenTownClutter.plan(layout)
	for m: String in clutter:
		for item: Dictionary in clutter[m]:
			add.call(m, item)
	var merlons := BoardgenTownDressing.merlons(layout)
	for i in merlons.size():
		var b: Dictionary = merlons[i]
		var size: Vector3 = b["hi"] - b["lo"]
		var centre: Vector3 = (b["lo"] + b["hi"]) * 0.5
		var yaw := (PI * 0.5 if size.z > size.x else 0.0) + (PI if i % 2 == 1 else 0.0)
		var whole := "merlon_v%d" % (1 + int(BoardgenTownDressing._hash(i, 2, 13) * 3.0) % 3)   # three joint patterns break the kit's tiling (kit batch A7)
		var mi := _item(Basis(Vector3.UP, yaw), Vector3(centre.x, b["lo"].y, centre.z))
		mi["colour"] = MERLON_MOSSY if BoardgenTownDressing._hash(i, 2, 17) < 0.4 else MERLON_WEATHERED
		add.call("merlon_v4" if BoardgenTownDressing._hash(i, 1, 11) < 0.2 else whole, mi)
	for item: Dictionary in coping(layout):
		item["colour"] = MERLON_MOSSY if BoardgenTownDressing._hash(int(item["xf"].origin.x * 1000.0) + int(item["xf"].origin.z * 37.0), 3, 17) < 0.4 else MERLON_WEATHERED
		add.call(item["module"], item)
	var nx: int = layout["nx"]
	var nz: int = layout["nz"]
	var cell_in := float(layout["cell_in"])
	var origin := Vector2(nx, nz) * cell_in * -0.5
	for cd: Dictionary in layout["cells"]:   # a breach: a level-0 wall cell; a heap against each wall end beside it
		if cd["lot_kind"] != "Wall" or cd["level"] != 0:
			continue
		for d: Vector2i in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
			var n := Vector2i(cd["x"], cd["z"]) + d
			if n.x < 0 or n.y < 0 or n.x >= nx or n.y >= nz or int(layout["cells"][n.y * nx + n.x]["level"]) == 0:
				continue
			var face := origin + (Vector2(cd["x"], cd["z"]) + Vector2(0.5, 0.5) + Vector2(d) * 0.5) * cell_in
			var id: int = cd["z"] * nx + cd["x"]
			var m: String = ["rubble_a", "rubble_b", "rubble_c"][int(BoardgenTownDressing._hash(id, d.x + 2 * d.y + 3, 12) * 3.0) % 3]
			add.call(m, _item(Basis(Vector3.UP, atan2(-float(d.x), -float(d.y))), Vector3(face.x, 0.0, face.y)))   # local +z into the breach
	return out


## The capstone runs of the city wall (kit batch A7): one 3 in run on the FIELD edge of every wall cell's top that drops on that side, its middle 0.25 in in from the edge (the parapet line
## the merlons stand on; 0.18 in high), a third of them turned end for end; three runs (a stone missing, one tilted) break the tiling. [{xf, colour, module}].
static func coping(layout: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var nx: int = layout["nx"]
	var nz: int = layout["nz"]
	var cell_in := float(layout["cell_in"])
	var origin := Vector2(nx, nz) * cell_in * -0.5
	for cd: Dictionary in layout["cells"]:
		var level := int(cd["level"])
		if cd["lot_kind"] != "Wall" or level < 1:
			continue
		var field := -1 if int(cd["x"]) * 2 < nx else 1
		var fx := int(cd["x"]) + field
		if fx >= 0 and fx < nx and int(layout["cells"][int(cd["z"]) * nx + fx]["level"]) >= level:
			continue   # no drop on the field side: no edge
		var i: int = cd["z"] * nx + cd["x"]
		var x := origin.x + (float(cd["x"]) + (0.0 if field < 0 else 1.0)) * cell_in - float(field) * 0.25
		var z := origin.y + (float(cd["z"]) + 0.5) * cell_in
		var h := BoardgenTownDressing._hash(i, 3, 14)
		var item := _item(Basis(Vector3.UP, PI * 0.5 + (PI if BoardgenTownDressing._hash(i, 3, 15) < 0.33 else 0.0)), Vector3(x, float(layout["level_in"][level]), z))
		item["module"] = "coping_a" if h < 0.34 else ("coping_b" if h < 0.67 else "coping_c")
		out.append(item)
	return out


## Modules that cast NO shadow (lead 21.11., the draw-call budget: a caster is drawn again in every shadow cascade): the fences, the signs, the flat debris (crows and rats have none either).
const NO_SHADOW := ["fence_", "sign_", "splinters_flat", "debris_flat", "cloth_flat", "weeds_flat"]


static func casts_shadow(m: String) -> bool:
	return (m.begins_with("roof_g") or m.begins_with("roof_sag") or m.begins_with("chimney") or CLUTTER_SET.get(m, "") == "timber") and not NO_SHADOW.any(func(pre: String) -> bool: return m.begins_with(pre))


## A7 modules that replace a K-R1 / A2 one in the same frame: while one is not cached, the board draws the older module in its place.
const FALLBACK := {"roof_sag_low": "roof_gable_low", "roof_sag_steep": "roof_gable_steep", "merlon_v1": "merlon", "merlon_v2": "merlon", "merlon_v3": "merlon", "merlon_v4": "merlon_broken", "fountain_basin_b": "fountain_basin", "lantern_post_iron": "lantern_post"}


## One MultiMesh per module, on its set's material (or the tinted kit material while the set is not cached).
func build(layout: Dictionary) -> void:
	var p := plan(layout)
	for m: String in p:
		var src := m if kit.usable([m]) or not FALLBACK.has(m) else String(FALLBACK[m])
		if not kit.usable([src]):
			continue   # a clutter module that is not cached: the procedural box (or nothing) stays
		var mmi := BoardgenKit.add_multimesh(self, m, kit.mesh_or(src), p[m], casts_shadow(m))
		var mat := lib.set_material(set_of(m))
		if GLOW.has(m):
			var glow := StandardMaterial3D.new()
			glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			glow.albedo_color = GLOW[m] * 0.4   # (lead 21.11.: the lamp glass read as a pure-white block - a warm amber, the light's own hue, clearly below white)
			glow.emission_enabled = true
			glow.emission = GLOW[m]
			glow.emission_energy_multiplier = 0.5
			mmi.material_override = glow
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			continue
		if m.begins_with("lantern_post"):
			mmi.layers |= BoardgenMood.LAMP_IRON_LAYER
		if mat != null and m.begins_with("roof_") and m != "roof_rafters":   # the roofs carry UVs in tiles (courses parallel to the eaves)
			mat.uv1_triplanar = false
			mat.uv1_scale = Vector3.ONE * ROOF_UV_TILE_IN / lib.tile_in("roof_tiles")
			mat.normal_enabled = false   # the GLB has no tangents; the course lips are the relief
			mat.albedo_texture = null   # (x ROOF_PLAIN_VALUE: without the dark clay texture the plain tone rendered as pale tin)  # (ROOF-WARM, lane townC4) the clay set's own hue fell into the warm class whatever the tint: the roofs take their tone from TINT x the instance colour (slate / dull clay), the course lips and the baked AO carry the relief
		mmi.material_override = mat
		for i in mmi.multimesh.instance_count:
			mmi.multimesh.set_instance_color(i, (TEXTURED_TINT if mat != null and mat.albedo_texture != null else TINT)[set_of(m)] * (ROOF_PLAIN_VALUE if mat != null and mat.albedo_texture == null else 1.0) * MODULE_TINT.get(src, MODULE_TINT.get(m, Color.WHITE)) * (p[m][i]["colour"] as Color))   # (a fallback module keeps its own tint)   # (the item's own colour: white for most, dry for some weeds)
