class_name MovementRangeController
extends Node3D
## Per-model movement reach indicator: two flat, base-anchored rings showing how far a
## model may move this turn — the inner Advance band and the outer Rush/Charge band — so a
## player can eyeball reach without a ruler. Display-only (shows reach, decides/enforces
## NOTHING — it never moves the model) and LOCAL: not synced to other players and not
## written to the .nml save, exactly like the base-anchored range rings whose flat-annulus +
## base-radius + player-colour logic this reuses. Each indicator is WORLD-ANCHORED at the
## model's position when shown (NOT parented to the model), so it stays put while the player
## drags the mini toward a band edge to judge its reach — no per-frame tracking.
##
## OPR core movement (Grimdark Future / Age of Fantasy): Advance = 6", Rush/Charge = 12".
## Movement-modifying special rules adjust the bands: their +N"/-N" modifiers are read from the
## unit's imported OPR rule descriptions (props["rule_descriptions"]), so ANY such rule is picked
## up automatically — "Swift", army-specific rules, etc. — not just a hard-coded few (issue #79).
## "Fast" (+2"/+4") and "Slow" (-2"/-4") additionally fall back to constants when no description
## text is present (e.g. a rule list without the army book), so they always apply.

# === Constants ===

const INCHES_TO_METERS: float = 0.0254
const ROOT_NODE_NAME: String = "MovementRange"
## Custom minis without a player_id use this neutral colour.
const NEUTRAL_COLOR: Color = Color(0.6, 0.6, 0.65)
const DEFAULT_BASE_RADIUS_M: float = 0.016  # 32 mm base

## OPR core move distances (inches). See class doc for the OPR reference.
const OPR_ADVANCE_INCHES: int = 6
const OPR_RUSH_CHARGE_INCHES: int = 12
## OPR "Fast": +2" Advance, +4" Rush/Charge. "Slow": the same magnitudes, subtracted.
const FAST_ADVANCE_BONUS: int = 2
const FAST_RUSH_BONUS: int = 4

const RING_Y: float = 0.004
const RING_SEGMENTS: int = 48
const RING_BAND_M: float = 0.004  # 4 mm visible band
const ADVANCE_ALPHA: float = 0.85
const RUSH_ALPHA: float = 0.4     # outer band dimmer so the two read apart
const LABEL_FONT_SIZE: int = 20
const LABEL_PIXEL_SIZE: float = 0.001
const LABEL_OUTLINE: int = 6

# === Private variables ===

var _active: Dictionary = {}  # model_node (Node3D) -> true while its indicator is shown

# === Public: pure logic (unit-tested) ===

## Base edge radius (metres) for a unit's props — round bases use half the round size, oval
## bases the averaged radius (same approximation as the range rings); empty props → 32 mm.
func base_radius_for_props(props: Dictionary) -> float:
	if props.get("base_is_oval", false) or props.get("base_is_square", false):
		var w: float = float(props.get("base_width_mm", 0))
		var d: float = float(props.get("base_depth_mm", 0))
		if w > 0.0 and d > 0.0:
			return ((w + d) / 4.0) * 0.001
	if props.has("base_size_round"):
		return (float(props["base_size_round"]) / 2.0) * 0.001
	return DEFAULT_BASE_RADIUS_M


## The Advance + Rush/Charge distances (inches) for a unit, applying every movement-modifying
## rule it effectively carries. `props["rule_descriptions"]` already holds the unit's EFFECTIVE
## rules — direct, item-granted AND free-text-granted (e.g. an ability that grants Swift) — so
## parsing every description here picks up indirectly-granted modifiers too (issue #79). A Fast/Slow
## constant fallback covers a core rule listed directly but without (parseable) description text.
## Returns {"advance": int, "rush": int}, clamped at 0 so a heavy Slow can't go negative.
func move_bands_for_props(props: Dictionary) -> Dictionary:
	var advance := OPR_ADVANCE_INCHES
	var rush := OPR_RUSH_CHARGE_INCHES
	var descriptions: Dictionary = props.get("rule_descriptions", {})
	var counted: Dictionary = {}  # rule base names whose modifier is already applied
	for name in descriptions:
		var mod := move_modifier_from_description(str(descriptions[name]))
		if int(mod["advance"]) != 0 or int(mod["rush"]) != 0:
			advance += int(mod["advance"])
			rush += int(mod["rush"])
			counted[name] = true
	for r in props.get("special_rules", []):
		var base := _rule_base_name(str(r))
		if counted.has(base):
			continue  # already applied from its description (don't double-count)
		if base == "Fast":
			advance += FAST_ADVANCE_BONUS
			rush += FAST_RUSH_BONUS
			counted[base] = true
		elif base == "Slow":
			advance -= FAST_ADVANCE_BONUS
			rush -= FAST_RUSH_BONUS
			counted[base] = true
	return {"advance": maxi(0, advance), "rush": maxi(0, rush)}


