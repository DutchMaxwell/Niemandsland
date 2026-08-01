extends GdUnitTestSuite
## E2E — #221 REPRO HARNESS, NOT A FIX: "Strike-back refused: 'no melee weapons in reach' after a
## successful pile-in".
##
## WHERE THE MESSAGE COMES FROM (main.gd, `_solo_melee_strike_phase`):
##     if not struck_any and filter == SoloStrike.ALL and battle_log != null:
##         "%s has no melee weapons in reach — no strikes (GF/AoF v3.5.1 p.9)"
## `struck_any` is only set once some profile survives `int(profile.get("attacks", 0)) <= 0`. The
## wording says "no melee weapons"; the CONDITION is "every melee profile scaled to zero attacks".
## The scaling factor is `SoloController.striking_models_for(member, enemy)` — the count of the
## member's models whose base EDGE is within MELEE_REACH_IN (2") of an enemy base edge. So the
## message really means: NO MODEL OF THIS UNIT IS WITHIN 2". The earlier gate in `_run_ai_melee`
## ("has no melee weapons — cannot strike back") cannot catch it: `_solo_attack_groups` still returns
## a group for a unit that owns a melee weapon, even when every profile is scaled to 0 attacks — so
## the player is offered the strike-back, accepts, and is then told there is nothing in reach.
##
## These cases drive the REAL sequence over scenes/main.tscn (snap_charge → pile_in → casualties →
## _solo_attack_groups) and record the two ways that count reaches 0. NOTHING IS FIXED HERE: the
## invariant assert that SHOULD hold is commented out below (it is red today), because the verdict
## — which of the two is a bug and which is correct OPR — belongs in the issue thread, not in a
## unilateral code change.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")

const IN2M := 0.0254

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


## A unit with one melee weapon (range 0) — the shape _solo_attack_groups reads. `xz` in INCHES.
func _melee_unit(pid: int, unit_name: String, xz: Array, attacks: int = 1) -> GameUnit:
	var positions: Array = []
	for p in xz:
		var v := p as Vector2
		positions.append(Vector3(v.x * IN2M, 0.0, v.y * IN2M))
	var u := E2EBoot.make_unit(_main, pid, unit_name, positions)
	var i := 0
	for m in u.models:
		(m as ModelInstance).model_index = i
		i += 1
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "CCW"
	w.range_value = 0
	w.attacks = attacks
	w.count = positions.size()
	var ws: Array[OPRApiClient.OPRWeapon] = [w]
	var src := OPRApiClient.OPRUnit.new()
	src.weapons = ws
	u.source_type = "opr"
	u.source_data = src
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## Total melee attacks the defender's strike-back rolls — 0 is exactly the #221 refusal.
func _strike_back_attacks(defender: GameUnit, charger: GameUnit) -> int:
	var total := 0
	for grp in _main._solo_attack_groups(defender, 0.0, true, charger):
		for p in (grp as Dictionary).get("profiles", []):
			total += int((p as Dictionary).get("attacks", 0))
	return total


## Per-model base-edge gap (inches) to the NEAREST charger model — the exact measure
## striking_models_for compares against MELEE_REACH_IN.
func _gaps(defender: GameUnit, charger: GameUnit) -> Array:
	var out: Array = []
	for m in defender.get_alive_models():
		var shape = SeparationChecker.shape_for_model(m as ModelInstance)
		var best := INF
		for c in charger.get_alive_models():
			var cs = SeparationChecker.shape_for_model(c as ModelInstance)
			if shape != null and cs != null:
				best = minf(best, SeparationChecker.edge_distance(shape, cs))
		out.append(snappedf(best, 0.01))
	return out


