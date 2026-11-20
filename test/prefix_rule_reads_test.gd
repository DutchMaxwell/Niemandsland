extends GdUnitTestSuite
## NML-1112 exact rule names for WEAPON-level reads of the solo AI (Plan H follow-up of #3156): `begins_with("Relentless")` and friends counted a rule that only LABELS a grant
## (a Mark, an Aura: "Relentless Mark", "Indirect when Shooting Aura", "Counter in Melee Aura") or another rule that starts alike ("Deadly Gaze") as the rule itself. The core reads a
## weapon's rules by exact name (`weapon_has` -> `rule_name_matches`), so the GDScript pricing and the core disagreed for such a bearer; they agree now. No epoch: these reads steer
## the AI's choices (hold-and-shoot, the target overlay, the Impact-reduction count), they roll nothing, and a recorded act carries the choice it made.
## RED: put the `begins_with` reads back -> every "label" row below counts as the rule.


func _weapon(rng: int, rules: Array, count := 1) -> OPRApiClient.OPRWeapon:
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "W%d" % rng
	w.range_value = rng
	w.attacks = 2
	w.count = count
	for r in rules:
		w.special_rules.append(str(r))
	return w


func test_hold_and_shoot_reads_the_exact_names() -> void:
	assert_str(SoloController.hold_and_shoot_rule([_weapon(24, ["Relentless"])], true)).is_equal("Relentless")
	assert_str(SoloController.hold_and_shoot_rule([_weapon(24, ["Indirect"])], true)).is_equal("Indirect")
	assert_str(SoloController.hold_and_shoot_rule([_weapon(24, ["Relentless (spell)"])], true)).override_failure_message("a grant mark is the rule").is_equal("Relentless")
	for label in ["Relentless Mark", "Relentless Aura", "Indirect Mark", "Indirect when Shooting Aura"]:
		assert_str(SoloController.hold_and_shoot_rule([_weapon(24, [label])], true)).override_failure_message("%s only labels a grant" % label).is_empty()
		assert_bool(SoloController._forces_hold_and_shoot([_weapon(24, [label])], true)).override_failure_message("%s forces no hold" % label).is_false()


func test_the_indirect_los_waiver_reads_the_exact_name() -> void:
	assert_bool(SoloController.has_indirect_ranged([_weapon(24, ["Indirect"])])).is_true()
	for label in ["Indirect Mark", "Indirect when Shooting Aura"]:
		assert_bool(SoloController.has_indirect_ranged([_weapon(24, [label])])).override_failure_message("%s waives no line of sight" % label).is_false()


func test_the_solo_sim_hold_and_shoot_reads_the_exact_name() -> void:
	var unit := {"weapons": [{"range_value": 24, "special_rules": ["Relentless"]}]}
	assert_bool(SoloSim._forces_hold_and_shoot(unit, true)).is_true()
	for label in ["Relentless Mark", "Relentless Aura"]:
		var other := {"weapons": [{"range_value": 24, "special_rules": [label]}]}
		assert_bool(SoloSim._forces_hold_and_shoot(other, true)).override_failure_message("%s only labels a grant" % label).is_false()


func test_the_target_overlay_reads_the_exact_names() -> void:
	assert_int(AiTargeting.weapon_overlay(["Takedown"])).is_equal(AiTargeting.Overlay.TAKEDOWN)
	assert_int(AiTargeting.weapon_overlay(["Deadly(3)"])).is_equal(AiTargeting.Overlay.DEADLY)
	assert_int(AiTargeting.weapon_overlay(["AP(2)"])).is_equal(AiTargeting.Overlay.AP)
	assert_int(AiTargeting.weapon_overlay(["Blast(3)"])).is_equal(AiTargeting.Overlay.BLAST)
	for label in ["Takedown Strike", "Takedown when Shooting", "Deadly Gaze", "Deadly Surge"]:
		assert_int(AiTargeting.weapon_overlay([label])).override_failure_message("%s is no overlay weapon rule" % label).is_equal(AiTargeting.Overlay.NONE)


func test_the_counter_model_count_reads_the_exact_weapon_name() -> void:
	RulesRegistry.reset_cache()
	for row in [[["Counter"], 3], [["Counter in Melee Aura"], 0], [["Counter in Melee Buff"], 0]]:
		var gu := GameUnit.new()
		gu.unit_properties = {"player_id": 1, "name": "Squad", "quality": 4, "defense": 4, "special_rules": [], "game_system": "gf", "faction_folder": "battle_brothers"}
		for _i in 3:
			var m := ModelInstance.new()
			m.is_alive = true
			gu.models.append(m)
		var src := OPRApiClient.OPRUnit.new()
		src.weapons.append(_weapon(0, row[0], 3))
		gu.source_type = "opr"
		gu.source_data = src
		assert_int(SoloController.counter_models_of(gu)).override_failure_message("a melee weapon carrying %s" % [row[0]]).is_equal(row[1])
