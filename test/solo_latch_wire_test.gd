extends GdUnitTestSuite
## MP (online co-op, #673): the AI's controller-side latches have to reach the other table.
##
## THE DEFECT. In an online co-op room two humans face one AI seat and the AI's activation resolves on
## whichever machine's activation it answered. SoloController closed three once-per-game latches with
## plain `unit_properties[...] = ...` writes: Second Wind (`second_wind_used`), the Limited weapon ledger
## (`limited_used`) and Ambush Re-Deployment (`ambush_redeploy_used` + the due round `ambush_return_round`).
## The machine that answers the AI's NEXT activation / the next round start never saw them spent.
##
## The suite drives the real controller on two "machines" (two armies holding the same unit), records the
## frames machine A hands to its NetworkManager and replays them into the REAL receiver on machine B, then
## asks machine B's controller the question the rule asks.

const FLAG_SW := "second_wind_used"


## The REAL NetworkManager with its transport swapped out (the WireNet of e2e_one_core_ai_body_test.gd):
## every frame this machine would send is recorded, and the real allow-list gate applies.
class WireNet extends "res://scripts/network_manager.gd":
	var active: bool = true
	var wire: Array = []
	func is_multiplayer_active() -> bool:
		return active
	func _validate_rpc_ready(_context: String = "") -> bool:
		return true
	func send_command(type: String, payload: Variant = {}, target_peer: int = 0) -> bool:
		wire.append({"t": type, "p": payload, "to": target_peer})
		return true
	func slot_has_human_peer(_slot: int) -> bool:
		return false
	func get_my_peer_id() -> int:
		return 1
	func get_my_player_slot() -> int:
		return 1


func _mgr() -> OPRArmyManager:
	var mgr := OPRArmyManager.new()
	add_child(mgr)
	return auto_free(mgr)


func _unit(mgr: OPRArmyManager, pid: int, unit_name: String, rules: Array = [], faction := "") -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = "%s_%d" % [unit_name, pid]
	u.unit_properties = {"player_id": pid, "name": unit_name, "quality": 4, "defense": 4, "special_rules": rules}
	if not faction.is_empty():
		u.unit_properties["faction_folder"] = faction
	var m := ModelInstance.new()
	m.is_alive = true
	var n := Node3D.new()
	add_child(n)
	n.global_position = Vector3.ZERO
	m.node = n
	u.models.append(m)
	mgr.game_units[u.unit_id] = u
	return u


## One machine: its own army, its own controller (human slot 1, AI slot 2), wired to `net`.
func _controller(mgr: OPRArmyManager, net: Node) -> SoloController:
	var sc := SoloController.new()
	add_child(sc)
	sc.setup(mgr, net, null, 1, 2)
	sc.round_provider = func() -> int: return int(mgr.current_round)
	return auto_free(sc)


func _wire() -> WireNet:
	return auto_free(WireNet.new())


## The unit-property frames machine A sent, in order: {unit, key, value}.
func _frames(net: WireNet) -> Array:
	var out: Array = []
	for w in net.wire:
		var p: Dictionary = (w as Dictionary)["p"] as Dictionary
		if str(p.get("m", "")) != "sync_unit_property":
			continue
		var a: Array = p["a"]
		out.append({"unit": str(a[0]), "key": str(a[1]), "value": a[2]})
	return out


func _values(net: WireNet, key: String) -> Array:
	var out: Array = []
	for e in _frames(net):
		if str((e as Dictionary)["key"]) == key:
			out.append((e as Dictionary)["value"])
	return out


## Machine B receives exactly the frames machine A sent, through the REAL receiver.
func _replay(net: WireNet, mgr_b: OPRArmyManager) -> void:
	var nm: Node = auto_free(preload("res://scripts/network_manager.gd").new())
	nm.army_manager = mgr_b
	for e in _frames(net):
		var d := e as Dictionary
		nm.sync_unit_property(str(d["unit"]), str(d["key"]), d["value"])


# === Second Wind ==================================================================================

func test_second_wind_latch_rides_the_wire_and_holds_on_the_other_table() -> void:
	var net := _wire()
	var mgr_a := _mgr()
	var sc_a := _controller(mgr_a, net)
	_unit(mgr_a, 1, "Plain")
	var carrier_a := _unit(mgr_a, 2, "Agent", ["Inquisitorial Agent"], "human_inquisition")
	carrier_a.is_activated = true
	assert_object(sc_a.second_wind_candidate()).override_failure_message("fixture check: A offers the carrier").is_same(carrier_a)

	sc_a.spend_second_wind(carrier_a)

	assert_array(_values(net, FLAG_SW)) \
		.override_failure_message("the once-per-game latch never reached the wire (frames: %s)" % str(_frames(net))) \
		.is_equal([true])
	# Machine B: the same unit, activated again (round 2), never saw A's spend.
	var mgr_b := _mgr()
	var sc_b := _controller(mgr_b, null)
	_unit(mgr_b, 1, "Plain")
	var carrier_b := _unit(mgr_b, 2, "Agent", ["Inquisitorial Agent"], "human_inquisition")
	carrier_b.is_activated = true
	assert_object(sc_b.second_wind_candidate()) \
		.override_failure_message("control: a machine that heard nothing offers the feat again") \
		.is_same(carrier_b)
	_replay(net, mgr_b)
	assert_object(sc_b.second_wind_candidate()) \
		.override_failure_message("the other table offers the once-per-game Second Wind a second time") \
		.is_null()


