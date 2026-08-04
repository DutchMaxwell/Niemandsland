extends GdUnitTestSuite
## E2E — #226 SPLIT FIRE (GF v3.5.1 p.8: "Each group may be fired at a different target,
## however you may fire only at up to two different targets"): the declared split resolves
## each weapon group at ITS target and completes the activation exactly once. Drives the
## real volley resolvers on main.tscn (the dialog itself is player-side; headless bypasses).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _armed(pid: int, unit_name: String, pos: Vector3, weapon_names: Array) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, [pos])
	var opr := OPRApiClient.OPRUnit.new()
	var ws: Array[OPRApiClient.OPRWeapon] = []
	for wn in weapon_names:
		var w := OPRApiClient.OPRWeapon.new()
		w.name = str(wn)
		w.range_value = 24
		w.attacks = 2
		ws.append(w)
	opr.weapons = ws
	u.source_type = "opr"
	u.source_data = opr
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## A 3-model heavy-weapon-team fixture with per-model loadout pins (the EquipmentDistributor
## truth alive_bearers_of reads): models 0+1 carry the Rifle, model 2 the Launcher (count 1).
func _team(pid: int, unit_name: String, pos: Vector3) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name,
		[pos, pos + Vector3(0.05, 0, 0), pos + Vector3(0.10, 0, 0)])
	var opr := OPRApiClient.OPRUnit.new()
	var ws: Array[OPRApiClient.OPRWeapon] = []
	var rifle := OPRApiClient.OPRWeapon.new()
	rifle.name = "Rifle"
	rifle.range_value = 24
	rifle.attacks = 2
	rifle.count = 2
	ws.append(rifle)
	var launcher := OPRApiClient.OPRWeapon.new()
	launcher.name = "Launcher"
	launcher.range_value = 24
	launcher.attacks = 1
	launcher.count = 1
	ws.append(launcher)
	opr.weapons = ws
	u.source_type = "opr"
	u.source_data = opr
	(u.models[0] as ModelInstance).properties["weapons"] = [{"name": "Rifle"}]
	(u.models[1] as ModelInstance).properties["weapons"] = [{"name": "Rifle"}]
	(u.models[2] as ModelInstance).properties["weapons"] = [{"name": "Launcher"}]
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func test_dead_bearer_weapon_is_not_offered_for_split() -> void:
	# NML-983 (maintainer game, heavy weapon team at 1/3 models): the split ask still listed every
	# gun. A weapon whose every pinned bearer is DEAD must not be offered — its volley would roll
	# zero dice (alive_bearers_of, the X2/B15 truth) — and with only one living weapon left the
	# ask (needs >= 2 names) must not open at all.
	var shooter := _team(1, "Team", Vector3.ZERO)
	var foe := _armed(2, "Foe", Vector3(8.0 * INCH, 0, 0), [])
	var bearer := shooter.models[2] as ModelInstance
	bearer.is_alive = false
	bearer.node.visible = false
	var names: Array = _main._solo_split_fire_offer_names(shooter, foe)
	assert_array(names) \
		.override_failure_message("NML-983: a weapon with every pinned bearer dead was still offered for split fire (offered: %s)" % [names]) \
		.not_contains(["Launcher"])
	assert_array(names).contains(["Rifle"])


func test_alive_bearer_weapons_stay_offered() -> void:
	# Counter-case: with all bearers alive both names are offered — the NML-983 filter must not
	# eat living specialists (nor units without per-model loadout data, which keep ratio scaling).
	var shooter := _team(1, "TeamAlive", Vector3.ZERO)
	var foe := _armed(2, "FoeAlive", Vector3(8.0 * INCH, 0, 0), [])
	var names: Array = _main._solo_split_fire_offer_names(shooter, foe)
	assert_array(names).contains(["Rifle", "Launcher"])


func test_declared_split_fires_each_group_at_its_target(timeout := 240000) -> void:
	var shooter := _armed(1, "Tank", Vector3.ZERO, ["Rifle", "Cannon"])
	var foe_a := _armed(2, "FoeA", Vector3(8.0 * INCH, 0, 0), [])
	var foe_b := _armed(2, "FoeB", Vector3(0, 0, 8.0 * INCH), [])
	await _main._run_human_attack_split(shooter, foe_a, foe_b, ["Cannon"])
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	assert_str(text).contains("Split fire: Tank fires at FoeA and FoeB")
	assert_str(text) \
		.override_failure_message("#226 — the A-volley did not fire the unchecked weapon at FoeA (log: %s)" % text.strip_edges()) \
		.contains("fires Rifle at FoeA")
	assert_str(text).contains("fires Cannon at FoeB")
	assert_str(text).not_contains("fires Cannon at FoeA")
	assert_str(text).not_contains("fires Rifle at FoeB")
	assert_bool(shooter.is_activated).is_true()   # completed exactly once, after volley B
	await E2EBoot.settle(get_tree())   # the activation's trailing bookkeeping, before gdUnit reads
