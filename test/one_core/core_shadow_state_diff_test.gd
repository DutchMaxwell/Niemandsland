extends GdUnitTestSuite
## Shadow comparator: a joined hero reads its host's core Shaken. The core shakes only the host after a failed morale test;
## landing its delta mirrors that onto the hero (`land_delta` -> `_solo_mirror_shaken`), exactly as the table's own morale
## does. Without the mirror every such volley was a false "shaken" mismatch (17 in the 24-game shadow soak).
## RED: drop the mirror in `CoreShadow._state_diff` -> the first case answers "shaken".
## Constructed: an army manager with a host, its joined hero and a foe; the core side is a hand-written plain state.

const IN2M := 0.0254


class StubMain:
	var opr_army_manager: OPRArmyManager


func _unit(uid: String, x_in: float) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = uid
	u.unit_properties = {"player_id": 1, "name": uid, "quality": 4, "defense": 4, "special_rules": []}
	var m := ModelInstance.new()
	m.is_alive = true
	m.unit = u
	var n: Node3D = auto_free(Node3D.new())
	add_child(n)
	n.global_position = Vector3(x_in * IN2M, 0, 0)
	m.node = n
	u.models.append(m)
	return u


func _main_with_shaken_chain() -> StubMain:
	var host := _unit("host", 0.0)
	var hero := _unit("hero", 1.0)
	EquipmentDistributor.attach_hero_to_unit(hero, host)
	host.is_shaken = true
	hero.is_shaken = true   # the table mirrored the host's failed test onto the hero
	var main := StubMain.new()
	main.opr_army_manager = auto_free(OPRArmyManager.new())
	main.opr_army_manager.game_units = {"host": host, "hero": hero}
	return main


func _core(host_shaken: bool) -> Dictionary:
	return {"units": {"host": {"alive": 1, "wounds": [1], "shaken": host_shaken, "fatigued": false},
		"hero": {"alive": 1, "wounds": [1], "shaken": false, "fatigued": false}}}


func test_a_joined_hero_reads_its_hosts_core_shaken() -> void:
	assert_str(CoreShadow._state_diff(_main_with_shaken_chain(), _core(true))).is_equal("")


func test_a_host_the_core_did_not_shake_is_still_a_difference() -> void:
	assert_str(CoreShadow._state_diff(_main_with_shaken_chain(), _core(false))).is_equal("shaken")