# === Limited weapons ==============================================================================

func test_limited_ledger_rides_the_wire_and_holds_on_the_other_table() -> void:
	var net := _wire()
	var mgr_a := _mgr()
	var sc_a := _controller(mgr_a, net)
	var unit_a := _unit(mgr_a, 2, "Gators")
	var profile := {"name": "Rocket-Pod", "limited": true}

	sc_a.mark_limited_used(unit_a, profile)

	assert_array(_values(net, "limited_used")) \
		.override_failure_message("the spent weapon never reached the wire (frames: %s)" % str(_frames(net))) \
		.is_equal([["Rocket-Pod"]])
	var mgr_b := _mgr()
	var sc_b := _controller(mgr_b, null)
	var unit_b := _unit(mgr_b, 2, "Gators")
	assert_bool(sc_b.is_limited_used(unit_b, profile)) \
		.override_failure_message("control: a machine that heard nothing sees the weapon as unspent") \
		.is_false()
	_replay(net, mgr_b)
	assert_bool(sc_b.is_limited_used(unit_b, profile)) \
		.override_failure_message("the other table fires the once-per-game Limited weapon a second time") \
		.is_true()


## A second spent weapon sends the whole new list (the receiver stores the value, it does not add).
func test_a_second_limited_weapon_sends_the_whole_list() -> void:
	var net := _wire()
	var mgr_a := _mgr()
	var sc_a := _controller(mgr_a, net)
	var unit_a := _unit(mgr_a, 2, "Gators")

	sc_a.mark_limited_used(unit_a, {"name": "Rocket-Pod", "limited": true})
	sc_a.mark_limited_used(unit_a, {"name": "Rocket-Pod", "limited": true})   # already spent: nothing new to say
	sc_a.mark_limited_used(unit_a, {"name": "Torpedo", "limited": true})

	assert_array(_values(net, "limited_used")) \
		.override_failure_message("frames: %s" % str(_frames(net))) \
		.is_equal([["Rocket-Pod"], ["Rocket-Pod", "Torpedo"]])


# === Ambush Re-Deployment =========================================================================

func test_redeploy_latch_and_return_round_ride_the_wire_and_hold_on_the_other_table() -> void:
	var net := _wire()
	var mgr_a := _mgr()
	var sc_a := _controller(mgr_a, net)
	var unit_a := _unit(mgr_a, 2, "Raiders", ["Ambush Re-Deployment"])
	assert_bool(SoloController.can_ambush_redeploy(unit_a)).override_failure_message("fixture check").is_true()

	var due: int = sc_a.ambush_redeploy_withdraw(unit_a, 1)

	assert_int(due).is_equal(2)
	assert_array(_values(net, "ambush_redeploy_used")) \
		.override_failure_message("the once-per-game use never reached the wire (frames: %s)" % str(_frames(net))) \
		.is_equal([true])
	assert_array(_values(net, "ambush_return_round")) \
		.override_failure_message("the due round never reached the wire (frames: %s)" % str(_frames(net))) \
		.is_equal([2])
	# Machine B: it closes round 2. The unit is back on the table there (reserve flag handled by the visibility channel).
	var mgr_b := _mgr()
	var unit_b := _unit(mgr_b, 2, "Raiders", ["Ambush Re-Deployment"])
	assert_bool(SoloController.can_ambush_redeploy(unit_b)).override_failure_message("control: B has not heard").is_true()
	_replay(net, mgr_b)
	assert_bool(SoloController.can_ambush_redeploy(unit_b)) \
		.override_failure_message("the other table offers the once-per-game Re-Deployment a second time") \
		.is_false()
	assert_int(int(unit_b.unit_properties.get("ambush_return_round", 0))) \
		.override_failure_message("the other table does not know the return date") \
		.is_equal(2)


# === Counter-proofs ===============================================================================

func test_a_solo_game_latches_without_a_frame() -> void:
	var net := _wire()
	net.active = false
	var mgr := _mgr()
	var sc := _controller(mgr, net)
	var unit := _unit(mgr, 2, "Raiders", ["Ambush Re-Deployment"])

	sc.mark_limited_used(unit, {"name": "Rocket-Pod", "limited": true})
	sc.ambush_redeploy_withdraw(unit, 1)

	assert_bool(bool(unit.unit_properties.get("ambush_redeploy_used", false))).is_true()
	assert_array(unit.unit_properties.get("limited_used", [])).is_equal(["Rocket-Pod"])
	assert_array(_frames(net)).override_failure_message("an offline game broadcast hidden state").is_empty()


func test_the_receiver_takes_the_controller_latch_keys() -> void:
	var mgr := _mgr()
	var unit := _unit(mgr, 2, "Raiders")
	var nm: Node = auto_free(preload("res://scripts/network_manager.gd").new())
	nm.army_manager = mgr
	for key in ["second_wind_used", "limited_used", "ambush_redeploy_used", "ambush_return_round"]:
		nm.sync_unit_property(unit.unit_id, key, 3)
		assert_int(int(unit.unit_properties.get(key, 0))).override_failure_message(key).is_equal(3)
	nm.sync_unit_property(unit.unit_id, "player_id", 1)
	assert_int(int(unit.unit_properties.get("player_id", 0))).is_equal(2)
