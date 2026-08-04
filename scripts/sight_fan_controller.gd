class_name SightFanController
extends Node3D
## Renders a unit's summed sight+range fan (SightFan geometry — the maintainer's sketch): a flat translucent
## yellow overlay just above the table, one polygon per merged region. Display-only and LOCAL (never synced,
## never saved), exactly like RangeRingController whose overlay conventions this follows. The caller passes
## the weapon range — the controller owns only presentation.

const FAN_Y := 0.004                       # just under the range rings (RING_Y 0.005), above decals
## Range-band fills, applied longest range FIRST (palest) to shortest LAST (strongest): the inner region
## every weapon reaches renders strong yellow, an outer crescent only the long guns cover stays pale —
## the maintainer's "farblich bei der Reichweite unterscheiden" (e.g. one 30" MG in a 24" unit).
const BAND_FILLS: Array = [Color(1.0, 0.85, 0.2, 0.26), Color(1.0, 0.78, 0.25, 0.18), Color(1.0, 0.72, 0.3, 0.12)]
const EDGE := Color(1.0, 0.8, 0.1, 0.8)    # thin bright rim so the fan boundary reads as a line

var _nodes: Array = []
var _bounds := Rect2()   # table rect (world XZ metres); non-empty clips the fan to the tabletop


func clear_fan() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			(n as Node).queue_free()
	_nodes.clear()


## Show the fan for `unit`: per alive model a base-edge ray fan at `range_in` (inches, measured from the
## base edge), merged into the unit's summed region. `overlay` publishes the 3D terrain volumes — the
## very truth the shooting gate reads (NML-005: eine LoS-Wahrheit); an absent overlay degrades
## gracefully to an open table.
func show_fan_for(unit: GameUnit, overlay: Node, ranges_in: Array, table_bounds: Rect2 = Rect2()) -> void:
	clear_fan()
	if unit == null or ranges_in.is_empty():
		return
	_bounds = table_bounds
	var volumes: Array = []
	if overlay != null and overlay.has_method("los_volumes"):
		volumes = overlay.los_volumes()
	# Bands per DISTINCT WEAPON RANGE of the unit, each emanating from ALL model bases: in OPR weapons
	# belong to the UNIT (which mini carries the flamer is the player's choice), so per-model attribution
	# would be fiction — the truthful read is "strong yellow: every weapon bites here; pale: only the
	# long guns reach". `ranges_in` = the unit's distinct positive weapon ranges (caller-provided);
	# capped to the palette size by keeping longest/middle/shortest.
	var emitters: Array = []
	for m in unit.get_alive_models():
		var node: Node3D = (m as ModelInstance).node
		if node == null or not is_instance_valid(node):
			continue
		# The EYE, not the footprint: where the model really stands (node y — a container roof lifts it)
		# plus its own volumetric height. The base radius doubles as the official base size in mm
		# (radius m x 2 x 1000), the one input that table takes.
		var base_r := LosRules.model_base_radius_m(m as ModelInstance)
		var eye_y: float = node.global_position.y \
			+ VolumetricLos.height_in_for_base_mm(base_r * 2000.0) * VolumetricLos.INCHES_TO_METERS
		emitters.append({"eye": Vector3(node.global_position.x, eye_y, node.global_position.z),
			"base_r": base_r})
	if emitters.is_empty():
		return
	var bands: Array = ranges_in.duplicate()
	bands.sort()
	bands.reverse()   # longest first
	while bands.size() > BAND_FILLS.size():
		bands.remove_at(bands.size() / 2)   # drop middles, keep longest + shortest
	for bi in range(bands.size()):
		var fill: Color = BAND_FILLS[bands.size() - 1 - bi]   # longest palest, shortest strongest
		var polys: Array = []
		for e in emitters:
			polys.append(SightFan.fan_polygon(e["eye"], e["base_r"], float(bands[bi]) * 0.0254, volumes))
		for poly in SightFan.union_fans(polys):
			_add_region(poly as PackedVector2Array, fill)


func _add_region(poly: PackedVector2Array, fill: Color = BAND_FILLS[0]) -> void:
	# Clip to the tabletop — a 30" fan from a table-edge unit otherwise floats over the void.
	if _bounds.size.x > 0.0:
		var rect := PackedVector2Array([_bounds.position, _bounds.position + Vector2(_bounds.size.x, 0),
			_bounds.end, _bounds.position + Vector2(0, _bounds.size.y)])
		var clipped := Geometry2D.intersect_polygons(poly, rect)
		for piece in clipped:
			if not Geometry2D.is_polygon_clockwise(piece):
				_add_region_raw(piece, fill)
		return
	_add_region_raw(poly, fill)


func _add_region_raw(poly: PackedVector2Array, fill: Color) -> void:
	var idx := Geometry2D.triangulate_polygon(poly)
	if idx.is_empty():
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in idx:
		st.add_vertex(Vector3(poly[i].x, FAN_Y, poly[i].y))
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = fill
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	add_child(mi)
	_nodes.append(mi)
	# rim line so the boundary (wall shadows, zone far edges) reads crisply, like the sketch's dashed edges
	var rim := ImmediateMesh.new()
	rim.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for p in poly:
		rim.surface_add_vertex(Vector3(p.x, FAN_Y + 0.0005, p.y))
	if poly.size() > 0:
		rim.surface_add_vertex(Vector3(poly[0].x, FAN_Y + 0.0005, poly[0].y))
	rim.surface_end()
	var rim_mi := MeshInstance3D.new()
	rim_mi.mesh = rim
	var rim_mat := StandardMaterial3D.new()
	rim_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rim_mat.albedo_color = EDGE
	rim_mi.material_override = rim_mat
	add_child(rim_mi)
	_nodes.append(rim_mi)
