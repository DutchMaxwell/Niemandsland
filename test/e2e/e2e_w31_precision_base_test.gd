extends GdUnitTestSuite
## E2E W31-F2 (rules 3.6, release 0.3.15): Precision Charge ("this model gets +1 to hit rolls when charging") and
## Precision Fighter ("... in melee") as BASE rules. Until now only the Aura spellings were read, so a carrier of the
## base itself got nothing and the note told the player to apply it by hand. Driven on the real main.tscn: the real
## _solo_hit_mod_info is the function the dice path calls for both melee and shooting.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")

## [system, book, rule, pays on a plain strike too]
const BASES := [
	["gf", "orc_marauders", "Precision Charge", false],
	["aof", "dwarves", "Precision Charge", false],
	["gf", "eternal_dynasty", "Precision Fighter", true],
]

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _epoch_before: int


func before_test() -> void:
	_epoch_before = AiActRecorder.rules_epoch
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch_before
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _unit(rules: Array, system: String, faction: String) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = "pb_%d" % rules.size()
	u.unit_properties = {"player_id": 2, "name": "Carrier", "quality": 4, "defense": 4,
		"special_rules": rules, "game_system": system, "faction_folder": faction}
	var m := ModelInstance.new()
	m.is_alive = true
	u.models.append(m)
	return u


func _mod(u: GameUnit, melee: bool, charging: bool) -> Dictionary:
	var foe := _unit([], str(u.unit_properties["game_system"]), str(u.unit_properties["faction_folder"]))
	return _main._solo_hit_mod_info(u, foe, 0.0 if melee else 12.0, melee, charging)


func test_a_base_carrier_hits_one_better_at_73_and_the_log_names_the_rule() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	for b: Array in BASES:
		var u := _unit([b[2]], b[0], b[1])
		var charged := _mod(u, true, true)
		var stood := _mod(u, true, false)
		assert_int(int(charged["mod"])).override_failure_message("%s/%s: %s on a charge: %s" % [b[0], b[1], b[2], charged]).is_equal(1)
		assert_str(str(charged["note"])).override_failure_message("the note must name %s: %s" % [b[2], charged]).contains("%s +1" % b[2])
		assert_int(int(stood["mod"])).override_failure_message("%s/%s: %s on a plain strike: %s" % [b[0], b[1], b[2], stood]) \
			.is_equal(1 if b[3] else 0)
		assert_int(int(_mod(u, false, false)["mod"])).override_failure_message("%s leaked into shooting" % b[2]).is_equal(0)


func test_a_base_carrier_is_unchanged_below_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	for b: Array in BASES:
		var u := _unit([b[2]], b[0], b[1])
		assert_int(int(_mod(u, true, true)["mod"])).override_failure_message("%s/%s at 72: %s" % [b[0], b[1], _mod(u, true, true)]).is_equal(0)


## The control behind the earlier double count: the Aura carrier, with the base the import copies onto it, gets +1 once.
func test_an_aura_carrier_with_the_expanded_base_counts_the_bonus_once() -> void:
	for epoch in [AiActRecorder.EPOCH_72_PLAYTEST_RULES, AiActRecorder.EPOCH_73_V36]:
		AiActRecorder.rules_epoch = epoch
		for b: Array in BASES:
			var u := _unit([str(b[2]) + " Aura", b[2]], b[0], b[1])
			assert_int(int(_mod(u, true, true)["mod"])).override_failure_message("%s/%s at %d: %s" % [b[0], b[1], epoch, _mod(u, true, true)]).is_equal(1)


## Model scope: the bonus is read off the picked member's own rules. A host without the rule gets nothing while the
## joined hero that carries it gets +1 - the two are separate GameUnits, as in the game.
func test_only_the_carrier_member_gets_the_bonus() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	assert_int(int(_mod(_unit([], "gf", "eternal_dynasty"), true, true)["mod"])).is_equal(0)
	assert_int(int(_mod(_unit(["Hero", "Precision Fighter"], "gf", "eternal_dynasty"), true, true)["mod"])).is_equal(1)
