extends GdUnitTestSuite
## E2E — the unit cards show EVERY piece of information and hide none of it (maintainer 23.09.: "die
## Informationen ... dürfen nicht eingekürzt werden" — "wir müssen das Abschneiden heilen").
##
## Four real lists go through the production importer (build_army_offline -> EquipmentDistributor ->
## joined heroes) into the real main.tscn: heroes, joined heroes, combined units, Tough vehicles, a
## transport, casters with spells, weapon teams, mounts, item grants, and the AI's army (player 2).
## A few units are put into states (activated / fatigued / shaken, destroyed, out of coherency, a custom
## token). Every unit's presented card, strip card and hover tooltip is read as a player reads it:
## every label, button, link, rich text (as displayed) and every tooltip of a tag.
##
## - The multisets must equal test/fixtures/card_text_golden.json, recorded on origin/main's card code
##   (NML_RECORD_CARD_GOLDEN=1 re-records it; never re-record to make a change pass).
## - Nothing on a card may be trimmed, clipped or sit outside its card / box.
## - The first stats tooltip of a session is as tall as its text (it came out screen-tall).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const GOLDEN := "res://test/fixtures/card_text_golden.json"
## [key, list, player] — the AI plays the ratmen.
const LISTS := [
	["wolf", "res://test/fixtures/wolf_brothers_3000.json", 1],
	["beastmen", "res://test/fixtures/card_list_aof_beastmen_1000.json", 1],
	["custodian", "res://test/fixtures/card_list_gf_custodian_brothers_1000.json", 1],
	["ratmen", "res://test/fixtures/card_list_aof_ratmen_1500.json", 2],
]
## Army books are not in the repo: every rule gets this text (long enough to wrap in its tooltip).
const DESCRIPTION := "What %s does at the table, written long enough to wrap over several lines of its tooltip."
const SPELLS := [
	{"name": "Test Bolt", "threshold": 4, "effect": "The target takes 3 hits with Blast(3)."},
	{"name": "A Spell With A Rather Long Name For A Card", "threshold": 5,
		"effect": "Friendly units within 12\" get Fearless until the end of the round."},
]

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


# === the units ================================================================================

## Every unit of the four lists as [["wolf#3", GameUnit], …], registered with the real army manager.
func _build_units() -> Array:
	var out: Array = []
	var am: OPRArmyManager = _main.opr_army_manager
	var client := OPRApiClient.new()
	for entry: Array in LISTS:
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(entry[1]))
		var army := client.build_army_offline(data)
		var by_unit := {}
		for unit: OPRApiClient.OPRUnit in army.units:
			var nodes: Array[Node3D] = []
			for i in range(maxi(unit.size, 1)):
				var n := Node3D.new()
				_main.object_manager.add_child(n)
				nodes.append(n)
			by_unit[unit] = EquipmentDistributor.create_from_opr_unit(unit, nodes, int(entry[2]))
		OPRArmyManager.attach_joined_heroes_of(army.units, by_unit)
		for i in army.units.size():
			var gu: GameUnit = by_unit[army.units[i]]
			am.game_units[gu.unit_id] = gu
			out.append(["%s#%d" % [entry[0], i], gu])
		am._session_spells[int(entry[2])] = SPELLS
	client.free()
	# Every rule, weapon rule and granted rule gets a description (keyed by its base name).
	for pair: Array in out:
		var gu: GameUnit = pair[1]
		var names: Array = gu.get_special_rules().duplicate()
		var opr := gu.source_data as OPRApiClient.OPRUnit
		for w: OPRApiClient.OPRWeapon in opr.weapons:
			names.append_array(w.special_rules)
		for it in opr.item_grants:
			names.append_array(opr.item_grants[it])
		for r in names:
			var nm := str(r.get("name", "")) if r is Dictionary else str(r)
			var base := nm.substr(0, nm.find("(")).strip_edges() if nm.find("(") > 0 else nm
			am.rule_descriptions[base] = DESCRIPTION % base
	_put_units_in_states(out)
	return out


func _unit(units: Array, key: String) -> GameUnit:
	for pair: Array in units:
		if pair[0] == key:
			return pair[1]
	return null


## States a card must show: chips lit, a destroyed unit, a unit out of coherency, a custom token.
func _put_units_in_states(units: Array) -> void:
	var busy := _unit(units, "wolf#1")
	busy.is_activated = true
	busy.is_fatigued = true
	busy.is_shaken = true
	var spread := _unit(units, "wolf#3")
	for i in spread.models.size():
		(spread.models[i] as ModelInstance).node.position = Vector3(0.3 * i, 0.0, 0.0)
	for m in _unit(units, "beastmen#5").models:
		(m as ModelInstance).is_alive = false
	var tokened := _unit(units, "custodian#5").models[0] as ModelInstance
	tokened.add_marker("Objective")
	tokened.set_marker_value("Objective", 2)


# === reading a card ===========================================================================

