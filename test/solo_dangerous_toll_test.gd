extends GdUnitTestSuite
## #316 — the dangerous-toll charge gate. The router already skirts Dangerous
## ground when a detour exists; this covers the FORCED crossing: when every
## corridor pays the minefield toll and the expected toll (one die per wound,
## a 1 wounds -> dice/6) matches or beats the charge's own expected value,
## the charge comes off the menu. Only Flying ignores Dangerous (p.13/14).

const IN2M := 0.0254


var _mgr: OPRArmyManager
var _solo: SoloController


func before_test() -> void:
	_mgr = auto_free(OPRArmyManager.new())
	_solo = auto_free(SoloController.new())
	add_child(_solo)
	_solo.army_manager = _mgr
	_solo.human_slot = 1
	_solo.ai_slot = 2
	# A dangerous band across the whole table at z in [4", 8"] — no detour exists.
	_solo.terrain_type_at = func(p: Vector3) -> int:
		var z_in := p.z / IN2M
		return TerrainRules.TerrainType.DANGEROUS if z_in >= 4.0 and z_in <= 8.0 \
			else TerrainRules.TerrainType.NONE


func _unit(id: String, n: int, rules: Array, pid: int, weapons: Array = []) -> GameUnit:
	var u: GameUnit = auto_free(GameUnit.new())
	u.unit_id = id
	u.unit_properties = {"player_id": pid, "special_rules": rules, "name": id,
		"quality": 4, "defense": 4}
	# _unit_weapons reads OPR source data — OPRUnit.weapons is typed, so the
	# fixture builds real OPRWeapon objects.
	var od := OPRApiClient.OPRUnit.new()
	for w in weapons:
		od.weapons.append(w)
	u.source_type = "opr"
	u.source_data = od
	for i in range(n):
		var m: ModelInstance = ModelInstance.new()
		m.unit = u
		m.wounds_max = 1
		m.node = auto_free(Node3D.new())
		add_child(m.node)
		m.node.global_position = Vector3(float(i) * IN2M, 0, 0)
		u.models.append(m)
	_mgr.game_units[id] = u
	return u


func _melee(wname: String, attacks: int, ap: int = 0, count: int = 1) -> OPRApiClient.OPRWeapon:
	var w := OPRApiClient.OPRWeapon.new()
	w.name = wname
	w.range_value = 0
	w.attacks = attacks
	w.count = count
	if ap > 0:
		w.special_rules.append("AP(%d)" % ap)
	return w


func test_forced_crossing_with_weak_melee_refuses() -> void:
	# 5 models x 1 wound = 5 dice -> toll 0.83 expected wounds; bare fists
	# against Defense 4 stay under that -> refused.
	var chargers := _unit("Chargers", 5, [], 2, [_melee("Fists", 1)])
	var leader := _unit("Leader", 1, [], 1)
	var toll: Dictionary = _solo.charge_dangerous_toll(chargers, leader,
		Vector3(0, 0, 0), Vector3(0, 0, 12.0 * IN2M))
	assert_float(float(toll["toll"])).is_equal_approx(5.0 / 6.0, 0.001)
	assert_bool(bool(toll["refused"])).is_true()


func test_strong_melee_pays_the_toll_and_charges() -> void:
	# The same crossing with a real payload (20 attacks, AP2): the charge EV
	# clears the 0.83-wound toll -> the charge stays on the menu.
	var bruisers := _unit("Bruisers", 5, [], 2, [_melee("Claws", 4, 2, 5)])
	var leader := _unit("Leader", 1, [], 1)
	var toll: Dictionary = _solo.charge_dangerous_toll(bruisers, leader,
		Vector3(0, 0, 0), Vector3(0, 0, 12.0 * IN2M))
	assert_bool(float(toll["cev"]) > float(toll["toll"])).is_true()
	assert_bool(bool(toll["refused"])).is_false()


func test_flying_ignores_the_field_and_detour_clears_the_gate() -> void:
	# Flying ignores Dangerous entirely (p.13/14).
	var fliers := _unit("Fliers", 5, ["Flying"], 2, [_melee("Fists", 1)])
	var leader := _unit("Leader", 1, [], 1)
	assert_bool(bool(_solo.charge_dangerous_toll(fliers, leader,
		Vector3(0, 0, 0), Vector3(0, 0, 12.0 * IN2M))["refused"])).is_false()
	# And a PATCH of dangerous ground (x in [-2", 2"] only) leaves a 4"-offset
	# detour clear -> not forced -> the router handles it, the gate stays out.
	_solo.terrain_type_at = func(p: Vector3) -> int:
		var z_in := p.z / IN2M
		var x_in := p.x / IN2M
		return TerrainRules.TerrainType.DANGEROUS \
			if z_in >= 4.0 and z_in <= 8.0 and absf(x_in) <= 1.0 \
			else TerrainRules.TerrainType.NONE
	var walkers := _unit("Walkers", 5, [], 2, [_melee("Fists", 1)])
	assert_bool(bool(_solo.charge_dangerous_toll(walkers, leader,
		Vector3(0, 0, 0), Vector3(0, 0, 12.0 * IN2M))["refused"])).is_false()
