extends GdUnitTestSuite
## Rules 3.6 wave, row MEL-01 (lead ruling D-ASSAULT): a weapon carrying Assault counts as a ranged AND a
## melee weapon. From the 3.6 epoch (73) its melee copy strikes with the weapon's own attacks, AP and rules;
## at 72 a unit armed only with such a pistol has nothing to fight with and cannot strike back. The copy
## sits at range 0, so every melee reader keeps its "range 0 = melee" meaning, and it carries the printed
## range apart (`printed_range`) for the range-relative gates.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")

var _epoch0: int
var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0   # statics leak across gdUnit tests: restore
	if _runner != null:
		E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _pistol(count: int) -> Dictionary:
	return {"name": "Assault Pistol", "range_value": 12, "attacks": 2, "count": count,
		"special_rules": ["Assault", "AP(1)"]}


func _melee_at(epoch: int, weapons: Array) -> Array:
	AiActRecorder.rules_epoch = epoch
	return AiShooting.melee_profiles(weapons)


func test_an_assault_pistol_gives_no_melee_profile_at_epoch_72() -> void:
	assert_array(_melee_at(AiActRecorder.EPOCH_72_PLAYTEST_RULES, [_pistol(3)])).is_empty()


func test_an_assault_pistol_strikes_in_melee_at_epoch_73() -> void:
	var melee := _melee_at(73, [_pistol(3)])
	assert_int(melee.size()).override_failure_message("the Assault pistol made no melee profile at 73").is_equal(1)
	if melee.size() != 1:
		return
	assert_int(int(melee[0].get("attacks", 0))).is_equal(6)   # 2 attacks x 3 pistols
	assert_int(int(melee[0].get("ap", 0))).is_equal(1)
	# It still shoots as before: the ranged profile is untouched.
	var shoot := AiShooting.profiles_in_range([_pistol(3)], 6.0)
	assert_int(shoot.size()).is_equal(1)
	assert_int(int(shoot[0].get("range", 0))).is_equal(12)


## D-ASSAULT trap: a half-range gate must read the printed 12" (half = 6") and stay off in base contact; a
## copy that only knew range 0 would read "over half of 0" as true at any distance.
func test_the_melee_copy_stays_melee_and_keeps_its_printed_range_at_epoch_73() -> void:
	var melee := _melee_at(73, [_pistol(3)])
	assert_int(melee.size()).is_equal(1)
	if melee.size() != 1:
		return
	assert_int(int(melee[0].get("range", -1))).is_equal(0)
	assert_bool(AiEv.facet_applies({"shooting_only": true}, int(melee[0].get("range", 0)))).is_false()
	assert_int(int(melee[0].get("printed_range", 0))).is_equal(12)


## Per-pick export lines of the same pistol merge into one melee profile, in weapon order.
func test_per_pick_assault_lines_merge_into_one_melee_profile_at_epoch_73() -> void:
	var ccw := {"name": "CCW", "range_value": 0, "attacks": 1, "count": 2, "special_rules": []}
	var melee := _melee_at(73, [_pistol(1), ccw, _pistol(1)])
	assert_int(melee.size()).is_equal(2)
	if melee.size() != 2:
		return
	assert_str(str(melee[0].get("name", ""))).is_equal("Assault Pistol")
	assert_int(int(melee[0].get("attacks", 0))).is_equal(4)


func _boot() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()


## A one-model unit armed only with the Assault pistol, and a foe in base contact.
func _duel() -> Array:
	var gun := E2EBoot.make_unit(_main, 1, "Pistols", [Vector3.ZERO])
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Assault Pistol"
	w.range_value = 12
	w.attacks = 2
	w.count = 1
	w.special_rules.append("Assault")
	var ws: Array[OPRApiClient.OPRWeapon] = [w]
	var src := OPRApiClient.OPRUnit.new()
	src.weapons = ws
	gun.source_type = "opr"
	gun.source_data = src
	_main.opr_army_manager.game_units[gun.unit_id] = gun
	var foe := E2EBoot.make_unit(_main, 2, "Foe", [Vector3(0.04, 0, 0)])
	return [gun, foe]


## The B14 strike-back gate reads exactly this list: empty = "cannot strike back", no dialog.
func test_a_pistol_only_defender_cannot_strike_back_at_epoch_72(timeout := 120000) -> void:
	await _boot()
	var d := _duel()
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	assert_array(_main._solo_attack_groups(d[0], 0.0, true, d[1])).is_empty()


func test_a_pistol_only_defender_strikes_back_with_it_at_epoch_73(timeout := 120000) -> void:
	await _boot()
	var d := _duel()
	AiActRecorder.rules_epoch = 73
	var groups: Array = _main._solo_attack_groups(d[0], 0.0, true, d[1])
	assert_int(groups.size()).override_failure_message("no melee group: the B14 gate still says no strike-back").is_equal(1)
	if groups.size() != 1:
		return
	var profs: Array = (groups[0] as Dictionary).get("profiles", [])
	assert_int(profs.size()).is_equal(1)
	if profs.size() != 1:
		return
	assert_str(str(profs[0].get("name", ""))).is_equal("Assault Pistol")
	assert_int(int(profs[0].get("attacks", 0))).is_equal(2)