## Every text a player can read on `root`: labels, buttons, links, rich text as displayed, tooltips.
static func texts(root: Node) -> Array:
	var out: Array = []
	_collect(root, out)
	out.sort()
	return out


static func _collect(n: Node, out: Array) -> void:
	if n is CanvasItem and not (n as CanvasItem).visible:
		return
	if n is RichTextLabel:
		_put(out, (n as RichTextLabel).get_parsed_text())
	elif n is Label:
		_put(out, (n as Label).text)
	elif n is Button or n is LinkButton:
		_put(out, str(n.get(&"text")))
	if n is Control and not (n as Control).tooltip_text.is_empty():
		_put(out, "tooltip: " + (n as Control).tooltip_text)
	for c in n.get_children():
		_collect(c, out)


static func _put(out: Array, s: String) -> void:
	if not s.strip_edges().is_empty():
		out.append(s)


## What `before` has that `after` lacks, and the other way round (multisets).
static func diff(before: Array, after: Array) -> Dictionary:
	var left := after.duplicate()
	var missing: Array = []
	for s in before:
		var i := left.find(s)
		if i < 0:
			missing.append(s)
		else:
			left.remove_at(i)
	return {"missing": missing, "extra": left}


## Every card's text: "<unit> presented" / "<unit> strip" / "<unit> tooltip" -> sorted texts.
func _read_all_cards(units: Array) -> Dictionary:
	var cards := {}
	var dock: UnitDock = _main.unit_dock
	for pair: Array in units:
		dock.present_unit(pair[1])
		await _runner.simulate_frames(4)
		cards["%s presented" % pair[0]] = texts(dock._presented)
	dock.rebuild()
	dock._toggle_dock()
	await _runner.simulate_frames(6)
	for pair: Array in units:
		var entry = dock._cards.get((pair[1] as GameUnit).unit_id)
		if entry != null:
			cards["%s strip" % pair[0]] = texts(entry["card"])
	dock._toggle_dock()
	var tip: OPRStatsTooltip = _main.opr_stats_tooltip
	for pair: Array in units:
		var gu: GameUnit = pair[1]
		tip.show_unit(gu.source_data, (gu.models[0] as ModelInstance).node, true)
		await _runner.simulate_frames(2)
		cards["%s tooltip" % pair[0]] = texts(tip)
		tip.hide_tooltip()
	return cards


# === tests ====================================================================================

func test_every_card_shows_exactly_what_it_showed_before(timeout := 300000) -> void:
	var cards: Dictionary = await _read_all_cards(_build_units())
	if OS.get_environment("NML_RECORD_CARD_GOLDEN") == "1":
		var f := FileAccess.open(ProjectSettings.globalize_path(GOLDEN), FileAccess.WRITE)
		f.store_string(JSON.stringify(cards, "  ", true) + "\n")
		f.close()
		print("CARD_GOLDEN_RECORDED ", cards.size(), " cards")
	var golden: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GOLDEN))
	var problems: Array = []
	for key: String in golden:
		if not cards.has(key):
			problems.append("%s: the card is gone" % key)
			continue
		var d := diff(golden[key], cards[key])
		for s in d["missing"]:
			problems.append("%s: MISSING %s" % [key, JSON.stringify(s)])
		for s in d["extra"]:
			problems.append("%s: NEW %s" % [key, JSON.stringify(s)])
	for key: String in cards:
		if not golden.has(key):
			problems.append("%s: a card that did not exist before" % key)
	assert_array(problems).override_failure_message("card text differs from before:\n" + "\n".join(problems)).is_empty()
	assert_int(golden.size()).override_failure_message("the golden holds too few cards to prove anything").is_greater(60)


func test_the_equality_check_names_a_dropped_weapon_tag(timeout := 120000) -> void:
	var units := _build_units()
	var dock: UnitDock = _main.unit_dock
	dock.present_unit(_unit(units, "wolf#1"))   # Wolf Veteran Assault Brothers: AP(4) on a weapon
	await _runner.simulate_frames(4)
	var before := texts(dock._presented)
	var tag: BaseButton = null
	for c: Node in dock._presented.find_children("*", "BaseButton", true, false):
		if tag == null and str(c.get_meta("rule_meta", "")).begins_with("AP("):
			tag = c
	if tag == null:
		fail("no weapon tag to drop — the check proves nothing")
		return
	var dropped := [str(tag.get(&"text")), "tooltip: " + tag.tooltip_text]
	tag.get_parent().remove_child(tag)
	tag.free()
	var d := diff(before, texts(dock._presented))
	assert_array(d["missing"]).contains_exactly_in_any_order(dropped)
	assert_array(d["extra"]).is_empty()


