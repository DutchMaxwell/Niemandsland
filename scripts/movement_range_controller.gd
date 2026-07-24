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
## OPR army-book "Rapid Rush": "+6" when using Rush actions" — Rush band only, Advance untouched.
const RAPID_RUSH_BONUS: int = 6
## OPR army-book "Quick": +2" on Advance AND Rush/Charge (the Scurry shape, unlike Fast's +2/+4).
const QUICK_BONUS: int = 2
## OPR army-book "Rapid Advance": "+4" when using Advance actions" — Advance band only.
const RAPID_ADVANCE_BONUS: int = 4

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
## STATIC + pure (reads only `props`): so callers WITHOUT a live controller instance — the Solo AI when
## no MovementRangeController is injected — resolve Fast/Slow through this ONE band source instead of a
## hardcoded 6"/12" fallback (field-test finding 1: a Slow unit moved the full 6").
static func move_bands_for_props(props: Dictionary) -> Dictionary:
	var advance := OPR_ADVANCE_INCHES
	var rush := OPR_RUSH_CHARGE_INCHES
	var descriptions: Dictionary = props.get("rule_descriptions", {})
	# Some rules NEGATE another movement rule (e.g. "Swift": "may ignore the Slow rule"); a negated
	# rule contributes nothing, so its modifier is skipped below (issue #79).
	var negated: Dictionary = _negated_move_rules(descriptions)
	# B10 (test game 2): counted tracks WHICH BAND a description contributed, not just the rule name.
	# A partial parse (e.g. the advance half attributed, the rush half not) used to mark the whole
	# rule counted and suppress the name fallback — Fast then lost its +4" rush/charge bonus. Now the
	# fallback fills exactly the missing band.
	var counted: Dictionary = {}  # rule base name -> {"advance": bool, "rush": bool} already applied
	for name in descriptions:
		if negated.has(name):
			continue
		var mod := move_modifier_from_description(str(descriptions[name]))
		if int(mod["advance"]) != 0 or int(mod["rush"]) != 0:
			advance += int(mod["advance"])
			rush += int(mod["rush"])
			counted[name] = {"advance": int(mod["advance"]) != 0, "rush": int(mod["rush"]) != 0}
	# Swift name-fallback ("This model may ignore the Slow rule"): with description text the negation
	# scan above cancels Slow already; with bare rule NAMES (no descriptions — tests, fallback imports)
	# the name pair must still cancel. Mixed shapes (Slow with text, Swift without) stay a documented
	# edge — imports deliver descriptions as a package.
	var swift_by_name := false
	for r in props.get("special_rules", []):
		if _rule_base_name(str(r)) == "Swift":
			swift_by_name = true
			break
	for r in props.get("special_rules", []):
		var base := _rule_base_name(str(r))
		if negated.has(base):
			continue  # negated by another rule
		# B10: the fallback fills only the band(s) the description pass did NOT already apply.
		var done: Dictionary = counted.get(base, {})
		var adv_done := bool(done.get("advance", false))
		var rush_done := bool(done.get("rush", false))
		if adv_done and rush_done:
			continue
		if base == "Slow" and swift_by_name:
			counted[base] = {"advance": true, "rush": true}
			continue  # Swift cancels Slow (name-level fallback)
		if base == "Fast":
			if not adv_done:
				advance += FAST_ADVANCE_BONUS
			if not rush_done:
				rush += FAST_RUSH_BONUS
			counted[base] = {"advance": true, "rush": true}
		elif base == "Slow":
			if not adv_done:
				advance -= FAST_ADVANCE_BONUS
			if not rush_done:
				rush -= FAST_RUSH_BONUS
			counted[base] = {"advance": true, "rush": true}
		elif base == "Rapid Rush":
			if not rush_done:
				rush += RAPID_RUSH_BONUS
			counted[base] = {"advance": true, "rush": true}
		elif base == "Quick":
			if not adv_done:
				advance += QUICK_BONUS
			if not rush_done:
				rush += QUICK_BONUS
			counted[base] = {"advance": true, "rush": true}
		elif base == "Rapid Advance":
			if not adv_done:
				advance += RAPID_ADVANCE_BONUS
			counted[base] = {"advance": true, "rush": true}
	# Coverage wave (2026-07-23): REGISTRY pass — data aliases of the move-band family (Scurry /
	# Highborn / Agile → Quick-style mods, Lustbound's charge half via Royal Legion, …) apply their
	# params to any band the description/name passes did not already cover. Offline-safe: works
	# without description texts (the bundled AI lists ship stripped).
	var reg_system := RulesRegistry.normalize_system(str(props.get("game_system", "")))
	var reg_faction := str(props.get("faction_folder", ""))
	for r in props.get("special_rules", []):
		var base2 := _rule_base_name(str(r))
		if negated.has(base2):
			continue
		var done2: Dictionary = counted.get(base2, {})
		if bool(done2.get("advance", false)) and bool(done2.get("rush", false)):
			continue
		var entry := RulesRegistry.lookup(reg_system, reg_faction, base2)
		var prim: Variant = entry.get("primitive")
		if not (prim is String) or not ["Fast", "Slow", "Quick", "Rapid Advance", "Rapid Rush", "Royal Legion"].has(str(prim)):
			continue
		var rp: Dictionary = entry.get("params", {})
		if int(rp.get("uses_per_game", 0)) > 0:
			continue   # once-per-game feats (Speed Feat) never ride the permanent bands
		if not bool(done2.get("advance", false)):
			advance += int(rp.get("advance_mod", 0))
		if not bool(done2.get("rush", false)):
			rush += int(rp.get("rush_mod", rp.get("charge_mod", 0)))
		counted[base2] = {"advance": true, "rush": true}
	# NML-006: active spell tokens with movement modifiers ('+2" advance / +4" rush', once) are stamped
	# into props as "spell_move_mod" by the solo layer — read here so the AI's bands AND the human's
	# move rings shrink/grow through this ONE band source (stays pure: props in, bands out).
	var spell_mod: Dictionary = props.get("spell_move_mod", {})
	advance += int(spell_mod.get("advance", 0))
	rush += int(spell_mod.get("rush", 0))
	return {"advance": maxi(0, advance), "rush": maxi(0, rush)}


