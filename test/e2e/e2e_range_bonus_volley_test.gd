extends GdUnitTestSuite
## E2E — NML-929: a shooting-range BONUS (Royal Legion +4", spell range tokens) must reach the human
## volley's per-weapon gate, not just the legality gate.
##
## The seam is the twin of #231's: `_solo_validate_target` adds SoloController.shooting_range_bonus
## when it judges the target legal, so a boosted shooter may DECLARE a shot beyond its printed range —
## but the per-weapon gate in `_solo_attack_groups` (the profile list `_run_human_shooting` and the
## split-fire ask both roll) measured the PRINTED range only. Declaration allowed, volley silently
## empty: the exact silent-refusal shape the Aircraft fix closed from the other side.
##
## The AI has folded the bonus into each shot's reach since the rule landed (`_run_ai_shooting`:
## `"reach": base_range + range_bonus`, then SoloController.effective_shoot_reach_in). These cases pin
## the human path to that SAME arithmetic — bonus first, target-side shrink second — so the two
## directions can never judge the same shot differently again.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")

const IN2M := 0.0254
## Both fixture units sit on the default base (VolumetricLos.DEFAULT_BASE_RADIUS_M = 0.016 m), and every
## range gate measures base-EDGE to base-edge (B11), so a centre offset carries both radii on top.
const EDGE_SLACK_IN := 2.0 * 0.016 / IN2M

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


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## A player unit whose OPR source carries the given ranged weapons — the shape _solo_all_weapons and
## _solo_attack_groups read. `weapons` entries: {name, range, attacks, count}.
func _armed(pid: int, unit_name: String, positions: Array, weapons: Array) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, positions)
	var i := 0
	for m in u.models:
		(m as ModelInstance).model_index = i
		i += 1
	var ws: Array[OPRApiClient.OPRWeapon] = []
	for wd in weapons:
		var d := wd as Dictionary
		var w := OPRApiClient.OPRWeapon.new()
		w.name = str(d.get("name", "Gun"))
		w.range_value = int(d.get("range", 24))
		w.attacks = int(d.get("attacks", 2))
		w.count = int(d.get("count", 1))
		ws.append(w)
	var src := OPRApiClient.OPRUnit.new()
	src.weapons = ws
	u.source_type = "opr"
	u.source_data = src
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## X offset (metres) that puts a single-model unit at `gap_in` base-edge-to-base-edge from origin.
func _x_for_gap(gap_in: float) -> float:
	return (gap_in + EDGE_SLACK_IN) * IN2M


## The profile names of a human volley against `target` at the measured gap — exactly the list
## _run_human_shooting rolls dice for.
func _volley_weapons(attacker: GameUnit, target: GameUnit) -> Array:
	var dist: float = _main.solo_controller.nearest_melee_gap_in(attacker, target)
	var out: Array = []
	for grp in _main._solo_attack_groups(attacker, dist, false, target):
		for p in (grp as Dictionary).get("profiles", []):
			out.append(str((p as Dictionary).get("name", "")))
	return out


## Attacks the named profile rolls in that same volley (0 when it never fires).
func _volley_attacks(attacker: GameUnit, target: GameUnit, weapon: String) -> int:
	var dist: float = _main.solo_controller.nearest_melee_gap_in(attacker, target)
	for grp in _main._solo_attack_groups(attacker, dist, false, target):
		for p in (grp as Dictionary).get("profiles", []):
			if str((p as Dictionary).get("name", "")) == weapon:
				return int((p as Dictionary).get("attacks", 0))
	return 0


func test_royal_legion_volley_fires_beyond_the_printed_range(timeout := 120000) -> void:
	# 24" rifle + Royal Legion (+4") = 28" of reach; the target sits at 26" — outside the print, inside
	# the bonus. The legality gate ALREADY allows this declaration, so the volley must roll dice too.
	var gunner := _armed(1, "Legionaries", [Vector3.ZERO], [{"name": "Rifle", "range": 24, "attacks": 2}])
	gunner.unit_properties["special_rules"] = ["Royal Legion"]
	var grunts := _armed(2, "Grunts", [Vector3(_x_for_gap(26.0), 0, 0)], [])
	assert_int(SoloController.shooting_range_bonus(gunner)) \
		.override_failure_message("fixture broken: Royal Legion did not resolve to +4\"") \
		.is_equal(4)
	assert_float(_main.solo_controller.nearest_melee_gap_in(gunner, grunts)) \
		.override_failure_message("fixture broken: the shooter is not 26\" from the target") \
		.is_equal_approx(26.0, 0.5)
	assert_str(_main._solo_validate_target(gunner, grunts, false)) \
		.override_failure_message("fixture broken: the bonus should make this a legal declaration") \
		.is_equal("")
	var fired := _volley_weapons(gunner, grunts)
	assert_array(fired) \
		.override_failure_message("NML-929 — the declaration was legal but the volley rolled NOTHING: the +4\" bonus never reached the per-weapon gate (fired: %s)" % str(fired)) \
		.contains(["Rifle"])
	assert_int(_volley_attacks(gunner, grunts, "Rifle")) \
		.override_failure_message("NML-929 — the boosted profile fired with 0 models (the per-model sighting gate still measured the printed range)") \
		.is_greater(0)


