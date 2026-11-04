extends GdUnitTestSuite
## E2E — S1-05 (wave-2 audit): a spell debuff whose grant is for "friendly units attacking it"
## (`beneficiary: "attackers"`, e.g. Head Bang / Magic Fists -> Rending, Bad Omen -> Furious,
## Calculated Foresight -> Relentless) handed the rule to the ENEMY it was cast on:
##   1. _solo_record_spell_mod -> _solo_apply_grant stamped "<rule> (spell)" onto the target's own
##      special_rules, so the target attacked with the rule (bridge, Furious stamp, Regeneration bypass);
##   2. the target's own attack then spent the once-record (mods_for "grant" never split the
##      beneficiary), so the friendly attackers never got it — the cast was wasted.
## The Rust core keeps the roles apart (mods.rs:104-105: Grant = !attackers, GrantVs = attackers).
## The attackers get the rule TARGET-AWARE through the bridge (attacker_grants_from_target).

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
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _unit(pid: int, unit_name: String, pos: Vector3) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, [pos])
	u.unit_properties["special_rules"] = []
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func _records_on(u: GameUnit) -> Array:
	return _main._solo_spell_mods.get(u.get_instance_id(), [])


func _log_text() -> String:
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


## The exporter's shape of the debuff: cast on the ENEMY, the rule is for whoever attacks it, once.
func _debuff_rending_on(target: GameUnit) -> void:
	_main._solo_record_spell_mod(target, "Head Bang", {"grants_rule": "Rending",
		"beneficiary": "attackers", "duration": "once", "scope": ""})


# ===== (1) the overlay must not land on the debuffed enemy ======================

func test_an_attackers_side_grant_does_not_land_on_its_target() -> void:
	var foe := _unit(2, "Grunts", Vector3.ZERO)
	_debuff_rending_on(foe)
	assert_array(_records_on(foe)) \
		.override_failure_message("fixture: the record itself must be stored on the target") \
		.has_size(1)
	assert_bool(foe.has_special_rule("Rending")) \
		.override_failure_message("S1-05 — the debuffed enemy carries the attackers' Rending itself: %s" % str(foe.get_special_rules())) \
		.is_false()


func test_the_debuffed_enemys_own_attack_gets_no_flag_from_it() -> void:
	var foe := _unit(2, "Grunts", Vector3.ZERO)
	var friend := _unit(1, "Hunters", Vector3(2.0 * INCH, 0, 0))
	_debuff_rending_on(foe)
	var own_attack: Dictionary = _main._solo_bridge_granted_flags(foe, {"range": 0, "rules": []}, friend)
	assert_bool(bool(own_attack.get("rending", false))) \
		.override_failure_message("S1-05 — the debuffed enemy's own attack got Rending (profile: %s)" % str(own_attack)) \
		.is_false()


## CONTROL (the actual purpose of the spell): whoever attacks the target DOES get the rule, via the bridge.
func test_the_friendly_attacker_still_gets_the_rule_against_the_target() -> void:
	var foe := _unit(2, "Grunts", Vector3.ZERO)
	var friend := _unit(1, "Hunters", Vector3(2.0 * INCH, 0, 0))
	_debuff_rending_on(foe)
	var attack: Dictionary = _main._solo_bridge_granted_flags(friend, {"range": 0, "rules": []}, foe)
	assert_bool(bool(attack.get("rending", false))) \
		.override_failure_message("the attackers-side grant must reach the friendly attacker (profile: %s)" % str(attack)) \
		.is_true()


## CONTROL: an own-store buff (`beneficiary` empty) still lands on its holder — only the attackers-side
## records stay off the overlay.
func test_an_own_store_grant_still_lands_on_its_holder() -> void:
	var holder := _unit(1, "Hunters", Vector3.ZERO)
	_main._solo_record_spell_mod(holder, "Battle Fury", {"grants_rule": "Rending",
		"beneficiary": "", "duration": "once", "scope": ""})
	assert_bool(holder.has_special_rule("Rending")) \
		.override_failure_message("a friendly utility buff must keep its live overlay: %s" % str(holder.get_special_rules())) \
		.is_true()


# ===== (2) the target's own attack must not spend the once-record ==============

func test_the_debuffed_enemys_own_attack_does_not_spend_the_record() -> void:
	var foe := _unit(2, "Grunts", Vector3.ZERO)
	var friend := _unit(1, "Hunters", Vector3(2.0 * INCH, 0, 0))
	_debuff_rending_on(foe)
	_main._solo_consume_once_mods(foe, friend, true)   # the ENEMY attacks first (melee)
	assert_array(_records_on(foe)) \
		.override_failure_message("S1-05 — the enemy's own attack spent the record meant for its attackers; log: %s" % _log_text().strip_edges()) \
		.has_size(1)


## CONTROL: when a friendly unit attacks the target the once-record IS spent, and it says so.
func test_a_friendly_attack_on_the_target_spends_the_record() -> void:
	var foe := _unit(2, "Grunts", Vector3.ZERO)
	var friend := _unit(1, "Hunters", Vector3(2.0 * INCH, 0, 0))
	_debuff_rending_on(foe)
	_main._solo_consume_once_mods(friend, foe, true)
	assert_array(_records_on(foe)).is_empty()
	assert_str(_log_text()).contains("\"Head Bang\" on Grunts is consumed (applies once)")


# ===== the two target-aware Mark readers ride the "grant_vs" role ===============

