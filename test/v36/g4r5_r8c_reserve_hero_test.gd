extends GdUnitTestSuite
## G4R5 R8c (gf_1000_net_032 act 4): a hero joined to a host that waits in Ambush reserve waits in the tray with it. The
## planner snapshot (BattleSim.capture) marked only the host dormant - a hero is not a reserve unit in its own right - so
## the hero was exported as a live lone hero at the spot it was deployed on, and the planner shot at it and walked toward
## it ("advance and shoot Rebel Leader") while the table, rightly, refused a reserved target. From EPOCH_73_V36 the hero of
## a reserved host is dormant too (zero table presence, its strength kept in dormant_*). Below 73 the old export stands.
## The Rust core reads `dormant` per unit off this snapshot (state.rs `dormant: Vec<bool>`), so the fix lives here.

const IN2M := 0.0254

var _epoch_before: int


func before_test() -> void:
	_epoch_before = AiActRecorder.rules_epoch
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch_before


func _unit(pid: int, positions: Array, uid: String, rules: Array) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = uid
	u.unit_properties = {"player_id": pid, "name": uid, "quality": 4, "defense": 4, "special_rules": rules}
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
	return army


## An Ambush host with a joined hero: the table sets `ambush_reserve` on the host at deployment and leaves the hero's
## models standing where the hero was deployed.
func _chain(host_in_reserve: bool) -> Array:
	var host := _unit(2, [Vector3(30.0 * IN2M, 0, 0), Vector3(31.0 * IN2M, 0, 0)], "Pioneers", ["Ambush"])
	var hero := _unit(2, [Vector3(5.0 * IN2M, 0, 0)], "Leader", ["Hero", "Tough(3)"])
	host.unit_properties["attached_heroes"] = [hero]
	hero.unit_properties["attached_to"] = host
	host.unit_properties["ambush_reserve"] = host_in_reserve
	var foe := _unit(1, [Vector3.ZERO], "Foe", [])
	return [host, hero, foe]


func _capture(units: Array) -> Dictionary:
	return BattleSim.capture(_army(units), func() -> Array: return [], func(_i: int) -> int: return 0, 1, 4)


func test_the_hero_of_a_reserved_host_is_dormant_at_73() -> void:
	var state := _capture(_chain(true))
	var host: Dictionary = state["units"]["Pioneers"]
	assert_bool(host.get("dormant", false)).is_true()
	var hero: Dictionary = state["units"]["Leader"]
	assert_bool(hero.get("dormant", false)) \
		.override_failure_message("the hero of a reserved host must wait in the tray with it").is_true()
	assert_int(hero["alive"]).is_equal(0)
	assert_array(hero["positions"]).is_empty()
	assert_int(int(hero.get("dormant_models", -1))).is_equal(1)
	assert_array(hero.get("dormant_wounds", [])).has_size(1)


## Control: once the host has arrived the hero is a live unit again, positions and all.
func test_the_hero_of_an_arrived_host_stays_live() -> void:
	var state := _capture(_chain(false))
	var hero: Dictionary = state["units"]["Leader"]
	assert_bool(hero.get("dormant", false)).is_false()
	assert_int(hero["alive"]).is_equal(1)
	assert_that(hero["positions"][0]).is_equal(Vector3(5.0 * IN2M, 0, 0))


## Control: below 73 the recorded corpus keeps the old export - the hero stands live while its host is reserved.
func test_the_epoch_72_control_keeps_the_old_export() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var state := _capture(_chain(true))
	var hero: Dictionary = state["units"]["Leader"]
	assert_bool(hero.get("dormant", false)).is_false()
	assert_int(hero["alive"]).is_equal(1)
