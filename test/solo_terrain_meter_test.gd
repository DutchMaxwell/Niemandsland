extends GdUnitTestSuite
## THE BEHAVIOUR METER'S `shot` FIELD (terrain grill D9, NML-1009).
##
## Measured 16.08.: the meter read report["shoot"] — and the two brains fill that key with
## answers to DIFFERENT questions. The decision tree writes "this unit fires" (do_shoot); the
## clone/planner overlay writes "the chosen menu entry carried a shoot key" (act.has("shoot")).
## Readings: tree 37.1% per activation, clone 1.8-3.6%, and the 3.6% is exactly the rate at
## which a picked entry carries that key. Two questions, one number — unusable as an
## acceptance criterion.
##
## The meter now reads report["can_shoot"]: the single post-move gate BOTH brains flow through
## (range + line of sight from the settled position, plus the Bug-27/28 retarget), and the exact
## predicate the drivers fire on — main._solo_activate_one_ai and tools/solo_selfplay both do
## `if can_shoot: _run_ai_shooting(report)`. These pin the meter to that gate.

const IN2M := 0.0254


func before_test() -> void:
	_meter(true)


func after_test() -> void:
	_meter(false)


## The meter's env gate caches its answer for the whole PROCESS (static var), so a suite that
## ran earlier has already answered "off" — flip the variable AND drop the cache.
func _meter(on: bool) -> void:
	OS.set_environment("NML_TERRAIN_METER", "1" if on else "")
	SoloController._meter_env = -1


func _unit(pid: int, positions: Array, rules: Array = [], uid: String = "") -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = uid if uid != "" else "p%d_%d" % [pid, positions.size()]
	u.unit_properties = {"player_id": pid, "name": (uid if uid != "" else "U%d" % pid),
		"quality": 4, "defense": 4, "special_rules": rules}
	for p in positions:
		var m := ModelInstance.new()
		m.is_alive = true
		m.unit = u
		var n := Node3D.new()
		add_child(n)
		n.global_position = p
		m.node = n
		u.models.append(m)
	return u


func _army(units: Array) -> OPRArmyManager:
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	var gu := {}
	for u in units:
		gu[(u as GameUnit).unit_id] = u
	army.game_units = gu
	army.current_round = 1
	return army


func _controller(units: Array) -> SoloController:
	var sc: SoloController = auto_free(SoloController.new())
	add_child(sc)
	sc.setup(_army(units), null, null, 1, 2)
	return sc


func _arm(u: GameUnit, weapons: Array) -> void:
	var opr := OPRApiClient.OPRUnit.new()
	for w in weapons:
		var ow := OPRApiClient.OPRWeapon.new()
		ow.name = str((w as Dictionary).get("name", "W"))
		ow.range_value = int((w as Dictionary).get("range", 0))
		ow.attacks = int((w as Dictionary).get("attacks", 2))
		ow.count = 1
		for r in (w as Dictionary).get("rules", []):
			ow.special_rules.append(str(r))
		opr.weapons.append(ow)
	u.source_type = "opr"
	u.source_data = opr


## The last terrain_meter record's data ({} when the meter stayed silent — asserted on, so a
## meter that never fires fails the test instead of reading as "no shot").
func _meter_data(sc: SoloController) -> Dictionary:
	var data := {}
	for rec in sc.drain_decisions():
		if str((rec as Dictionary).get("kind", "")) == "terrain_meter":
			data = (rec as Dictionary).get("data", {}) as Dictionary
	return data


## [controller, shooter] — the control shape of solo_aircraft_test's ground run: 24" rifle,
## enemy 20" out, so the tree plans the volley and the post-move gate keeps it. `los` decides
## whether the lane is clear.
func _shooter_board(los: bool) -> Array:
	var shooter := _unit(2, [Vector3.ZERO], [], "Shooter")
	_arm(shooter, [{"name": "Rifle", "range": 24, "attacks": 2, "rules": []}])
	var enemy := _unit(1, [Vector3(20.0 * IN2M, 0, 0)], [], "Grunts")
	var sc := _controller([shooter, enemy])
	sc.los_checker = func(_a: Vector3, _b: Vector3) -> bool: return los
	return [sc, shooter]


# === The two questions, told apart ===

func test_the_meter_reads_the_fire_gate_not_the_plan() -> void:
	# The clone's failure mode: the picked menu entry carried no shoot key (shoot=false) while
	# the post-move gate opened the volley. main.gd rolls dice for THIS activation, so it is a
	# shot — the old reading counted zero and buried the clone's real firing rate.
	var board := _shooter_board(true)
	var sc: SoloController = board[0]
	sc._terrain_meter(board[1] as GameUnit, {"shoot": false, "can_shoot": true})
	var data := _meter_data(sc)
	assert_bool(data.has("shot")).is_true()
	assert_bool(bool(data["shot"])).is_true()


func test_a_plan_whose_post_move_gate_closed_is_no_shot() -> void:
	# The mirror: the tree promised a volley, the gate refused it after the move. Nothing fires,
	# so the meter must read zero — the old reading counted the intention.
	var board := _shooter_board(true)
	var sc: SoloController = board[0]
	sc._terrain_meter(board[1] as GameUnit, {"shoot": true, "can_shoot": false})
	var data := _meter_data(sc)
	assert_bool(data.has("shot")).is_true()
	assert_bool(bool(data["shot"])).is_false()


# === The same thing through a REAL activation ===

func test_a_live_activation_meters_the_trigger_and_not_the_intention() -> void:
	# 24" rifle, target 20" away, NO line of sight: the tree still plans the volley (LOS is not
	# part of its shoot branch), the post-move gate refuses it and the retarget finds nothing
	# else — main.gd would roll no dice at all. shoot=true, can_shoot=false, meter: no shot.
	var sc: SoloController = _shooter_board(false)[0]
	sc.activate_next_ai_unit()
	assert_bool(bool(sc.last_report.get("shoot", false))).is_true()       # the plan wanted it
	assert_bool(bool(sc.last_report.get("can_shoot", true))).is_false()   # the gate refused it
	var data := _meter_data(sc)
	assert_bool(data.has("shot")).is_true()
	assert_bool(bool(data["shot"])).is_false()


func test_the_same_board_with_a_clear_lane_meters_a_shot() -> void:
	# Red-green control: the same activation with the lane open must read as a shot, otherwise
	# the test above would pass against a meter hardwired to false.
	var sc: SoloController = _shooter_board(true)[0]
	sc.activate_next_ai_unit()
	assert_bool(bool(sc.last_report.get("can_shoot", false))).is_true()
	var data := _meter_data(sc)
	assert_bool(data.has("shot")).is_true()
	assert_bool(bool(data["shot"])).is_true()


func test_the_meter_stays_silent_without_its_env_gate() -> void:
	# Measurement costs one LOS check per enemy — with NML_TERRAIN_METER unset nothing is
	# recorded at all (and the tests above are therefore reading a gate they turned on).
	_meter(false)
	var sc: SoloController = _shooter_board(true)[0]
	sc.activate_next_ai_unit()
	assert_bool(_meter_data(sc).is_empty()).is_true()
