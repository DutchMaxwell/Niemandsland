extends GdUnitTestSuite
## Audit finding T-1 (rules 3.6, EPOCH_73_V36): the Ogres item feat "Piercing Feat" grants +1 AP on every attack of
## the bearer's FIRST attacking exchange, then never again. The core grants it that way; the table's conditional-AP
## read has no arm for the feat's `any_attack` condition, so the bearer got nothing, ever.

const Boot := preload("res://test/e2e/e2e_boot.gd")
const CONTEXTS := ["aof", "aofr", "aofs"]
const WEAPON := {"name": "Club", "attacks": 6, "ap": 0, "rules": []}
const TRAP := {"name": "Trap", "ap": 0, "deadly": 0, "rules": []}
const PART := [{"name": "Piercing Feat", "bonus": 1}]

var _runner: GdUnitSceneRunner
var _main: Node
var _roots: Array
var _epoch0: int


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch
	Boot.arm_harness_mode()
	_roots = Boot.root_children(get_tree())
	_runner = scene_runner(Boot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main._solo_batch = true


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0   # statics leak across gdUnit tests - restore
	Boot.free_stray_root_nodes(get_tree(), _roots)
	_main = null
	_runner = null


## One alive model; the bearer carries the feat through an item grant, the way the import records an Ogres upgrade.
func _plain(system: String, bearer: bool) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = "t1_%s_%s" % [system, bearer]
	u.unit_properties = {"player_id": 2, "name": "Fixture", "quality": 4, "defense": 4,
		"special_rules": [], "game_system": system, "faction_folder": "ogres"}
	if bearer:
		u.unit_properties["item_grants"] = {"Doom of Kingdoms": ["Piercing Feat"]}
	var model := ModelInstance.new()
	model.is_alive = true
	u.models.append(model)
	return u


func test_the_feat_pays_its_ap_while_unspent_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	for system in CONTEXTS:
		var bearer := _plain(system, true)
		var foe := _plain(system, false)
		assert_array(_main._solo_conditional_ap_parts(WEAPON, bearer, foe, false, 10.0, false)).is_equal(PART)
		assert_array(_main._solo_conditional_ap_parts(WEAPON, bearer, foe, false, -1.0, true)).is_equal(PART)


func test_a_spent_latch_pays_nothing() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	for system in CONTEXTS:
		var bearer := _plain(system, true)
		var foe := _plain(system, false)
		bearer.unit_properties[SoloController.shot_feat_flag("Piercing Feat")] = true
		assert_array(_main._solo_conditional_ap_parts(WEAPON, bearer, foe, false, 10.0, false)).is_empty()
		assert_array(_main._solo_conditional_ap_parts(WEAPON, bearer, foe, false, -1.0, true)).is_empty()


func test_below_epoch_73_nothing_changes() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36 - 1
	for system in CONTEXTS:
		var bearer := _plain(system, true)
		var foe := _plain(system, false)
		assert_array(_main._solo_conditional_ap_parts(WEAPON, bearer, foe, false, 10.0, false)).is_empty()
		assert_array(_main._solo_conditional_ap_parts(WEAPON, bearer, foe, false, -1.0, true)).is_empty()


func test_a_hit_source_without_attacks_gets_no_feat() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	for system in CONTEXTS:
		var bearer := _plain(system, true)
		assert_array(_main._solo_conditional_ap_parts(TRAP, bearer, bearer, false, -1.0, true)).is_empty()
