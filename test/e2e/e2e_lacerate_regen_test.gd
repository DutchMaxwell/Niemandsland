extends GdUnitTestSuite
## E2E — play test 29.10.2026 (audit A1): Lacerate wounds never rolled the target's Self-Repair.
##
## The army-book Lacerate (every GF/AoF book that fields it, version 3.5.3) only makes the target re-roll
## unmodified Defense 6s. Bane (GF/AoF Advanced Rules v3.5.1 p.13) has the same re-roll AND ignores
## Regeneration; Rending (p.14) ignores Regeneration for ALL of its hits, not only the 6s that get AP(+4).
## The table treated Lacerate as Bane on both damage paths (weapons via `_solo_ignores_regen`, spells via
## the `ignores_regen` facet), so a Lacerate volley skipped the Regeneration-family roll — silently.
## These suites ride the real volley / spell resolution on scenes/main.tscn.

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


## The attacker. A gf faction whose mechanics map files "Lacerate" (with the regen-bypass param the
## table must NOT honour for this name), so the registry leg of `_solo_ignores_regen` is exercised too.
func _attacker() -> GameUnit:
	var u := E2EBoot.make_unit(_main, 1, "Laced Raiders", [Vector3.ZERO])
	u.unit_properties["game_system"] = "gf"
	u.unit_properties["faction_folder"] = "infected_colonies"
	u.unit_properties["special_rules"] = []
	var opr := OPRApiClient.OPRUnit.new()
	var ws: Array[OPRApiClient.OPRWeapon] = []
	opr.weapons = ws
	u.source_type = "opr"
	u.source_data = opr
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## The AI-owned target (its saves and its Self-Repair roll auto-roll): every model carries Self-Repair.
func _self_repair_foe() -> GameUnit:
	var positions: Array = []
	for i in range(5):
		positions.append(Vector3(6.0 * INCH, 0, 0.02 * i))
	var foe := E2EBoot.make_unit(_main, 2, "Clockwork Squad", positions)
	foe.unit_properties["special_rules"] = ["Self-Repair"]
	_main.opr_army_manager.game_units[foe.unit_id] = foe
	return foe


func _gun(rules: Array, attacks: int = 60, reach: int = 24) -> OPRApiClient.OPRWeapon:
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Test Gun" if reach > 0 else "Test Blade"
	w.range_value = reach
	w.attacks = attacks
	w.count = 1
	var rs: Array[String] = []
	for r in rules:
		rs.append(str(r))
	w.special_rules = rs
	return w


func _volley(rules: Array, attacks: int = 60) -> String:
	var attacker := _attacker()
	var foe := _self_repair_foe()
	var profiles := AiShooting.profiles_in_range([_gun(rules, attacks)], 0.0)
	assert_int(profiles.size()).is_equal(1)
	var shots := [{"member": attacker, "quality": attacker.get_quality(),
		"alive": attacker.get_alive_count(), "max": attacker.models.size(),
		"reach": 24, "profile": profiles[0]}]
	_main.seed_tray_rng(7)
	await _main._solo_resolve_ai_volley(attacker, foe, shots)
	var text := _log_text()
	await E2EBoot.settle(get_tree())
	return text


func _spell(weapon_rules: Array) -> String:
	var caster := _attacker()
	var foe := _self_repair_foe()
	var entry := {"effect": {"kind": "damage", "hits": 12, "weapon_rules": weapon_rules},
		"target": {"kind": "unit", "side": "enemy"}}
	_main.seed_tray_rng(7)
	await _main._solo_resolve_spell_damage(caster, caster, "Test Bolt", entry, foe)
	var text := _log_text()
	await E2EBoot.settle(get_tree())
	return text


# ===== the decision =====

## The claim: a weapon's Lacerate does not ignore Regeneration — shooting or melee, even with the
## profile's `bane` flag (AiShooting folds Lacerate into it for the re-roll) and the registry entry.
func test_lacerate_weapon_does_not_ignore_regeneration() -> void:
	var attacker := _attacker()
	var shoot := AiShooting.profiles_in_range([_gun(["Lacerate"])], 0.0)
	var melee := AiShooting.melee_profiles([_gun(["Lacerate"], 3, 0)])
	assert_int(melee.size()).is_equal(1)
	assert_bool(_main._solo_ignores_regen(attacker, shoot[0])) \
		.override_failure_message("A1 — a shooting Lacerate weapon must leave Regeneration in place") \
		.is_false()
	assert_bool(_main._solo_ignores_regen(attacker, melee[0])) \
		.override_failure_message("A1 — a melee Lacerate weapon must leave Regeneration in place") \
		.is_false()