func test_without_the_bonus_the_same_shot_is_refused(timeout := 120000) -> void:
	# The counter-probe that makes the case above a RULE and not an always-open gate: the identical
	# geometry without Royal Legion is out of range — refused by the legality gate AND dice-less.
	var gunner := _armed(1, "Riflemen", [Vector3.ZERO], [{"name": "Rifle", "range": 24, "attacks": 2}])
	var grunts := _armed(2, "Grunts", [Vector3(_x_for_gap(26.0), 0, 0)], [])
	assert_int(SoloController.shooting_range_bonus(gunner)) \
		.override_failure_message("fixture broken: a plain unit must carry no range bonus") \
		.is_equal(0)
	assert_str(_main._solo_validate_target(gunner, grunts, false)) \
		.override_failure_message("a plain 24\" rifle must not reach 26\"") \
		.contains("out of range")
	assert_array(_volley_weapons(gunner, grunts)) \
		.override_failure_message("a plain 24\" rifle rolled dice at 26\"") \
		.not_contains(["Rifle"])
	# … and the bonus is not a blanket permit either: beyond 28" the boosted unit is refused too.
	var far := _armed(1, "Legionaries", [Vector3.ZERO], [{"name": "Rifle", "range": 24, "attacks": 2}])
	far.unit_properties["special_rules"] = ["Royal Legion"]
	E2EBoot.place_unit_at(grunts, Vector3(_x_for_gap(32.0), 0, 0))
	assert_str(_main._solo_validate_target(far, grunts, false)) \
		.override_failure_message("Royal Legion (+4\") must not reach 32\" with a 24\" rifle") \
		.contains("out of range")
	assert_array(_volley_weapons(far, grunts)) \
		.override_failure_message("the boosted rifle rolled dice 4\" past its boosted reach") \
		.not_contains(["Rifle"])


func test_spell_range_token_reaches_the_volley_too(timeout := 120000) -> void:
	# NML-006's spell token is the SECOND source behind the one bonus seam — a caster's +6" must open
	# the same gate, otherwise the buff reads as "cast, logged, and then nothing happened".
	var gunner := _armed(1, "Handgunners", [Vector3.ZERO], [{"name": "Handgun", "range": 24, "attacks": 2}])
	var grunts := _armed(2, "Grunts", [Vector3(_x_for_gap(28.0), 0, 0)], [])
	assert_array(_volley_weapons(gunner, grunts)) \
		.override_failure_message("fixture broken: the unbuffed 24\" handgun already reached 28\"") \
		.not_contains(["Handgun"])
	gunner.unit_properties["spell_range_mod"] = 6
	assert_str(_main._solo_validate_target(gunner, grunts, false)) \
		.override_failure_message("fixture broken: +6\" should make 28\" a legal declaration") \
		.is_equal("")
	assert_array(_volley_weapons(gunner, grunts)) \
		.override_failure_message("NML-929 — the spell's +6\" range token never reached the volley's per-weapon gate") \
		.contains(["Handgun"])


func test_per_model_sighting_counts_at_the_boosted_reach(timeout := 120000) -> void:
	# Per-model shooting (GF v3.5.1 p.8) measures at the unit's OWN effective reach: with +4" the rear
	# model 26" away is inside the 28" boost, so the profile fires with BOTH models — full dice. The
	# nearest model is in printed range either way, so ONLY the per-model gate can drop the rear one.
	var gunner := _armed(1, "Legionaries", [Vector3.ZERO, Vector3(-6.0 * IN2M, 0, 0)],
		[{"name": "Rifle", "range": 24, "attacks": 2, "count": 2}])
	var grunts := _armed(2, "Grunts", [Vector3(_x_for_gap(20.0), 0, 0)], [])
	assert_int(_volley_attacks(gunner, grunts, "Rifle")) \
		.override_failure_message("fixture broken: unbuffed, the rear model (26\") is out of a 24\" rifle's reach — expected the front model's share only") \
		.is_equal(2)
	gunner.unit_properties["special_rules"] = ["Royal Legion"]
	assert_int(_volley_attacks(gunner, grunts, "Rifle")) \
		.override_failure_message("NML-929 — with +4\" both models reach (20\"/26\" vs 28\") but the per-model count still measured the printed 24\"") \
		.is_equal(4)


