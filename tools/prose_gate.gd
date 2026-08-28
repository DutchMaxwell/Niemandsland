extends SceneTree
## PROSE GATE (NML-1115, tier 1) — does OPR rule TEXT still change what the table PLAYS?
##
## The table parses `±N"` modifiers out of Army Forge rule DESCRIPTIONS and adds them to a
## unit's Advance/Rush bands (`MovementRangeController.move_bands_for_props`), and the tray's
## Ambush/Scout lane word-scans the same texts (`OPRArmyManager._unit_rule_describes`). Neither
## the Godot-free trainer nor the Rust core has that prose, and nothing in a recording pins WHICH
## text produced a band — so every reading that depends on it is a silent table/trainer split.
##
## This gate builds every unit of every list in the given pools TWICE through the table's own
## import path — once with the fetched rule texts, once with `rule_descriptions` forced EMPTY —
## and diffs the three readings prose could reach: the move bands, the shooting-range bonus
## (the control channel: it reads the registry only, so it must stay at 0) and the tray lane.
## Any difference is RED and exits non-zero.
##
## Rule texts come from the LIVE Army Forge API, through the normal import (`_parse_tts_api_response`),
## so the gate measures what the table would actually have played today.
##
## BASELINE at main 41fc35e (28.08., 435 lists / 4279 units): band 0, lane 30, range 0 — RED.
## The bands are already clean: #441 (enemy-targeted phrases), #452 (registry target=enemy) and
## #453 (Ethereal's -6"/-6" as registry data) closed every band difference the NML-1115 recon
## still measured at 25ee0f2 (88). What is left is the tray lane: 30 unit-instances (12 distinct
## units) staged into the Ambush/Scout band because another rule's TEXT merely mentions the word.
##
## Run:
##   godot --headless --path . -s res://tools/prose_gate.gd -- \
##     lists=<ai_lists_gf> lists=<ai_lists_aof> [samples=20]

var _pools: Array[String] = []
var _max_samples := 12
var _lists := 0
var _units := 0
var _band_diffs := 0
var _range_diffs := 0
var _lane_diffs := 0
var _samples: Array[String] = []


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("lists="):
			_pools.append(arg.substr(6))
		elif arg.begins_with("samples="):
			_max_samples = int(arg.substr(8))
	# Nodes added during _initialize never enter the tree (core_selfplay.gd's note) — the
	# OPRApiClient below needs its HTTPRequest children, so start on the first process frame.
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	if _pools.is_empty():
		printerr("[PROSE] no lists=<dir> given"); quit(2); return
	var client := OPRApiClient.new()
	root.add_child(client)
	# _unit_rule_describes is non-static (it uses _word_in); a bare, tree-less instance is enough.
	var manager := OPRArmyManager.new()
	for pool in _pools:
		var dir := DirAccess.open(pool.replace("~", OS.get_environment("HOME")))
		if dir == null:
			printerr("[PROSE] pool not readable: %s" % pool); quit(2); return
		for file in dir.get_files():
			if file.ends_with(".json") and not file.begins_with("_"):
				await _check_list(client, manager, dir.get_current_dir() + "/" + file)
	manager.free()
	for line in _samples:
		printerr("[PROSE] %s" % line)
	printerr("[PROSE] %d lists, %d units | band differences %d | lane differences %d | range differences %d" % [
		_lists, _units, _band_diffs, _lane_diffs, _range_diffs])
	var total := _band_diffs + _lane_diffs + _range_diffs
	printerr("[PROSE] %s — rule text %s the table's readings" % [
		"RED" if total > 0 else "GREEN", "still moves" if total > 0 else "no longer moves"])
	quit(1 if total > 0 else 0)


## One list through the table's own import (network: the army book carries the rule texts),
## including the two post-spawn passes `OPRArmyManager.spawn_army` runs — a joined hero and an
## aura-granted rule both change the bands, and a gate that skips them invents differences
## (measured: "Rapid Advance Aura" alone looked like a prose-only +4" until `expand_auras_of` ran).
func _check_list(client: OPRApiClient, manager: OPRArmyManager, path: String) -> void:
	var army = await client._parse_tts_api_response(FileAccess.get_file_as_string(path))
	if army == null or army.units.is_empty():
		printerr("[PROSE] FATAL: import produced no units: %s" % path); quit(2); return
	_lists += 1
	var list_name := path.get_file().get_basename()
	var nodes: Array[Node3D] = []
	var by_unit: Dictionary = {}
	for ou in army.units:
		var models: Array[Node3D] = []
		for _m in range(maxi(ou.size, 1)):
			var n := Node3D.new()
			root.add_child(n)
			models.append(n)
			nodes.append(n)
		var gu := EquipmentDistributor.create_from_opr_unit(ou, models, 1, army.rule_descriptions)
		gu.unit_properties["faction_folder"] = army.faction_folder
		by_unit[ou] = gu
	OPRArmyManager.attach_joined_heroes_of(army.units, by_unit)
	OPRArmyManager.expand_auras_of(army.units, by_unit)
	for ou in army.units:
		var gu: GameUnit = by_unit[ou]
		var with_text := _reading(gu)
		gu.unit_properties["rule_descriptions"] = {}
		var without_text := _reading(gu)
		var lane_with := [_lane(manager, ou, army.rule_descriptions, "Ambush"),
			_lane(manager, ou, army.rule_descriptions, "Scout")]
		var lane_without := [_lane(manager, ou, {}, "Ambush"), _lane(manager, ou, {}, "Scout")]
		_units += 1
		if with_text[0] != without_text[0] or with_text[1] != without_text[1]:
			_band_diffs += 1
			_sample("band  %s / %s: %d/%d with text, %d/%d without" % [list_name, ou.name,
				with_text[0], with_text[1], without_text[0], without_text[1]])
		if with_text[2] != without_text[2]:
			_range_diffs += 1
			_sample("range %s / %s: %d with text, %d without" % [list_name, ou.name,
				with_text[2], without_text[2]])
		if lane_with != lane_without:
			_lane_diffs += 1
			_sample("lane  %s / %s: ambush/scout %s with text, %s without" % [list_name, ou.name,
				lane_with, lane_without])
	for n in nodes:
		n.queue_free()


## The three readings prose can reach, in the table's own primitives.
static func _reading(gu: GameUnit) -> Array:
	var bands := MovementRangeController.move_bands_for_props(gu.unit_properties)
	return [int(bands["advance"]), int(bands["rush"]), SoloController.shooting_range_bonus(gu)]


## The tray's staging lane for one rule, exactly as `OPRArmyManager._spawn_army_units` builds it.
static func _lane(manager: OPRArmyManager, opr_unit: Variant, descriptions: Dictionary, rule: String) -> bool:
	return OPRArmyManager._unit_has_rule(opr_unit, rule) \
		or manager._unit_rule_describes(opr_unit, rule, descriptions)


func _sample(line: String) -> void:
	if _samples.size() < _max_samples:
		_samples.append(line)