## Parses the Advance and Rush/Charge movement modifiers out of an OPR rule description, e.g.
## "...moves +2\" when using Advance, and +4\" when using Rush/Charge." -> {advance:2, rush:4}.
## Each signed inch modifier is attributed to whichever action ("advance" vs "rush"/"charge") is
## named in the text up to the next modifier — matching OPR's "<value> when using <action>" phrasing.
## The sign is required, so plain distances (ranges, auras) aren't mistaken for move modifiers.
## Static + side-effect-free so it can be unit-tested directly.
static func move_modifier_from_description(description: String) -> Dictionary:
	var result := {"advance": 0, "rush": 0}
	if description.is_empty():
		return result
	var re := RegEx.new()
	if re.compile("([+-]\\d+)\\s*[\"”]") != OK:
		return result
	var matches := re.search_all(description)
	for i in matches.size():
		var m: RegExMatch = matches[i]
		var value := int(m.get_string(1))
		var win_start := m.get_end()
		var win_end := description.length()
		if i + 1 < matches.size():
			win_end = matches[i + 1].get_start()
		var window := description.substr(win_start, win_end - win_start).to_lower()
		# Stems so inflections match too ("advancing", "charges").
		var adv_at := window.find("advanc")
		var rush_at := _first_index(window, ["rush", "charg"])
		if adv_at != -1 and (rush_at == -1 or adv_at <= rush_at):
			result["advance"] = int(result["advance"]) + value
		elif rush_at != -1:
			result["rush"] = int(result["rush"]) + value
	return result


## Lowest index at which any of `needles` occurs in `haystack`, or -1 if none do.
static func _first_index(haystack: String, needles: Array) -> int:
	var best := -1
	for n in needles:
		var idx: int = haystack.find(n)
		if idx != -1 and (best == -1 or idx < best):
			best = idx
	return best


## A rule's base name without its rating parenthetical: "Swift(3)" -> "Swift", "Fast" -> "Fast".
func _rule_base_name(rule: String) -> String:
	return rule.split("(")[0].strip_edges()


## Outer radius (metres) of a band = base edge radius + the band distance.
func band_radius_for_props(props: Dictionary, band_inches: int) -> float:
	return base_radius_for_props(props) + float(band_inches) * INCHES_TO_METERS


func color_for_props(props: Dictionary) -> Color:
	if props.has("player_id"):
		return OPRArmyManager.PLAYER_COLORS.get(int(props["player_id"]), NEUTRAL_COLOR)
	return NEUTRAL_COLOR

# === Public: indicator management ===

## Toggle the movement indicator on each given model (shown ⇄ hidden), independently.
func toggle(model_nodes: Array) -> void:
	for node in model_nodes:
		if not (node is Node3D) or not is_instance_valid(node):
			continue
		if _active.has(node):
			clear(node)
		else:
			_build_indicator(node)


func is_active(model_node: Node3D) -> bool:
	return _active.has(model_node)


func clear(model_node: Node3D) -> void:
	if _active.has(model_node):
		var root = _active[model_node]
		if is_instance_valid(root):
			root.queue_free()
		_active.erase(model_node)


func clear_all() -> void:
	for node in _active.keys():
		var root = _active[node]
		if is_instance_valid(root):
			root.queue_free()
	_active.clear()


func active_count() -> int:
	return _active.size()

# === Private ===

## TEMP diagnostic (issue #79): dumps what the move-band parser actually sees for a unit, so a
## failing Swift-style rule can be matched against the real OPR text. Remove once #79 is confirmed.
func _log_move_diagnostic(props: Dictionary, bands: Dictionary) -> void:
	var rules: Array = props.get("special_rules", [])
	var descriptions: Dictionary = props.get("rule_descriptions", {})
	print("[MOVE #79] rules=", rules)
	print("[MOVE #79] description_keys=", descriptions.keys())
	for name in descriptions:
		print("[MOVE #79]   '", name, "' -> ", str(descriptions[name]).substr(0, 140))
	print("[MOVE #79] bands advance=", bands.get("advance"), " rush=", bands.get("rush"))