## CONTROL: the Piercing Fighting Mark's once-record on the target still folds AP(+1) into the
## friendly attacker's save step and says so (main.gd _solo_resolve_saves).
func test_the_piercing_mark_grant_still_reaches_the_friendly_attacker() -> void:
	var foe := _unit(2, "Grunts", Vector3.ZERO)
	var friend := _unit(1, "Hunters", Vector3(2.0 * INCH, 0, 0))
	_main._solo_batch = true
	_main._solo_record_spell_mod(foe, "Piercing Fighting Mark", {"grants_rule": "AP(+1) in melee",
		"beneficiary": "attackers", "duration": "once", "scope": "melee", "no_live_grant": true})
	await _main._solo_resolve_saves(friend, foe, "Blade", [], 4, 4,
		{"name": "Blade", "ap": 0, "deadly": 0, "rules": []}, false, true)
	assert_str(_log_text()) \
		.override_failure_message("the Mark's AP(+1) must reach the attacker (log: %s)" % _log_text().strip_edges()) \
		.contains("Piercing Mark: friendly attackers get AP(+1) against Grunts (once)")
	await E2EBoot.settle(get_tree())


## CONTROL: the Indirect Mark's once-record on the target still answers the targeting-time gate.
func test_the_indirect_mark_grant_still_answers_the_targeting_gate() -> void:
	var foe := _unit(2, "Grunts", Vector3.ZERO)
	_main._solo_record_spell_mod(foe, "Indirect Mark", {"grants_rule": "Indirect when Shooting",
		"beneficiary": "attackers", "duration": "once", "scope": "shooting", "no_live_grant": true})
	assert_bool(_main._solo_target_grants_indirect(foe)) \
		.override_failure_message("the Mark's Indirect must still be readable on the target") \
		.is_true()


# ===== (3) the MP peer adopts the record without the overlay ===================

func test_a_peer_adopting_the_record_does_not_stamp_the_target() -> void:
	var foe := _unit(2, "Grunts", Vector3.ZERO)
	_main._on_remote_spell_mods_updated(foe, [{"spell": "Head Bang", "hit_mod": 0, "def_mod": 0,
		"casting_mod": 0, "morale_mod": 0, "range_in": 0, "advance_in": 0, "rush_in": 0,
		"grants_rule": "Rending", "scope": "", "beneficiary": "attackers", "duration": "once"}])
	assert_array(_records_on(foe)).has_size(1)
	assert_bool(foe.has_special_rule("Rending")) \
		.override_failure_message("S1-05 (MP) — the peer stamped the attackers' Rending onto the target: %s" % str(foe.get_special_rules())) \
		.is_false()


# ===== G4-T10: a once grant is spent when its effect applies, not by the bearer's own strike ======

func _armed(pid: int, unit_name: String, x: float, attacks: int, quality: int) -> GameUnit:
	var u := _unit(pid, unit_name, Vector3(x * INCH, 0, 0))
	u.unit_properties["quality"] = quality
	var model := u.models[0] as ModelInstance
	model.model_index = 0
	model.wounds_max = 10
	model.wounds_current = 10
	var weapon := OPRApiClient.OPRWeapon.new()
	weapon.name = "Club"
	weapon.range_value = 0
	weapon.attacks = attacks
	var source := OPRApiClient.OPRUnit.new()
	source.weapons = [weapon]
	u.source_type = "opr"
	u.source_data = source
	return u


func _blood_dome_charge(epoch: int) -> String:
	var epoch0: int = AiActRecorder.rules_epoch
	AiActRecorder.rules_epoch = epoch
	_main.solo_ai_slots = {1: true, 2: true}   # both seats AI: the strike-back auto-resolves, no dialog
	_main._ensure_solo_controller()
	_main._solo_batch = true
	var charger := _armed(2, "Pathfinders", 0.0, 2, 4)
	var sisters := _armed(1, "Sisters", 1.0, 12, 3)   # quality 3: hits on 3+, on 4+ against an Evasive unit
	_main._solo_record_spell_mod(charger, "Blood Dome", {"grants_rule": "Evasive",
		"beneficiary": "", "duration": "once", "scope": ""})
	await _main.begin_activation(charger)
	_main.seed_tray_rng(7)
	await _main._run_ai_melee({"unit": charger, "target": sisters, "charge_from_in": 1.0,
		"dangerous_wounds_taken": 0})
	var text := _log_text()
	await E2EBoot.settle(get_tree())
	AiActRecorder.rules_epoch = epoch0
	return text


func _line_starting(text: String, prefix: String) -> String:
	for line in text.split("\n"):
		if line.strip_edges().begins_with(prefix):
			return line.strip_edges()
	return ""


## The act-27 shape (gf_1000_net_002): Blood Dome gave the CHARGER a once Evasive grant. The grant works when
## the unit is ATTACKED, so the charger's own strike does not spend it: the Sisters (quality 3) hit on 4+ in
## the strike-back, and only THEN is the grant consumed (lead ruling G4-T10, 3.6 once-grants).
func test_a_once_evasive_grant_survives_the_chargers_own_strike_at_epoch_73() -> void:
	var text: String = await _blood_dome_charge(AiActRecorder.EPOCH_73_V36)
	assert_str(_line_starting(text, "AI (Sisters):")).ends_with("(4+)")
	var consumed := "\"Blood Dome\" on Pathfinders is consumed (applies once)"
	assert_int(text.count(consumed)).is_equal(1)
	assert_bool(text.find(consumed) > text.find("AI (Sisters):")) \
		.override_failure_message("the grant was spent before the strike-back it was meant for:\n%s" % text) \
		.is_true()


## Below 73 the old order stands (byte-identical): the charger's strike spends the grant, the strike-back hits on 3+.
func test_a_once_evasive_grant_is_still_spent_by_the_chargers_strike_below_epoch_73() -> void:
	var text: String = await _blood_dome_charge(AiActRecorder.EPOCH_73_V36 - 1)
	assert_str(_line_starting(text, "AI (Sisters):")).ends_with("(3+)")