## MECHANISM A — the pile-in itself moves a model AWAY from the enemy.
##
## GF v3.5.1 p.9: models "must move by up to 3\" to get into base contact with a charging model, or as
## close as possible". `SoloController.pile_in` implements this as a per-model walk toward a CONTACT
## SLOT (`MovementPlanner.charge_contact_slots`), and every charger base offers only ~3 usable slots:
## the fan is [0, ±0.7, ±1.4] rad, and two neighbours 0.7 rad apart sit 0.86" apart on a 25 mm contact
## circle while the occupancy test rejects anything closer than (ri + r)*0.95 = 1.20". Surplus
## defenders therefore get a slot on a DIFFERENT charger model and step up to 3" toward it — which
## points away from the charger model they were already within 2" of. There is no post-condition
## anywhere in pile_in that compares the resulting gap with the one it started from.
##
## Measured below with two charger models 12" apart: the 5th defender's gap GROWS 1.60" → 1.85"
## across a pile-in that reports 5 successful moves. It stays inside 2" here, so the strike-back
## survives — but on a table with anything else in the way the same step crosses the line: the same
## fixture run after three other melees on the board (i.e. with foreign bases blocking the short
## legal steps) loses a model out of reach, 5 in reach → 4.
func test_repro_a_pile_in_can_increase_a_models_gap_to_the_enemy(timeout := 300000) -> void:
	var charger := _melee_unit(2, "Chargers", [Vector2(0, 4), Vector2(12, 4)], 2)
	var defender := _melee_unit(1, "Defenders",
		[Vector2(-1.5, 0), Vector2(0, 0), Vector2(1.5, 0), Vector2(-0.75, -1.5),
		Vector2(0.75, -1.5), Vector2(0, -3.0)], 1)
	var solo = _main.solo_controller
	solo.snap_charge(charger, defender)
	var gaps_before := _gaps(defender, charger)
	var reach_before: int = solo.striking_models_for(defender, charger)
	var moves: Array = solo.pile_in(defender, charger)
	var gaps_after := _gaps(defender, charger)
	var reach_after: int = solo.striking_models_for(defender, charger)
	prints("[#221-A] moves:", moves.size(), "| reach", reach_before, "->", reach_after)
	prints("[#221-A] gaps before:", str(gaps_before))
	prints("[#221-A] gaps after :", str(gaps_after))
	# The precondition of the report: the pile-in DID run and DID move models.
	assert_int(moves.size()) \
		.override_failure_message("fixture broken: this pile-in was supposed to move models") \
		.is_greater(0)
	# Evidence: at least one model ended up FARTHER from the enemy than it started.
	var grew := false
	for i in range(mini(gaps_before.size(), gaps_after.size())):
		if float(gaps_after[i]) > float(gaps_before[i]) + 0.01:
			grew = true
	assert_bool(grew) \
		.override_failure_message("#221 mechanism A no longer reproduces — pile-in kept every model at or nearer its gap (before %s / after %s). If that is intentional, retire this case." % [str(gaps_before), str(gaps_after)]) \
		.is_true()
	# ── THE INVARIANT THAT SHOULD HOLD — RED TODAY, DELIBERATELY NOT ENFORCED ──────────────────
	# A pile-in may only ever move models TOWARD contact, so no model's gap may grow and the count
	# of models in strike reach may never fall. Uncomment once the verdict on #221 is in:
	#
	# for i in range(gaps_before.size()):
	#     assert_float(gaps_after[i]).is_less_equal(float(gaps_before[i]) + 0.01)
	# assert_int(reach_after).is_greater_equal(reach_before)
	#
	# Candidate fix (NOT applied): clamp each pile-in step so the model's distance to its NEAREST
	# enemy base never increases — i.e. reject a candidate in the fraction ladder at
	# solo_controller.gd `pile_in` when its nearest-enemy edge gap exceeds the pre-step gap.


## MECHANISM B — why ANY loss of reach surfaces as this particular sentence.
##
## The two gates disagree about what "can strike back" means. `_run_ai_melee` asks
## `_solo_attack_groups(target, 0.0, true, unit).is_empty()` and only refuses with "has no melee
## weapons — cannot strike back" when the unit owns no melee weapon at all — but `_solo_attack_groups`
## builds its group from `AiShooting.melee_profiles`, which is a pure `range_value == 0` filter with
## NO geometry in it. A unit that owns a CCW but has no model within 2" therefore passes that gate
## with a non-empty group whose every profile was scaled to 0 attacks by `striking_models_for`, the
## player is offered the strike-back, accepts, and only THEN is told "no melee weapons in reach".
##
## That is the constant factor behind every report of this shape: whichever mechanism empties the
## reach (A above, casualties between the phases, terrain, a blocked pile-in), the symptom is always
## this misleading sentence AFTER an accepted offer, never an honest refusal up front.
##
## Deterministic, no charge needed — the geometry alone decides.
func test_repro_b_a_unit_out_of_reach_still_passes_the_cannot_strike_back_gate(timeout := 300000) -> void:
	var charger := _melee_unit(2, "Charger", [Vector2(0, 0)], 2)
	var defender := _melee_unit(1, "Defender", [Vector2(5.0, 0), Vector2(6.5, 0)], 1)
	var solo = _main.solo_controller
	assert_int(solo.striking_models_for(defender, charger)) \
		.override_failure_message("fixture broken: nobody should be within the 2\" strike reach") \
		.is_equal(0)
	# The gate that is SUPPOSED to catch a unit that cannot strike back — it does not.
	assert_array(_main._solo_attack_groups(defender, 0.0, true, charger)) \
		.override_failure_message("the 'cannot strike back' gate now catches this — #221 can no longer take this route, retire the case") \
		.is_not_empty()
	# … and every profile in that non-empty group rolls nothing: the #221 refusal.
	assert_int(_strike_back_attacks(defender, charger)) \
		.override_failure_message("the out-of-reach defender rolled melee dice") \
		.is_equal(0)
	# ── OPEN LEAD, not reproduced in isolation ────────────────────────────────────────────────
	# Casualties are removed OUTERMOST-first (`SoloController.casualty_order`, rank = v*1000 - d),
	# and the charger's strike phase runs BEFORE the strike-back — so the models the pile-in just
	# put into contact are candidates to die first. In a clean two-unit scene this does NOT empty
	# the reach (the pile-in pulls the tail in, and the survivors are still within 2"): a 4-model
	# column at 0/-3.2/-3.9/-4.6" ends at reach 2 after two casualties. It DID empty to 0 on a
	# crowded board, where foreign bases blocked every legal pile-in step (`_pile_spot_free`) and
	# `pile_in` moved nobody at all. So the casualty half needs a BLOCKED pile-in to bite — which
	# is also why the reporter's board state matters. Do not "fix" casualty_order on this evidence.
