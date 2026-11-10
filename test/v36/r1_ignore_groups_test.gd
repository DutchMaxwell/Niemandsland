extends GdUnitTestSuite

const Boot := preload("res://test/e2e/e2e_boot.gd")
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


func _unit(rules: Array, system: String, faction: String) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = "rule_%d" % rules.size()
	u.unit_properties = {"player_id": 2, "name": "Fixture", "quality": 4, "defense": 2,
		"special_rules": rules, "game_system": system, "faction_folder": faction}
	var model := ModelInstance.new()
	model.is_alive = true
	u.models.append(model)
	return u


## Forms of ONE rule share a key; differently named rules keep their own.
func test_the_group_key_folds_only_forms_of_one_rule() -> void:
	var cases := [
		["Plaguebound Boost", {"upgrades": "Plaguebound"}, "Plaguebound"],
		["Enhanced Plaguebound", {}, "Plaguebound"],
		["Angelic Blessing Boost", {}, "Angelic Blessing"],
		["Enhanced Angelic Blessing", {}, "Angelic Blessing"],
		["Enhanced Knightborn", {}, "Knightborn"],
		["Self-Repair Boost", {}, "Self-Repair"],
		["Enhanced Self-Repair", {}, "Self-Repair"],
		["self-repair", {}, "Self-Repair"],
		["Regeneration Aura", {}, "Regeneration"],
		["Regeneration Buff", {}, "Regeneration"],
		["regeneration", {}, "Regeneration"],
		["Medical Training", {}, "Regeneration"],
		["resistance", {}, "Resistance"],
		["Spell Resistance", {}, "Spell Resistance"],
		["Protection Feat", {}, "Protection Feat"],
		["Protected", {}, "Protected"],
		["Grounded Protection", {}, "Grounded Protection"],
	]
	for c in cases:
		assert_str(_main._solo_ignore_group_key(str(c[0]), c[1])).is_equal(str(c[2]))
