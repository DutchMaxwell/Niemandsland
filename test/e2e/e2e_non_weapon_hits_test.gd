extends GdUnitTestSuite
## E2E — hits that come from no weapon (Impact, Trap, Breath Attack, Retaliate, Deathstrike, Self-Destruct)
## are built as synthetic profiles and saved through _solo_resolve_saves. A UNIT-level rule of the unit that
## causes the hit (conditional AP, the Bane save re-roll, the Regeneration bypass, the attackers-side
## Piercing Mark grant) belongs to that unit's WEAPONS, so none of it may reach these hits. The Rust core
## already behaves this way. Fixed AP that belongs to the hit itself (Breath Attack's own AP, Heavy Impact)
## stays. Both seats are AI so every save auto-rolls.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254
const ALL := 0   # SoloStrike.ALL

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _epoch0: int


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {1: true, 2: true}
	_main._ensure_solo_controller()
	_main.solo_controller.human_slot = 1
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main._solo_batch = true


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0   # statics leak across gdUnit tests
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


# ------------------------------------------------------------------------------------------ helpers

func _unit(pid: int, uname: String, pos: Array, system: String, faction: String, unit_rules: Array,
		attacks: int = 4, wounds: int = 9, defense: int = 4) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, uname, pos)
	var i := 0
	for m in u.models:
		(m as ModelInstance).model_index = i
		(m as ModelInstance).wounds_max = wounds
		(m as ModelInstance).wounds_current = wounds
		i += 1
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Probe Blade"
	w.range_value = 0
	w.attacks = attacks
	w.count = 1
	var src := OPRApiClient.OPRUnit.new()
	src.weapons = [w]
	u.source_type = "opr"
	u.source_data = src
	u.unit_properties["game_system"] = system
	u.unit_properties["faction_folder"] = faction
	u.unit_properties["special_rules"] = unit_rules
	u.unit_properties["defense"] = defense
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func _lines(needle: String) -> Array:
	var out: Array = []
	for e in _main.battle_log.entries():
		var t := str((e as Dictionary)["text"])
		if t.contains(needle):
			out.append(t)
	return out


func _log_text() -> String:
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


## Tough models, so a big Impact pool never wipes the foe before every pool has rolled.
func _tough_foe(uname: String = "Anvils") -> GameUnit:
	return _unit(2, uname, [Vector3(0.5 * INCH, 0, -0.5 * INCH), Vector3(0.5 * INCH, 0, 0.5 * INCH)],
		"gf", "orc_marauders", ["Tough(30)"], 4, 30)


func _pierce_mark(on_unit: GameUnit) -> void:
	_main._solo_record_spell_mod(on_unit, "Piercing Fighting Mark", {"grants_rule": "AP(+1) in melee",
		"beneficiary": "attackers", "duration": "once", "scope": "melee", "no_live_grant": true})


# ------------------------------------------------------------------ (a) conditional AP, one per site

## CONTROL: the rule is live in this fixture — on a real weapon strike a unit-level melee AP rule reaches the save.
func test_control_unit_melee_ap_reaches_a_real_weapon_strike(timeout := 90000) -> void:
	var striker := _unit(1, "Hitters", [Vector3.ZERO], "gf", "alien_hives", ["Piercing Fighter"], 24)
	var foe := _unit(2, "Anvils", [Vector3(0.5 * INCH, 0, -0.5 * INCH), Vector3(0.5 * INCH, 0, 0.5 * INCH)],
		"gf", "orc_marauders", [], 4)
	_main.seed_tray_rng(7)
	await _main._solo_melee_strike_phase(striker, foe, true, ALL)
	assert_array(_lines(" saves on ")).is_equal(["Anvils saves on 5+ (Def 4+, AP 1)"])
	assert_str(_log_text()).contains("Piercing Fighter: AP(+1) against Anvils")
	await E2EBoot.settle(get_tree())


func test_trap_hits_get_no_unit_melee_ap_from_the_seized_unit(timeout := 90000) -> void:
	var victim := _unit(2, "Victim", [Vector3.ZERO, Vector3(0.7 * INCH, 0, 0)], "gf", "alien_hives", ["Piercing Fighter"])
	_main.seed_tray_rng(7)
	await _main._solo_secret_trap_hits(victim)
	assert_array(_lines(" saves on ")).is_equal(["Victim saves on 4+"])
	assert_str(_log_text()).not_contains("Piercing Fighter: AP(")
	await E2EBoot.settle(get_tree())


func _breath(rules: Array, system: String, faction: String) -> void:
	var bearer := _unit(2, "Dragon", [Vector3.ZERO], system, faction, ["Breath Attack"] + rules)
	_unit(1, "Victims", [Vector3(3 * INCH, 0, 0), Vector3(3 * INCH, 0, 0.7 * INCH), Vector3(3 * INCH, 0, -0.7 * INCH)],
		"gf", "orc_marauders", ["Tough(9)"])
	for s in range(1, 25):   # the trigger die has to succeed once
		_main.seed_tray_rng(s)
		await _main._solo_apply_breath_attack(bearer)
		if _log_text().contains("breathes on"):
			return


