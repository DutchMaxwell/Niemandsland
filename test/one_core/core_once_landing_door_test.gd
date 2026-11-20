extends GdUnitTestSuite
## PLAN H / landing lane: the once-records the TABLE's pre-attack beat placed after the activation's capture are spent by the door's landing. A Utility Buff bearer's
## beat runs on the table first (Furious Buff on a friend, a Shred / Slayer / Indirect / Quick Shot / Increased Shooting Range Mark on the foe), the core's one call then resolves
## its own copy of the beat from the board it captured BEFORE the beat and spends it, so the table's record (and the table's `"X" on U is consumed (applies once)` line) went
## stale: the delta names only records the capture held (`buffs_spent`). One REAL AI activation per seed (`_solo_activate_one_ai`), door on against door off, the slice = the
## committed deny file with the Utility Buff primitive taken out of the beat group (the lift itself is a data PR of its own), and the door really ran the core (`CoreActivation.ai_runs`).
## What is compared here is the LANDING: the units' once-records and the `"X" on U is consumed (applies once)` lines. The rest of the volley (dice faces and the other lines) is the
## lift's own test; the Slayer Mark's AP and the moved-Indirect to-hit note are core gaps of their own (PLAN H log), so the end state is not compared whole.
## RED: `CoreActivation.land_late_once = false` (the second test) -> the records stay on the table and the consumed line is missing.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const Harness := preload("res://test/one_core/golden_witness_harness.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")
const RosterSweep := preload("res://test/one_core/roster_sweep.gd")
const DICE := "user://once_landing_dice"
const SLICE := "user://deny_without_utility_buff_beat.json"
const SEEDS := 5
## [rule, system, faction folder]: the first (system, faction) whose map fields the rule.
const NAMES := [["Furious Buff", "gf", "alien_hives"], ["Shred Mark", "gf", "custodian_brothers"], ["Slayer Mark", "gf", "elven_jesters"],
	["Indirect Mark", "gf", "robot_legions"], ["Quick Shot Mark", "gf", "daemons_of_lust"], ["Increased Shooting Range Mark", "gf", "eternal_dynasty"]]
## [half gap, friend distance] in inches: a foe 14 in away (the AI advances and shoots) and a foe 7 in away (the AI holds and shoots), the friend close behind.
const PLACEMENTS := [[7.0, 3.0], [3.5, 1.5]]

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	var committed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CoreSlice.DENY_PATH))
	var beat: Dictionary = committed["groups"]["pre_attack_beat_twice"]
	(beat["primitives"] as Array).erase("Utility Buff")
	var f := FileAccess.open(SLICE, FileAccess.WRITE)
	f.store_string(JSON.stringify(committed))
	f.close()
	CoreSlice.path_override = SLICE
	CoreSlice.reset_cache()
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	RosterSweep.arm(_main, ProjectSettings.globalize_path(DICE))
	CoreActivation._env = 1
	CoreActivation.ai_runs = 0
	CoreActivation.ai_refusals = 0


func after_test() -> void:
	CoreActivation._env = 1
	CoreActivation.land_late_once = true
	CoreSlice.path_override = ""
	CoreSlice.reset_cache()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SLICE))
	RosterSweep.disarm(_main)
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _rolls() -> Array:
	AiDiceRecorder.close()
	var path := ProjectSettings.globalize_path(DICE).path_join("dice.jsonl")
	var rolls: Array = []
	if FileAccess.file_exists(path):
		for line in FileAccess.get_file_as_string(path).split("\n", false):
			rolls.append(JSON.parse_string(line))
		DirAccess.remove_absolute(path)
	return rolls


const KEYS := ["piercing_tag_markers", "piercing_tag_source", "piercing_tag_used", "tag_markers", "precision_tag_used", "precision_target_used",
	"utility_buff_round", "reckless_ap_round", "reckless_backfire_round", "reckless_rolled_round", "piercing_spot_round", "spotted_round",
	"mind_control_moved_round", "storm_used_storm_of_war", "mend_round", "breath_round"]


func _digest(units: Array) -> Dictionary:
	var out := {}
	for u in units:
		var gu := u as GameUnit
		var row := {}
		for k in KEYS:
			if gu.unit_properties.has(k):
				row[k] = gu.unit_properties[k]
		var recs: Array = _main._solo_spell_mods.get(gu.get_instance_id(), [])
		row["mods"] = recs.map(func(r: Dictionary) -> String: return "%s/%s/%s" % [r.get("spell", ""), r.get("scope", ""), r.get("duration", "")])
		row["alive"] = gu.get_alive_count()
		row["shaken"] = gu.is_shaken
		row["fatigued"] = gu.is_fatigued
		out[gu.get_name()] = row
	return out