## Movement rules that are NEGATED by another rule's text — e.g. "Swift" whose description reads
## "This model may ignore the Slow rule" cancels Slow. Returns the set of negated rule base names.
## Detected by an "ignore … <RuleName>" phrase where <RuleName> is another rule with a description.
static func _negated_move_rules(descriptions: Dictionary) -> Dictionary:
	var negated: Dictionary = {}
	for name in descriptions:
		var text: String = str(descriptions[name]).to_lower()
		var at: int = text.find("ignore")
		while at != -1:
			var window: String = text.substr(at, 48)
			for other in descriptions:
				var other_name: String = str(other)
				if other_name != name and window.find(other_name.to_lower()) != -1:
					negated[other_name] = true
			at = text.find("ignore", at + 1)
	return negated


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
		# B10: ONE modifier naming BOTH actions ("+2\" when using Advance or Rush actions") applies to
		# both bands — the old first-stem-wins attribution silently dropped the second band. Windows
		# end at the next modifier, so the classic "+2\" Advance, +4\" Rush" pair is unaffected.
		if adv_at != -1 and rush_at != -1:
			result["advance"] = int(result["advance"]) + value
			result["rush"] = int(result["rush"]) + value
		elif adv_at != -1:
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
static func _rule_base_name(rule: String) -> String:
	return rule.split("(")[0].strip_edges()


## The Advance/Rush bands (inches) for a model NODE — resolves its effective props (base upgrade +
## movement rules + auras) then computes the bands. Public entry for callers like the movement cap.
## B10: an unresolvable node is NAMED loudly instead of silently moving at the bare 6"/12" bands.
func bands_for_model(model_node: Node3D) -> Dictionary:
	var props := _props_of(model_node)
	if props.is_empty():
		push_warning("bands_for_model: no GameUnit resolved for '%s' — bare 6\"/12\" OPR bands in effect" % model_node.name)
	return move_bands_for_props(props)