## The shooting-scoped unit rule (Piercing Shooter) of the breathing bearer must not add to the breath's own AP 1.
func test_breath_gets_no_unit_shooting_ap_from_the_bearer(timeout := 90000) -> void:
	await _breath(["Piercing Shooter"], "gf", "alien_hives")
	assert_str(_log_text()).contains("breathes on")
	assert_array(_lines(" saves on ")).is_equal(["Victims saves on 5+ (Def 4+, AP 1)"])
	assert_str(_log_text()).not_contains("Piercing Shooter: AP(")
	await E2EBoot.settle(get_tree())


## Slayer (a hold-or-charge AP rule, shooting leg) in a book that carries it together with Breath Attack.
func test_breath_gets_no_slayer_ap_from_the_bearer(timeout := 90000) -> void:
	await _breath(["Slayer"], "aof", "kingdom_of_angels")
	assert_str(_log_text()).contains("breathes on")
	assert_array(_lines(" saves on ")).is_equal(["Victims saves on 5+ (Def 4+, AP 1)"])
	assert_str(_log_text()).not_contains("Slayer: AP(")
	await E2EBoot.settle(get_tree())


func test_retaliate_hits_get_no_unit_melee_ap_from_the_retaliating_unit(timeout := 90000) -> void:
	var striker := _unit(1, "Hitters", [Vector3.ZERO], "gf", "orc_marauders", [], 30)
	var lasher := _unit(2, "Lashers", [Vector3(0.5 * INCH, 0, -0.5 * INCH), Vector3(0.5 * INCH, 0, 0.5 * INCH)],
		"gf", "blood_prime_brothers", ["Retaliate(2)", "Piercing Fighter"], 4, 9, 6)
	_main.seed_tray_rng(7)
	await _main._solo_melee_strike_phase(striker, lasher, false, ALL)
	assert_str(_log_text()).contains("Retaliate: Lashers lashes back")
	assert_array(_lines("Hitters saves on ")).is_equal(["Hitters saves on 4+"])
	assert_str(_log_text()).not_contains("Piercing Fighter: AP(")
	await E2EBoot.settle(get_tree())


func test_deathstrike_hits_get_no_unit_melee_ap_from_the_dying_unit(timeout := 90000) -> void:
	var striker := _unit(1, "Hitters", [Vector3.ZERO], "gf", "orc_marauders", [], 30)
	var dying := _unit(2, "Martyrs", [Vector3(0.5 * INCH, 0, -0.5 * INCH), Vector3(0.5 * INCH, 0, 0.5 * INCH)],
		"gf", "infected_colonies", ["Deathstrike(2)", "Piercing Fighter"], 4, 1, 6)
	_main.seed_tray_rng(7)
	await _main._solo_melee_strike_phase(striker, dying, false, ALL)
	assert_str(_log_text()).contains("dying models lash out")
	assert_array(_lines("Hitters saves on ")).is_equal(["Hitters saves on 4+"])
	assert_str(_log_text()).not_contains("Piercing Fighter: AP(")
	await E2EBoot.settle(get_tree())


func test_self_destruct_hits_get_no_unit_melee_ap_from_the_detonating_unit(timeout := 90000) -> void:
	var bomb := _unit(2, "Bombers", [Vector3.ZERO, Vector3(0.7 * INCH, 0, 0)], "gf", "alien_hives",
		["Self-Destruct(2)", "Piercing Fighter"])
	var enemy := _unit(1, "Enemies", [Vector3(0.5 * INCH, 0, 0.5 * INCH)], "gf", "orc_marauders", [])
	await _main._solo_self_destruct_post_melee(bomb, enemy)
	assert_str(_log_text()).contains("detonates after the melee")
	assert_array(_lines("Enemies saves on ")).is_equal(["Enemies saves on 4+"])
	assert_str(_log_text()).not_contains("Piercing Fighter: AP(")
	await E2EBoot.settle(get_tree())


# --------------------------------------------------------------------- (b) the Bane save re-roll (Impact)

## CONTROL: the same unit-level Bane on a real weapon strike makes the defender re-roll its Defense 6s.
func test_control_unit_bane_rerolls_the_saves_of_a_real_weapon_strike(timeout := 90000) -> void:
	var striker := _unit(1, "Hitters", [Vector3.ZERO], "gf", "orc_marauders", ["Bane"], 60)
	var foe := _tough_foe()
	_main.seed_tray_rng(7)
	await _main._solo_melee_strike_phase(striker, foe, true, ALL)
	assert_str(_log_text()).contains("re-rolls")
	await E2EBoot.settle(get_tree())