func _build_indicator(model_node: Node3D) -> void:
	var props := _props_of(model_node)
	var bands := move_bands_for_props(props)
	var base_color := color_for_props(props)
	_log_move_diagnostic(props, bands)

	var root := Node3D.new()
	root.name = ROOT_NODE_NAME
	# Outer (Rush/Charge) first so the inner Advance band draws on top of it.
	_add_band(root, props, int(bands["rush"]), base_color, RUSH_ALPHA, "Rush/Charge")
	_add_band(root, props, int(bands["advance"]), base_color, ADVANCE_ALPHA, "Advance")
	# World-anchor the rings at the model's CURRENT spot instead of parenting them to the model,
	# so they stay put while the player drags the mini toward a band edge to judge its reach.
	add_child(root)
	root.global_position = model_node.global_position
	_active[model_node] = root
	# Drop the orphaned indicator if its model is freed (e.g. table clear) while still shown.
	model_node.tree_exiting.connect(_on_model_gone.bind(model_node), CONNECT_ONE_SHOT)


func _add_band(root: Node3D, props: Dictionary, dist_inches: int, base_color: Color,
		alpha: float, tag: String) -> void:
	var outer := band_radius_for_props(props, dist_inches)
	var inner := maxf(0.001, outer - RING_BAND_M)
	var color := base_color.lightened(0.2)
	color.a = alpha

	var ring := MeshInstance3D.new()
	ring.name = "%sRing" % tag.replace("/", "")
	ring.mesh = _make_flat_ring_mesh(inner, outer, RING_SEGMENTS)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	ring.material_override = mat
	ring.position = Vector3(0, RING_Y, 0)
	root.add_child(ring)

	var label := Label3D.new()
	label.name = "%sLabel" % tag.replace("/", "")
	label.text = "%s %d\"" % [tag, dist_inches]
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.pixel_size = LABEL_PIXEL_SIZE
	label.font_size = LABEL_FONT_SIZE
	label.modulate = Color.WHITE
	label.outline_modulate = Color.BLACK
	label.outline_size = LABEL_OUTLINE
	label.position = Vector3(0, RING_Y + 0.02, outer)
	root.add_child(label)


## A shown model left the tree (e.g. table clear): drop its now-orphaned world-anchored indicator.
func _on_model_gone(model_node: Node3D) -> void:
	clear(model_node)


## A model node's unit_properties (game_unit meta, or via model_instance.unit), or {}.
func _props_of(model_node: Node3D) -> Dictionary:
	var props: Dictionary = {}
	if model_node.has_meta("game_unit"):
		var gu = model_node.get_meta("game_unit")
		if gu is GameUnit and gu.unit_properties != null:
			props = gu.unit_properties
	if props.is_empty() and model_node.has_meta("model_instance"):
		var m = model_node.get_meta("model_instance")
		if m is ModelInstance and m.unit is GameUnit and m.unit.unit_properties != null:
			props = m.unit.unit_properties
	if props.is_empty():
		return {}
	# Anchor the bands to the model's ACTUAL base: a per-model Tough upgrade enlarges it (the mesh
	# stays natural-sized, but the base — and so the measuring edge — grows).
	return OPRArmyManager.effective_base_props(props, _model_tough_of(model_node))


## The per-model Tough value (drives the enlarged base), 0 if none.
func _model_tough_of(model_node: Node3D) -> int:
	if model_node.has_meta("model_instance"):
		var m = model_node.get_meta("model_instance")
		if m is ModelInstance and m.properties != null:
			return int(m.properties.get("tough", 0))
	return 0


## Flat ring (annulus) mesh in the XZ plane between inner and outer radius.
func _make_flat_ring_mesh(inner: float, outer: float, segments: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(segments):
		var a0 := TAU * i / segments
		var a1 := TAU * (i + 1) / segments
		var ci0 := Vector3(cos(a0) * inner, 0, sin(a0) * inner)
		var co0 := Vector3(cos(a0) * outer, 0, sin(a0) * outer)
		var ci1 := Vector3(cos(a1) * inner, 0, sin(a1) * inner)
		var co1 := Vector3(cos(a1) * outer, 0, sin(a1) * outer)
		for v in [co0, ci0, ci1, co0, ci1, co1]:
			st.set_normal(Vector3.UP)
			st.add_vertex(v)
	return st.commit()