func _probe(sys: String, faction: String, rule: String, seed: int, gap_x: float, friend_rules: Array, friend_dx: float, door: bool) -> Dictionary:
	CoreActivation._env = 1 if door else 0
	var side := {"quality": 4, "defense": 4, "tough": 3, "z_step_in": 1.2, "game_system": sys, "faction_folder": faction, "rules": [rule]}
	var att := ParityTable._make_unit(_main, side.merged({"player": 2, "name": "Att", "models": 5, "x_in": -gap_x}, true),
		{"name": "Rifle", "range_in": 24, "attacks": 1, "count": 5, "rules": []})
	var foe := ParityTable._make_unit(_main, side.merged({"player": 1, "name": "Def", "models": 5, "x_in": gap_x, "rules": []}, true),
		{"name": "Rifle", "range_in": 24, "attacks": 1, "count": 5, "rules": []})
	var units: Array = [att, foe]
	if friend_dx != 0.0:
		var fr := ParityTable._make_unit(_main, side.merged({"player": 2, "name": "Friend", "models": 3, "x_in": -gap_x - friend_dx, "rules": friend_rules}, true),
			{"name": "Rifle", "range_in": 24, "attacks": 1, "count": 3, "rules": []})
		units.append(fr)
	var takes := CoreSlice.takes(att)
	_main.seed_tray_rng(seed)
	var runs_before := CoreActivation.ai_runs
	var lines: Array = []
	var tap: Callable = Harness._line_tap(lines)
	_main.battle_log.entry_added.connect(tap)
	await _main._solo_activate_one_ai()
	_main.battle_log.entry_added.disconnect(tap)
	var rolls := _rolls()
	var out := {"takes": takes, "ran": CoreActivation.ai_runs - runs_before, "lines": lines, "rolls": rolls, "digest": _digest(units)}
	Harness._free_units(_main, units)
	_main.solo_controller._peeked_unit = null
	await _main.get_tree().process_frame
	return out


## A roll without its running counters (`act`, `seq` differ between two activations by construction).
func _sig(rolls: Array) -> Array:
	return rolls.map(func(x: Dictionary) -> String: return "%s:%d:%s:%s:%s" % [x.get("roll_kind", "?"), int(x["count"]), str(x["owner"]), str(x.get("leg", "")), str(x["faces"])])


## The units' once-records (name / scope / duration), per unit name.
func _mods(r: Dictionary) -> Dictionary:
	var out := {}
	for u in r["digest"]:
		out[u] = r["digest"][u]["mods"]
	return out


## The table's own spend lines.
func _consumed(r: Dictionary) -> Array:
	return (r["lines"] as Array).filter(func(l: Variant) -> bool: return str(l).contains(" is consumed (applies once)"))


func test_the_table_records_a_beat_placed_are_spent_through_the_door() -> void:
	for row in NAMES:
		var ran := 0
		var unequal: Array = []
		for placement in PLACEMENTS:
			for s in SEEDS:
				var on := await _probe(row[1], row[2], row[0], s, placement[0], ["Caster(2)"], placement[1], true)
				var off := await _probe(row[1], row[2], row[0], s, placement[0], ["Caster(2)"], placement[1], false)
				ran += int(on["ran"])
				if not bool(on["takes"]):
					unequal.append("seed %d at %s: the slice refuses the bearer" % [s, placement])
				elif _mods(on) != _mods(off):
					unequal.append("seed %d at %s: records on %s, off %s" % [s, placement, _mods(on), _mods(off)])
				elif _consumed(on) != _consumed(off):
					unequal.append("seed %d at %s: consumed lines on %s, off %s" % [s, placement, _consumed(on), _consumed(off)])
				elif _consumed(off).is_empty():
					unequal.append("seed %d at %s: the table spent nothing, nothing was compared" % [s, placement])
		assert_array(unequal).override_failure_message("%s: %d unequal, e.g. %s" % [row[0], unequal.size(), unequal.slice(0, 2)]).is_empty()
		assert_int(ran).override_failure_message("%s: the door must run the core in every seed" % row[0]).is_equal(SEEDS * PLACEMENTS.size())


## The check can fail: with the landing off the door leaves the table's record on the foe and says no consumed line.
func test_without_the_landing_the_record_goes_stale() -> void:
	CoreActivation.land_late_once = false
	var on := await _probe("gf", "custodian_brothers", "Shred Mark", 0, 7.0, ["Caster(2)"], 3.0, true)
	var off := await _probe("gf", "custodian_brothers", "Shred Mark", 0, 7.0, ["Caster(2)"], 3.0, false)
	assert_int(int(on["ran"])).is_equal(1)
	assert_array(_mods(on)["Def"]).is_equal(["Shred Mark//once"])
	assert_array(_mods(off)["Def"]).is_empty()
	assert_array(_consumed(on)).is_empty()
	assert_int(_consumed(off).size()).is_equal(1)
