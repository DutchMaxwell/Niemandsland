extends GdUnitTestSuite
## MP (online co-op, #673): the AI's once-per-game Speed Feat latch has to reach the other table.
##
## THE DEFECT. SoloController._spend_speed_feat closed the latch with a plain write to
## `unit_properties["speed_feat_used_<rule>"]`. The key IS on NetworkManager's allow-list (the HUMAN
## spend in main.gd syncs it), but the AI's spend never sent it. In an online co-op room the AI's
## activation resolves on whichever machine's activation it answered, so the second machine still
## saw the feat as unspent and spent it AGAIN - twice per game instead of once.
##
## The suite drives the real controller on two "machines" (two copies of the same bearer), records the
## frames machine A hands to its NetworkManager and replays them into the REAL receiver on machine B.

const NetworkManagerScript := preload("res://scripts/network_manager.gd")
const IN2M := 0.0254
const FLAG := "speed_feat_used_speed_feat"

var _epoch0 := 0


## A live session that records every outbound hidden state delta.
class FakeNet extends Node:
	var active: bool = true
	var sent: Array = []
	func is_multiplayer_active() -> bool:
		return active
	func broadcast_unit_property(gu: GameUnit, key: String, value: Variant) -> void:
		sent.append({"unit": gu.unit_id, "key": key, "value": value})


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_76_MOVE_FIXES


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0


func _unit(pid: int, pos: Vector3, uid: String, rules: Array) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = uid
	u.unit_properties = {"player_id": pid, "name": uid, "quality": 4, "defense": 4, "special_rules": rules,
		"game_system": "gf", "faction_folder": "orc_marauders", "base_size_round": 25}
	var m := ModelInstance.new()
	m.is_alive = true
	m.wounds_current = 1
	m.unit = u
	var n := Node3D.new()
	add_child(n)
	n.global_position = pos
	m.node = n
	u.models.append(m)
	var opr := OPRApiClient.OPRUnit.new()
	var ow := OPRApiClient.OPRWeapon.new()
	ow.name = "CCW"
	ow.range_value = 0
	ow.attacks = 2
	ow.count = 1
	opr.weapons.append(ow)
	u.source_type = "opr"
	u.source_data = opr
	return u


## One machine: its own army (bearer = AI player 2 at 0", a foe 20" off), round 3 of 4 (the endgame
## window the feat waits for), and its own controller wired to `net`.
func _machine(net: Node) -> Dictionary:
	var bearer := _unit(2, Vector3.ZERO, "Boyz", ["Speed Feat"])
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {bearer.unit_id: bearer, "Foe": _unit(1, Vector3(20.0 * IN2M, 0, 0), "Foe", [])}
	army.current_round = 3
	var sc: SoloController = auto_free(SoloController.new())
	add_child(sc)
	sc.setup(army, net, null, 1, 2)
	sc.game_rounds = 4
	sc.round_provider = func() -> int: return 3
	sc.objectives_provider = func() -> Array: return []
	sc.objective_owner_of = func(_i: int) -> int: return 0
	return {"bearer": bearer, "sc": sc, "army": army}


func _spend_notes(report: Dictionary) -> Array:
	return (report["rule_notes"] as Array).filter(func(n: Dictionary) -> bool:
		return str(n["text"]).contains("spends its once-per-game move bonus"))


func _values(net: FakeNet) -> Array:
	var out: Array = []
	for e in net.sent:
		if str((e as Dictionary)["key"]) == FLAG:
			out.append((e as Dictionary)["value"])
	return out


## The spend sends the latch: one frame, the flag, true, naming the bearer.
func test_the_ai_speed_feat_spend_sends_its_latch() -> void:
	var net: FakeNet = auto_free(FakeNet.new())
	var a := _machine(net)
	var report: Dictionary = (a["sc"] as SoloController)._act(a["bearer"])

	assert_int(_spend_notes(report).size()).override_failure_message("fixture check: the bearer must spend the feat").is_equal(1)
	assert_array(_values(net)) \
		.override_failure_message("the AI's once-per-game latch never reached the wire (sent: %s)" % str(net.sent)) \
		.is_equal([true])
	assert_str(str((net.sent[0] as Dictionary).get("unit", "<no message>")) if not net.sent.is_empty() else "<no message>") \
		.is_equal("Boyz")


## Below 76 the head of _act spends the feat; that leg sends the latch as well.
func test_the_head_spend_below_76_sends_its_latch_too() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_76_MOVE_FIXES - 1
	var net: FakeNet = auto_free(FakeNet.new())
	var a := _machine(net)
	(a["sc"] as SoloController)._act(a["bearer"])

	assert_array(_values(net)).override_failure_message("sent: %s" % str(net.sent)).is_equal([true])


## THE CO-OP CASE: machine A's AI spent the feat; the AI answers the other human on machine B. B only
## knows what the wire told it - and must NOT spend the once-per-game feat a second time.
func test_the_other_table_does_not_spend_the_feat_again() -> void:
	var net: FakeNet = auto_free(FakeNet.new())
	var a := _machine(net)
	(a["sc"] as SoloController)._act(a["bearer"])

	var b := _machine(null)
	var nm: Node = auto_free(NetworkManagerScript.new())
	nm.army_manager = b["army"]
	for e in net.sent:
		var d := e as Dictionary
		nm.sync_unit_property(str(d["unit"]), str(d["key"]), d["value"])

	assert_bool(bool((b["bearer"] as GameUnit).unit_properties.get(FLAG, false))) \
		.override_failure_message("the second machine never learned the feat was spent (sent: %s)" % str(net.sent)) \
		.is_true()
	var report_b: Dictionary = (b["sc"] as SoloController)._act(b["bearer"])
	assert_int(_spend_notes(report_b).size()) \
		.override_failure_message("the once-per-game feat was spent a second time on the other table") \
		.is_equal(0)


## CONTROL (green before and after the fix): a machine that heard nothing spends again - that is the
## double spend the case above guards against, so its assertion can fail.
func test_a_machine_that_heard_nothing_spends_again() -> void:
	var a := _machine(null)
	(a["sc"] as SoloController)._act(a["bearer"])
	var b := _machine(null)
	var report_b: Dictionary = (b["sc"] as SoloController)._act(b["bearer"])
	assert_int(_spend_notes(report_b).size()).is_equal(1)


## Offline nothing is sent, and the latch is still closed locally.
func test_a_solo_game_spends_without_a_frame() -> void:
	var net: FakeNet = auto_free(FakeNet.new())
	net.active = false
	var a := _machine(net)
	(a["sc"] as SoloController)._act(a["bearer"])

	assert_bool(bool((a["bearer"] as GameUnit).unit_properties.get(FLAG, false))).is_true()
	assert_array(net.sent).override_failure_message("an offline game broadcast hidden state").is_empty()