## Every text element of `card` that is trimmed, clipped, larger than its box or outside the card.
static func truncations(card: Control, label: String) -> Array:
	var bad: Array = []
	for n: Node in card.find_children("*", "", true, false):
		var c := n as Control
		if c == null or not c.is_visible_in_tree():
			continue
		var what := ""
		if c is Label:
			var l := c as Label
			what = l.text
			if l.text_overrun_behavior != TextServer.OVERRUN_NO_TRIMMING or l.clip_text:
				bad.append("%s: trimmed %s" % [label, JSON.stringify(what)])
			elif l.get_minimum_size().x > l.size.x + 0.5 or l.get_minimum_size().y > l.size.y + 0.5:
				bad.append("%s: bigger than its box %s %s > %s" % [label, JSON.stringify(what), l.get_minimum_size(), l.size])
		elif c is RichTextLabel:
			var r := c as RichTextLabel
			what = r.get_parsed_text()
			if r.get_content_height() > r.size.y + 1.0:
				bad.append("%s: rich text taller than its box %s" % [label, JSON.stringify(what.left(40))])
		elif c is Button or c is LinkButton:
			what = str(c.get(&"text"))
			if c.get_minimum_size().x > c.size.x + 0.5:
				bad.append("%s: button wider than its box %s" % [label, JSON.stringify(what)])
		if what.is_empty():
			continue
		var r := Rect2(Vector2.ZERO, c.size)
		var p: Node = c
		while p != card and p is Control:
			r.position += (p as Control).position
			p = p.get_parent()
		if not Rect2(Vector2.ZERO, card.size).grow(1.0).encloses(r):
			bad.append("%s: outside the card %s %s in %s" % [label, JSON.stringify(what), r, card.size])
	return bad


func test_no_card_text_is_trimmed_clipped_or_outside_its_card(timeout := 300000) -> void:
	var units := _build_units()
	var dock: UnitDock = _main.unit_dock
	var bad: Array = []
	var tallest := {"presented": 0.0, "strip": 0.0}
	for pair: Array in units:
		dock.present_unit(pair[1])
		await _runner.simulate_frames(4)
		bad.append_array(truncations(dock._presented, "%s presented" % pair[0]))
		tallest["presented"] = maxf(tallest["presented"], dock._presented.size.y)
	dock.rebuild()
	dock._toggle_dock()
	await _runner.simulate_frames(6)
	# A live status change rebuilds a strip card — it must still fit afterwards.
	for pair: Array in units:
		(pair[1] as GameUnit).is_fatigued = not (pair[1] as GameUnit).is_fatigued
	dock._refresh_status()
	await _runner.simulate_frames(6)
	for pair: Array in units:
		var entry = dock._cards.get((pair[1] as GameUnit).unit_id)
		if entry != null:
			bad.append_array(truncations(entry["card"], "%s strip" % pair[0]))
			tallest["strip"] = maxf(tallest["strip"], (entry["card"] as Control).size.y)
			# A rebuilt card's rule links keep their descriptions (they came back empty).
			for b: Node in (entry["card"] as Node).find_children("*", "BaseButton", true, false):
				if b.has_meta("rule_meta") and (b as Control).tooltip_text.is_empty():
					bad.append("%s strip: lost its description — link %s" % [pair[0], JSON.stringify(b.get(&"text"))])
	print("CARD_HEIGHTS tallest presented %d strip %d of %d" % [tallest["presented"], tallest["strip"], dock.get_viewport_rect().size.y])
	dock._toggle_dock()
	var tip: OPRStatsTooltip = _main.opr_stats_tooltip
	for pair: Array in units:
		var gu: GameUnit = pair[1]
		tip.show_unit(gu.source_data, (gu.models[0] as ModelInstance).node, true)
		await _runner.simulate_frames(3)
		bad.append_array(truncations(tip, "%s tooltip" % pair[0]))
		tip.hide_tooltip()
	# Five examples of every kind of finding, so one kind cannot hide the others.
	var shown: Array = []
	for kind: String in [": trimmed", ": bigger than its box", ": rich text taller", ": button wider", ": outside the card",
			": lost its description"]:
		var of_kind := bad.filter(func(s: String) -> bool: return s.contains(kind))
		if not of_kind.is_empty():
			shown.append("%d x%s, e.g.:" % [of_kind.size(), kind])
			shown.append_array(of_kind.slice(0, 5))
	assert_array(bad).override_failure_message("%d truncated / clipped texts:\n%s" % [bad.size(), "\n".join(shown)]).is_empty()


func test_the_first_stats_tooltip_is_as_tall_as_its_text(timeout := 120000) -> void:
	var units := _build_units()
	var gu := _unit(units, "wolf#1")
	var tip: OPRStatsTooltip = _main.opr_stats_tooltip
	tip.show_unit(gu.source_data, (gu.models[0] as ModelInstance).node, true)   # the session's first show
	await _runner.simulate_frames(3)
	var need: float = tip.get_combined_minimum_size().y
	assert_float(tip.size.y).override_failure_message("the first tooltip is %d px tall, its text needs %d (screen %d)" % [
		tip.size.y, need, tip.get_viewport_rect().size.y]).is_less_equal(need + 1.0)
