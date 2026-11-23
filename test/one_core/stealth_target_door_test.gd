extends GdUnitTestSuite
## One core DS-STEALTH (the Changebound / Stealth Aura deny names, lead lane "stealth", 20.11.): a unit that is shot from over 9" by a Q4 line
## of rifles is hit one worse (GF/AoF Advanced Rules v3.5.1 p.14 Stealth; the 3.6 text counts most models). The roster sweep of 18.11. listed
## 8 taken volleys where the TABLE hit a Changebound / Stealth Aura target at 3+ and the core at 4+ and the deny file refused both names. The
## cause is not the penalty: every case below, the table and the core roll the same dice. The volleys all had a shooter with a Deadly weapon
## beside another weapon (Change Brothers -> Echo-3G01): the table lands Deadly inline, the target is dead when the second weapon rolls, and
## its LIVE most-models read finds no model with Stealth; the core lands after the dice (lead ruling O1, all weapons fire together) and keeps
## it. That shooter shape is refused by `deadly_beside_other_weapons` since dlines2, so the names are redundant for it.
## Real: the main scene, NmlCore, the importer's unit builder, the table's AI body. Constructed: the units.
##
## PLAN_FIRST_DELETION 34 FT-C5: the table arm left before step 31 (the AI table resolver retires); door values are pinned as literals read on main af5c83610.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const RosterSweep := preload("res://test/one_core/roster_sweep.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")
const SEEDS := 12
const UNSTOPPABLE_LINE := "Unstoppable: negative to-hit modifiers ignored"
## The fold line once per seed's volley, read on main af5c83610 (the table said it 12 times).
# Snapshot pin: read from the rules core on main, not derived from the rulebook (docs/adr/0005-snapshot-pins.md).
const WANT_UNSTOPPABLE_LINES := 12
const DICE := "user://stealth_target_dice"

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _armed := false


func before_test() -> void:
	_armed = false
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)


func after_test() -> void:
	RosterSweep.disarm(_main)
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## `weapons`: [[name, range in, attacks, [rules]]]; one gun per model, Quality 4 so the penalty reads as a 5+.
func _entry(uname: String, size: int, rules: Array, faction: String, weapons: Array, tough := 1) -> Dictionary:
	var ou := OPRApiClient.OPRUnit.new()
	ou.name = uname
	ou.size = size
	ou.quality = 4
	ou.defense = 6
	ou.game_system = "gf"
	ou.special_rules.assign(rules + (["Tough(%d)" % tough] if tough > 1 else []))
	for spec in weapons:
		var w := OPRApiClient.OPRWeapon.new()
		w.name = str(spec[0])
		w.range_value = int(spec[1])
		w.attacks = int(spec[2])
		w.special_rules.assign(spec[3])
		ou.weapons.append(w)
	return {"unit": ou, "faction": faction, "system": "gf"}


func _rifles(extra := []) -> Dictionary:
	return _entry("Rifles", 10, [], "robot_legions", [["Rifle", 24, 2, []]] + extra)


## One HOLD activation of `att` at `tgt` (with `hero` joined to it when given) on one path.
func _volley(core: bool, seed_n: int, att_e: Dictionary, tgt_e: Dictionary, hero_e: Dictionary, dist_in: float) -> Dictionary:
	var att := RosterSweep.spawn(_main, att_e, RosterSweep.SEAT_SHOOTER, 0.0)
	var tgt := RosterSweep.spawn(_main, tgt_e, RosterSweep.SEAT_TARGET, dist_in)
	var made: Array = [att, tgt]
	if not hero_e.is_empty():
		var hero := RosterSweep.spawn(_main, hero_e, RosterSweep.SEAT_TARGET, dist_in + 3.0)
		EquipmentDistributor.attach_hero_to_unit(hero, tgt)
		made.append(hero)
	_main.seed_tray_rng(seed_n)
	var lines: Array = []
	var on_entry := func(e: Dictionary) -> void:
		lines.append(str(e["text"]))
	_main.battle_log.entry_added.connect(on_entry)
	if core:
		CoreActivation.reset_all(_main)
		var h := CoreActivation.capture(_main)
		var at: Array = att.get_alive_models().map(func(m: ModelInstance) -> Vector3: return m.node.global_position)
		var trails: Array = att.get_alive_models().map(func(_m: ModelInstance) -> Array: return [])
		var t: Array = [{"t": "begin"}, {"t": "placed", "positions": at, "trails": trails},
			{"t": "intent", "kind": AiDecision.Action.HOLD, "shoot": tgt.unit_id}]
		var r: Dictionary = await CoreActivation.drive(_main, h, att, t, true)
		if str(r["step"]) != "done":
			_main.solo_controller._core_node_ready().release(h)
	else:
		_main._solo_core_ai_h = 0
		await _main._run_ai_shooting({"unit": att, "moved": false, "action": AiDecision.Action.HOLD})
	_main.battle_log.entry_added.disconnect(on_entry)
	AiDiceRecorder.close()
	var out := {"lines": lines, "rolls": ParityTable._read_dice(ProjectSettings.globalize_path(DICE)), "state": RosterSweep.state_of(att, tgt),
		"labels": {"att": [], "tgt": []}, "names": [att.get_name(), tgt.get_name()],
		"deny": CoreSlice.refusals_in(CoreSlice.DENY_PATH, att) + CoreSlice.refusals_in(CoreSlice.DENY_PATH, tgt, true) \
			+ CoreSlice.pair_refusals_in(CoreSlice.DENY_PATH, att, tgt)}
	RosterSweep.free_units(_main, made)
	await _main.get_tree().process_frame
	return out


