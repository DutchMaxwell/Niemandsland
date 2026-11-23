extends GdUnitTestSuite
## C-19 (the Shred twin of surge_contact_door_test.gd): a volley fired at base contact measures an edge gap of 0" or less,
## and `_solo_save_batch` took `charge_from_in > 0.0 or dist_in > 0.0` as its only "this is a shot or a charge" test for
## the Enhanced form of a Shred alias (rules 3.6: Enhanced Warbound / Destroyer / Infected deal the extra wound on an
## unmodified Defense 1 at ANY distance). So the table paid nothing for a contact shot while the core paid +1 wound per
## unmodified 1. The shooting callers now say `shooting`. Fixture shape: surge_contact_door_test.gd (the table body vs the
## production door, deny slice, `SEEDS` seeds, dice by parity_compare.py, end state of shooter and target). RED before the
## fix: the Enhanced contact case differs on the target's wounds on most of the 16 seeds; GREEN after. The controls were
## equal before and stay equal: the base form at contact pays nothing on both sides, the Enhanced form at 12" pays on both.
## PLAN_FIRST_DELETION 34 FT-C2: the table arm left before step 31 (the AI table resolver retires); door values are pinned as literals read on main af5c83610.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const RosterSweep := preload("res://test/one_core/roster_sweep.gd")
const SlicePin := preload("res://test/one_core/slice_pin.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")
const SEEDS := 16
const DICE := "user://shred_contact_dice"
const FACTION := "war_disciples"
const CONTACT_IN := 0.98   # the target's front rank overlaps the shooter's by a hair: an edge gap just under 0 inches (the soak's shape)
const FAR_IN := 14.0

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	SlicePin.dice_only()   # the dice are the subject: the production deny list minus its line refusals (DLINES2)
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.combat_stage.force_for_tests = true   # the stage runs headless: its headline says which group was staged last
	GraphicsSettings.combat_stage_hold_s = 0.0


func after_test() -> void:
	GraphicsSettings.combat_stage_hold_s = 2.5
	SlicePin.release_dice_only()
	RosterSweep.disarm(_main)
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _weapon(wname: String, attacks: int, rng: int, count: int) -> OPRApiClient.OPRWeapon:
	var w := OPRApiClient.OPRWeapon.new()
	w.name = wname
	w.range_value = rng
	w.attacks = attacks
	w.count = count
	return w


func _entry(uname: String, size: int, rules: Array, weapons: Array, defense: int) -> Dictionary:
	var ou := OPRApiClient.OPRUnit.new()
	ou.name = uname
	ou.size = size
	ou.quality = 4
	ou.defense = defense
	ou.game_system = "gf"
	ou.special_rules.assign(rules)
	for w in weapons:
		ou.weapons.append(w)
	return {"unit": ou, "faction": FACTION, "system": "gf"}


## One activation of the shooter at the target on one path. `core` = the production door (a live capture handed to `_run_ai_shooting`).
func _volley(rules: Array, x_in: float, seed_n: int, core: bool) -> Dictionary:
	var att := RosterSweep.spawn(_main, _entry("Shredders", 10, rules, [_weapon("Bolt Rifle", 2, 24, 10)], 4), RosterSweep.SEAT_SHOOTER, 0.0)
	var tgt := RosterSweep.spawn(_main, _entry("Targets", 12, [], [], 4), RosterSweep.SEAT_TARGET, x_in)
	_main.seed_tray_rng(seed_n)
	var runs_before := CoreActivation.ai_runs
	var refusals_before := CoreActivation.ai_refusals
	var log_before: int = _main.battle_log.entries().size()
	CoreActivation.reset_all(_main)
	_main._solo_core_ai_h = CoreActivation.capture(_main) if core else 0
	await _main._run_ai_shooting({"unit": att, "moved": false, "action": AiDecision.Action.HOLD})
	if _main._solo_core_ai_h != 0:
		_main.solo_controller._core_node_ready().release(_main._solo_core_ai_h)
		_main._solo_core_ai_h = 0
	AiDiceRecorder.close()
	var shred_lines := 0   # rules-must-log: the table names the Warbound form on every volley it pays
	for e in (_main.battle_log.entries() as Array).slice(log_before):
		var line := str((e as Dictionary)["text"])
		if line.contains("Warbound: ") and line.contains(" of 1 → +"):   # the pay line, not the profile stamp's
			shred_lines += 1
	var out := {"rolls": ParityTable._read_dice(ProjectSettings.globalize_path(DICE)), "state": RosterSweep.state_of(att, tgt),
		"labels": {"att": [], "tgt": []}, "names": [att.get_name(), tgt.get_name()], "shred_lines": shred_lines,
		"runs": CoreActivation.ai_runs - runs_before, "refusals": CoreActivation.ai_refusals - refusals_before}
	RosterSweep.free_units(_main, [att, tgt])
	await _main.get_tree().process_frame
	return out


func _run(rules: Array, x_in: float) -> Dictionary:
	RosterSweep.arm(_main, ProjectSettings.globalize_path(DICE))
	CoreActivation._env = 1   # the door ON: `arm` set the table half's kill switch
	var core_runs := 0
	var core_refusals := 0
	var door_lines := 0
	for s in SEEDS:
		var core := await _volley(rules, x_in, s, true)
		core_runs += int(core["runs"])
		core_refusals += int(core["refusals"])
		door_lines += int(core["shred_lines"])
	print("SHRED_DOOR seeds=%d core_runs=%d core_refusals=%d door_shred_lines=%d" % [SEEDS, core_runs, core_refusals, door_lines])
	return {"core_runs": core_runs, "core_refusals": core_refusals, "door_lines": door_lines}


## The door's Warbound pay-line total per case, read on main af5c83610 in the door-only run. The compare run's table arm said 10
## and its door arm 9 (the table volley first changes which models the pay hits); the door-only run says 16 at both distances: every
## seed pays the line. The end state stays equal across all three readings.
# Snapshot pin: read from the rules core on main, not derived from the rulebook (docs/adr/0005-snapshot-pins.md).
const WANT_SHRED_CONTACT := 16
# Snapshot pin: read from the rules core on main, not derived from the rulebook (docs/adr/0005-snapshot-pins.md).
const WANT_SHRED_FAR := 16


func _check(r: Dictionary, pays: bool, want_lines: int) -> void:
	assert_int(int(r["core_runs"])).override_failure_message("the core did not take the volley").is_equal(SEEDS)
	assert_int(int(r["core_refusals"])).is_equal(0)
	if pays:
		assert_int(int(r["door_lines"])).override_failure_message("the door never logged Warbound paying").is_equal(want_lines)
	else:
		# Snapshot pin: read from the rules core on main, not derived from the rulebook (docs/adr/0005-snapshot-pins.md).
		assert_int(int(r["door_lines"])).override_failure_message("the base form paid where it must not").is_equal(0)


func test_enhanced_warbound_at_base_contact_pays_on_the_table_as_in_the_core() -> void:
	await _check(await _run(["Warbound", "Enhanced Warbound"], CONTACT_IN), true, WANT_SHRED_CONTACT)


## Control: the base form needs a target over 9 inches, so a contact shot pays nothing - on both sides.
func test_base_warbound_at_base_contact_pays_nothing_on_either_side() -> void:
	await _check(await _run(["Warbound"], CONTACT_IN), false, 0)


## Control: the Enhanced form over 9 inches paid on both sides before the fix.
func test_enhanced_warbound_over_nine_inches_is_equal() -> void:
	await _check(await _run(["Warbound", "Enhanced Warbound"], FAR_IN), true, WANT_SHRED_FAR)
