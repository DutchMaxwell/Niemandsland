extends GdUnitTestSuite
## PLAN H / landing lane: the Slayer Mark (gf / aof books: `target: enemy, beneficiary: attackers`, picked in the table's pre-attack slot) hands the marked unit's
## attackers the Slayer rule. The table reads it (`_solo_bridge_granted_flags`): a shooter that held gets AP(+2) against a Tough(3+) target and says why, one that moved
## says `Slayer: no AP, <U> moved`. The core bridged Rending / Furious / Relentless / Shred / Surge from that record and not Slayer (`ctx_live_vs`), so a held volley saved on
## the plain Defense and said nothing. From `PENDING_EPOCH_SLAYER_MARK_GRANT` (94) the core reads it. One REAL AI activation per seed (`_solo_activate_one_ai`), door on against
## door off, two placements (a foe 14 in away: the AI advances; a foe 7 in away: it holds), the slice = the committed deny file with the Utility Buff primitive taken out of the
## beat group (the lift is a data PR of its own): the same dice, the same end state, the same battle-log lines, and the door really ran the core.
## RED: at epoch 93 the held placement differs (AP, the save line, the Slayer line) - the second test.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const Harness := preload("res://test/one_core/golden_witness_harness.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")
const RosterSweep := preload("res://test/one_core/roster_sweep.gd")
const DICE := "user://slayer_mark_dice"
const SLICE := "user://deny_without_utility_buff_beat_slayer.json"
const SEEDS := 8
## [half gap, friend distance] in inches.
const PLACEMENTS := [[7.0, 3.0], [3.5, 1.5]]

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _epoch_before := 0


func before_test() -> void:
	var committed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CoreSlice.DENY_PATH))
	var beat: Dictionary = committed["groups"]["pre_attack_beat_twice"]
	(beat["primitives"] as Array).erase("Utility Buff")
	var f := FileAccess.open(SLICE, FileAccess.WRITE)
	f.store_string(JSON.stringify(committed))
	f.close()
	CoreSlice.path_override = SLICE
	CoreSlice.reset_cache()
	_epoch_before = AiActRecorder.rules_epoch
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
	AiActRecorder.rules_epoch = _epoch_before
	CoreActivation._env = 1
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


## The battle-log lines of a volley, as door on and off say them: all of them (the roll echoes carry the save target, which is what the AP changes).
func _differs(placement: Array, seed: int) -> Dictionary:
	var on := await _probe("gf", "elven_jesters", "Slayer Mark", seed, placement[0], ["Caster(2)"], placement[1], true)
	var off := await _probe("gf", "elven_jesters", "Slayer Mark", seed, placement[0], ["Caster(2)"], placement[1], false)
	var why: Array = []
	if _sig(on["rolls"]) != _sig(off["rolls"]):
		why.append("rolls")
	if on["digest"] != off["digest"]:
		why.append("digest")
	if on["lines"] != off["lines"]:
		why.append("lines")
	var named := (off["lines"] as Array).any(func(l: Variant) -> bool: return str(l).begins_with("COMBAT|Slayer: "))
	return {"why": why, "ran": int(on["ran"]), "named": named}


func test_a_slayer_mark_resolves_alike_through_the_door_from_epoch_94() -> void:
	AiActRecorder.rules_epoch = 94
	var ran := 0
	var named := 0
	var unequal: Array = []
	for placement in PLACEMENTS:
		for s in SEEDS:
			var r := await _differs(placement, s)
			ran += int(r["ran"])
			named += 1 if bool(r["named"]) else 0
			if not (r["why"] as Array).is_empty():
				unequal.append("seed %d at %s: differs in %s" % [s, placement, r["why"]])
	assert_array(unequal).override_failure_message("%d unequal, e.g. %s" % [unequal.size(), unequal.slice(0, 2)]).is_empty()
	assert_int(ran).override_failure_message("the door must run the core in every seed").is_equal(SEEDS * PLACEMENTS.size())
	assert_int(named).override_failure_message("the table must say its Slayer line in every seed, or nothing was compared").is_equal(SEEDS * PLACEMENTS.size())


## The check can fail: below the gate the core reads nothing, so the held placement saves on the plain Defense and says no Slayer line.
func test_below_the_gate_the_held_volley_differs() -> void:
	AiActRecorder.rules_epoch = 93
	var r := await _differs(PLACEMENTS[1], 0)
	assert_int(int(r["ran"])).is_equal(1)
	assert_array(r["why"]).contains(["lines"])
