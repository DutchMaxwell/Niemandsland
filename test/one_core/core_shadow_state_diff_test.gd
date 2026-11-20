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


func before_test() -> void:
	CoreShadow._wiped_at_capture = {}


func test_a_joined_hero_reads_its_hosts_core_shaken() -> void:
	assert_str(CoreShadow._state_diff(_main_with_shaken_chain(), _core(true))).is_equal("")


func test_a_host_the_core_did_not_shake_is_still_a_difference() -> void:
	assert_str(CoreShadow._state_diff(_main_with_shaken_chain(), _core(false))).is_equal("shaken")


## The table signs a joined hero's save with its unit's label ("AI (Assault Brothers)") where the core names the hero
## (C-18 lift soak: 4 such volleys). One unit, one roller: the keys match through the hero's host, and only through it.
## RED: plain key equality -> the first case is a mismatch.
func test_a_hero_signed_roll_matches_its_hosts_label() -> void:
	var host_of := {"Elite Pathfinder": "Assault Brothers"}
	assert_bool(CoreShadow.same_roll(["defense", 2, 5, "Elite Pathfinder"], ["defense", 2, 5, "Assault Brothers"], host_of)).is_true()
	assert_bool(CoreShadow.same_roll(["defense", 2, 4, "Elite Pathfinder"], ["defense", 2, 5, "Assault Brothers"], host_of)).is_false()
	assert_bool(CoreShadow.same_roll(["defense", 2, 5, "Elite Pathfinder"], ["defense", 2, 5, "Assault Brothers"], {})).is_false()
	assert_bool(CoreShadow.same_roll(["attack", 3, 5, "Grunt Veteran"], ["attack", 3, 5, "Grunt Veteran"], host_of)).is_true()


## Gate 10 (game 12, d46589e10): the host was wiped Shaken in an EARLIER activation; the hero fought on alone, idled and
## recovered. Both sides read the hero 0, but the compare mirrored the dead host's stale 1 onto it (3 false "shaken").
## RED: drop `not _wiped_at_capture.has(host)` in `CoreShadow._state_diff` -> this case answers "shaken".
func test_a_host_wiped_before_the_activation_is_not_mirrored() -> void:
	var main := _main_with_shaken_chain()
	var host: GameUnit = main.opr_army_manager.game_units["host"]
	var hero: GameUnit = main.opr_army_manager.game_units["hero"]
	(host.models[0] as ModelInstance).is_alive = false
	hero.is_shaken = false   # the lone hero spent its activation idle and recovered; the dead host keeps its flag
	CoreShadow.note_wiped(main.opr_army_manager)   # the capture: the host is already gone
	var core := {"units": {"host": {"alive": 0, "wounds": [], "shaken": true, "fatigued": false},
		"hero": {"alive": 1, "wounds": [1], "shaken": false, "fatigued": false}}}
	assert_str(CoreShadow._state_diff(main, core)).is_equal("")


## The other half (game 12 volleys 2 and 7): the host is shaken AND wiped inside this activation; the table's landing
## mirrors that onto the hero, so the compare must still mirror. RED for a "host alive at the end" guard: "shaken".
func test_a_host_wiped_in_this_activation_is_still_mirrored() -> void:
	var main := _main_with_shaken_chain()
	var host: GameUnit = main.opr_army_manager.game_units["host"]
	CoreShadow.note_wiped(main.opr_army_manager)   # the capture: the host still stands
	(host.models[0] as ModelInstance).is_alive = false   # this volley wipes it, Shaken; the hero reads Shaken too
	var core := {"units": {"host": {"alive": 0, "wounds": [], "shaken": true, "fatigued": false},
		"hero": {"alive": 1, "wounds": [1], "shaken": false, "fatigued": false}}}
	assert_str(CoreShadow._state_diff(main, core)).is_equal("")