## The to-hit number of every attack die group, in firing order.
func _hit_targets(rolls: Array) -> Array:
	return rolls.filter(func(x: Dictionary) -> bool: return str(x["kind"]) == "attack").map(func(x: Dictionary) -> int: return int(x["target"]))


func _arm() -> void:
	if not _armed:
		RosterSweep.arm(_main, ProjectSettings.globalize_path(DICE))
		_armed = true


## `SEEDS` door volleys: {"core": the first volley's hit targets, "deny": its refusals, "core_said": the fold-line count over all seeds}.
func _run(att_e: Dictionary, tgt_e: Dictionary, hero_e := {}, dist_in := 14.0) -> Dictionary:
	_arm()
	var rows: Array = []
	for s in SEEDS:
		var core := await _volley(true, s, att_e, tgt_e, hero_e, dist_in)
		rows.append(core)
	var first_c := _hit_targets((rows[0] as Dictionary)["rolls"])
	var said := func(r: Dictionary) -> int:
		return (r["lines"] as Array).filter(func(l: String) -> bool: return l == UNSTOPPABLE_LINE).size()
	var c_said: int = rows.map(func(r: Dictionary) -> int: return said.call(r)).reduce(func(a: int, b: int) -> int: return a + b, 0)
	print("STEALTH_TARGET %s dist=%s seeds=%d core=%s deny=%s" % [((rows[0] as Dictionary)["names"] as Array)[1], dist_in, SEEDS, first_c, (rows[0] as Dictionary)["deny"]])
	return {"core": first_c, "deny": (rows[0] as Dictionary)["deny"], "core_said": c_said}


## RED on main decf711aa: the target is refused by name ("unit_rule:Changebound"). The dice themselves are equal and the penalty is on both sides.
func test_a_changebound_unit_shot_from_over_9_in_is_hit_one_worse_in_both_halves() -> void:
	var tgt := _entry("Shifters", 5, ["Changebound"], "change_disciples", [])
	var far := await _run(_rifles(), tgt)
	assert_array(far["deny"]).override_failure_message("the door must take a Changebound target").is_empty()
	# Snapshot pin: read from the rules core on main, not derived from the rulebook (docs/adr/0005-snapshot-pins.md).
	assert_int((far["core"] as Array)[0]).override_failure_message("14 in: Q4 + 1 is a 5+ on the door").is_equal(5)
	var near := await _run(_rifles(), tgt, {}, 8.0)
	assert_int((near["core"] as Array)[0]).override_failure_message("8 in: no penalty on the door").is_equal(4)


func test_a_stealth_aura_hero_is_hit_one_worse_in_both_halves() -> void:
	var hero := _entry("Echo", 1, ["Hero", "Stealth Aura"], "robot_legions", [], 3)
	var far := await _run(_rifles(), hero)
	assert_array(far["deny"]).override_failure_message("the door must take a Stealth Aura target").is_empty()
	# Snapshot pin: read from the rules core on main, not derived from the rulebook (docs/adr/0005-snapshot-pins.md).
	assert_int((far["core"] as Array)[0]).is_equal(5)


## Joined: Changebound counts most models (3.6), so a plain hero does not switch it off; a Changebound hero does not give it to a plain unit.
func test_a_joined_hero_follows_the_most_models_read_in_both_halves() -> void:
	var host := _entry("Shifters", 5, ["Changebound"], "change_disciples", [])
	var plain_hero := _entry("Captain", 1, ["Hero"], "change_disciples", [], 3)
	var most := await _run(_rifles(), host, plain_hero)
	assert_array(most["deny"]).is_empty()
	# Snapshot pin: read from the rules core on main, not derived from the rulebook (docs/adr/0005-snapshot-pins.md).
	assert_int((most["core"] as Array)[0]).override_failure_message("most models carry it").is_equal(5)
	var plain_host := _entry("Troopers", 5, [], "change_disciples", [])
	var bound_hero := _entry("Seer", 1, ["Hero", "Changebound"], "change_disciples", [], 3)
	var few := await _run(_rifles(), plain_host, bound_hero)
	assert_int((few["core"] as Array)[0]).override_failure_message("one model of six is not most").is_equal(4)


## The line the lift exposed (#3134) and the core now says (#3145): an Unstoppable weapon swallows the Stealth -1 (hit on 4+ instead of 5+), the
## table says so once per weapon and so does the core, so the pair is no longer refused. RED: the line missing on the door side (core_said 0).
func test_an_unstoppable_weapon_against_a_changebound_unit_says_the_same_line_on_both_paths() -> void:
	var tgt := _entry("Shifters", 5, ["Changebound"], "change_disciples", [])
	var res := await _run(_rifles([["Cannon", 24, 4, ["Unstoppable"]]]), tgt)
	assert_int(int(res["core_said"])).override_failure_message("the door says the fold line").is_greater(0)
	assert_int(int(res["core_said"])).override_failure_message("the door says it once per volley, every seed").is_equal(WANT_UNSTOPPABLE_LINES)
	assert_array(res["deny"]).override_failure_message("the pair is taken").is_empty()
