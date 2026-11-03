extends GdUnitTestSuite
## Row FAB-A5: the sim's shoot EV must read the table's Hold state — `moved_round != current round`
## (the expression main.gd's `_solo_unit_held` uses) — instead of `ctx_for`'s optimistic default.
## An Artillery gun that moved this round gets no shooter +1, and as a target it hands the shooter
## no -1; a gun that held keeps its +1. Driven through BattleSim.capture + BattleSim.resolve, so
## the shoot leg's own ctx build is what is measured.

## RED proof (CI red at the RED commit, gdUnit shard 8): https://github.com/DutchMaxwell/Niemandsland/actions/runs/41597416642/job/125789003687
const IN2M := 0.0254
const ROUND := 73

var _epoch0: int


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	RulesRegistry.reset_cache()


func after_test() -> void:
	# statics leak across gdUnit tests — restore
	AiActRecorder.rules_epoch = _epoch0


func _unit(pid: int, positions: Array, uid: String, rules: Array, attacks: int,
		wounds_now: int) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = uid
	u.unit_properties = {"player_id": pid, "name": uid, "quality": 4, "defense": 4,
		"special_rules": rules}
	for p in positions:
		var m := ModelInstance.new()
		m.is_alive = true
		m.wounds_current = wounds_now
		m.unit = u
		var n := Node3D.new()
		add_child(n)
		n.global_position = p
		m.node = n
		u.models.append(m)
	var opr := OPRApiClient.OPRUnit.new()
	var ow := OPRApiClient.OPRWeapon.new()
	ow.name = "Gun"
	ow.range_value = 24
	ow.attacks = attacks
	ow.count = 1
	opr.weapons.append(ow)
	u.source_type = "opr"
	u.source_data = opr
	return u


func _five_at(dist_in: float) -> Array:
	var out: Array = []
	for i in range(5):
		out.append(Vector3((dist_in + float(i)) * IN2M, 0.0, 0.0))
	return out


## The real sim route: capture a round-73 board, then resolve the declared shoot in expectation.
func _wounds_left_after_shot(shooter: GameUnit, target: GameUnit) -> int:
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {shooter.unit_id: shooter, target.unit_id: target}
	var state := BattleSim.capture(army, Callable(), Callable(), ROUND)
	var action := {"unit": shooter.unit_id, "kind": AiDecision.Action.HOLD,
		"shoot": target.unit_id}
	var next := BattleSim.resolve(state, action)
	return BattleSim._wounds_left(next["units"][target.unit_id])


## 10 Quality-4 attacks into Defense 4+: 3+ to hit = 3 wounds, 4+ to hit = 2 wounds on 10 wounds.
func test_artillery_that_moved_this_round_earns_no_plus_one() -> void:
	var gun := _unit(1, [Vector3.ZERO], "Gun", ["Artillery"], 10, 1)
	gun.unit_properties["moved_round"] = ROUND
	var foe := _unit(2, _five_at(15.0), "Foe", [], 10, 2)
	assert_int(_wounds_left_after_shot(gun, foe)) \
		.override_failure_message("a moved gun got the Hold +1 at 15\"") \
		.is_equal(8)


## Control: the same gun that held this round keeps the +1.
func test_artillery_that_held_keeps_the_plus_one() -> void:
	var gun := _unit(1, [Vector3.ZERO], "Gun", ["Artillery"], 10, 1)
	var foe := _unit(2, _five_at(15.0), "Foe", [], 10, 2)
	assert_int(_wounds_left_after_shot(gun, foe)) \
		.override_failure_message("a held gun lost the Hold +1 at 15\"") \
		.is_equal(7)


## The defender leg: a target that moved this round is not a Held gun, so no -1.
## 10 Quality-4 attacks: free = 2 wounds, with the target's -1 = 1 wound on 10 wounds.
func test_artillery_target_that_moved_this_round_hands_no_minus_one() -> void:
	var rifle := _unit(1, [Vector3.ZERO], "Rifle", [], 10, 1)
	var gun := _unit(2, _five_at(15.0), "Gun", ["Artillery"], 10, 2)
	gun.unit_properties["moved_round"] = ROUND
	assert_int(_wounds_left_after_shot(rifle, gun)) \
		.override_failure_message("a moved gun still gave the shooter the target -1") \
		.is_equal(8)


## Fable F5: the ATTACKER's Hold comes from the SIMULATED action. The live unit never moved, so the
## old live read priced a simulated ADVANCE+shoot as a Hold (+1); the sim HOLD must keep it.
func _resolve_with(shooter: GameUnit, target: GameUnit, kind: int) -> Dictionary:
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {shooter.unit_id: shooter, target.unit_id: target}
	var state := BattleSim.capture(army, Callable(), Callable(), ROUND)
	return BattleSim.resolve(state, {"unit": shooter.unit_id, "kind": kind,
		"dest": (shooter.models[0].node as Node3D).global_position + Vector3(2.0 * IN2M, 0.0, 0.0),
		"shoot": target.unit_id})


func test_a_simulated_advance_and_shoot_pays_no_hold_bonus() -> void:
	var gun := _unit(1, [Vector3.ZERO], "Gun", ["Artillery"], 10, 1)
	var foe := _unit(2, _five_at(15.0), "Foe", [], 10, 2)
	var advanced := _resolve_with(gun, foe, AiDecision.Action.ADVANCE)
	assert_int(BattleSim._wounds_left(advanced["units"][foe.unit_id])) \
		.override_failure_message("a simulated advance still got the Hold +1") \
		.is_equal(8)
	var gun2 := _unit(1, [Vector3.ZERO], "Gun", ["Artillery"], 10, 1)
	var foe2 := _unit(2, _five_at(15.0), "Foe", [], 10, 2)
	var held := _resolve_with(gun2, foe2, AiDecision.Action.HOLD)
	assert_int(BattleSim._wounds_left(held["units"][foe2.unit_id])) \
		.override_failure_message("a simulated hold lost its +1") \
		.is_equal(7)


## The defender leg through the SIM STATE: a gun that advanced EARLIER in the same simulated round
## hands no target -1; a gun that held does. Two resolutions on one snapshot chain.
func test_a_defender_that_moved_in_this_sim_round_hands_no_minus_one() -> void:
	var gun := _unit(2, _five_at(15.0), "Gun", ["Artillery"], 10, 2)
	var rifle := _unit(1, [Vector3.ZERO], "Rifle", [], 10, 1)
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {gun.unit_id: gun, rifle.unit_id: rifle}
	var state := BattleSim.capture(army, Callable(), Callable(), ROUND)
	var moved := BattleSim.resolve(state, {"unit": gun.unit_id, "kind": AiDecision.Action.ADVANCE,
		"dest": (gun.models[0].node as Node3D).global_position + Vector3(0.0, 0.0, 2.0 * IN2M)})
	var after := BattleSim.resolve(moved, {"unit": rifle.unit_id, "kind": AiDecision.Action.HOLD,
		"shoot": gun.unit_id})
	assert_int(BattleSim._wounds_left(after["units"][gun.unit_id])) \
		.override_failure_message("a gun that moved in this sim round still gave the -1") \
		.is_equal(8)
	var still := BattleSim.resolve(state, {"unit": rifle.unit_id, "kind": AiDecision.Action.HOLD,
		"shoot": gun.unit_id})
	assert_int(BattleSim._wounds_left(still["units"][gun.unit_id])) \
		.override_failure_message("a held gun stopped giving the -1") \
		.is_equal(9)