func test_impact_hits_give_the_defender_no_bane_reroll_from_the_charger(timeout := 90000) -> void:
	var charger := _unit(1, "Rammers", [Vector3.ZERO], "gf", "orc_marauders", ["Bane", "Impact(30)"], 2)
	_main.seed_tray_rng(7)
	await _main._solo_charge_impact(charger, _tough_foe(), false)
	assert_str(_log_text()).contains("Impact(30) rolls 30 dice")
	assert_array(_lines(" saves on ")).is_equal(["Anvils saves on 4+"])
	assert_str(_log_text()).not_contains("re-rolls")
	await E2EBoot.settle(get_tree())


# ----------------------------------------------------------- (c) the Regeneration bypass (Impact)

## CONTROL: a unit-level Unstoppable cuts through Regeneration for a real weapon profile, not for a marked hit.
func test_the_regeneration_bypass_is_read_for_a_weapon_profile_and_skipped_for_a_marked_hit(timeout := 90000) -> void:
	var charger := _unit(1, "Rammers", [Vector3.ZERO], "gf", "orc_marauders", ["Unstoppable"], 2)
	var foe := _unit(2, "Anvils", [Vector3(0.5 * INCH, 0, 0)], "gf", "orc_marauders", ["Regeneration"])
	var weapon: Dictionary = {"name": "Blade", "ap": 0, "deadly": 0, "rules": []}
	var hit: Dictionary = {"name": "Impact", "ap": 0, "deadly": 0, "rules": [], "_impact_pool": true}
	assert_bool(_main._solo_ignores_regen(charger, weapon, foe)).is_true()
	assert_bool(_main._solo_ignores_regen(charger, hit, foe)).is_false()
	await E2EBoot.settle(get_tree())


## The same read through the real Impact path: the wounds Impact causes meet the defender's Regeneration.
func test_impact_wounds_are_not_regeneration_proof_from_the_chargers_unit_rule(timeout := 90000) -> void:
	var charger := _unit(1, "Rammers", [Vector3.ZERO], "gf", "orc_marauders", ["Unstoppable", "Impact(30)"], 2)
	var foe := _unit(2, "Anvils", [Vector3(0.5 * INCH, 0, -0.5 * INCH), Vector3(0.5 * INCH, 0, 0.5 * INCH)],
		"gf", "orc_marauders", ["Tough(30)", "Regeneration"], 4, 30)
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	_main.seed_tray_rng(7)
	_main._solo_regen_ignored = 0
	await _main._solo_charge_impact(charger, foe, false)
	assert_str(_log_text()).contains("Impact(30) rolls 30 dice")
	assert_int(_main._solo_regen_ignored).is_greater(0)
	await E2EBoot.settle(get_tree())


# ------------------------------------------------------------ (d) the attackers-side Piercing Mark grant

## CONTROL: the Mark's once-record on the defender folds AP(+1) into a real weapon profile's save.
func test_control_the_piercing_mark_reaches_a_weapon_profile(timeout := 90000) -> void:
	var friend := _unit(1, "Hunters", [Vector3(2.0 * INCH, 0, 0)], "gf", "orc_marauders", [])
	var foe := _unit(2, "Anvils", [Vector3.ZERO], "gf", "orc_marauders", [])
	_pierce_mark(foe)
	await _main._solo_resolve_saves(friend, foe, "Blade", [], 4, 4,
		{"name": "Blade", "ap": 0, "deadly": 0, "rules": []}, false, true)
	assert_str(_log_text()).contains("Piercing Mark: friendly attackers get AP(+1) against Anvils (once)")
	await E2EBoot.settle(get_tree())


func test_self_destruct_hits_get_no_piercing_mark_grant(timeout := 90000) -> void:
	var bomb := _unit(2, "Bombers", [Vector3.ZERO, Vector3(0.7 * INCH, 0, 0)], "gf", "alien_hives", ["Self-Destruct(2)"])
	var enemy := _unit(1, "Enemies", [Vector3(0.5 * INCH, 0, 0.5 * INCH)], "gf", "orc_marauders", [])
	_pierce_mark(enemy)
	await _main._solo_self_destruct_post_melee(bomb, enemy)
	assert_str(_log_text()).contains("detonates after the melee")
	assert_array(_lines("Enemies saves on ")).is_equal(["Enemies saves on 4+"])
	assert_str(_log_text()).not_contains("Piercing Mark")
	await E2EBoot.settle(get_tree())


func test_impact_hits_get_no_piercing_mark_grant(timeout := 90000) -> void:
	var charger := _unit(1, "Rammers", [Vector3.ZERO], "gf", "orc_marauders", ["Impact(30)"], 2)
	var foe := _tough_foe()
	_pierce_mark(foe)
	_main.seed_tray_rng(7)
	await _main._solo_charge_impact(charger, foe, false)
	assert_str(_log_text()).contains("Impact(30) rolls 30 dice")
	assert_array(_lines(" saves on ")).is_equal(["Anvils saves on 4+"])
	assert_str(_log_text()).not_contains("Piercing Mark")
	await E2EBoot.settle(get_tree())