## CONTROL: Lacerate keeps its own half — the target still re-rolls unmodified Defense 6s.
func test_lacerate_keeps_the_defense_six_reroll() -> void:
	var attacker := _attacker()
	var shoot := AiShooting.profiles_in_range([_gun(["Lacerate"])], 0.0)
	assert_bool(_main._solo_striker_has_bane(attacker, shoot[0], false)).is_true()


## CONTROL: Bane and Rending still ignore Regeneration (p.13 / p.14).
func test_bane_and_rending_weapons_still_ignore_regeneration() -> void:
	var attacker := _attacker()
	assert_bool(_main._solo_ignores_regen(attacker, AiShooting.profiles_in_range([_gun(["Bane"])], 0.0)[0])).is_true()
	assert_bool(_main._solo_ignores_regen(attacker, AiShooting.profiles_in_range([_gun(["Rending"])], 0.0)[0])).is_true()


# ===== the volley =====

## The claim on the dice: a Lacerate volley's wounds face the Self-Repair roll, and the re-roll line
## names Lacerate, not Bane.
func test_lacerate_volley_rolls_self_repair() -> void:
	var text: String = await _volley(["AP(4)", "Lacerate"])
	assert_str(text) \
		.override_failure_message("A1 — the Lacerate wounds skipped Self-Repair (log: %s)" % text.strip_edges()) \
		.contains("self-repair di")
	assert_str(text) \
		.override_failure_message("A1 — the re-roll must name the rule that caused it (log: %s)" % text.strip_edges()) \
		.contains("Lacerate: Clockwork Squad re-rolls")
	assert_str(text).not_contains("ignore Regeneration")


## Bane's wounds skip Self-Repair, and the log says so (rules-must-log: the skip is never silent).
func test_bane_volley_skips_self_repair_and_says_so() -> void:
	var text: String = await _volley(["AP(4)", "Bane"])
	assert_str(text).not_contains("self-repair di")
	assert_str(text) \
		.override_failure_message("A1 — the skipped Self-Repair roll must be logged (log: %s)" % text.strip_edges()) \
		.contains("ignore Regeneration — no self-repair roll")


## Rending (p.14) ignores Regeneration on EVERY hit — not only the unmodified 6s that get AP(+4). No AP
## here, so most wounds come from non-6 hits; a 6s-only bypass would roll Self-Repair for them.
func test_rending_volley_skips_self_repair_on_every_hit() -> void:
	var text: String = await _volley(["Rending"])
	assert_str(text).contains("Rending:")
	assert_str(text).not_contains("self-repair di")
	assert_str(text) \
		.override_failure_message("A1 — the skipped Self-Repair roll must be logged (log: %s)" % text.strip_edges()) \
		.contains("ignore Regeneration — no self-repair roll")


## CONTROL (the check can fail): a plain volley rolls Self-Repair and claims no skip.
func test_plain_volley_rolls_self_repair() -> void:
	var text: String = await _volley(["AP(4)"])
	assert_str(text).contains("self-repair di")
	assert_str(text).not_contains("ignore Regeneration")


# ===== the spell =====

## The claim on the spell path: a damage spell with Lacerate still meets the Self-Repair roll.
func test_lacerate_spell_rolls_self_repair() -> void:
	var text: String = await _spell(["AP(4)", "Lacerate"])
	assert_str(text) \
		.override_failure_message("A1 — the Lacerate spell wounds skipped Self-Repair (log: %s)" % text.strip_edges()) \
		.contains("self-repair di")
	assert_str(text).not_contains("ignore Regeneration")


## A Bane spell skips Self-Repair and says so.
func test_bane_spell_skips_self_repair_and_says_so() -> void:
	var text: String = await _spell(["AP(4)", "Bane"])
	assert_str(text).not_contains("self-repair di")
	assert_str(text) \
		.override_failure_message("A1 — the skipped Self-Repair roll must be logged (log: %s)" % text.strip_edges()) \
		.contains("ignore Regeneration — no self-repair roll")
