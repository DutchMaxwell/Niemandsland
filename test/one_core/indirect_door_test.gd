extends GdUnitTestSuite
## One core C-20 (EPOCH_85_INDIRECT_GATE, lane S1's soak, 17.11.): a HOLDING Artillery beast with an Indirect gun fired nothing in the core at a
## target another unit hid from it, while the table fired (the 45 Indirect volleys the deny list keeps on the table; two of the soak's
## eight taken-but-unequal volleys). The table's per-shot sight count waives line of sight for a weapon's own Indirect; the core's pooled target
## gate asked for sight only. This is the soak's volley as a fixture: the beast (one model, a 36" Indirect gun with AP and Blast, the soak's
## Spitter Bio-Artillery) HOLDs, 20" from a five-model unit with a unit of the beast's own side between them, `SEEDS` seeds, on the table
## (AI body) and on the core door (live capture + step driver, as `RosterSweep.volley`), dice by parity_compare.py, end states here.
## RED at epoch 84 (table rolls 2 dice sets, the core none), GREEN from 85; controls: clear sight is equal at both epochs, and a target
## standing in cover (the soak's other symptom: "cover differs") has the same save in both halves.
## Real: the main scene, NmlCore, the importer's unit builder, the table's AI body. Constructed: the units.
## PLAN_FIRST_DELETION 34 FT-C2: the table arm left before step 31 (the AI table resolver retires); door values are pinned as literals read on main af5c83610.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const RosterSweep := preload("res://test/one_core/roster_sweep.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")
const Harness := preload("res://test/one_core/golden_witness_harness.gd")
const SEEDS := 16
const DICE := "user://indirect_door_dice"

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _epoch_before: int


func before_test() -> void:
	_epoch_before = AiActRecorder.rules_epoch
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch_before
	RosterSweep.disarm(_main)
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _weapon(wname: String, range_in: int, attacks: int, rules: Array) -> OPRApiClient.OPRWeapon:
	var w := OPRApiClient.OPRWeapon.new()
	w.name = wname
	w.range_value = range_in
	w.attacks = attacks
	w.count = 1
	w.special_rules.assign(rules)
	return w


func _entry(uname: String, size: int, weapons: Array) -> Dictionary:
	var ou := OPRApiClient.OPRUnit.new()
	ou.name = uname
	ou.size = size
	ou.quality = 4
	ou.defense = 4
	ou.game_system = "gf"
	for w in weapons:
		ou.weapons.append(w)
	return {"unit": ou, "faction": "alien_hives", "system": "gf"}


## One HOLD activation of the beast at the target on one path; `core` = capture + step driver with the AI door's transcript.
func _volley(core: bool, seed_n: int, gun_rules: Array, hidden: bool, cover: bool) -> Dictionary:
	var beast := _entry("Artillery Beast", 1, [_weapon("Stomp", 0, 5, ["AP(2)"]), _weapon("Spitter", 36, 6, gun_rules)])
	var att := RosterSweep.spawn(_main, beast, RosterSweep.SEAT_SHOOTER, 0.0)
	var tgt := RosterSweep.spawn(_main, _entry("Pathfinders", 5, []), RosterSweep.SEAT_TARGET, 20.0)
	var wall: GameUnit = RosterSweep.spawn(_main, _entry("Screen", 5, []), RosterSweep.SEAT_SHOOTER, 13.0) if hidden else null
	var painted: Dictionary = Harness._paint_cover(_main, tgt) if cover else {}
	_main.seed_tray_rng(seed_n)
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
	AiDiceRecorder.close()
	var out := {"rolls": ParityTable._read_dice(ProjectSettings.globalize_path(DICE)), "state": RosterSweep.state_of(att, tgt),
		"labels": {"att": [], "tgt": []}, "names": [att.get_name(), tgt.get_name()]}
	Harness._unpaint_cover(_main, painted)
	RosterSweep.free_units(_main, [att, tgt] + ([wall] if wall != null else []))
	await _main.get_tree().process_frame
	return out


## `SEEDS` door volleys at `epoch`: {"fired": volleys where the door rolled, "alive": the target's alive count per seed}.
func _run(epoch: int, gun_rules: Array, hidden: bool, cover: bool) -> Dictionary:
	AiActRecorder.rules_epoch = epoch
	RosterSweep.arm(_main, ProjectSettings.globalize_path(DICE))
	var volleys: Array = []
	for s in SEEDS:
		volleys.append(await _volley(true, s, gun_rules, hidden, cover))
	var fired := volleys.filter(func(v: Dictionary) -> bool: return not (v["rolls"] as Array).is_empty()).size()
	var alive := volleys.map(func(v: Dictionary) -> int: return int((v["state"] as Dictionary)["tgt"]["alive"]))
	print("INDIRECT_DOOR epoch=%d hidden=%s cover=%s gun=%s seeds=%d door_fired=%d" % [epoch, hidden, cover, gun_rules, SEEDS, fired])
	return {"fired": fired, "alive": alive}


const GUN := ["AP(1)", "Blast(3)", "Indirect"]
## At epoch 84 the core fired nothing at the hidden target (the old gap), read on main af5c83610.
# Snapshot pin: read from the rules core on main, not derived from the rulebook (docs/adr/0005-snapshot-pins.md).
const WANT_FIRED_84 := 0
## Per-seed target alive count on the door under cover, read on main af5c83610.
# Snapshot pin: read from the rules core on main, not derived from the rulebook (docs/adr/0005-snapshot-pins.md).
const WANT_ALIVE_COVER_FALSE := [5, 4, 4, 3, 3, 5, 5, 3, 4, 4, 4, 5, 5, 3, 3, 4]
# Snapshot pin: read from the rules core on main, not derived from the rulebook (docs/adr/0005-snapshot-pins.md).
const WANT_ALIVE_COVER_TRUE := [5, 4, 4, 3, 3, 5, 5, 3, 4, 4, 4, 5, 5, 3, 3, 4]


func test_a_holding_indirect_gun_fires_at_a_hidden_target_in_the_core_as_on_the_table() -> void:
	var old := await _run(84, GUN, true, false)
	assert_int(int(old["fired"])).override_failure_message("at epoch 84 the core fired nothing at the hidden target").is_equal(WANT_FIRED_84)
	var now := await _run(85, GUN, true, false)
	assert_int(int(now["fired"])).is_equal(SEEDS)


## The soak's other symptom: a target standing in cover. With the Indirect gun alone (no Blast, which skips cover on its own) the save is the same
## in both halves, hidden or not.
func test_a_covered_target_saves_the_same_in_both_halves() -> void:
	for hidden in [false, true]:
		var now := await _run(85, ["Indirect"], hidden, true)
		assert_int(int(now["fired"])).is_equal(SEEDS)
		var want: Array = WANT_ALIVE_COVER_TRUE if hidden else WANT_ALIVE_COVER_FALSE
		assert_array(now["alive"]).override_failure_message("hidden=%s: the door's target alive count" % hidden).is_equal(want)


## Controls: a plain gun at a hidden target is silent, an Indirect gun with sight fires at both epochs.
func test_controls_hold() -> void:
	for epoch in [84, 85]:
		var silent := await _run(epoch, ["AP(1)", "Blast(3)"], true, false)
		assert_int(int(silent["fired"])).override_failure_message("a plain gun fired at a hidden target").is_equal(0)
		var seen := await _run(epoch, GUN, false, false)
		assert_int(int(seen["fired"])).is_equal(SEEDS)
