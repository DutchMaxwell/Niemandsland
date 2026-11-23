extends GdUnitTestSuite
## PLAN H / landing lane: Furious Buff and the Shred / Quick Shot / Increased Shooting Range Marks leave the `pre_attack_beat_twice` group by name (`lifted_names` in
## assets/solo/core_slice_deny.json) now that the door's landing spends the once-records the table's beat placed (core_once_landing_door_test.gd). One REAL AI activation per seed
## (`_solo_activate_one_ai`: the table's beat block runs, then the door takes the activation) with the COMMITTED slice, door on against door off, two placements (a foe 14 in away: the AI
## advances; 7 in: it holds): the same dice, the same end state (records included), the same battle-log lines, and the door really ran the core (`CoreActivation.ai_runs`).
## The Slayer Mark (core gap, epoch 94) and the Indirect Mark (the moved-Indirect to-hit note) are not here: each is lifted by the PR that closes its own gap.
## RED: take a name out of `lifted_names` -> the slice refuses the bearer and the core never runs (`ran` 0).
## PLAN_FIRST_DELETION 34 FT-C7: the table arm left before step 31 (the AI table resolver retires); door values are pinned as literals read on main 97fa324e9.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const Harness := preload("res://test/one_core/golden_witness_harness.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")
const RosterSweep := preload("res://test/one_core/roster_sweep.gd")
const DICE := "user://once_lift_dice"
const SEEDS := 8
## [rule, system, faction folder]: the first (system, faction) whose map fields the rule.
const NAMES := [["Furious Buff", "gf", "alien_hives"], ["Shred Mark", "gf", "custodian_brothers"], ["Quick Shot Mark", "gf", "daemons_of_lust"],
	["Increased Shooting Range Mark", "gf", "eternal_dynasty"]]
## [half gap, friend distance] in inches.
const PLACEMENTS := [[7.0, 3.0], [3.5, 1.5]]
## Per rule, per placement, per seed: door battle-log lines containing the rule name, and door dice records (read on main).
# Snapshot pin: read from the rules core on main, not derived from the rulebook (docs/adr/0005-snapshot-pins.md).
const WANT_NAMED := {"Furious Buff": [[3, 3, 3, 3, 3, 3, 3, 3], [3, 3, 3, 3, 3, 3, 3, 3]],
	"Shred Mark": [[3, 3, 3, 3, 3, 3, 3, 3], [3, 3, 3, 3, 3, 3, 3, 3]],
	"Quick Shot Mark": [[3, 3, 3, 3, 3, 3, 3, 3], [3, 3, 3, 3, 3, 3, 3, 3]],
	"Increased Shooting Range Mark": [[3, 3, 3, 3, 3, 3, 3, 3], [3, 3, 3, 3, 3, 3, 3, 3]]}
# Snapshot pin: read from the rules core on main, not derived from the rulebook (docs/adr/0005-snapshot-pins.md).
const WANT_ROLLS := {"Furious Buff": [[2, 2, 2, 2, 2, 2, 2, 2], [2, 2, 2, 2, 2, 2, 2, 2]],
	"Shred Mark": [[2, 2, 2, 2, 2, 2, 2, 2], [2, 2, 2, 2, 2, 2, 2, 2]],
	"Quick Shot Mark": [[2, 2, 2, 2, 2, 2, 2, 2], [2, 2, 2, 2, 2, 2, 2, 2]],
	"Increased Shooting Range Mark": [[2, 2, 2, 2, 2, 2, 2, 2], [2, 2, 2, 2, 2, 2, 2, 2]]}

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	CoreSlice.path_override = ""
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


func test_the_lifted_beat_names_resolve_alike_through_the_door() -> void:
	for row in NAMES:
		var ran := 0
		var unequal: Array = []
		for pi in PLACEMENTS.size():
			var placement: Array = PLACEMENTS[pi]
			for s in SEEDS:
				var on := await _probe(row[1], row[2], row[0], s, placement[0], ["Caster(2)"], placement[1], true)
				ran += int(on["ran"])
				var named := (on["lines"] as Array).filter(func(l: Variant) -> bool: return str(l).contains(row[0])).size()
				var rolls := _sig(on["rolls"]).size()
				if not bool(on["takes"]):
					unequal.append("seed %d at %s: the slice refuses the bearer" % [s, placement])
				elif named != int(WANT_NAMED[row[0]][pi][s]):
					unequal.append("seed %d at %s: named %d times, want %d" % [s, placement, named, WANT_NAMED[row[0]][pi][s]])
				elif rolls != int(WANT_ROLLS[row[0]][pi][s]):
					unequal.append("seed %d at %s: %d rolls, want %d" % [s, placement, rolls, WANT_ROLLS[row[0]][pi][s]])
		assert_array(unequal).override_failure_message("%s: %d unequal, e.g. %s" % [row[0], unequal.size(), unequal.slice(0, 2)]).is_empty()
		assert_int(ran).override_failure_message("%s: the door must run the core in every seed" % row[0]).is_equal(SEEDS * PLACEMENTS.size())