## Outer radius (metres) of a band = base edge radius + the band distance.
func band_radius_for_props(props: Dictionary, band_inches: int) -> float:
	return base_radius_for_props(props) + float(band_inches) * INCHES_TO_METERS


func color_for_props(props: Dictionary) -> Color:
	if props.has("player_id"):
		return OPRArmyManager.army_color(int(props["player_id"]), NEUTRAL_COLOR)
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

func _build_indicator(model_node: Node3D) -> void:
	var props := _props_of(model_node)
	var bands := move_bands_for_props(props)
	var base_color := color_for_props(props)

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
	var game_unit := _game_unit_of(model_node)
	if game_unit == null or game_unit.unit_properties == null:
		return {}
	# Anchor the bands to the model's ACTUAL base: a per-model Tough upgrade enlarges it (the mesh
	# stays natural-sized, but the base — and so the measuring edge — grows).
	var effective := OPRArmyManager.effective_base_props(game_unit.unit_properties, _model_tough_of(model_node))
	# Fold in aura-granted movement rules from the rest of the combined unit, so a hero's "Swift
	# Aura" (which grants Swift to the whole unit) affects every model's reach — not just the
	# hero's (#79 aura). effective_base_props already duplicated the dict, so this is non-mutating.
	effective["rule_descriptions"] = _combined_unit_rule_descriptions(
		game_unit, effective.get("rule_descriptions", {}))
	return effective


## The GameUnit a model node belongs to (via the game_unit meta, or model_instance.unit), or null.
## B10: walks UP the parents too — a nested pickable child (mount part, proxy mesh) otherwise
## resolved nothing and the caller silently fell back to the bare 6"/12" bands, losing Fast/Slow.
func _game_unit_of(model_node: Node3D) -> GameUnit:
	var n: Node = model_node
	while n != null:
		if n.has_meta("game_unit"):
			var gu = n.get_meta("game_unit")
			if gu is GameUnit:
				return gu
		if n.has_meta("model_instance"):
			var m = n.get_meta("model_instance")
			if m is ModelInstance and m.unit is GameUnit:
				return m.unit
		n = n.get_parent()
	return null


## `own` rule descriptions merged with the AURA-granted rules of the OTHER members of `game_unit`'s
## combined unit (host + attached heroes). So a hero's "Swift Aura" reaches the unit's models, and
## a unit aura reaches its hero. Non-aura members contribute nothing (a hero's personal Fast won't
## leak to the unit). Own descriptions win on a key clash.
func _combined_unit_rule_descriptions(game_unit: GameUnit, own: Dictionary) -> Dictionary:
	var host: GameUnit = game_unit
	var attached_to = game_unit.unit_properties.get("attached_to", null)
	if attached_to is GameUnit:
		host = attached_to
	var members: Array = []
	if host != game_unit:
		members.append(host)
	for hero in host.unit_properties.get("attached_heroes", []):
		if hero is GameUnit and hero != game_unit:
			members.append(hero)
	var member_data: Array = []
	for m: GameUnit in members:
		member_data.append({
			"rules": m.unit_properties.get("special_rules", []),
			"descriptions": m.unit_properties.get("rule_descriptions", {}),
		})
	return merge_aura_descriptions(own, member_data)


## Merge AURA-granted rule descriptions from combined-unit members into `own`. Each member is
## {"rules": Array, "descriptions": Dictionary}; a member contributes its descriptions only if it
## carries an aura rule. Own keys are never overwritten. Static + pure for unit testing.
static func merge_aura_descriptions(own: Dictionary, members: Array) -> Dictionary:
	var merged: Dictionary = own.duplicate()
	for m in members:
		if not _has_aura_rule(m.get("rules", [])):
			continue
		var descriptions: Dictionary = m.get("descriptions", {})
		for key in descriptions:
			if not merged.has(key):
				merged[key] = descriptions[key]
	return merged


## True if any rule name marks an aura (name contains "aura"), e.g. "Swift Aura".
static func _has_aura_rule(rules: Array) -> bool:
	for r in rules:
		if "aura" in str(r).to_lower():
			return true
	return false


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