func test_the_bonus_applies_before_the_target_side_shrink(timeout := 120000) -> void:
	# ORDER, symmetrical to the AI volley (`"reach": base_range + range_bonus` → effective_shoot_reach_in):
	# the bonus rides the PRINTED range, and the target's shrink applies to the sum. Ranged Shrouding
	# (-6", floored at 6") is where the two orders disagree: eff(8+4) = 6, but eff(8)+4 would be 10.
	# A 7" gap therefore fires only under the wrong order. The 36" cannon keeps the target legal so the
	# per-weapon gate is what decides — exactly the #231 construction.
	var gunner := _armed(1, "Legionaries", [Vector3.ZERO],
		[{"name": "Cannon", "range": 36, "attacks": 2}, {"name": "Pistol", "range": 8, "attacks": 2}])
	gunner.unit_properties["special_rules"] = ["Royal Legion"]
	var shrouded := _armed(2, "Shrouded", [Vector3(_x_for_gap(7.0), 0, 0)], [])
	shrouded.unit_properties["special_rules"] = ["Ranged Shrouding"]
	assert_float(SoloController.effective_shoot_reach_in(12.0, shrouded)) \
		.override_failure_message("fixture broken: Ranged Shrouding did not resolve on the target") \
		.is_equal_approx(6.0, 0.001)
	assert_str(_main._solo_validate_target(gunner, shrouded, false)) \
		.override_failure_message("fixture broken: the cannon should keep the shrouded target legal") \
		.is_equal("")
	var fired := _volley_weapons(gunner, shrouded)
	assert_array(fired) \
		.override_failure_message("NML-929 — the 8\" pistol fired at 7\": the bonus was added AFTER the Shrouding shrink (eff(8)+4 = 10\"), not before it like the AI's volley (eff(8+4) = 6\") — fired: %s" % str(fired)) \
		.not_contains(["Pistol"])
	assert_array(fired) \
		.override_failure_message("the 36\" cannon (eff(40) = 34\") must still fire (fired: %s)" % str(fired)) \
		.contains(["Cannon"])


func test_battle_log_names_the_weapon_the_bonus_lifts_into_reach(timeout := 120000) -> void:
	# rules-must-log, POSITIVE case: a weapon that fires PAST the range printed on its card reads as a
	# bug just like a silent refusal does. The volley names the bonus, its source and the profile.
	var gunner := _armed(1, "Legionaries", [Vector3.ZERO],
		[{"name": "Cannon", "range": 36, "attacks": 2}, {"name": "Rifle", "range": 24, "attacks": 2}])
	gunner.unit_properties["special_rules"] = ["Royal Legion"]
	var grunts := _armed(2, "Grunts", [Vector3(_x_for_gap(26.0), 0, 0)], [])
	_main._solo_log_range_bonus(gunner, grunts)
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	assert_str(text) \
		.override_failure_message("NML-929 — the volley never named the weapon the +4\" lifted into reach (log: %s)" % text.strip_edges()) \
		.contains("Rifle")
	assert_str(text) \
		.override_failure_message("the line must name the rule that granted the reach (log: %s)" % text.strip_edges()) \
		.contains("Royal Legion")
	# The 36" cannon reaches on its own, so the bonus never "lifted" it — it is not listed.
	assert_str(text.substr(text.find("shooting range"))).not_contains("Cannon")
	# Counter-probe: no bonus, no line — the log never claims a rule that did nothing.
	var plain := _armed(1, "Riflemen", [Vector3.ZERO], [{"name": "Rifle", "range": 24, "attacks": 2}])
	var before: int = _main.battle_log.entries().size()
	_main._solo_log_range_bonus(plain, grunts)
	assert_int(_main.battle_log.entries().size()) \
		.override_failure_message("a unit without a range bonus still logged a bonus line") \
		.is_equal(before)
