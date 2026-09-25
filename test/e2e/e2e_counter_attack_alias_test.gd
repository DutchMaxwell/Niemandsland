extends GdUnitTestSuite
## E2E — S1-04 (wave-2 audit): "Counter-Attack" (Ratmen, Ogres, Orcs, Saurians ... in AoF; DAO Union,
## Wolf Brothers ... in GF) is the registry's DATA alias of the Counter primitive
## (`strikes_first: true`, GF/AoF v3.5.1 p.13: "Strikes first with this weapon when charged").
## The strike-first gate (_solo_has_counter) already counted the alias, but the profile stamp read
## the exact name "Counter" only — since NML-1112 `has_special_rule("Counter")` is false for
## "Counter-Attack" — so the COUNTER_ONLY phase struck nothing and every weapon swung in the
## normal slot, after the charger. The Rust core stamps the alias (unit.rs:5825-5832).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254
const COUNTER_ONLY := 1   # SoloStrike.COUNTER_ONLY
const NON_COUNTER := 2    # SoloStrike.NON_COUNTER

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main._solo_batch = true


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _log_text() -> String:
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


## A striker with one plain MELEE weapon (range 0, no weapon rules) and the given UNIT-level rules
## in the given book/faction (mirrors _melee_armed in e2e_unstoppable_melee_test.gd).
func _fighter(unit_rules: Array, system: String, faction: String) -> GameUnit:
	var u := E2EBoot.make_unit(_main, 1, "Rat Pack", [Vector3.ZERO])
	(u.models[0] as ModelInstance).model_index = 0
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Rusty Blades"
	w.range_value = 0
	w.attacks = 2
	w.count = 1
	var src := OPRApiClient.OPRUnit.new()
	src.weapons = [w]
	u.source_type = "opr"
	u.source_data = src
	u.unit_properties["game_system"] = system
	u.unit_properties["faction_folder"] = faction
	u.unit_properties["special_rules"] = unit_rules
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func _foe() -> GameUnit:
	var foe := E2EBoot.make_unit(_main, 2, "Grunts", [Vector3(0.5 * INCH, 0, -0.5 * INCH),
		Vector3(0.5 * INCH, 0, 0.5 * INCH)])
	_main.opr_army_manager.game_units[foe.unit_id] = foe
	return foe


## The claim: a Counter-Attack unit's weapons resolve in the strike-FIRST (COUNTER_ONLY) phase.
func test_counter_attack_unit_strikes_in_the_counter_slot() -> void:
	var striker := _fighter(["Counter-Attack"], "aof", "ratmen")
	var foe := _foe()
	await _main._solo_melee_strike_phase(striker, foe, false, COUNTER_ONLY)
	var text := _log_text()
	assert_str(text) \
		.override_failure_message("S1-04 — a Counter-Attack unit struck nothing in the strike-first phase (log: %s)" % text.strip_edges()) \
		.contains("strikes with Rusty Blades")
	await E2EBoot.settle(get_tree())


## The other half: the weapons that struck first must not swing again in the normal strike-back slot.
func test_counter_attack_unit_does_not_strike_twice() -> void:
	var striker := _fighter(["Counter-Attack"], "aof", "ratmen")
	var foe := _foe()
	await _main._solo_melee_strike_phase(striker, foe, false, NON_COUNTER)
	var text := _log_text()
	assert_str(text) \
		.override_failure_message("S1-04 — the Counter-Attack weapons also swung in the normal slot (log: %s)" % text.strip_edges()) \
		.not_contains("strikes with")
	await E2EBoot.settle(get_tree())


## CONTROL: the plain unit-wide "Counter" rule keeps striking first (the shape the old stamp covered).
func test_plain_counter_rule_still_strikes_first() -> void:
	var striker := _fighter(["Counter"], "aof", "ratmen")
	var foe := _foe()
	await _main._solo_melee_strike_phase(striker, foe, false, COUNTER_ONLY)
	assert_str(_log_text()).contains("strikes with Rusty Blades")
	await E2EBoot.settle(get_tree())


## CONTROL: a unit with no Counter of any name strikes nothing in the strike-first phase.
func test_unit_without_counter_does_not_strike_first() -> void:
	var striker := _fighter(["Fearless"], "aof", "ratmen")
	var foe := _foe()
	await _main._solo_melee_strike_phase(striker, foe, false, COUNTER_ONLY)
	assert_str(_log_text()).not_contains("strikes with")
	await E2EBoot.settle(get_tree())


## CONTROL: the same unit strikes in the normal slot when the phase is ALL/NON_COUNTER — no Counter, no split.
func test_unit_without_counter_strikes_in_the_normal_slot() -> void:
	var striker := _fighter(["Fearless"], "aof", "ratmen")
	var foe := _foe()
	await _main._solo_melee_strike_phase(striker, foe, false, NON_COUNTER)
	assert_str(_log_text()).contains("strikes with Rusty Blades")
	await E2EBoot.settle(get_tree())
