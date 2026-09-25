extends GdUnitTestSuite
## E2E — S1-06 (wave-2 audit): a weapon with the printed rule Unstoppable ("Ignores Regeneration, and
## ignores all negative modifiers to this weapon", GF/AoF v3.5.1 p.15) still let the target roll
## Regeneration. AiShooting stamps `profile.unstoppable` from the weapon, but _solo_ignores_regen read
## only Bane / Rending / Lacerate names, registry `bypass_regen` (the plain Unstoppable entry has no
## params) and UNIT-level Unstoppable — never the weapon's own rule. EV (ai_ev.gd:580) and the Rust
## core (dice.rs:1212-1217) both bypass; the table was the odd one out.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254

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


func _carrier(rules: Array) -> GameUnit:
	var u := E2EBoot.make_unit(_main, 1, "Unstoppable Carrier", [Vector3.ZERO])
	u.unit_properties["game_system"] = "gf"
	u.unit_properties["faction_folder"] = "battle_brothers"
	u.unit_properties["special_rules"] = rules
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## A striker with one MELEE weapon of 60 attacks (so wounds land for certain) and the given weapon rules.
func _melee_armed(weapon_rules: Array) -> GameUnit:
	var u := E2EBoot.make_unit(_main, 1, "Brawlers", [Vector3.ZERO])
	(u.models[0] as ModelInstance).model_index = 0
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Runeblade"
	w.range_value = 0
	w.attacks = 60
	w.count = 1
	var rules: Array[String] = []
	for r in weapon_rules:
		rules.append(str(r))
	w.special_rules = rules
	var src := OPRApiClient.OPRUnit.new()
	src.weapons = [w]
	u.source_type = "opr"
	u.source_data = src
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func _regenerating_foe() -> GameUnit:
	var foe := E2EBoot.make_unit(_main, 2, "Trolls", [Vector3(0.5 * INCH, 0, -0.5 * INCH),
		Vector3(0.5 * INCH, 0, 0.5 * INCH)])
	foe.unit_properties["special_rules"] = ["Regeneration"]
	_main.opr_army_manager.game_units[foe.unit_id] = foe
	return foe


## The claim: a weapon carrying the printed rule Unstoppable ignores Regeneration — in melee ...
func test_weapon_unstoppable_melee_wounds_bypass_regeneration() -> void:
	var striker := _carrier([])
	assert_bool(_main._solo_ignores_regen(striker, {"range": 0, "rules": ["Unstoppable"]})) \
		.override_failure_message("S1-06 — a melee weapon with Unstoppable must ignore Regeneration (GF p.15)") \
		.is_true()


## ... and when shooting (the rule is the WEAPON's, not the melee half's).
func test_weapon_unstoppable_ranged_wounds_bypass_regeneration() -> void:
	var striker := _carrier([])
	assert_bool(_main._solo_ignores_regen(striker, {"range": 24, "rules": ["Unstoppable"]})) \
		.override_failure_message("S1-06 — a ranged weapon with Unstoppable must ignore Regeneration (GF p.15)") \
		.is_true()


## CONTROL: a plain weapon on a plain carrier stays Regeneration-able — the fix is not a blanket bypass.
func test_plain_weapon_stays_regenable() -> void:
	var striker := _carrier([])
	assert_bool(_main._solo_ignores_regen(striker, {"range": 0, "rules": ["Reliable"]})).is_false()
	assert_bool(_main._solo_ignores_regen(striker, {"range": 24, "rules": []})).is_false()


## CONTROL (exact name, the Ferocious lesson): the scoped names are their own rules. "Unstoppable in
## Melee" never cuts through Regeneration when shooting, "Unstoppable when Shooting" never in melee —
## the registry's melee_only / shooting_only facet still owns them.
func test_scoped_unstoppable_names_stay_scoped() -> void:
	var striker := _carrier([])
	assert_bool(_main._solo_ignores_regen(striker, {"range": 24, "rules": ["Unstoppable in Melee"]})).is_false()
	assert_bool(_main._solo_ignores_regen(striker, {"range": 0, "rules": ["Unstoppable when Shooting"]})).is_false()


## Behaviour: the wounds of an Unstoppable melee weapon land WITHOUT a Regeneration roll, and the log
## says why (rules-must-log).
func test_unstoppable_melee_strike_skips_the_regeneration_roll() -> void:
	var striker := _melee_armed(["Unstoppable"])
	var foe := _regenerating_foe()
	await _main._solo_melee_strike_phase(striker, foe, false, 0)   # 0 = SoloStrike.ALL
	var text := _log_text()
	assert_str(text) \
		.override_failure_message("S1-06 — the Trolls still rolled Regeneration against an Unstoppable weapon (log: %s)" % text.strip_edges()) \
		.not_contains("regeneration di")
	assert_str(text) \
		.override_failure_message("rules-must-log — the bypass names itself (log: %s)" % text.strip_edges()) \
		.contains("Unstoppable: Regeneration ignored")
	await E2EBoot.settle(get_tree())


## CONTROL: the same strike with a plain weapon does roll Regeneration and never claims the rule.
func test_plain_melee_strike_rolls_regeneration() -> void:
	var striker := _melee_armed([])
	var foe := _regenerating_foe()
	await _main._solo_melee_strike_phase(striker, foe, false, 0)
	var text := _log_text()
	assert_str(text) \
		.override_failure_message("fixture broken: a plain weapon must face the Regeneration roll (log: %s)" % text.strip_edges()) \
		.contains("regeneration di")
	assert_str(text).not_contains("Unstoppable")
	await E2EBoot.settle(get_tree())
