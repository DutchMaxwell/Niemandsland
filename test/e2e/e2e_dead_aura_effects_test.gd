extends GdUnitTestSuite
## E2E — NML-931: the healed aura families measured against the REAL resolution code in main.gd.
##
## test/dead_aura_families_test.gd proves the granted rules resolve and that the pure stampers move.
## The three effects that live inside main.gd itself — the Shred facet, the Regeneration bypass and
## the to-hit modifier — can only be proven against main.gd, so this suite boots the real scene and
## calls the very functions the dice path calls. Each family is asserted in BOTH halves of the game:
## the half it is printed for, and the half it must stay out of.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _unit(rules: Array, system: String, faction: String) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = "aura_%d" % rules.size()
	u.unit_properties = {"player_id": 2, "name": "Aura", "quality": 4, "defense": 4,
		"special_rules": rules, "game_system": system, "faction_folder": faction}
	var m := ModelInstance.new()
	m.is_alive = true
	u.models.append(m)
	return u


## What the import hands the table for a model carrying "<base> Aura".
func _carrier(base: String, system: String, faction: String) -> GameUnit:
	return _unit([base + " Aura", base], system, faction)


func test_shred_facet_lands_on_the_half_the_rule_is_printed_for() -> void:
	# Family 1. main.gd stamps prof["shred"] from the unit's rules; both stamps used to accept ANY
	# Shred-primitive rule, so the shooting half also shredded in melee and the melee half when shooting.
	var shooter := _carrier("Shred when Shooting", "aof", "change_disciples")
	assert_bool(_main._solo_shred_facet_applies(shooter, 24)) \
		.override_failure_message("granted Shred when Shooting never reaches a shooting profile").is_true()
	assert_bool(_main._solo_shred_facet_applies(shooter, 0)) \
		.override_failure_message("Shred when Shooting leaked into melee").is_false()
	var fighter := _unit(["Shred in Melee"], "aof", "change_disciples")
	assert_bool(_main._solo_shred_facet_applies(fighter, 0)).is_true()
	assert_bool(_main._solo_shred_facet_applies(fighter, 24)) \
		.override_failure_message("Shred in Melee leaked into shooting").is_false()


func test_regeneration_bypass_respects_both_halves() -> void:
	# The borderline family: "Unstoppable when Shooting" is Lacerate + shooting_only. The generic
	# Lacerate consumer only gated melee_only, so the shooting half would have cut through
	# Regeneration in melee as well.
	var shooter := _carrier("Unstoppable when Shooting", "gf", "robot_legions")
	assert_bool(_main._solo_ignores_regen(shooter, {"range": 24, "rules": []})) \
		.override_failure_message("granted Unstoppable when Shooting never bypasses Regeneration").is_true()
	assert_bool(_main._solo_ignores_regen(shooter, {"range": 0, "rules": []})) \
		.override_failure_message("a shooting-only Regeneration bypass leaked into melee").is_false()
	# Family 3's melee sibling, the mirror image, in the book that had lost it.
	var fighter := _carrier("Unstoppable in Melee", "aofs", "duchies_of_vinci")
	assert_bool(_main._solo_ignores_regen(fighter, {"range": 0, "rules": []})) \
		.override_failure_message("granted Unstoppable in Melee never bypasses Regeneration").is_true()
	assert_bool(_main._solo_ignores_regen(fighter, {"range": 24, "rules": []})).is_false()
	# A unit with neither keeps its opponent's Regeneration intact.
	assert_bool(_main._solo_ignores_regen(_unit([], "gf", "robot_legions"), {"range": 24, "rules": []})).is_false()


func test_precision_fighter_aura_adds_its_plus_one_in_melee_and_not_to_every_shot() -> void:
	# Family 4. The Shot Modifier family was scoped exactly the wrong way round: the melee branch
	# demanded `all_attacks`, so a melee_only bonus never reached melee, while the shooting branch
	# applied every Shot Modifier to every shot.
	var u := _carrier("Precision Fighter", "gf", "jackals")
	var foe := _unit([], "gf", "jackals")
	var melee: Dictionary = _main._solo_hit_mod_info(u, foe, 0.0, true)
	var shoot: Dictionary = _main._solo_hit_mod_info(u, foe, 12.0, false)
	assert_int(int(melee.get("mod", 0))) \
		.override_failure_message("Precision Fighter Aura grants no melee bonus (note: %s)" % melee.get("note", "")) \
		.is_equal(1)
	assert_int(int(shoot.get("mod", 0))) \
		.override_failure_message("a melee-only bonus was added to shooting (note: %s)" % shoot.get("note", "")) \
		.is_equal(0)
	assert_str(str(melee.get("note", ""))).contains("Precision Fighter Aura")


func test_precision_shooter_aura_adds_its_plus_one_when_shooting() -> void:
	# Family 5.
	var u := _carrier("Precision Shooter", "gf", "ratmen_clans")
	var foe := _unit([], "gf", "ratmen_clans")
	var shoot: Dictionary = _main._solo_hit_mod_info(u, foe, 12.0, false)
	assert_int(int(shoot.get("mod", 0))) \
		.override_failure_message("Precision Shooter Aura grants no shooting bonus (note: %s)" % shoot.get("note", "")) \
		.is_equal(1)
	assert_int(int((_main._solo_hit_mod_info(u, foe, 0.0, true) as Dictionary).get("mod", 0))) \
		.override_failure_message("a shooting bonus reached melee").is_equal(0)


func test_precision_charge_aura_only_pays_out_on_a_charge() -> void:
	# Family 6. The bonus is printed for charges, so it must fire in the melee that came out of one —
	# and nowhere else. The melee strike phase is the caller that knows.
	var u := _carrier("Precision Charge", "gf", "orc_marauders")
	var foe := _unit([], "gf", "orc_marauders")
	var charged: Dictionary = _main._solo_hit_mod_info(u, foe, 0.0, true, true)
	var stood: Dictionary = _main._solo_hit_mod_info(u, foe, 0.0, true, false)
	var shot: Dictionary = _main._solo_hit_mod_info(u, foe, 12.0, false)
	assert_int(int(charged.get("mod", 0))) \
		.override_failure_message("no bonus on the charge it is printed for (note: %s)" % charged.get("note", "")) \
		.is_equal(1)
	assert_int(int(stood.get("mod", 0))) \
		.override_failure_message("a charge bonus paid out without a charge").is_equal(0)
	assert_int(int(shot.get("mod", 0))) \
		.override_failure_message("a charge bonus was added to every shot").is_equal(0)
